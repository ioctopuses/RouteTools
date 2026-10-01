import Foundation

/// 一条静态路由配置。
struct Route: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var destination: String
    var gateway: String
    var enabled: Bool
    var note: String

    /// 分组名（可选）。快速启动页按它分段显示；为空归入「未分组」。
    ///
    /// 声明成 `String?` 而不是 `String = ""` 是有意的：Swift 合成的
    /// `init(from:)` 对**可选类型**走 `decodeIfPresent`，旧版本写下的
    /// routes.json 里没有这个键也能正常解码；若用非可选 String，
    /// 升级后读旧文件会直接抛 keyNotFound，用户的路由配置会全部丢失。
    var group: String?

    /// 自定义图标的**文件名**（不是路径，也不是图片本身）。
    ///
    /// 文件落在 `~/Library/Application Support/RouteBar/Icons/`，读写与清理都走
    /// `RouteIconLibrary`；为空 = 用自绘的默认路由图标（`RBDefaultRouteIcon`）。
    /// 与 `group` 同理声明成可选类型，旧版本写下的 routes.json 里没有这个键也能
    /// 正常解码 —— 用非可选 String 会让升级后读旧文件直接抛 keyNotFound。
    var icon: String?

    init(id: UUID = UUID(),
         name: String = "",
         destination: String,
         gateway: String,
         enabled: Bool = true,
         note: String = "",
         group: String? = nil,
         icon: String? = nil) {
        self.id = id
        self.name = name
        self.destination = destination
        self.gateway = gateway
        self.enabled = enabled
        self.note = note
        self.group = group
        self.icon = icon
    }
}

/// 把 Route 转换为 macOS 的 /sbin/route 命令。
struct RouteCommands {
    static func parse(_ target: String) -> (address: String, netmask: String?) {
        if let range = target.range(of: "/") {
            let addr = String(target[..<range.lowerBound])
            let prefixStr = String(target[range.upperBound...])
            guard let prefix = Int(prefixStr), (0...32).contains(prefix) else {
                return (target, nil)
            }
            return (addr, netmaskFromPrefix(prefix))
        }
        return (target, nil)
    }

    static func netmaskFromPrefix(_ prefix: Int) -> String {
        let mask: UInt32 = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - UInt32(prefix)))
        let a = (mask >> 24) & 0xFF
        let b = (mask >> 16) & 0xFF
        let c = (mask >> 8) & 0xFF
        let d = mask & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    static func addCommand(for route: Route) -> String {
        let (addr, mask) = parse(route.destination)
        if let mask = mask {
            return "/sbin/route add -net \(addr) -netmask \(mask) \(route.gateway)"
        }
        return "/sbin/route add -host \(addr) \(route.gateway)"
    }

    static func deleteCommand(for route: Route) -> String {
        let (addr, mask) = parse(route.destination)
        if let mask = mask {
            return "/sbin/route delete -net \(addr) -netmask \(mask) \(route.gateway)"
        }
        return "/sbin/route delete -host \(addr) \(route.gateway)"
    }

    // MARK: - IPv4 工具

    /// 点分十进制 → 32 位整数（非法输入返回 nil）
    static func ipv4ToUInt32(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let v = UInt32(part), v <= 255 else { return nil }
            result = (result << 8) | v
        }
        return result
    }

    /// 32 位整数 → 点分十进制
    static func uint32ToIPv4(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }

    /// 点分十进制掩码 → 前缀长度（对连续掩码有效）
    static func prefixFromNetmask(_ mask: String) -> Int? {
        guard let m = ipv4ToUInt32(mask) else { return nil }
        return m.nonzeroBitCount
    }

    /// 构造用于 `route get` 的**探测地址**。
    ///
    /// **为什么不能直接用网络地址**：macOS（BSD）的 `route get` 在查询
    /// **网络地址本身**时不会命中该网段的路由，而是回落到默认路由。
    /// 实测：系统表中存在 `8.0.0.0/5` 时，
    ///   `route -n get 8.0.0.0`  → destination: default   （错误命中）
    ///   `route -n get 8.8.8.8`  → destination: 8.0.0.0   （正确命中）
    /// 因此若直接用网络地址查询，会把"明明存在的路由"误判为缺失，
    /// 导致每次启动都白白提权添加 —— 取「网络地址 + 1」可避开这个坑。
    static func probeAddress(for target: String) -> String {
        let (addr, mask) = parse(target)
        // 主机路由（用户未写掩码）：地址本身就是探测目标
        guard let mask = mask,
              let network = ipv4ToUInt32(addr),
              let prefix = prefixFromNetmask(mask) else {
            return addr
        }
        // /31、/32 可用地址极少，直接探测地址本身
        guard prefix <= 30 else { return addr }
        return uint32ToIPv4(network + 1)
    }

    /// 构造「查询系统路由表里是否存在这条路由」的命令。
    ///
    /// 使用 `route -n get <探测地址>`：该命令**普通用户即可执行**，无需 root，
    /// 因此查询动作不会触发任何授权对话框（原先误用了提权通道，是弹窗的主要来源）。
    /// `-n` 表示以数字形式输出，避免 DNS 反查导致额外延迟。
    ///
    /// 注意探测地址取「网络地址 + 1」而非网络地址本身，原因见 `probeAddress(for:)`。
    static func getRouteQueryCommand(for route: Route) -> String {
        let probe = probeAddress(for: route.destination)
        return "/sbin/route -n get \(probe)"
    }
}

