from pathlib import Path
import plistlib

root = Path(__file__).parent
app = (root / "CarPlayAuditApp.m").read_text()
probe = (root / "CarPlayRuntimeProbe.m").read_text()
ownership = (root / "CPAOwnership.m").read_text()
attribution=(root / "CarPlayAttribution.m").read_text()
home_trace=(root / "CarPlayHomeTrace.m").read_text()
control = (root / "control").read_text()
assert "QUÉT MÁY" in app and "CHIA SẺ BÁO CÁO" in app
assert "CPAReadPackages" in app and "CPAReadFilesystem" in app and "CPAReadRuntime" in app
assert "_dyld_register_func_for_add_image" in probe
assert "PROBE_LOADED" in probe and "DYLD_IMAGE" in probe
assert "%hook" not in probe and "%hook" not in attribution and "method_setImplementation" not in probe
assert "PACKAGE_OWNER" in ownership and "NO_DPKG_FILE_OWNER" in ownership
assert "GEOMETRY_SNAPSHOT" in probe and "METHOD_IMPL_SNAPSHOT" in probe
assert "Version: 0.5.0" in control
assert "HOME_UNRESPONSIVE" in app and "APP_SWITCH_UNRESPONSIVE" in app
assert "CPAReadHomeTrace(out)" in app
assert "CPAHomeHitTest" in home_trace and "CPAHomeSendEvent" in home_trace
assert "72 * 3600" in home_trace and "256 * 1024" in home_trace
assert "CarPlayHomeTouchTrace.previous.log" in home_trace
assert "CarPlayHomeTouchTrace.previous.log" in app
assert "72 GIỜ" in app and "HOME KẸT" in app and "APP KẸT" in app
assert "CPAHomeControlAction" in home_trace and "CPAHomeAppAction" in home_trace
assert "TRACE_STARTED v0.5" in home_trace and "CPAHomeArmRecent" in home_trace
assert "method_setImplementation" in home_trace and "sendEvent:" in home_trace
assert "armTapped" in app and "PHASE_NORMAL" in app and "PHASE_ZOOM_IN" in app
assert 'TRACE_STOP_REQUEST' in app
assert "CPAReadAttribution(out)" in app
assert "method_setImplementation" in attribution and "CPAArmIsFresh" in attribution
assert "CALLER_GEOMETRY" in attribution and "SAFEAREA_NOTIFICATION" in attribution
assert "TRACE_END" in attribution and "original" in attribution
assert "setFrame:" in attribution and "setAdditionalSafeAreaInsets:" in attribution
assert "com.chuong.carplayaudit" in control
assert "com.sensetechlab.duodash" not in control
assert "Architecture: iphoneos-arm64" in control
info = plistlib.loads((root / "Info.plist").read_bytes())
assert info["CFBundleExecutable"] == "CarPlayAudit"
assert info["MinimumOSVersion"] == "16.0"
ent = plistlib.loads((root / "entitlements.plist").read_bytes())
assert ent["com.apple.private.security.no-container"]
print("STATIC_AUDIT_PASS")
