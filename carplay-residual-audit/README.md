# CarPlay Residual Audit (read-only diagnostic)

Standalone iPhone interface and injection-only dylib for **iOS 16 rootless jailbreak**.
It is separate from DuoFace, DuoDash and AiraW and changes **no screen dimensions**.

## Purpose

Audit potential residual DuoDash, DuoDashGeometryFix, AiraW, DuoFace, CarBridge, OmniCar,
CarPlayDSP or similar tweak traces even after package removal. The user reported that
the thin bar / bottom inset issue reproduces across apps only when jailbroken.

Three evidence levels are intentionally separate:

1. **INSTALLED:** packages still marked "install ok installed" in dpkg status.
2. **ON_DISK:** injection dylib/plist, launch daemons, preference/residual names.
   ON_DISK does not establish active injection.
3. **PROBE_LOADED / DYLD_IMAGE:** real images seen by a constructor-only (no hooks)
   dylib loaded into CarPlay, CarPlayApp, SpringBoard or Dashboard.
   The process name and timestamp identify evidence freshness.

Absence of a probe log is **UNVERIFIED**, never "no conflict".

## Use (NO terminal / keyboard)

1. Install the .deb through Sileo.
2. Respring once manually so the injected logger can be loaded.
3. Reconnect CarPlay and reproduce the bottom-bar problem.
4. Open **CarPlay Audit** icon on the iPhone.
5. Tap **QUÉT MÁY**, then **CHIA SẺ BÁO CÁO**. Send TXT using Files / Share Sheet.

Saved reports: /var/mobile/Documents/CarPlayAudit/CarPlayAudit-*.txt.
Probe stream: /var/mobile/Documents/CarPlayAudit/CarPlayRuntimeProbe.log.

## Safety

- Does not remove/disable tweaks, call any private fullscreen selector, or hook UIKit.
- No network traffic, no user conversations, no preference values or app documents collected.
- A read-only probe is still code injected into privileged processes. On-device
  compatibility must be validated; never promise zero risk.
- User may need to manually respring again after removal of the probe.
- Uses ldid platform/non-container entitlements for rootless filesystem read access;
  actual access depends on jailbreak policy and is reported as unavailable when blocked.
- Build/packaging pass is **not** proof of a successful on-device scan.

## Build

From macOS with Xcode iPhoneOS SDK, ldid and dpkg installed:

bash carplay-residual-audit/build.sh

GitHub Actions workflow: .github/workflows/build-carplay-residual-audit.yml.
Output: carplay-residual-audit/packages/com.chuong.carplayaudit_0.1.0_iphoneos-arm64.deb.

No dependency on DuoDash, AiraW, DuoFace, or any proprietary dylib.
Never publish to Sileo before verifying package metadata, expected payload and CI.
