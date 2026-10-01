#ifndef PrivilegedShim_h
#define PrivilegedShim_h

#import <Security/Security.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 以 root 身份执行 shell 命令（经由 Authorization Services，进程内缓存凭据）。
/// @param command   要执行的命令（由 /bin/sh -c 执行）
/// @param outBuf    输出缓冲区（stdout + stderr 合并写入），可为 NULL
/// @param outSize   输出缓冲区大小（字节）
/// @param cancelled 输出参数：若用户取消授权则置 1
/// @return 0 表示已成功派发执行；<0 表示授权失败（此时命令未执行）
int RBRunAsRoot(const char *command, char *outBuf, size_t outSize, int *cancelled);

/// 清除进程内缓存的 AuthorizationRef，使下次提权需重新验证。
void RBResetAuth(void);

/// 主动取得管理员凭据（不执行任何命令）。
///
/// 设置页「申请授权」用它**预热**凭据：用户点一下、输一次密码，之后约 5 分钟
/// 内的路由增删改都走系统凭据缓存，不再弹窗。
/// @param cancelled 输出参数：若用户取消授权则置 1
/// @return 0 表示凭据可用；-1 表示失败
int RBWarmUpAuth(int *cancelled);

#ifdef __cplusplus
}
#endif

#endif /* PrivilegedShim_h */
