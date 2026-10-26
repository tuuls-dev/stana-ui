#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <consumer-package> <executable-product> <bundle-id>" >&2
    exit 2
fi
task_package=$(cd "$1" && pwd)
task_product=$2
task_bundle_id=$3
case "$task_product" in *[!A-Za-z0-9_-]*|'') echo 'Invalid executable product name' >&2; exit 2;; esac
case "$task_bundle_id" in *[!A-Za-z0-9.-]*|'') echo 'Invalid bundle identifier' >&2; exit 2;; esac
task_root=$(cd "$(dirname "$0")/.." && pwd)
swift build --package-path "$task_package" -c release --product "$task_product"
task_bin=$(swift build --package-path "$task_package" -c release --show-bin-path)
mkdir -p "$task_root/dist"
task_output="$task_root/dist/$task_product.app"
task_stage=$(mktemp -d "$task_root/dist/.stana-package.XXXXXX")
cleanup() {
    if [ -d "$task_stage/previous.app" ] && [ ! -e "$task_output" ]; then
        mv "$task_stage/previous.app" "$task_output"
    fi
    rm -rf "$task_stage"
}
trap cleanup EXIT HUP INT TERM
task_app="$task_stage/$task_product.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources" "$task_app/Contents/Frameworks"
cp "$task_bin/$task_product" "$task_app/Contents/MacOS/$task_product"
xcrun swift-stdlib-tool --copy --scan-executable "$task_app/Contents/MacOS/$task_product" --destination "$task_app/Contents/Frameworks" --platform macosx
for task_resource in "$task_bin"/*.bundle; do
    [ -d "$task_resource" ] || continue
    cp -R "$task_resource" "$task_app/Contents/Resources/"
done
python3 - "$task_app" "$task_product" "$task_bundle_id" <<'PY'
import plistlib,sys
from pathlib import Path
app,product,identity=sys.argv[1:]
info={'CFBundleName':product,'CFBundleDisplayName':product,'CFBundleExecutable':product,
      'CFBundleIdentifier':identity,'CFBundlePackageType':'APPL','CFBundleVersion':'1',
      'CFBundleShortVersionString':'0.1.0','LSMinimumSystemVersion':'14.0',
      'NSHighResolutionCapable':True}
with (Path(app)/'Contents/Info.plist').open('wb') as f: plistlib.dump(info,f)
PY
if [ -e "$task_output" ]; then mv "$task_output" "$task_stage/previous.app"; fi
mv "$task_app" "$task_output"
echo "$task_output"
