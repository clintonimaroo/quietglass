from pathlib import Path
import json
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
binary_directory = Path(sys.argv[1])
resources = Path(sys.argv[2])
with tempfile.TemporaryDirectory(prefix="quietglass-intents-") as temporary:
    stage = Path(temporary)
    sources = sorted((root / "Sources/QuietGlass").glob("*.swift"))
    values = stage / "QuietGlass.swiftconstvalues"
    target = f"{platform.machine()}-apple-macosx14.0"
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
    version = subprocess.check_output(["xcodebuild", "-version"], text=True).split("Build version ", 1)[1].strip()
    subprocess.run([
        str(compiler), "-emit-module", "-whole-module-optimization", "-parse-as-library",
        "-target", target, "-sdk", sdk, "-I", str(binary_directory / "Modules"),
        *map(str, sources), "-module-name", "QuietGlass",
        "-emit-module-path", str(stage / "QuietGlass.swiftmodule"),
        "-emit-const-values-path", str(values), "-Xfrontend", "-const-gather-protocols-file",
        "-Xfrontend", str(root / "scripts/intent-protocols.json")
    ], check=True)
    (stage / "sources.txt").write_text("\n".join(map(str, sources)) + "\n")
    (stage / "values.txt").write_text(str(values) + "\n")
    subprocess.run([
        "xcrun", "appintentsmetadataprocessor", "--output", str(resources),
        "--toolchain-dir", str(compiler.parent.parent), "--module-name", "QuietGlass",
        "--sdk-root", sdk, "--xcode-version", version, "--platform-family", "macOS",
        "--deployment-target", "14.0", "--target-triple", target,
        "--source-file-list", str(stage / "sources.txt"), "--swift-const-vals-list", str(stage / "values.txt")
    ], check=True)
    data = json.loads((resources / "Metadata.appintents/extract.actionsdata").read_text())
    encoded = json.dumps(data)
    for intent in ["BlurScreenIntent", "PauseQuietGlassIntent", "FocusQuietGlassIntent"]:
        if intent not in encoded:
            raise RuntimeError(f"Missing App Intent metadata: {intent}")
