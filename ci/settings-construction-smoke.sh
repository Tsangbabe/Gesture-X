#!/bin/bash
# Execute the production Swift Settings constructor in UIKit, not a text mock.
# Preferences.framework here is an isolated native superclass/factory fixture.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
BASELINE=72826b2a558b03e20a7dd5e98047dfdecc489202
HIERARCHY_BASELINE=94b384d64ce44705e754f4695c98661110db76ff
OPEN_APP_BASELINE=7f35f9e51aa9d61d8bd052f0ab6b85127313d326
ICON_BASELINE=cb3f53b27e102b74cea93bf9a44d476cb873477a
CONTROL_CENTER_BASELINE=b8d6994be7defcc37ceac3bb158c5526c952ac3a
NOTIFICATION_CENTER_BASELINE=1b6615b46242abeb5b8ef0f0bf4afba14db18e2a
SCREENSHOT_BASELINE=078b98fb67582422a577b70ae3335ecc0d1e2ab9
APP_SWITCHER_BASELINE=fc79961bd6a1003aab36f43d0ab010a9bb6b1859
REFERENCE_BASELINE=f3a2e138fa9ac93d250645e9c66226b074d429ee
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-settings.XXXXXX")"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-ios15.0-simulator"
DEVICE=""
RESULTS="$RUNNER_TEMP/SETTINGS_CONSTRUCTION_TESTS.txt"
REFERENCE_RESULTS="$RUNNER_TEMP/REFERENCE_SETTINGS_TESTS.txt"
cleanup() {
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" || true
        xcrun simctl delete "$DEVICE" || true
    fi
}
trap cleanup EXIT

# Use an already installed Xcode-16-compatible runtime; never download an OS.
xcrun simctl list runtimes --json > "$WORK/runtimes.json"
xcrun simctl list devicetypes --json > "$WORK/types.json"
RUNTIME="$(python3 - "$WORK/runtimes.json" <<'PY'
import json, sys
items = [r for r in json.load(open(sys.argv[1]))['runtimes']
         if r.get('isAvailable') and r['name'].startswith('iOS ')
         and r['version'].split('.')[0] == '18']
if not items:
    raise SystemExit('No installed iOS 18 simulator runtime for Xcode 16.4')
print(max(items, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier'])
PY
)"
DEVICE_TYPE="$(python3 - "$WORK/types.json" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))['devicetypes']
print(next(d['identifier'] for d in items if d['name'] == 'iPhone 16'))
PY
)"
DEVICE="$(xcrun simctl create "TapLock constructor ${GITHUB_RUN_ID:-test}" "$DEVICE_TYPE" "$RUNTIME")"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b

# No production build ever sees this fixture framework or the Objective-C shim.
FRAMEWORK="$WORK/frameworks/Preferences.framework"
mkdir -p "$FRAMEWORK"
xcrun clang -target "$TARGET" -isysroot "$SDK" -fobjc-arc -dynamiclib \
    "$ROOT/Tests/SettingsConstructionFixture.m" -framework UIKit -framework Foundation \
    -install_name @rpath/Preferences.framework/Preferences -o "$FRAMEWORK/Preferences"
python3 - "$FRAMEWORK/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='Preferences', CFBundleName='Preferences',
        CFBundleIdentifier='com.tsangbaby.taplock.test-host-fixture',
        CFBundlePackageType='FMWK', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='15.0'), f)
PY
codesign --force --sign - "$FRAMEWORK"

# Freeze the actual failing source, not a hand-rewritten version of the bug.
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
OLD="$WORK/baseline-source"
for path in Shared/Preferences.swift Preferences/SettingsController.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$OLD/$(dirname "$path")"
    git -C "$ROOT" show "$BASELINE:$path" > "$OLD/$path"
done
git -C "$ROOT" fetch --no-tags --depth=1 origin "$HIERARCHY_BASELINE"
STABLE="$WORK/accepted-source"
for path in Shared/Preferences.swift Preferences/SettingsController.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$STABLE/$(dirname "$path")"
    git -C "$ROOT" show "$HIERARCHY_BASELINE:$path" > "$STABLE/$path"
done
python3 - "$RESULTS" "$BASELINE" "$RUNTIME" "$TARGET" <<'PY'
import sys
with open(sys.argv[1], 'w') as f:
    f.write('Boundary: real production Swift + UIKit, native Preferences superclass fixture; NOT device Settings\n')
    f.write('Frozen failing source: ' + sys.argv[2] + '\n')
    f.write('Runtime: ' + sys.argv[3] + '\nTarget: ' + sys.argv[4] + '\n')
