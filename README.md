# RouteBar — macOS 菜单栏路由管理工具

一个常驻菜单栏的原生 macOS 应用，用图形界面管理静态路由，告别手敲 `route add/delete`。

## 功能

- 菜单栏常驻（无 Dock 图标），点开即可管理路由
- 添加 / 编辑 / 删除路由
- 每条路由一个开关，**一键启用 / 禁用**（对应系统路由表的加入 / 删除）
- 支持网段（CIDR，如 `172.16.0.0/16`）与主机路由（如 `10.0.0.1`）
- 可选「启动时自动应用已启用路由」，重启后自动恢复
- 配置持久化保存，无需重复输入

## 目录结构

```
RouteTools/
├── Sources/RouteBar/
│   ├── RouteModel.swift     # Route 数据模型 + route 命令生成 + 提权执行（Authorization Services）
│   ├── RouteStore.swift     # 本地存储 + 实际执行系统命令
│   └── RouteBarApp.swift    # 菜单栏界面、添加/编辑窗口、版本显示
├── AppIcon.icns             # 应用图标
├── Info.plist               # .app 包配置
├── build.sh                 # 编译 + 打包脚本
└── README.md
```

## 编译打包（生成 .app）

1. 安装 Xcode 命令行工具（只需一次）：
   ```bash
   xcode-select --install
   ```
2. 在项目目录执行打包脚本：
   ```bash
   bash build.sh
   ```
3. 完成后会生成 `RouteBar.app`。双击即可打开，或拖入 `/Applications` 长期使用。

## 使用方法

1. 打开 `RouteBar.app`，菜单栏出现一个「网络」图标。
2. 点击图标 → 「添加路由」：
   - **名称**（可选）：随便写，便于识别，如「公司内网」。
   - **目标网段**：如 `172.16.0.0/16`（网段）或 `10.0.0.1`（单台主机）。
   - **网关**：如 `192.168.1.15`。
   - 勾选「保存后立即启用」。
3. 保存后，开关打开即为已写入系统路由表。
4. 之后在菜单栏点开，**拨动开关即可启用 / 禁用某条路由**；点铅笔图标编辑，点垃圾桶图标删除。
5. 退出：菜单里「退出」。

**关于密码输入**：macOS 的安全机制要求对路由表的修改需要管理员权限。当前版本使用 **Authorization Services**（macOS 原生授权框架），首次使用时会弹出系统授权对话框。

**授权缓存**：macOS 会自动缓存授权状态，**首次授权后约5分钟内**再次执行路由操作不需要再输入密码。这是系统级的缓存机制，无需任何配置。

## 它实际执行的命令

以「目标 `172.16.0.0/16`，网关 `192.168.1.15`」为例：

```bash
# 启用（添加）
/sbin/route add -net 172.16.0.0 -netmask 255.255.0.0 192.168.1.15

# 禁用（删除）
/sbin/route delete -net 172.16.0.0 -netmask 255.255.0.0 192.168.1.15
```

主机路由会被转换为 `route add -host <目标> <网关>`。

## 配置保存位置

`~/Library/Application Support/RouteBar/routes.json`
（记录你配置的路由及启用状态；系统路由表本身在重启后清空，由上面的「自动应用」负责恢复。）

## 常见问题

**Q：打开时提示「无法验证开发者 / 已损坏」？**
自签名应用会被 Gatekeeper 拦截，解除隔离即可（只需一次）：
```bash
xattr -dr com.apple.quarantine "/path/to/RouteBar.app"
```

**Q：为什么还要输密码？能用指纹吗？**
macOS 的安全机制要求对系统路由表的修改需要管理员验证。当前版本使用系统原生的 **Authorization Services** 授权对话框。

> **关于 Touch ID**：macOS 的 Authorization Services 授权对话框本身**不支持 Touch ID**（系统限制）。要实现指纹需要修改系统 PAM 配置（`/etc/pam.d/sudo`）或使用 Apple Developer 证书签名 + SMJobBless 安装特权助手工具。

**Q：授权缓存是多久？**
macOS 系统会自动缓存授权状态，通常**约5分钟**。期间内再次执行路由操作不需要再输入密码。缓存时间由系统控制，用户无法修改（除非修改 sudoers 配置）。

**Q：菜单栏图标点不开 / 看不到？**
确认系统版本 ≥ macOS 13（Ventura）。若被其它菜单栏工具挤掉，可长按 Command 拖动菜单栏图标调整位置。

## 进阶：Touch ID（指纹）支持

macOS 的 Authorization Services 授权对话框**不支持 Touch ID**（系统限制）。如果你确实需要指纹验证，有两个方向：

1. **修改系统 PAM**（全局生效，影响所有 `sudo`）：在 `/etc/pam.d/sudo` 顶部加 `auth sufficient pam_tid.so`。配置后系统级 sudo 支持指纹。
2. **SMJobBless + 特权助手**（Apple 官方推荐方案）：用 Apple Developer 证书签名，安装一个 LaunchDaemon 作为特权助手工具，通过 XPC 通信。这是最正规的 macOS 提权架构，但需要付费开发者账号。

当前版本选择**不修改系统配置**的稳定路线。

## 进阶：免密执行（可选）

