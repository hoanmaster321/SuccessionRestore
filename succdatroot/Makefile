ARCHS = armv7 armv7s arm64 arm64e
TARGET = iphone::10.3:7.0
include $(THEOS)/makefiles/common.mk

TOOL_NAME = succdatroot
succdatroot_FILES = main.c
succdatroot_CODESIGN_FLAGS = -Sent.plist

include $(THEOS_MAKE_PATH)/tool.mk
