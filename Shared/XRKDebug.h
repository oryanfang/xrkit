#import <Foundation/Foundation.h>

// 调试日志：仅在调试版（XRK_DEBUG=1）里写入状态文件，正式版为空操作。
// 文件在手机上的真实路径：/var/mobile/Library/Caches/com.xyrith.xrkit.status
// （通过 roothide 的 SSH 查看时要加 /rootfs 前缀）
#define XRK_DEBUG_FILE @"/var/mobile/Library/Caches/com.xyrith.xrkit.status"

void XRKDebugReset(void);
void XRKDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// 调试版：注销 30 秒后开始，每 10 秒记录一次本进程 CPU 占用（100% = 占满一个核），共 2 分钟
void XRKDebugStartCPUSampling(void);

// 调试版：监听截屏请求文件（见 XRKDebug.m）
void XRKDebugStartScreenshotWatcher(void);
// 调试版：截屏时顺便执行（各模块登记，比如把视图位置写进日志）
void XRKDebugAddShotDumper(void (^dumper)(void));