若你希望开关联路由**完全不弹任何框**（包括首次也不提示），可把 `route` 命令授权给当前用户免密 `sudo`：

```bash
sudo visudo
# 追加一行（把 zhangyu 换成你的用户名）：
# zhangyu ALL=(root) NOPASSWD: /sbin/route
```

配置后，App 中的 `sudo /sbin/route ...` 会静默以 root 执行，无需任何验证。**仅在可信的单机环境下这样操作。**

## 版本记录

版本号规则：`主版本.次版本.修订号`
- **修订号（第三位）**：小更新，如修复、小功能增强。
- **次版本（第二位）**：较大更新，如新增功能模块。
- **主版本（第一位）**：颠覆性变更，如架构重写或核心逻辑改变。

---

### v1.4.0 — 2026-08-20

**真正落地 Authorization Services 凭据缓存（解决"每次都输密码"）**

- **背景**：v1.3.0 虽在注释里写了 Authorization Services，但实际 `PrivilegedRunner` 仍只调用 `osascript with administrator privileges`，而该方式**每次都重新弹窗、不缓存凭据**，所以用户依然每次都要输密码
- **修复**：改用 `AuthorizationExecuteWithPrivileges` + 进程内**复用同一个 `AuthorizationRef`**（带 `extendRights`）。首次弹一次系统授权框，macOS 在默认约 5 分钟内缓存该权限，期间反复开关 / 增删路由**不再弹窗**
- **新增「清除授权缓存」菜单项**：点击后失效当前授权，下次提权需重新验证（用于换人 / 超时兜底）
- `osascript` 降级为极端兜底（仅当 Authorization Services 不可用时）
- `applyAllEnabled()` 改回逐条调用（授权已缓存，不会每条各弹一次，且能拿到每条路由的真实结果）
- 版本号升至 1.4.0

---

### v1.3.0 — 2026-08-20

**使用 Authorization Services 优化提权体验**

- **改进**：从 `osascript` 改为使用 macOS 原生的 **Authorization Services** 框架
- **效果**：首次授权后，macOS 会自动缓存授权状态（约5分钟），期间内不会重复弹窗
- **优势**：
  - 使用系统原生授权对话框（更稳定）
  - 不修改任何系统配置
  - 授权缓存由系统自动管理
- 版本号升至 1.3.0

---

### v1.2.0 — 2026-08-20

**优化提权方式，减少重复密码输入**

- **改进**：从 `osascript` 改为 `sudo` 执行路由命令
- **效果**：首次输入密码后，**5 分钟内**再次执行路由操作不需要再输入密码
- 版本号升至 1.2.0

---

### v1.1.0 — 2026-08-20

**修复启动时路由状态检测不准确的问题**

- **问题**：启动时无法正确同步系统路由表状态，导致菜单栏中 Toggle 显示状态与实际路由表不一致
- **根因**：`route get` 命令即使路由不存在也会返回默认路由信息，原来的判断逻辑只检查命令是否成功，无法区分路由是否存在
- **修复**：`isRouteInSystemTable()` 现在检查命令输出中是否包含预期的网关地址（`gateway: <网关>`），只有网关匹配才认为路由存在
- 版本号升至 1.1.0

---

### v1.0.9 — 2026-08-15

**修复 Intel Mac（macOS 14）无法使用**

- **根因**：`build.sh` 之前用 `uname -m` 取本机架构（`arm64`），只编出单一架构的 Mach-O，纯 arm64 二进制无法在 Intel Mac 上运行
- **修复**：`build.sh` 改为默认产出**通用二进制（universal）**——分别交叉编译 `arm64` 与 `x86_64`，再用 `lipo -create` 合并
- 版本号升至 1.0.9

---

### v1.0.8 — 2026-08-15

**彻底修复启动时弹两次密码框**

- **根因**：`autoApplyOnLaunch` 的 `didSet` 和 `init()` 中的延时调用是**两条独立路径**，防重入标志在两次调用之间（0.6s 间隔）已经释放
- **修复**：彻底拆分职责——`didSet` 只负责持久化到 UserDefaults；启动自动应用只走 `init()` 的延时路径
- 版本号升至 1.0.8

---

### v1.0.7 — 2026-08-15

**修复启动时弹两次密码框 + 菜单栏图标回退系统默认**

- **两次密码根因**：`init()` 延时执行 `applyAllEnabled()` 一次 + `autoApplyOnLaunch` 的 `didSet` 在 UI 绑定初始化时间接触发第二次
- **修复**：给 `applyAllEnabled()` 加 `isApplyingOnLaunch` 防重入标志
- **菜单栏图标**：回退到系统 SF Symbol「地球」(`systemImage: "network"`)
- 版本号升至 1.0.7

---

### v1.0.0 — 2026-08-14

**初始发布**

- 菜单栏常驻应用（无 Dock 图标），点击即可管理静态路由
- 添加 / 编辑 / 删除路由配置
- 每条路由独立开关：一键启用 / 禁用
- 支持 CIDR 网段路由与主机路由
- 通过 `osascript` 提权执行 `/sbin/route` 命令
- 配置持久化保存

---

## 卸载

直接把 `RouteBar.app` 移到废纸篓即可。若想清掉配置，删除
`~/Library/Application Support/RouteBar/`。
