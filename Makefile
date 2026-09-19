ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CraneAdv
CraneAdv_FILES = $(wildcard Tweak.x Tweak.xm) $(wildcard TweakApp.x TweakApp.xm)
CraneAdv_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
CraneAdv_FRAMEWORKS = UIKit Foundation
CraneAdv_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
