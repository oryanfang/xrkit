# ---- 构建环境（roothide / Relaxin, iOS 17）----
export THEOS := $(HOME)/theos-roothide
export THEOS_PACKAGE_SCHEME = roothide
export TARGET := iphone:clang:16.5:15.0
export ARCHS = arm64 arm64e
# 装机用的手机地址写在 local.mk（不进仓库），例如：THEOS_DEVICE_IP = iphone.local
-include local.mk
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = xrkit
xrkit_FILES = $(wildcard Tweak/*.x Tweak/*.xm Tweak/*.m) $(wildcard Shared/*.m)
xrkit_CFLAGS = -fobjc-arc -IShared
ifneq ($(FINALPACKAGE),1)
xrkit_CFLAGS += -DXRK_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk

# 桌面快捷 App「xrkit」只放进调试版（正式版从「设置」进入，不占桌面）
SUBPROJECTS += Prefs Modules
ifneq ($(FINALPACKAGE),1)
SUBPROJECTS += Launcher
endif
include $(THEOS_MAKE_PATH)/aggregate.mk