PY

git -C "$ROOT" fetch --no-tags --depth=1 origin "$OPEN_APP_BASELINE"
APP_OLD="$WORK/accepted-lock-ui"
for path in Shared/Preferences.swift Preferences/SettingsController.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$APP_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$OPEN_APP_BASELINE:$path" > "$APP_OLD/$path"
done

# Freeze the actual version whose picker had no image assignment.
git -C "$ROOT" fetch --no-tags --depth=1 origin "$ICON_BASELINE"
ICON_OLD="$WORK/no-app-icons"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$ICON_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$ICON_BASELINE:$path" > "$ICON_OLD/$path"
done

git -C "$ROOT" fetch --no-tags --depth=1 origin "$CONTROL_CENTER_BASELINE"
CC_OLD="$WORK/accepted-no-control-center"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$CC_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$CONTROL_CENTER_BASELINE:$path" > "$CC_OLD/$path"
done

git -C "$ROOT" fetch --no-tags --depth=1 origin "$NOTIFICATION_CENTER_BASELINE"
NC_OLD="$WORK/accepted-no-notification-center"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$NC_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$NOTIFICATION_CENTER_BASELINE:$path" > "$NC_OLD/$path"
done

git -C "$ROOT" fetch --no-tags --depth=1 origin "$SCREENSHOT_BASELINE"
SCREENSHOT_OLD="$WORK/accepted-no-screenshot"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$SCREENSHOT_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$SCREENSHOT_BASELINE:$path" > "$SCREENSHOT_OLD/$path"
done

git -C "$ROOT" fetch --no-tags --depth=1 origin "$APP_SWITCHER_BASELINE"
APP_SWITCHER_OLD="$WORK/accepted-no-app-switcher"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$APP_SWITCHER_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$APP_SWITCHER_BASELINE:$path" > "$APP_SWITCHER_OLD/$path"
done
python3 - "$APP_SWITCHER_OLD" "$RESULTS" <<'PY'
import hashlib
import sys
from pathlib import Path
root = Path(sys.argv[1])
for path, digest in {
    'Shared/Preferences.swift': '27120df2fef94c5120b0f4a59db02a1be1629e6489ac30612e67891f886ca62f',
    'Preferences/SettingsController.swift': 'd11128abc1896375f99d6a7f4c7a941ecab05ef2d0b476de2d174a3df99b3876',
}.items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest, path
with open(sys.argv[2], 'a') as f:
    f.write('APP_SWITCHER_UIKIT_BASELINE_BYTES_VERIFIED: exact unmodified device-accepted 0.1.7 preferences and Settings controller\n')
PY

# Preserve every historical UIKit assertion on the exact accepted 0.1.8 UI.
# The new resource-driven UI has its own same-harness behavioral RED/GREEN.
git -C "$ROOT" fetch --no-tags --depth=1 origin "$REFERENCE_BASELINE"
ACCEPTED_UI="$WORK/accepted-018-ui"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$ACCEPTED_UI/$(dirname "$path")"
    git -C "$ROOT" show "$REFERENCE_BASELINE:$path" > "$ACCEPTED_UI/$path"
done
python3 - "$ACCEPTED_UI" "$ROOT" "$RESULTS" "$REFERENCE_RESULTS" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
accepted, root = map(Path, sys.argv[1:3])
manifest = json.loads((root / 'Tests/settings_layout_baseline.json').read_text())
paths = sorted(path for path in accepted.rglob('*') if path.is_file())
assert len(paths) == 7
for path in paths:
    relative = str(path.relative_to(accepted))
    assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest['frozen'][relative], relative
with open(sys.argv[3], 'a') as stream:
    stream.write('REFERENCE_UIKIT_BASELINE_BYTES_VERIFIED: frozen 0.1.8 UI plus unchanged Shared/icon/host dependencies\n')
