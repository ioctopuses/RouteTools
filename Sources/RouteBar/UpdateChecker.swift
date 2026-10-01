import Foundation
import AppKit
import os.log

/// 更新检查的状态机
enum UpdateCheckState: Equatable {
    /// 尚未检查过
    case idle
    /// 正在请求更新源
    case checking
    /// 已是最新（携带当前版本）
    case upToDate(version: String)
    /// 发现新版本，等待用户决定
    case available(version: String)
    /// 正在下载新版本
    case downloading(version: String)
    /// 已交给替换助手，主进程即将退出
    case installing(version: String)
    /// 失败（网络 / 解析 / 校验…）
    case failed(message: String)

    /// 是否有流程正在进行 —— UI 据此禁用按钮
    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    /// 若已发现可用版本则返回其版本号
    var availableVersion: String? {
        if case .available(let version) = self { return version }
        return nil
    }
}

/// 更新源声明的一个可用版本
struct AvailableUpdate {
    /// 归一化后的版本号，如 `1.7.0`（去掉 tag 的 `v` 前缀）
    let version: String
    /// 更新源里的原始 tag
    let tag: String
    /// 该版本的 zip 下载地址
    let downloadURL: URL
    /// Release 说明（可能很长，展示前截断）
    let notes: String?
}

/// 更新流程中可能出现的错误
enum UpdateError: Error, CustomStringConvertible {
    case badFeed
    case badResponse
    case httpStatus(Int)
    case noAsset
    case extractFailed
    case noAppInArchive
    case invalidBundle
    case wrongBundleID(String)
    case versionMismatch(expected: String, actual: String)
    case missingExecutable
    case helperMissing

    var description: String {
        switch self {
        case .badFeed:
            return "更新源地址无效。"
        case .badResponse:
            return "更新源返回了无法识别的响应。"
        case .httpStatus(let code):
            return "更新源返回 HTTP \(code)。"
        case .noAsset:
            return "该版本没有可下载的安装包（zip）。"
        case .extractFailed:
            return "安装包解压失败。"
        case .noAppInArchive:
            return "安装包里没有找到 App。"
        case .invalidBundle:
            return "安装包结构不完整（Info.plist 缺失或损坏）。"
        case .wrongBundleID(let id):
            return "安装包不是 RouteBar（包标识为 \(id)），已拒绝安装。"
        case .versionMismatch(let expected, let actual):
            return "安装包版本不符：期望 \(expected)，实际 \(actual)。"
        case .missingExecutable:
            return "安装包里缺少可执行文件。"
        case .helperMissing:
            return "更新助手脚本缺失，自动替换不可用。"
        }
    }
}

