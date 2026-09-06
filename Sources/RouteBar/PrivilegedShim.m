#import <Security/Security.h>
#import <stdio.h>
#import <string.h>

/// 进程内复用的授权引用。首次授权成功后缓存，
/// 之后约 5 分钟内（系统默认超时）重复调用不再弹窗。
static AuthorizationRef gAuthRef = NULL;

int RBRunAsRoot(const char *command, char *outBuf, size_t outSize, int *cancelled) {
    if (cancelled) *cancelled = 0;

    // 首次：创建 AuthorizationRef。
    // kAuthorizationFlagInteractionAllowed：允许弹出系统授权对话框；
    // kAuthorizationFlagExtendRights：授权成功后扩展/缓存该权限（约 5 分钟）。
    if (gAuthRef == NULL) {
        OSStatus s = AuthorizationCreate(
            NULL,
            kAuthorizationEmptyEnvironment,
            kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights,
            &gAuthRef);
        if (s != errAuthorizationSuccess) {
            if (cancelled) *cancelled = (s == errAuthorizationCanceled);
            return -1;
        }
    }

    // 以 root 执行 /bin/sh -c "<command>"
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
