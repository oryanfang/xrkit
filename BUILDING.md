# Building · 从源码编译

[English](#english) · [中文](#中文)

## English

Requires [Theos](https://theos.dev) (the **roothide** fork) and GNU make 4 (`gmake` from Homebrew; macOS's own make 3.81 is too old). Theos does not support spaces in the project path.

```bash
gmake package                     # debug build (writes a debug log on the device)
gmake package FINALPACKAGE=1      # release build
```

The Makefile expects Theos at `~/theos-roothide`; change the first block of `Makefile` if yours is elsewhere.

**Install to a device.** Create `local.mk` in the project root (it is not committed) with your device's SSH address, then run `gmake package install`:

```make
THEOS_DEVICE_IP = iphone.local
```

**Settings pages.** The `.plist` files in `Prefs/Resources` are generated: edit `Prefs/make_plists.py` and run `python3 Prefs/make_plists.py`. Icons are drawn by `Prefs/make_icons.swift` (settings rows) and `Prefs/make_logo.swift` (the xrkit icon).

**Debug build.** A debug build writes a status log to `/var/mobile/Library/Caches/com.xyrith.xrkit.status` on the device: one `ok=1/0` line per feature (whether the classes and methods it hooks exist), plus CPU samples after a respring. Release builds write nothing.

**Other jailbreaks.** Only roothide is supported and tested. For rootless, set `THEOS_PACKAGE_SCHEME = rootless` and `ARCHS`/package architecture accordingly; paths that use `jbroot()` (the Control Center module loader) need the matching rootless prefix.

## 中文

需要 [Theos](https://theos.dev)（**roothide** 分支）和 GNU make 4（Homebrew 的 `gmake`；macOS 自带的 make 3.81 太旧）。Theos 不支持路径里有空格。

```bash
gmake package                     # 调试版（会在手机上写调试日志）
gmake package FINALPACKAGE=1      # 正式版
```

Makefile 默认 Theos 在 `~/theos-roothide`，路径不同请改 `Makefile` 第一段。

**装到手机。** 在项目根目录建一个 `local.mk`（不会提交），写上手机的 SSH 地址，再运行 `gmake package install`：

```make
THEOS_DEVICE_IP = iphone.local
```

**设置页。** `Prefs/Resources` 里的 `.plist` 是生成的：改 `Prefs/make_plists.py`，再运行 `python3 Prefs/make_plists.py`。图标由 `Prefs/make_icons.swift`（设置页各行）和 `Prefs/make_logo.swift`（xrkit 图标）画出来。

**调试版。** 调试版会在手机上写 `/var/mobile/Library/Caches/com.xyrith.xrkit.status`：每个功能一行 `ok=1/0`（它要 hook 的类和方法是否存在），注销后还会记录 CPU 占用。正式版什么都不写。

**其他越狱。** 只支持、也只测过 roothide。rootless 要把 `THEOS_PACKAGE_SCHEME` 改成 `rootless`、架构相应调整；用到 `jbroot()` 的路径（控制中心模块加载器）要换成 rootless 的前缀。
