# CarPlay Residual Audit 0.3 (opt-in attribution)

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

## v0.3 opt-in frame / safe-area call-path attribution
- Uses a narrow, time-limited (5 minute, max 240 events) opt-in Objective-C IMP interposer to log method call stacks and original implementations in the **CarPlay process only**. Default OFF unless the user taps ARM then resprings within five minutes.
- Hooks `setFrame:`, `setBounds:` on UIKit base views/window and DBAnimationView where present, and observes `safeAreaInsetsDidChange`, `setAdditionalSafeAreaInsets:`. The original implementation is called with unmodified parameters. No replacement frame/safe area, no automatic restart.
- Hooking UIKit is non-zero risk, even read-only; rollback by tapping STOP and respring, or uninstalling the diagnostic from Sileo. Do NOT use while driving.
- During a **parked** CarPlay session, tap ARM, respring manually, reconnect, let ordinary mode run briefly, tap MOC THUONG, turn Zoom In on, tap MOC ZOOM IN, then STOP / QUET MAY / CHIA SE BAO CAO.
- Trace evidence file: `/var/mobile/Documents/CarPlayAudit/CarPlayAttributionTrace.log`; log records include `TRACE_BEGIN`, `HOOK_CHAIN`, `CALLER_GEOMETRY`, `SAFEAREA_NOTIFICATION`, `EXPLICIT_ADDITIONAL_SAFEAREA`, `USER_MARK`, `TRACE_END`.
- A caller stack or UIKit notification indicates a call path, NOT conclusive assignment of blame. If the 20pt inset is system-provided at startup and never set explicitly, this probe may not identify a setter.
- Test without jailbreak/injection is a different baseline and cannot be produced inside injected CarPlay; do not pretend this captures a clean baseline.

## v0.4 HOME / app-switch touch trace
- Diagnostic reports observed CarPlay UIWindow \`sendEvent:\`, \`hitTest:withEvent:\`, UIApplication/UIControl \`sendAction...\`, and user-confirmed failure markers, with previous IMPs called normally.
- When installed and armed, restart CarPlay within 5 minutes. On an OFF-ROAD / parked vehicle, reproduce failure to return to CarPlay Home or open another app, then tap HOME KẸT / APP KẸT on the iPhone, followed by STOP / QUÉT MÁY / share.
- Output is \`/var/mobile/Documents/CarPlayAudit/CarPlayHomeTouchTrace.log\`, embedded in exported TXT section 6.
- The trace does NOT navigate to Home, alter gesture recognizers or activate arbitrary apps.
- If touch events never reach CarPlay process, this is one possible clue, NOT conclusive blocking (CarPlay input may route through another process).

## v0.5 — intermittent failure capture (72-hour opt-in)
- For rare CarPlay Home/app-switch failures, ARM once and respring; CarPlay touch/action trace is active for up to 72 hours, without repeated forced reproduction. On the iPhone press HOME KẸT or APP KẸT if/when a failure happens, then STOP / QUÉT MÁY / CHIA SẺ.
- CarPlayHomeTouchTrace.log rotates at approximately 256KiB to CarPlayHomeTouchTrace.previous.log. The export combines the two files (up to approximately 512KiB). Older records are discarded; export close to the event.
- The broad UIKit geometry caller-attribution trace remains independently limited to 5 minutes; the intermittent HOME stream stays active for up to 72h only if ARM was selected.
- Read-only with respect to UI/frame/application state, but the method interposition itself is non-zero compatibility risk. User may stop at any time and respring if any interference. Do not manipulate device while driving.
- If crash/kill happens, a subsequent CarPlay process reactivates only if ARM is still present and within the 72h window; there can be recording gaps during restarts. Hooks observe UI routing but cannot prove private scene activation acknowledged or reveal arbitrary IPC failures.