/// 自动更新：检查 → 下载 → 校验 → 交给独立助手替换。
///
/// **更新源**：`AppConfig.updateFeedRepo`（`ioctopuses/RouteTools`）。
/// 该仓库本身是公开的，客户端可以直接读它的 Release，无需另建发布仓库。
///
/// **为什么不校验代码签名**：RouteBar 用的是自签名证书，在别人的机器上证书链
/// 不受信任，`codesign -v` 必然失败 —— 拿它当准入条件会 100% 误报，把正常更新
/// 全挡掉。这里改用**结构性校验**：解压后读新包的 `Info.plist`，核对 bundle id
/// 与版本号是否与更新源声明的一致，并要求可执行文件存在。
///
/// **为什么替换要交给外部脚本**：正在运行的 App 无法安全替换自己（bundle 正被
/// 自身占用，直接覆盖会得到半损坏的产物）。下载解压后启动 `update-helper.sh`，
/// 由它等主进程退出再替换、失败回滚、最后重启。
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var state: UpdateCheckState = .idle

    /// 上次完成检查的时间（含「已是最新」）
    @Published private(set) var lastCheckedAt: Date?

    private let logger = Logger(subsystem: AppConfig.bundleID, category: "update")

    /// 同一时刻只允许一个流程在跑
    private var isRunning = false

    /// 用户选「稍后」之后仍保留，便于在设置页一键安装
    private var pendingUpdate: AvailableUpdate?

    private init() {}

    /// 当前版本号 —— 唯一来源是 `Info.plist`，发版时须与 tag 一致
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var isBusy: Bool { state.isBusy }

    /// 设置页展示用的状态文案
    var statusText: String {
        switch state {
        case .idle:
            return lastCheckedAt == nil ? "尚未检查" : "上次检查：\(Self.timestamp(lastCheckedAt))"
        case .checking:
            return "正在检查…"
        case .upToDate(let version):
            return "已是最新（\(version)）"
        case .available(let version):
            return "发现新版本 \(version)"
        case .downloading(let version):
            return "正在下载 \(version)…"
        case .installing(let version):
            return "正在安装 \(version)…"
        case .failed(let message):
            return message
        }
    }

    // MARK: - 检查

    /// 查询更新源。
    ///
    /// - Parameter interactive: 用户手动触发时为 `true` —— 无论结果如何都给反馈；
    ///   启动时的静默检查传 `false`，只在**发现新版本**时打扰用户，失败仅写日志。
    func check(interactive: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        state = .checking
        defer { isRunning = false }

        do {
            let update = try await fetchLatest()
            lastCheckedAt = Date()

            guard let update else {
                pendingUpdate = nil
                state = .upToDate(version: currentVersion)
                if interactive {
                    presentInfo(title: "已是最新版本",
                                message: "RouteBar \(currentVersion) 已是最新版本。")
                }
                return
            }

            pendingUpdate = update
            state = .available(version: update.version)

            if confirmUpdate(to: update.version, notes: update.notes) {
                await downloadAndInstall(update)
            }
        } catch {
            let message = (error as? UpdateError)?.description ?? error.localizedDescription
            logger.error("检查更新失败: \(message, privacy: .public)")
            state = .failed(message: message)
            if interactive {
                presentInfo(title: "检查更新失败", message: message)
            }
        }
    }

    /// 安装上一次检查发现的版本（供设置页的「立即更新」按钮使用）
    func installPendingUpdate() async {
        guard let update = pendingUpdate, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        await downloadAndInstall(update)
    }

    // MARK: - 与更新源交互

    private func fetchLatest() async throws -> AvailableUpdate? {
        let repo = AppConfig.updateFeedRepo.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !repo.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw UpdateError.badFeed
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // GitHub API 强制要求 User-Agent，缺失会直接返回 403
        request.setValue("RouteBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        guard http.statusCode == 200 else { throw UpdateError.httpStatus(http.statusCode) }

        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName

        // 只有严格更新才提示；相同或更旧一律视为已是最新
        guard Self.compare(version, currentVersion) == .orderedDescending else { return nil }

        guard let asset = payload.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateError.noAsset
        }

        return AvailableUpdate(
            version: version,
            tag: payload.tagName,
            downloadURL: downloadURL,
            notes: payload.body
        )
    }

    // MARK: - 下载与安装

    /// 下载并安装。
    ///
    /// **不做互斥判断**：调用方（`check` / `installPendingUpdate`）已经保证同一时刻
    /// 只有一个流程在跑 —— 这里再判断一次会把 `check` 内部发起的安装挡在门外
    /// （那时 `isRunning` 还是 `true`）。
    private func downloadAndInstall(_ update: AvailableUpdate) async {
        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RouteBarUpdate-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            state = .downloading(version: update.version)
            let zipURL = workDir.appendingPathComponent("RouteBar.zip")
            try await download(update.downloadURL, to: zipURL)

            let staged = try extractApp(from: zipURL, into: workDir)
            try validate(stagedApp: staged, expectedVersion: update.version)

            state = .installing(version: update.version)
            try launchHelper(newApp: staged, workDir: workDir)
            pendingUpdate = nil

            logger.info("更新已交给助手，主进程即将退出")
            // 给助手一点时间起来（它自己会等主进程退出），然后退出由它完成替换
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            let message = (error as? UpdateError)?.description ?? error.localizedDescription
            logger.error("安装更新失败: \(message, privacy: .public)")
            state = .failed(message: message)
            try? FileManager.default.removeItem(at: workDir)
            presentInfo(title: "更新失败", message: message)
        }
    }

    private func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("RouteBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    /// 用系统的 ditto 解压 —— 它能正确处理 `.app` 这类含符号链接与扩展属性的目录
    private func extractApp(from zipURL: URL, into workDir: URL) throws -> URL {
        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw UpdateError.extractFailed }
        guard let app = Self.findAppBundle(in: extractDir) else { throw UpdateError.noAppInArchive }
        return app
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension == "app",
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return url
            }
        }
        return nil
    }

    /// 结构性校验：确认拿到的是**本应用**的、版本正确的完整 bundle。
    ///
    /// 这是整个更新流程的安全闸门 —— 少了它，等于「谁往 Release 里丢个 zip
    /// 就能在用户机器上执行任意代码」。校验三项：包标识、版本号、可执行文件。
    private func validate(stagedApp: URL, expectedVersion: String) throws {
        let plistURL = stagedApp.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw UpdateError.invalidBundle
        }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? "nil"
        guard bundleID == AppConfig.bundleID else {
            throw UpdateError.wrongBundleID(bundleID)
        }

        let version = plist["CFBundleShortVersionString"] as? String ?? "nil"
        guard Self.compare(version, expectedVersion) == .orderedSame else {
            throw UpdateError.versionMismatch(expected: expectedVersion, actual: version)
        }

        let executable = stagedApp.appendingPathComponent("Contents/MacOS/RouteBar").path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw UpdateError.missingExecutable
        }
    }

    /// 启动替换助手。
    ///
    /// 两个要点：
    /// 1. 助手脚本先**复制到临时目录**再执行 —— 因为它随后会 `mv` 掉整个旧 bundle，
    ///    脚本自己就住在里面，从 bundle 里运行等于边跑边被搬走；
    /// 2. 用 `nohup … &` 让它脱离主进程 —— 主进程马上要退出，不能被一起带走。
    private func launchHelper(newApp: URL, workDir: URL) throws {
        guard let bundledHelper = Bundle.main.path(forResource: "update-helper", ofType: "sh") else {
            throw UpdateError.helperMissing
        }

        let helperURL = workDir.appendingPathComponent("update-helper.sh")
        try? FileManager.default.removeItem(at: helperURL)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundledHelper), to: helperURL)

        let destination = Bundle.main.bundleURL
        let logURL = workDir.appendingPathComponent("update.log")

        let command = "nohup /bin/bash \(Self.quoted(helperURL.path)) "
            + "\(Self.quoted(newApp.path)) \(Self.quoted(destination.path)) "
            + "\(ProcessInfo.processInfo.processIdentifier) "
            + "> \(Self.quoted(logURL.path)) 2>&1 < /dev/null &"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()

        logger.info("已启动更新助手（日志：\(logURL.path, privacy: .public)）")
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - 版本比较

    /// 按 `.` 分段做数值比较（`1.7.10` > `1.7.9`），段数不等时短的一方补 0。
    ///
    /// 不能用字符串比较：那样 `1.10.0` 会小于 `1.9.0`。
    nonisolated static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    // MARK: - 弹窗

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func confirmUpdate(to version: String, notes: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "发现新版本 RouteBar \(version)"

        var body = "当前版本 \(currentVersion)，可更新到 \(version)。"
        if let notes, !notes.isEmpty {
            let trimmed = notes.count > 600 ? String(notes.prefix(600)) + "…" : notes
            body += "\n\n" + trimmed
        }
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")

        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - 工具

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 更新源响应结构

    private struct ReleasePayload: Decodable {
        let tagName: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case assets
        }
    }
}
