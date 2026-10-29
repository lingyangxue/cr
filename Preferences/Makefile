THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:17.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GuestModePrefs
GuestModePrefs_FILES = GuestModeRootListController.m
GuestModePrefs_FRAMEWORKS = UIKit Foundation
GuestModePrefs_INSTALL_PATH = /Library/PreferenceBundles
GuestModePrefs_CFLAGS = -fobjc-arc
GuestModePrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
