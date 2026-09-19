ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CraneAdv
CraneAdv_FILES = Tweak.x TweakApp.x
CraneAdv_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CraneAdv_FRAMEWORKS = UIKit Foundation
CraneAdv_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += craneadvprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
