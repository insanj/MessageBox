GO_EASY_ON_ME = 1
THEOS_PACKAGE_DIR_NAME = debs
TARGET = iphone:clang:latest:7.0
ARCHS = arm64

include theos/makefiles/common.mk

TWEAK_NAME = messagebox
messagebox_CFLAGS = -fobjc-arc -IXcode-Theos
messagebox_OBJC_FILES = MBChatHeadWindow.m Tweak.xmi
messagebox_FRAMEWORKS = Foundation CoreGraphics QuartzCore UIKit
messagebox_LIBRARIES = substrate rocketbootstrap

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += messageboxpreferences
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-after-install::
	install.exec "killall -9 backboardd"
