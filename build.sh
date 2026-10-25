#!/bin/sh
set -eu

source_dir=$(cd "$(dirname "$0")" && pwd)
app="$HOME/Applications/LaserJet 1020.app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
bundle="$staging/LaserJet 1020.app"

mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos14 \
  -o "$bundle/Contents/MacOS/LaserJet1020" \
  "$source_dir/main.swift" "$source_dir/Model.swift" "$source_dir/StepViews.swift" "$source_dir/QueueViews.swift" "$source_dir/Pages.swift" "$source_dir/Printing.swift" "$source_dir/Queue.swift" "$source_dir/AutoLoad.swift"
cp "$source_dir/Info.plist" "$bundle/Contents/Info.plist"
cp "/Library/Printers/hp/laserjet/hplaserjetzjs.bundle/Contents/Resources/HP LaserJet 1022.icns" "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$bundle"

rm -rf "$app"
mkdir -p "$(dirname "$app")"
mv "$bundle" "$app"
mkdir -p "$HOME/Library/PDF Services"
ln -sfn "$app" "$HOME/Library/PDF Services/Open in LaserJet 1020"
echo "Installed $app"
