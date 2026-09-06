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

#ifdef __cplusplus
}
#endif

#endif /* PrivilegedShim_h */
