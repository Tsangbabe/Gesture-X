#!/usr/bin/env bash
# Cloud macOS only. Never installs onto a handset or publishes a Release.
set -euo pipefail
: "${THEOS:?Pinned RootHide Theos is required}"
: "${OUT_DIR:?Set an artifact directory outside the source tree}"
: "${GITHUB_SHA:?Exact CI source SHA is required}"
: "${GITHUB_REPOSITORY:?Exact CI repository is required}"
test "$(uname -s)" = Darwin
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
# Only the canonical repository and its build mirror may publish an artifact
# under this identity; any other fork stops before compilation.
case "$GITHUB_REPOSITORY" in
    Tsangbaby/Gesture-X|Tsangbabe/Gesture-X) ;;
    *) printf 'Unexpected repository: %s\n' "$GITHUB_REPOSITORY" >&2; exit 1 ;;
esac
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_REF"
mkdir -p "$OUT_DIR"
{
    printf 'Repository: %s\nCommit: %s\nScheme: roothide\n' "$GITHUB_REPOSITORY" "$GITHUB_SHA"
    printf 'Theos: %s\nSDK source: %s\n' "$THEOS_REF" "$SDK_REF"
    xcodebuild -version
    xcrun swift --version
    xcrun --sdk iphoneos --show-sdk-path
    git -C "$THEOS" submodule status --recursive
    python3 -B -c 'import os,plistlib;from pathlib import Path;p=Path(os.environ["THEOS"])/"sdks/iPhoneOS16.5.sdk/SDKSettings.plist";d=plistlib.loads(p.read_bytes());print("Compile SDK metadata:", {k:d.get(k) for k in ("CanonicalName","DisplayName","Version")})'
    command -v make dpkg-deb ldid
} | tee "$OUT_DIR/TOOLCHAIN.txt"

# Explicitly compile both Makefile targets, then package the same compiled graph.
args=(THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1 INSTALL=0
      'TARGET=iphone:clang:16.5:15.0' 'ARCHS=arm64 arm64e')
make all "${args[@]}" 2>&1 | tee "$OUT_DIR/compile.log"
make package "${args[@]}" 2>&1 | tee "$OUT_DIR/package.log"
python3 -B ci/verify_package.py packages --report "$OUT_DIR/VERIFICATION.json"
python3 -B -c 'import os,shutil;from pathlib import Path;packages=list(Path("packages").glob("*.deb"));assert len(packages)==1, packages;shutil.copy2(packages[0],Path(os.environ["OUT_DIR"])/packages[0].name)'
printf '%s\n' "$GITHUB_SHA" > "$OUT_DIR/SOURCE_COMMIT.txt"
printf '%s\n' "$GITHUB_REPOSITORY" > "$OUT_DIR/SOURCE_REPOSITORY.txt"
python3 -B -c 'import hashlib,os;from pathlib import Path;p=Path(os.environ["OUT_DIR"]);d=next(p.glob("*.deb"));(p/"SHA256SUMS.txt").write_text(hashlib.sha256(d.read_bytes()).hexdigest()+"  "+d.name+"\n")'
