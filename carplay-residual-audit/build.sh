#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/packages"
ROOT="$HERE/.buildroot"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
rm -rf "$ROOT"
mkdir -p "$ROOT/DEBIAN" "$ROOT/var/jb/Applications/CarPlayAudit.app" \
 "$ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries" "$OUT"
APP="$ROOT/var/jb/Applications/CarPlayAudit.app"
INJECT="$ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" \
 -miphoneos-version-min=16.0 -fobjc-arc -fmodules -O2 \
 -framework Foundation -framework UIKit \
 "$HERE/CarPlayAuditApp.m" "$HERE/CPAOwnership.m" -o "$APP/CarPlayAudit"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" \
 -miphoneos-version-min=16.0 -fobjc-arc -fmodules -O2 \
 -dynamiclib -framework Foundation -framework UIKit \
 "$HERE/CarPlayRuntimeProbe.m" "$HERE/CarPlayAttribution.m" -o "$INJECT/CarPlayRuntimeProbe.dylib"
cp "$HERE/Info.plist" "$APP/Info.plist"
cp "$HERE/CarPlayRuntimeProbe.plist" "$INJECT/CarPlayRuntimeProbe.plist"
ldid -S"$HERE/entitlements.plist" "$APP/CarPlayAudit"
ldid -S "$INJECT/CarPlayRuntimeProbe.dylib"
cp "$HERE/control" "$ROOT/DEBIAN/control"
cp "$HERE/postinst" "$ROOT/DEBIAN/postinst"
cp "$HERE/prerm" "$ROOT/DEBIAN/prerm"
chmod 755 "$APP/CarPlayAudit" "$INJECT/CarPlayRuntimeProbe.dylib" \
 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/prerm"
dpkg-deb --build --root-owner-group "$ROOT" \
 "$OUT/com.chuong.carplayaudit_0.3.0_iphoneos-arm64.deb"
dpkg-deb -I "$OUT/com.chuong.carplayaudit_0.3.0_iphoneos-arm64.deb"
dpkg-deb -c "$OUT/com.chuong.carplayaudit_0.3.0_iphoneos-arm64.deb"
shasum -a 256 "$OUT/com.chuong.carplayaudit_0.3.0_iphoneos-arm64.deb" \
 > "$OUT/SHA256SUMS.txt"
