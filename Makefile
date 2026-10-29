THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:17.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GuestMode
GuestMode_FILES = Tweak.xm GuestModeState.m
GuestMode_FRAMEWORKS = Foundation UIKit
GuestMode_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
