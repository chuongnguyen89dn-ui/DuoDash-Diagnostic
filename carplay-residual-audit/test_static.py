from pathlib import Path
import plistlib

root = Path(__file__).parent
app = (root / "CarPlayAuditApp.m").read_text()
probe = (root / "CarPlayRuntimeProbe.m").read_text()
ownership = (root / "CPAOwnership.m").read_text()
control = (root / "control").read_text()
assert "QUÉT MÁY" in app and "CHIA SẺ BÁO CÁO" in app
assert "CPAReadPackages" in app and "CPAReadFilesystem" in app and "CPAReadRuntime" in app
assert "_dyld_register_func_for_add_image" in probe
assert "PROBE_LOADED" in probe and "DYLD_IMAGE" in probe
assert "%hook" not in probe and "setFrame:" not in probe and "_setFullScreenEnabled:" not in probe
assert "PACKAGE_OWNER" in ownership and "NO_DPKG_FILE_OWNER" in ownership
assert "GEOMETRY_SNAPSHOT" in probe
assert "Version: 0.2.0" in control
assert "com.chuong.carplayaudit" in control
assert "com.sensetechlab.duodash" not in control
assert "Architecture: iphoneos-arm64" in control
info = plistlib.loads((root / "Info.plist").read_bytes())
assert info["CFBundleExecutable"] == "CarPlayAudit"
assert info["MinimumOSVersion"] == "16.0"
ent = plistlib.loads((root / "entitlements.plist").read_bytes())
assert ent["com.apple.private.security.no-container"]
print("STATIC_AUDIT_PASS")
