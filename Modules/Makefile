# xrkit 自己的控制中心模块：每个模块一个 bundle，装到 /Library/ControlCenter/Bundles（由 Tweak/CCModules.x 加载）
include $(THEOS)/makefiles/common.mk

MODULES = XRKPowerModule XRKLockModule XRKScreenshotModule XRKAutoBrightnessModule XRKClearAppsModule XRKSettingsModule XRKVPNModule XRKDarkModeModule XRKNightShiftModule XRKTrueToneModule XRKKeepAwakeModule XRKHotspotModule XRKLocationModule XRKNetSpeedModule XRKBatteryModule
BUNDLE_NAME = $(MODULES)

define XRK_MODULE_VARS
$(1)_FILES = $(1)/$(1).m
$(1)_RESOURCE_DIRS = $(1)/Resources
$(1)_INSTALL_PATH = /Library/ControlCenter/Bundles
$(1)_FRAMEWORKS = UIKit
$(1)_PRIVATE_FRAMEWORKS = ControlCenterUIKit
$(1)_CFLAGS = -fobjc-arc
endef
$(foreach m,$(MODULES),$(eval $(call XRK_MODULE_VARS,$(m))))

include $(THEOS_MAKE_PATH)/bundle.mk
