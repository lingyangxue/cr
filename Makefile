ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CraneIcon
CraneIcon_FILES = Tweak.x
CraneIcon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
CraneIcon_FRAMEWORKS = UIKit Foundation
CraneIcon_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