with open(sys.argv[4], 'w') as stream:
    stream.write('REFERENCE_UIKIT_SOURCE_COMMIT: ' + subprocess.check_output(
        ['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip() + '\n')
    stream.write('Boundary: real UIKit, native Preferences superclass fixture; NOT handset Settings or pixel parity\n')
    stream.write('Behavioral RED source: ' + manifest['baseline'] + '\n')
    for relative in ('Tests/ReferenceSettingsApp.swift', 'Preferences/Resources/SettingsReference.json'):
        stream.write(relative + ' SHA256: ' + hashlib.sha256((root / relative).read_bytes()).hexdigest() + '\n')
PY

run_case() {
    local source_root="$1" label="$2" mode="$3" marker="$4"
    local app="$WORK/$label.app" bundle="com.tsangbaby.taplock.constructor-$label"
    mkdir -p "$app/Frameworks"
    cp -R "$FRAMEWORK" "$app/Frameworks/"
    python3 - "$app/Info.plist" "$bundle" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='SettingsConstruction',
        CFBundleIdentifier=sys.argv[2], CFBundleName='SettingsConstruction',
        CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='15.0',
        LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={}), f)
PY
    local compile_sources=("$source_root/Shared/Preferences.swift" "$source_root/Preferences/SettingsController.swift")
    local compile_flags=(-parse-as-library -swift-version 5)
    if [ "$label" = app-baseline ] || [ "$label" = icon-baseline ] || [ "$label" = control-center-baseline ] || [ "$label" = notification-center-baseline ] || [ "$label" = screenshot-baseline ] || [ "$label" = app-switcher-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DOPEN_APP_ROWS)
    fi
    if [ "$label" = icon-baseline ] || [ "$label" = control-center-baseline ] || [ "$label" = notification-center-baseline ] || [ "$label" = screenshot-baseline ] || [ "$label" = app-switcher-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DOPEN_APP_FEATURE -DAPP_ICONS)
        compile_sources+=("$source_root/Shared/Applications.swift" "$source_root/Sources/PrivateAPI.swift")
    fi
    if [ "$label" = control-center-baseline ] || [ "$label" = notification-center-baseline ] || [ "$label" = screenshot-baseline ] || [ "$label" = app-switcher-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DCONTROL_CENTER_ROWS)
        compile_sources+=("$source_root/Preferences/ApplicationIcons.swift")
    fi
    if [ "$label" = notification-center-baseline ] || [ "$label" = screenshot-baseline ] || [ "$label" = app-switcher-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DNOTIFICATION_CENTER_ROWS)
    fi
    if [ "$label" = screenshot-baseline ] || [ "$label" = app-switcher-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DSCREENSHOT_ROWS)
    fi
    if [ "$label" = fixed ]; then
        compile_flags+=(-DAPP_ICON_LOADER_TESTS -DCONTROL_CENTER_FEATURE -DNOTIFICATION_CENTER_FEATURE -DSCREENSHOT_FEATURE -DAPP_SWITCHER_FEATURE)
    fi
    if [ "$label" = app-switcher-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DAPP_SWITCHER_ROWS)
    fi
    xcrun swiftc "${compile_flags[@]}" -target "$TARGET" -sdk "$SDK" \
        -I "$source_root/Interfaces" -F "$WORK/frameworks" \
        -import-objc-header "$ROOT/Tests/SettingsConstructionFixture.h" \
        "${compile_sources[@]}" \
        "$ROOT/Tests/SettingsConstructionApp.swift" \
        -Xlinker -rpath -Xlinker @executable_path/Frameworks \
        -o "$app/SettingsConstruction"
    codesign --force --sign - "$app"
    xcrun simctl install "$DEVICE" "$app"
    python3 - "$DEVICE" "$bundle" "$mode" "$marker" "$RESULTS" <<'PY'
import subprocess, sys
from pathlib import Path

def launch(device, bundle, mode):
    return subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
                           device, bundle, mode],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)

p = launch(sys.argv[1], sys.argv[2], sys.argv[3])
# simctl can return before the app finishes its first run loop on a loaded
# simulator, which loses the app's terminal marker. Retry the transport twice;
# the exact-marker gate below is unchanged and every attempt stays in the log.
for attempt in range(2):
    if not p.returncode and sys.argv[4] in p.stdout:
        break
    print('CI-only relaunch after incomplete transport:', attempt + 1, p.returncode, flush=True)
    print(p.stdout, flush=True)
    p = launch(sys.argv[1], sys.argv[2], sys.argv[3])
