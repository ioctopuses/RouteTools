#import <Security/Security.h>
#import <stdio.h>
#import <string.h>

/// 进程内复用的授权引用。首次授权成功后缓存，
/// 之后约 5 分钟内（系统默认超时）重复调用不再弹窗。
static AuthorizationRef gAuthRef = NULL;

/// 确保管理员凭据就绪。
///
/// 首次调用会弹出**一次**系统授权对话框并把凭据缓存进 gAuthRef；
/// 之后在系统凭据有效期内（默认约 5 分钟）再次调用会静默复用，不再弹窗。
///
/// 注意：`AuthorizationCreate` 只是创建一个空的授权会话，并不等于拿到了权限。
/// 必须显式 `AuthorizationCopyRights` 申请 `system.privilege.admin`，
/// 否则每次 `AuthorizationExecuteWithPrivileges` 都可能重新走一遍认证流程。
///
/// 返回 0 表示凭据可用；-1 表示失败（*cancelled 用于区分"用户点了取消"）。
static int RBEnsureRights(int *cancelled) {
    if (gAuthRef == NULL) {
        OSStatus s = AuthorizationCreate(NULL,
                                         kAuthorizationEmptyEnvironment,
                                         kAuthorizationFlagDefaults,
                                         &gAuthRef);
        if (s != errAuthorizationSuccess) {
            if (cancelled && s == errAuthorizationCanceled) *cancelled = 1;
            return -1;
        }
    }

    AuthorizationItem item = { "system.privilege.admin", 0, NULL, 0 };
    AuthorizationRights rights = { 1, &item };

    // InteractionAllowed：必要时弹出系统授权框；
    // ExtendRights     ：授权成功后由系统缓存该权限；
    // PreAuthorize     ：预先取得授权，避免执行阶段才校验（减少二次弹窗）。
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed
                             | kAuthorizationFlagExtendRights
                             | kAuthorizationFlagPreAuthorize;

    OSStatus s = AuthorizationCopyRights(gAuthRef, &rights,
                                         kAuthorizationEmptyEnvironment,
                                         flags, NULL);
    if (s != errAuthorizationSuccess) {
        if (cancelled && s == errAuthorizationCanceled) *cancelled = 1;
        return -1;
    }
    return 0;
}

int RBRunAsRoot(const char *command, char *outBuf, size_t outSize, int *cancelled) {
    if (cancelled) *cancelled = 0;

    // 第一步：确保已取得管理员凭据（首次弹一次，之后复用缓存）
    if (RBEnsureRights(cancelled) != 0) {
        return -1;
    }

    // 第二步：以 root 执行 /bin/sh -c "<command>"
    char *args[] = { "-c", (char *)command, NULL };
    FILE *pipe = NULL;
    OSStatus s = AuthorizationExecuteWithPrivileges(
        gAuthRef, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);
    if (s != errAuthorizationSuccess) {
        if (cancelled) *cancelled = (s == errAuthorizationCanceled);
        return -1;
    }

    // 读取输出（stdout + 经调用方 2>&1 合并的 stderr）
    if (pipe != NULL && outBuf != NULL && outSize > 1) {
        size_t total = 0;
        size_t r;
        while ((r = fread(outBuf + total, 1, outSize - total - 1, pipe)) > 0) {
            total += r;
            if (total >= outSize - 1) break;
        }
        outBuf[total] = '\0';
    }
    if (pipe != NULL) fclose(pipe);
    return 0;
}

void RBResetAuth(void) {
    if (gAuthRef != NULL) {
        AuthorizationFree(gAuthRef, kAuthorizationFlagDefaults);
        gAuthRef = NULL;
    }
}

int RBWarmUpAuth(int *cancelled) {
    if (cancelled) *cancelled = 0;
    return RBEnsureRights(cancelled);
}
