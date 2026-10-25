#!/bin/bash
set -euo pipefail

repo=https://github.com/kyashrathore/laserjet-1020.git
home_dir="$HOME/Library/Printers/HP LaserJet 1020"
checkout="$home_dir/App"
firmware="$home_dir/sihp1020.dl"
queue=HP_LaserJet_1020
ppd="Library/Printers/PPDs/Contents/Resources/HP LaserJet 1022.gz"

driver_url=https://updates.cdn-apple.com/2021/macos/071-46903-20211101-0BD2764A-901C-41BA-9573-C17B8FDC4D90/HewlettPackardPrinterDrivers.dmg
driver_sha=523836b630431bc39b0170a17099099d6f821ef62ff29e6ec64ebb69b9954133
firmware_url=https://foo2zjs.linkevich.net/foo2zjs/firmware/sihp1020.tar.gz
firmware_tar_sha=ec4665c6704c2db3cfaeb71bb06f1bbc9449c030504b04f533a84bdfae89f966
firmware_sha=133b21fe0cb24bfe53e2eff2f00a82cce4beb970749049661ade7a6801f22663
foo2zjs_url=https://foo2zjs.linkevich.net/foo2zjs/foo2zjs.tar.gz

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

work=$(mktemp -d)
trap 'hdiutil detach -quiet "$work/mnt" 2>/dev/null || true; rm -rf "$work"' EXIT

step "Checking this Mac"
[ "$(uname -m)" = arm64 ] || fail "This needs a Mac with Apple silicon."
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  fail "Install the command line tools in the window that opened, then run this again."
fi
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  step "Installing Rosetta (the HP driver is Intel code)"
  sudo softwareupdate --install-rosetta --agree-to-license
fi

step "Getting the app's source"
script=${BASH_SOURCE[0]:-}
if [ -f "$script" ] && [ -f "$(dirname "$script")/build.sh" ]; then
  checkout=$(cd "$(dirname "$script")" && pwd)
elif [ -d "$checkout/.git" ]; then
  git -C "$checkout" pull --ff-only
elif [ -e "$checkout" ]; then
  fail "$checkout exists but isn't a copy of $repo. Move it away and run this again."
else
  mkdir -p "$home_dir"
  git clone "$repo" "$checkout"
fi
echo "$checkout"

step "HP driver"
if pkgutil --pkg-info com.apple.pkg.HewlettPackardPrinterDrivers >/dev/null 2>&1 && [ -f "/$ppd" ]; then
  echo "Already installed."
else
  echo "Downloading Apple's HP Printer Drivers 5.1.1 (585 MB)…"
  curl -fL --retry 3 -o "$work/hp.dmg" "$driver_url"
  [ "$(sha "$work/hp.dmg")" = "$driver_sha" ] || fail "The HP driver download doesn't match the expected file."
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$work/mnt" "$work/hp.dmg"
  pkgutil --check-signature "$work/mnt/HewlettPackardPrinterDrivers.pkg" | grep -q "Status: signed Apple Software" \
    || fail "The HP driver package isn't signed by Apple."
  pkgutil --expand "$work/mnt/HewlettPackardPrinterDrivers.pkg" "$work/expanded"
  hdiutil detach -quiet "$work/mnt"
  # The package refuses Apple silicon and any macOS newer than 15.0; both checks live only in Distribution.
  sed -i '' \
    -e "s/system.compareVersions(system.version.ProductVersion, '15.0') \&gt; 0/false/" \
    -e 's/hostArchitectures="x86_64"/hostArchitectures="x86_64,arm64"/' \
    "$work/expanded/Distribution"
  grep -q 'hostArchitectures="x86_64,arm64"' "$work/expanded/Distribution" && grep -q 'if (false)' "$work/expanded/Distribution" \
    || fail "The HP package's install checks didn't look as expected, so it wasn't patched."
  pkgutil --flatten "$work/expanded" "$work/HP-patched.pkg"
  rm -rf "$work/expanded" "$work/hp.dmg"
  echo "Installing it needs your Mac password."
  sudo installer -pkg "$work/HP-patched.pkg" -target / -allowUntrusted
fi

step "Printer firmware"
if [ -f "$firmware" ] && [ "$(sha "$firmware")" = "$firmware_sha" ]; then
  echo "Already in place."
else
  curl -fsSL -o "$work/sihp1020.tar.gz" "$firmware_url"
  [ "$(sha "$work/sihp1020.tar.gz")" = "$firmware_tar_sha" ] || fail "The firmware download doesn't match the expected file."
  curl -fsSL -o "$work/foo2zjs.tar.gz" "$foo2zjs_url"
  tar -xzf "$work/sihp1020.tar.gz" -C "$work"
  tar -xzf "$work/foo2zjs.tar.gz" -C "$work" foo2zjs/arm2hpdl.c
  cc -O2 -w -o "$work/arm2hpdl" "$work/foo2zjs/arm2hpdl.c"
  "$work/arm2hpdl" "$work/sihp1020.img" > "$work/sihp1020.dl"
  [ "$(sha "$work/sihp1020.dl")" = "$firmware_sha" ] || fail "The converted firmware doesn't match the expected file."
  mkdir -p "$home_dir"
  mv "$work/sihp1020.dl" "$firmware"
  echo "$firmware"
fi

step "Printer queue"
if lpstat -p "$queue" >/dev/null 2>&1; then
  echo "Already set up."
else
  echo "Connect the printer by USB and switch it on."
  uri=""
  for _ in $(seq 1 60); do
    uri=$(lpinfo --include-schemes usb -v 2>/dev/null | awk '/HP%20LaserJet%201020/ { print $2; exit }')
    [ -n "$uri" ] && break
    sleep 2
  done
  [ -n "$uri" ] || fail "No LaserJet 1020 showed up on USB. Connect it, switch it on and run this again."
  lpadmin -p "$queue" -D "HP LaserJet 1020" -L USB -E -v "$uri" -m "$ppd" -o printer-is-shared=false
  locale=$(defaults read NSGlobalDomain AppleLocale 2>/dev/null || echo en_US)
  region=${locale#*_}
  case "${region%%@*}" in
    US | CA | MX | PH) paper=Letter ;;
    *) paper=A4 ;;
  esac
  lpadmin -p "$queue" -o PageSize=$paper -o PageRegion=$paper
  echo "Added $queue with $paper paper."
fi

step "Building the app"
"$checkout/build.sh"

printf '\nDone. Open LaserJet 1020 from %s/Applications.\n' "$HOME"