print(p.stdout, flush=True)
print('simctl launch exit:', p.returncode, flush=True)
# simctl reports transport success, not the app's exit status. Every case
# still requires its own exact terminal assertion/completion marker.
if p.returncode or sys.argv[4] not in p.stdout:
    # This is CI-harness evidence only, collected before the disposable
    # simulator is deleted. Never weaken the exact-marker failure gate.
    roots = [Path.home() / 'Library/Logs/DiagnosticReports',
             Path.home() / 'Library/Developer/CoreSimulator/Devices' / sys.argv[1] /
             'data/Library/Logs/CrashReporter']
    reports = [path for root in roots for path in root.glob('SettingsConstruction*') if path.is_file()]
    for path in sorted(reports, key=lambda item: item.stat().st_mtime, reverse=True)[:2]:
        print('SettingsConstruction crash report:', path.name, flush=True)
        print(path.read_text(errors='replace')[:24000], flush=True)
    try:
        logs = subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], 'log', 'show',
                               '--last', '3m', '--style', 'compact', '--predicate',
                               'process == "SettingsConstruction"'], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=30)
        print(logs.stdout[-24000:], flush=True)
    except subprocess.TimeoutExpired:
        print('CI-only SettingsConstruction log read timed out', flush=True)
    raise SystemExit('Constructor test failed: missing verified completion marker / nonzero exit')
with open(sys.argv[5], 'a') as f:
    f.write(p.stdout + '\n')
PY
    # Free the simulator slot before the next case; a lingering app changes
    # launch timing for the one that follows.
    xcrun simctl terminate "$DEVICE" "$bundle" >/dev/null 2>&1 || true
}
run_case "$OLD" baseline --expect-legacy-failure BASELINE_EXPECTED_FAILURE
run_case "$STABLE" accepted --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: root must link to 主屏幕的手势'
run_case "$APP_OLD" app-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: unimplemented actions must not be exposed'
run_case "$ICON_OLD" icon-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: App picker icon missing'
run_case "$CC_OLD" control-center-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: Control Center action row missing'
run_case "$NC_OLD" notification-center-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: Notification Center action row missing'
run_case "$SCREENSHOT_OLD" screenshot-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: Screenshot action row missing'
run_case "$APP_SWITCHER_OLD" app-switcher-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: App Switcher action row missing'
run_case "$ACCEPTED_UI" fixed --expect-fixed FIXED_CONSTRUCTION_PASS

MEDIA_SETTINGS_BASELINE=1e2b7ef11a5f743b8db122c02d9a5478d2f20bfa
git -C "$ROOT" fetch --no-tags --depth=1 origin "$MEDIA_SETTINGS_BASELINE"
MEDIA_UI="$WORK/accepted-019-ui"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap Preferences/Resources/SettingsReference.json; do
    mkdir -p "$MEDIA_UI/$(dirname "$path")"
    git -C "$ROOT" show "$MEDIA_SETTINGS_BASELINE:$path" > "$MEDIA_UI/$path"
done
python3 - "$MEDIA_UI" "$ROOT" "$REFERENCE_RESULTS" <<'PY'
import hashlib, json, sys
from pathlib import Path
accepted, root = map(Path, sys.argv[1:3])
frozen = json.loads((root / 'Tests/media_play_pause_baseline.json').read_text())
paths = [p for p in accepted.rglob('*') if p.is_file()]
assert len(paths) == 8
for path in paths:
    relative = str(path.relative_to(accepted))
    assert hashlib.sha256(path.read_bytes()).hexdigest() == frozen['frozen'][relative], relative
with open(sys.argv[3], 'a') as stream:
    stream.write('MEDIA_UIKIT_BASELINE_BYTES_VERIFIED: eight exact accepted 0.1.9 source/resource inputs\n')
PY

TRACK_SETTINGS_BASELINE=cd480bfe09c7080b0523e1c73910b8af617edb01
git -C "$ROOT" fetch --no-tags --depth=1 origin "$TRACK_SETTINGS_BASELINE"
TRACK_UI="$WORK/accepted-0110-ui"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap Preferences/Resources/SettingsReference.json; do
    mkdir -p "$TRACK_UI/$(dirname "$path")"
    git -C "$ROOT" show "$TRACK_SETTINGS_BASELINE:$path" > "$TRACK_UI/$path"
