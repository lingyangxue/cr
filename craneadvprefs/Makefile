ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CraneAdvPrefs
CraneAdvPrefs_FILES = CraneRootListController.m \
                      CraneAppListController.m \
                      CraneAppDetailController.m \
                      CraneContainerDetailController.m
CraneAdvPrefs_INSTALL_PATH = /Library/PreferenceBundles
CraneAdvPrefs_FRAMEWORKS = UIKit
CraneAdvPrefs_PRIVATE_FRAMEWORKS = Preferences
CraneAdvPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
