ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TapLock
TapLock_FILES = Shared/Preferences.swift Sources/AppAction.swift Sources/ControlCenterAction.swift Sources/NotificationCenterAction.swift Sources/ScreenshotAction.swift Sources/AppSwitcherAction.swift Sources/MediaPlayPauseAction.swift Sources/FlashlightAction.swift Sources/SystemMuteAction.swift Sources/PrivateAPI.swift Sources/LockAction.swift Sources/HomeDoubleTap.swift Sources/BottomSwipeGeometry.swift Sources/BottomSwipeUp.swift Sources/NativeHomeGestureGate.swift Sources/NativeHook.swift Sources/Bootstrap.swift
TapLock_FRAMEWORKS = Foundation UIKit
TapLock_LIBRARIES = substrate
TapLock_SWIFT_VERSION = 5
TapLock_SWIFTFLAGS = -IInterfaces -enable-experimental-feature SymbolLinkageMarkers

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