done
python3 - "$TRACK_UI" "$ROOT" "$REFERENCE_RESULTS" <<'PY'
import hashlib, json, sys
from pathlib import Path
accepted, root = map(Path, sys.argv[1:3])
frozen = json.loads((root / 'Tests/media_tracks_baseline.json').read_text())
assert frozen['baseline'] == 'cd480bfe09c7080b0523e1c73910b8af617edb01'
paths = [p for p in accepted.rglob('*') if p.is_file()]
assert len(paths) == 8
for path in paths:
    relative = str(path.relative_to(accepted))
    assert hashlib.sha256(path.read_bytes()).hexdigest() == frozen['frozen'][relative], relative
with open(sys.argv[3], 'a') as stream:
    stream.write('MEDIA_TRACKS_UIKIT_BASELINE_BYTES_VERIFIED: eight exact accepted 0.1.10 source/resource inputs\n')
PY

# Fetch explicitly: a shallow candidate checkout need not contain the frozen
# 0.1.11 commit. Compile its unmodified controller/preferences with its OWN
# resource, never the candidate's newly closed nine-action schema.
FLASHLIGHT_SETTINGS_BASELINE="$(python3 - "$ROOT/Tests/flashlight_baseline.json" <<'PY'
import json, sys
frozen = json.load(open(sys.argv[1]))
assert frozen['baseline'] == '925df18141606b75f71c77ddd998ad2baa237efe'
assert len(frozen['frozen']) == 26
print(frozen['baseline'])
PY
)"
git -C "$ROOT" fetch --no-tags --depth=1 origin "$FLASHLIGHT_SETTINGS_BASELINE"
FLASHLIGHT_UI="$WORK/accepted-0111-ui"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap Preferences/Resources/SettingsReference.json; do
    mkdir -p "$FLASHLIGHT_UI/$(dirname "$path")"
    git -C "$ROOT" show "$FLASHLIGHT_SETTINGS_BASELINE:$path" > "$FLASHLIGHT_UI/$path"
done
python3 - "$FLASHLIGHT_UI" "$ROOT" "$REFERENCE_RESULTS" <<'PY'
import hashlib, json, sys
from pathlib import Path
accepted, root = map(Path, sys.argv[1:3])
frozen = json.loads((root / 'Tests/flashlight_baseline.json').read_text())
assert frozen['baseline'] == '925df18141606b75f71c77ddd998ad2baa237efe'
assert len(frozen['frozen']) == 26
paths = [p for p in accepted.rglob('*') if p.is_file()]
assert len(paths) == 8
for path in paths:
    relative = str(path.relative_to(accepted))
    assert hashlib.sha256(path.read_bytes()).hexdigest() == frozen['frozen'][relative], relative
with open(sys.argv[3], 'a') as stream:
    stream.write('FLASHLIGHT_UIKIT_BASELINE_BYTES_VERIFIED: eight exact accepted 0.1.11 source/resource inputs\n')
PY

# Freeze the device-accepted 0.1.12 source/resource bytes, not a reconstructed
# controller or the current ten-action schema. The inverse fixture is shared
# with the native regression gate and must retain all 27 production digests.
SYSTEM_MUTE_SETTINGS_BASELINE="$(python3 - "$ROOT/Tests/system_mute_baseline.json" <<'PY'
import json, sys
frozen = json.load(open(sys.argv[1]))
assert frozen['baseline'] == '0cc50fbd3e82c336f89394f80cb298aa150a1c70'
assert len(frozen['frozen']) == 27
print(frozen['baseline'])
PY
)"
git -C "$ROOT" fetch --no-tags --depth=1 origin "$SYSTEM_MUTE_SETTINGS_BASELINE"
SYSTEM_MUTE_UI="$WORK/accepted-0112-ui"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap Preferences/Resources/SettingsReference.json; do
    mkdir -p "$SYSTEM_MUTE_UI/$(dirname "$path")"
    git -C "$ROOT" show "$SYSTEM_MUTE_SETTINGS_BASELINE:$path" > "$SYSTEM_MUTE_UI/$path"
