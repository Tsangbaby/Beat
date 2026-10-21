# Phase-one reconstruction build candidate; not a functional restoration.
TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Stheno SthenoCamera SthenoKeyboard

Stheno_FILES = $(shell find Sources/Stheno -name '*.swift') Sources/Support/SthenoPaths.mm Sources/Support/SthenoMethodABI.mm Sources/Support/SthenoTypeEncoding.c
Stheno_SWIFT_BRIDGING_HEADER = Stheno-Bridging-Header.h
Stheno_SWIFT_VERSION = 5
Stheno_CFLAGS = -fobjc-arc
Stheno_FRAMEWORKS = UIKit SwiftUI QuartzCore IOKit
Stheno_LIBRARIES = substrate roothide
# Private ObjC classes are declared in the bridge, and supplied by the host.
# No missing Swift framework import is hidden by this linker option.
Stheno_LDFLAGS = -Wl,-undefined,dynamic_lookup

SthenoCamera_FILES = Sources/SthenoCamera/SthenoCamera.xm Sources/Support/SthenoPaths.mm Sources/Support/SthenoMethodABI.mm Sources/Support/SthenoTypeEncoding.c
SthenoCamera_CFLAGS = -fobjc-arc
SthenoCamera_FRAMEWORKS = Foundation
SthenoCamera_LIBRARIES = substrate roothide

SthenoKeyboard_FILES = Sources/SthenoKeyboard/SthenoKeyboard.xm Sources/Support/SthenoPaths.mm Sources/Support/SthenoMethodABI.mm Sources/Support/SthenoTypeEncoding.c
SthenoKeyboard_CFLAGS = -fobjc-arc
SthenoKeyboard_FRAMEWORKS = UIKit Foundation
SthenoKeyboard_LIBRARIES = substrate roothide

include $(THEOS_MAKE_PATH)/tweak.mk
