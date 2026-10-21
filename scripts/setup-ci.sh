#!/bin/bash
set -euo pipefail
: "${THEOS:?THEOS is required}"
THEOS_COMMIT=cfba89a53a05b4a1b822121158acc3669c20602f
# Source and recursive gitlinks are pinned; host Xcode is recorded by the job.
git clone --filter=blob:none --no-checkout https://github.com/roothide/theos.git "$THEOS"
git -C "$THEOS" checkout --detach "$THEOS_COMMIT"
git -C "$THEOS" submodule sync --recursive
git -C "$THEOS" submodule update --init --recursive
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_COMMIT"
test -f "$THEOS/vendor/include/roothide.h"
test -f "$THEOS/vendor/lib/iphone/roothide/libroothide.tbd"
test -f "$THEOS/vendor/lib/iphone/roothide/libsubstrate.tbd"
git -C "$THEOS" submodule status --recursive