done
python3 - "$SYSTEM_MUTE_UI" "$ROOT" "$REFERENCE_RESULTS" <<'PY'
import hashlib, json, sys
from pathlib import Path
accepted, root = map(Path, sys.argv[1:3])
frozen = json.loads((root / 'Tests/system_mute_baseline.json').read_text())
assert frozen['baseline'] == '0cc50fbd3e82c336f89394f80cb298aa150a1c70'
assert len(frozen['frozen']) == 27
paths = [p for p in accepted.rglob('*') if p.is_file()]
assert len(paths) == 8
assert {str(path.relative_to(accepted)) for path in paths} == {
    'Shared/Preferences.swift', 'Shared/Applications.swift', 'Sources/PrivateAPI.swift',
    'Preferences/SettingsController.swift', 'Preferences/ApplicationIcons.swift',
    'Interfaces/TapLockPreferencesHost/PSViewController.h',
    'Interfaces/TapLockPreferencesHost/module.modulemap',
    'Preferences/Resources/SettingsReference.json',
}
for path in paths:
    relative = str(path.relative_to(accepted))
    assert hashlib.sha256(path.read_bytes()).hexdigest() == frozen['frozen'][relative], relative
with open(sys.argv[3], 'a') as stream:
    stream.write('SYSTEM_MUTE_UIKIT_BASELINE_BYTES_VERIFIED: eight exact accepted 0.1.12 source/resource inputs\n')
PY

run_reference_case() {
    local source_root="$1" label="$2" mode="$3"
    local app="$WORK/$label.app" bundle="com.tsangbaby.taplock.$label"
    mkdir -p "$app/Frameworks"
    cp -R "$FRAMEWORK" "$app/Frameworks/"
    if [ "$label" = media-baseline ] || [ "$label" = track-baseline ] || [ "$label" = flashlight-baseline ] || [ "$label" = system-mute-baseline ]; then
        cp "$source_root/Preferences/Resources/SettingsReference.json" "$app/SettingsReference.json"
    else
        cp "$ROOT/Preferences/Resources/SettingsReference.json" "$app/SettingsReference.json"
    fi
    # macOS /bin/bash 3.2 treats an empty array expansion under nounset as
    # unbound. Use one always-present scalar; each baseline lacks newer enums.
    local compile_flag=-DREFERENCE_SETTINGS_CURRENT
    if [ "$label" = system-mute-baseline ]; then
        compile_flag=-DSYSTEM_MUTE_BASELINE
    elif [ "$label" = flashlight-baseline ]; then
        compile_flag=-DFLASHLIGHT_BASELINE
    elif [ "$label" = track-baseline ]; then
        compile_flag=-DMEDIA_TRACKS_UNAVAILABLE
    elif [ "$label" != reference-fixed ]; then
        compile_flag=-DMEDIA_PLAY_PAUSE_UNAVAILABLE
    fi
    python3 - "$app/Info.plist" "$bundle" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump(dict(CFBundleExecutable='ReferenceSettings', CFBundleIdentifier=sys.argv[2],
        CFBundleName='ReferenceSettings', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='15.0', LSRequiresIPhoneOS=True,
        UIDeviceFamily=[1], UILaunchScreen={}), stream)
PY
    xcrun swiftc -parse-as-library -swift-version 5 "$compile_flag" -target "$TARGET" -sdk "$SDK" \
        -I "$source_root/Interfaces" -F "$WORK/frameworks" \
        -import-objc-header "$ROOT/Tests/SettingsConstructionFixture.h" \
        "$source_root/Shared/Preferences.swift" "$source_root/Shared/Applications.swift" \
        "$source_root/Sources/PrivateAPI.swift" "$source_root/Preferences/ApplicationIcons.swift" \
        "$source_root/Preferences/SettingsController.swift" "$ROOT/Tests/ReferenceSettingsApp.swift" \
        -Xlinker -rpath -Xlinker @executable_path/Frameworks -o "$app/ReferenceSettings"
    codesign --force --sign - "$app"
    xcrun simctl install "$DEVICE" "$app"
    python3 -B "$ROOT/ci/reference_settings_guard.py" "$DEVICE" "$bundle" "$mode" "$REFERENCE_RESULTS"
}
run_reference_case "$ACCEPTED_UI" reference-baseline --expect-reference-baseline-failure
run_reference_case "$MEDIA_UI" media-baseline --expect-media-baseline-failure
run_reference_case "$TRACK_UI" track-baseline --expect-track-baseline-failure
run_reference_case "$FLASHLIGHT_UI" flashlight-baseline --expect-flashlight-baseline-failure
run_reference_case "$SYSTEM_MUTE_UI" system-mute-baseline --expect-system-mute-baseline-failure
run_reference_case "$ROOT" reference-fixed --expect-reference-fixed
bash "$ROOT/ci/native-startup-smoke.sh" "$DEVICE"
