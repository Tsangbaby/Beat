#!/usr/bin/env python3
"""Verify the exact RootHide candidate; no installation or device claims."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from verify_macho_signatures import verify_macho

ROOT = Path(__file__).resolve().parents[1]


def check(deb, output):
    output.mkdir(parents=True, exist_ok=True)
    meta = subprocess.check_output(["dpkg-deb", "-f", str(deb)], text=True)
    listing = subprocess.check_output(["dpkg-deb", "-c", str(deb)], text=True)
    (output / "PACKAGE_METADATA.txt").write_text(meta)
    (output / "PACKAGE_CONTENTS.txt").write_text(listing)
    fields = dict(line.split(": ", 1) for line in meta.splitlines() if ": " in line and not line.startswith(" "))
    expected = dict(line.split(": ", 1) for line in (ROOT / "control").read_text().splitlines() if ": " in line)
    for field in ["Package", "Version", "Architecture", "Depends"]:
        assert fields[field] == expected[field], (field, fields[field], expected[field])
    assert fields["Architecture"] == "iphoneos-arm64e"
    assert "./var/jb/" not in listing, "Rootless prefix in RootHide package"
    reports = []
    with tempfile.TemporaryDirectory(prefix="stheno-check-", dir=os.environ.get("TMPDIR")) as temp:
        payload, control = Path(temp) / "payload", Path(temp) / "control"
        subprocess.run(["dpkg-deb", "-x", str(deb), str(payload)], check=True)
        subprocess.run(["dpkg-deb", "-e", str(deb), str(control)], check=True)
        dynamic = payload / "Library/MobileSubstrate/DynamicLibraries"
        dylibs = sorted(payload.rglob("*.dylib"))
        assert {p.name for p in dylibs} == {"Stheno.dylib", "SthenoCamera.dylib", "SthenoKeyboard.dylib"}
        for name in ["Stheno", "SthenoCamera", "SthenoKeyboard"]:
            binary = dynamic / (name + ".dylib")
            assert binary.is_file(), str(binary)
            actual_filter = plistlib.loads((dynamic / (name + ".plist")).read_bytes())
            expected_filter = plistlib.loads((ROOT / (name + ".plist")).read_bytes())
            assert actual_filter == expected_filter, name + " injection filter mismatch"
            slices = verify_macho(binary, ("arm64", "arm64e"))
            for item in slices:
                assert not any("/var/jb/" in p for p in item["load_dylibs"] + item["rpaths"])
                assert any("libroothide" in p for p in item["load_dylibs"]), name + " missing RootHide linkage"
            reports.append({"binary": str(binary.relative_to(payload)), "slices": slices})
        for script in ["postinst", "preinst", "prerm", "postrm"]:
            path = control / script
            if path.exists():
                assert path.stat().st_mode & 0o777 == 0o755, script
                subprocess.run(["sh", "-n", str(path)], check=True)
    report = {"evidence": "package_structure_and_signature_code_pages_not_device_validation", "metadata": fields, "binaries": reports,
              "sha256": hashlib.sha256(deb.read_bytes()).hexdigest(), "bytes": deb.stat().st_size}
    (output / "VERIFICATION.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    destination = output / deb.name
    if destination.resolve() != deb.resolve():
        shutil.copy2(deb, destination)
    assert hashlib.sha256(destination.read_bytes()).hexdigest() == report["sha256"]
    (output / "SHA256SUMS.txt").write_text(report["sha256"] + "  " + deb.name + "\n")
    return report


if __name__ == "__main__":
    if not __debug__:
        raise SystemExit("Run without Python -O; verification assertions are required")
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify_package.py DEB OUTPUT_DIRECTORY")
    print(json.dumps(check(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()), indent=2))
