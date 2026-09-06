import Foundation

/// 一条静态路由配置。
struct Route: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var destination: String
    var gateway: String
    var enabled: Bool
    var note: String

    init(id: UUID = UUID(),
         name: String = "",
         destination: String,
         gateway: String,
         enabled: Bool = true,
         note: String = "") {
        self.id = id
        self.name = name
        self.destination = destination
        self.gateway = gateway
        self.enabled = enabled
        self.note = note
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

    static func getRouteQueryCommand(for route: Route) -> String {
        let (addr, mask) = parse(route.destination)
        if let mask = mask {
            return "/sbin/route get -net \(addr) -netmask \(mask)"
        }
        return "/sbin/route get -host \(addr)"
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