/// 使用 macOS Authorization Services 执行管理员权限命令（替代 osascript 的每次弹窗）。
///
/// 工作原理：
/// 1. 首次需要提权时，通过 Authorization Services 弹出**一次**系统授权对话框；
/// 2. 授权成功后，OS 在默认超时（约 5 分钟）内缓存该权限，
///    并且本 App 进程内复用同一个 `AuthorizationRef`；
/// 3. 因此在缓存有效期内，反复开关 / 增删路由**不再弹窗**；
/// 4. 仅当系统缓存过期（约 5 分钟后）或用户点击「清除授权缓存」时才需再次验证；
/// 5. 若 Authorization Services 不可用（极少见），自动回退到 osascript 密码框。
///
/// 注意：Swift 中 `AuthorizationExecuteWithPrivileges` 已被标记为 unavailable，
/// 因此真正的 Authorization Services 调用放在 Objective-C 桥接层 `PrivilegedShim.m`，
/// 这里只通过 Bridging.h 导入的 C 函数 `RBRunAsRoot` / `RBResetAuth` 与之交互。
struct PrivilegedRunner {

    /// 退出码哨兵：用于从合并输出中解析命令的真实返回码。
    private static let exitSentinel = "__RBEXIT__:"

    /// 执行管理员权限命令。
    static func runAsAdmin(_ command: String) -> (success: Bool, output: String) {
        switch runWithAuthorizationServices(command) {
        case .success(let ok, let out):
            return (ok, out)
        case .fallback:
            return runWithOsascript(command)
        }
    }

    private enum AuthResult {
        case success(Bool, String)   // 明确结果（含用户取消）
        case fallback                 // 技术故障，交给 osascript
    }

    // MARK: - 方案 1：Authorization Services（经 Objective-C 桥接层，缓存凭据）

    /// 由 PrivilegedShim.m 提供的 C 函数（通过 Bridging.h 导入）：
    ///   int  RBRunAsRoot(const char *command, char *outBuf, size_t outSize, int *cancelled);
    ///   void RBResetAuth(void);
    /// 桥接层内部复用同一个 AuthorizationRef，因此首次授权后约 5 分钟内不再弹窗，
    /// 且即使本进程多次调用也只弹一次（系统级凭据缓存 + 进程内复用）。
    private static func runWithAuthorizationServices(_ command: String) -> AuthResult {
        // 包装命令：合并 stderr 到 stdout，并追加退出码哨兵
        let wrapped = "\(command) 2>&1; printf '\(exitSentinel)%d\\n' $?"

        var outBuf = [CChar](repeating: 0, count: 16384)
        var cancelled: Int32 = 0
        let rc: Int32 = wrapped.withCString { cstr in
            outBuf.withUnsafeMutableBufferPointer { ptr in
                RBRunAsRoot(cstr, ptr.baseAddress!, ptr.count, &cancelled)
            }
        }

        if rc < 0 {
            if cancelled != 0 {
                return .success(false, "用户取消了授权")
            }
            return .fallback
        }

        let raw = outBuf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        if let range = raw.range(of: exitSentinel),
           let code = Int(raw[range.upperBound...]
                            .trimmingCharacters(in: .whitespacesAndNewlines)) {
            let clean = String(raw[..<range.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(code == 0, clean)
        }
        return .success(true, raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 清除进程内缓存的授权（下次提权需重新验证）。菜单「清除授权缓存」调用。
    static func resetAuthorization() {
        RBResetAuth()
    }

    /// 主动申请（预热）管理员授权 —— 设置页「申请授权」调用。
    ///
    /// 不同于 `resetAuthorization()` 的「清空」语义，这里走一次完整的
    /// `AuthorizationCopyRights`，因此**会弹出系统授权框**（首次）并把凭据
    /// 缓存起来，让随后约 5 分钟内的路由增删改都不再弹窗。
    ///
    /// - Returns: `true` 表示凭据已就绪；`false` 表示用户取消或授权失败。
    @discardableResult
    static func warmUpAuthorization() -> Bool {
        var cancelled: Int32 = 0
        let rc = RBWarmUpAuth(&cancelled)
        return rc == 0
    }

    // MARK: - 方案 2：osascript 兜底（仅密码，无缓存）

    private static func runWithOsascript(_ command: String) -> (success: Bool, output: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 非提权执行（不触发任何授权弹窗）

    /// 以**当前用户身份**执行命令，不申请管理员权限，因此**永远不会弹出授权框**。
    ///
    /// 用于只读查询类命令（如 `route get`、`netstat -rn`）——这些命令普通用户
    /// 即可执行，走提权通道纯属浪费，而且每次都会触发一次系统授权对话框。
    static func runAsUser(_ command: String) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// 检查当前用户是否有管理员权限（不弹窗）
    static func hasAdminPrivileges() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        process.arguments = ["-Gn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let groups = String(data: data, encoding: .utf8) ?? ""
            return groups.split(separator: "\n").contains(where: { $0 == "admin" })
        } catch {
            return false
        }
    }
}
