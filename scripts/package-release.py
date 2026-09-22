#!/usr/bin/env python3
"""Package an already built universal app, with optional Apple notarization."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

from ds_store import DSStore
from mac_alias import Alias

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    result = subprocess.run(list(map(str, args)), text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed:\n{result.stdout}\n{result.stderr}')
    return result.stdout.strip()


def signature(path):
    result = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], text=True, capture_output=True, check=True)
    return result.stderr


def verify_app(app, version, build):
    run('codesign', '--verify', '--strict', '--all-architectures', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info['CFBundleShortVersionString'], info['CFBundleVersion']) != (version, build):
        raise RuntimeError('Packaged version does not match the source Info.plist')
    executable = app / 'Contents/MacOS/QuietGlass'
    if set(run('lipo', '-archs', executable).split()) != {'arm64', 'x86_64'}:
        raise RuntimeError('Build with QUIETGLASS_UNIVERSAL=1 before packaging')
    if '/Users/' in run('otool', '-L', executable):
        raise RuntimeError('Executable links to a developer-local library')
    for resource in ['SFace.mlmodelc/model.espresso.weights', 'QuietGlass.icns', 'Assets.car',
                     'BlurPreview.png', 'BlurPreview.mp4', 'QuietGlass Help.html', 'NearbyAlert.mp3', 'LICENSE.txt', 'ThirdPartyNotices.txt']:
        if not (app / 'Contents/Resources' / resource).is_file():
            raise RuntimeError(f'Missing app resource: {resource}')
    if (app / 'Contents/Resources/LICENSE.txt').read_bytes() != (ROOT / 'LICENSE').read_bytes():
        raise RuntimeError('Bundled license does not match the source')
    notices = (app / 'Contents/Resources/ThirdPartyNotices.txt').read_text()
    if (ROOT / 'Resources/Models/SFace-LICENSE.txt').read_text() not in notices:
        raise RuntimeError('Missing recognition model attribution')
    if (ROOT / 'Resources/Sounds/NOTICE.txt').read_text() not in notices:
        raise RuntimeError('Missing warning sound attribution')
    if (app / 'Contents/Resources/NearbyAlert.mp3').read_bytes() != (ROOT / 'Sources/QuietGlass/Resources/NearbyAlert.mp3').read_bytes():
        raise RuntimeError('Bundled warning sound does not match the source')
    for preview in ['BlurPreview.png', 'BlurPreview.mp4']:
        if (app / 'Contents/Resources' / preview).read_bytes() != (ROOT / 'Resources/Preview' / preview).read_bytes():
            raise RuntimeError(f'Bundled preview does not match the source: {preview}')


def notarize(path, profile):
    result = json.loads(run('xcrun', 'notarytool', 'submit', path,
                            '--keychain-profile', profile, '--wait', '--output-format', 'json'))
    if result.get('status') != 'Accepted':
        raise RuntimeError(f'Apple did not accept the submission: {result.get("id")} ({result.get("status")})')
    return result['id']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; requires Developer ID signing')
    args = parser.parse_args()
    source = args.app.resolve()
    output = args.output.resolve()
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    developer_id = 'Authority=Developer ID Application:' in signature(source)
    if args.notary_profile and not developer_id:
        raise RuntimeError('Notarization requires a Developer ID Application signature')
    if developer_id and not args.notary_profile:
        raise RuntimeError('Provide --notary-profile for the Developer ID release; do not ship an unstapled build')
    output.mkdir(parents=True, exist_ok=True)
    stem = f'QuietGlass-{version}-macOS-universal'
    archive, dmg = output / f'{stem}.zip', output / f'{stem}.dmg'
    for path in (archive, dmg, output / 'SHA256SUMS', output / 'PACKAGE-INFO.json'):
        if path.exists():
            raise RuntimeError(f'Output already exists; choose a new directory: {path}')

    with tempfile.TemporaryDirectory(prefix='quietglass-release-') as temporary:
        stage = Path(temporary)
        package = stage / 'QuietGlass'
        package.mkdir()
        app = package / 'QuietGlass.app'
        run('ditto', '--norsrc', '--noextattr', source, app)
        # Documents sync may attach Finder metadata to the local build. Check
        # the clean staging copy that will actually be distributed.
        verify_app(app, version, build)
        notarization = {}
        if args.notary_profile:
            upload = stage / 'notarize.zip'
            run('ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr', app, upload)
            notarization['app'] = notarize(upload, args.notary_profile)
            run('xcrun', 'stapler', 'staple', app)
            run('xcrun', 'stapler', 'validate', app)
            run('spctl', '--assess', '--type', 'execute', app)
        verify_app(app, version, build)
        gatekeeper = ('This release is signed with Developer ID and notarized by Apple.\n' if developer_id else
                     'This release is locally signed and is not Apple-notarized. If macOS\n'
                     'blocks the first launch and you trust the download, first try opening\n'
                     'the app, then choose System Settings > Privacy & Security > Open Anyway.\n'
                     'Apple\'s instructions: https://support.apple.com/en-us/102445\n')
        (package / 'Getting Started.txt').write_text(
            f'QuietGlass {version} · Build {build}\nmacOS 14 or later · Apple silicon and Intel\n\n'
            'INSTALL\n1. Quit any previous copy of QuietGlass.\n'
            '2. Drag QuietGlass.app into Applications.\n'
            '3. Open QuietGlass from Applications, then eject the disk image.\n\n'
            + gatekeeper + '\n'
            'GET STARTED\nAllow Screen Recording for blur. In Settings > Head tracking, choose\n'
            'Camera or AirPods, start tracking, and calibrate facing your screen.\n'
            'Camera head tracking and Nearby people use Camera permission.\n'
            'Manual, window, area and Focus protection need no AirPods or camera.\n'
            'The menu bar icon opens Settings and Help; hover over the floating\n'
            'control bar for quick controls. Closing Settings keeps the app running.\n\n'
            'Control-Option-Command-P toggles screen blur. Escape clears protection\n'
            'and stops camera head tracking and Nearby people until enabled again.\n\n'
            'PRIVACY\nScreen, camera and motion processing stay on your Mac. Camera images\n'
            'are not saved or uploaded. Optional recognition saves a face template\n'
            'in the macOS login Keychain; delete it in Settings. Recognition can\n'
            'make mistakes or be fooled by photos or video. Lock your Mac when away.\n\n'
            'HELP AND UPDATES\nChoose QuietGlass Help from the menu bar for the offline guide.\n'
            'Choose Downloads & Updates for releases. Updates install manually.\n'
            'No account, API key or developer tools are required to use the app.\n'
            'For help without GitHub access: hi@clintonimaro.com\n'
            'Source and support: https://github.com/clintonimaroo/quietglass\n', encoding='utf-8')
        run('ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr', package, archive)
        with zipfile.ZipFile(archive) as zipped:
            if zipped.testzip() is not None:
                raise RuntimeError('ZIP integrity check failed')
            forbidden = ['.git/', '.build/', '.env', '.p12', '.pem', '.keychain', '__MACOSX', '.DS_Store']
            if any(part in name for name in zipped.namelist() for part in forbidden):
                raise RuntimeError('ZIP contains a development or credential file')
        extracted = stage / 'extracted'
        run('ditto', '-x', '-k', archive, extracted)
        verify_app(extracted / 'QuietGlass/QuietGlass.app', version, build)

        os.symlink('/Applications', package / 'Applications')
        (package / '.background').mkdir()
        shutil.copyfile(ROOT / 'Resources/InstallerBackground.png', package / '.background/background.png')
        writable = stage / 'installer.dmg'
        run('hdiutil', 'create', '-srcfolder', package, '-volname', f'QuietGlass {version}',
            '-fs', 'HFS+', '-format', 'UDRW', writable)
        mount = stage / 'mounted'
        mount.mkdir()
        run('hdiutil', 'attach', '-nobrowse', '-mountpoint', mount, writable)
        try:
            with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
                store['.']['bwsp'] = dict(ShowStatusBar=False, ShowToolbar=False, ShowSidebar=False,
                                         ShowTabView=False, ShowPathbar=False,
                                         WindowBounds='{{160, 120}, {700, 450}}')
                store['.']['icvp'] = dict(viewOptionsVersion=1, backgroundType=2,
                                         backgroundImageAlias=Alias.for_file(str(mount / '.background/background.png')).to_bytes(),
                                         iconSize=96.0, textSize=13.0, gridSpacing=100.0, gridOffsetX=0.0,
                                         gridOffsetY=0.0, arrangeBy='none', labelOnBottom=True,
                                         showIconPreview=True, showItemInfo=False)
                store['.']['vSrn'] = ('long', 1)
                store['.']['vstl'] = ('type', 'icnv')
                for name, point in [('QuietGlass.app', (190, 205)), ('Applications', (510, 205)),
                                    ('Getting Started.txt', (350, 345))]:
                    store[name]['Iloc'] = point
        finally:
            run('hdiutil', 'detach', mount)
        run('hdiutil', 'convert', writable, '-format', 'UDZO', '-imagekey', 'zlib-level=9', '-o', dmg)
        if args.notary_profile:
            identity = os.environ.get('QUIETGLASS_SIGN_IDENTITY')
            if not identity:
                raise RuntimeError('Set QUIETGLASS_SIGN_IDENTITY to sign the disk image')
            run('codesign', '--sign', identity, '--timestamp', dmg)
            notarization['dmg'] = notarize(dmg, args.notary_profile)
            run('xcrun', 'stapler', 'staple', dmg)
            run('xcrun', 'stapler', 'validate', dmg)
            run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', dmg)
        run('hdiutil', 'verify', dmg)
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, dmg)
        try:
            verify_app(mount / 'QuietGlass.app', version, build)
            if os.readlink(mount / 'Applications') != '/Applications':
                raise RuntimeError('Invalid Applications shortcut')
        finally:
            run('hdiutil', 'detach', mount)
        files = {path.name: dict(bytes=path.stat().st_size, sha256=hashlib.file_digest(path.open('rb'), 'sha256').hexdigest())
                 for path in (dmg, archive)}
        (output / 'SHA256SUMS').write_text(''.join(f'{value["sha256"]}  {name}\n' for name, value in files.items()))
        manifest = dict(version=version, build=build, minimum_macos=info['LSMinimumSystemVersion'],
                        architectures=['arm64', 'x86_64'], notarized=bool(args.notary_profile),
                        signature='Developer ID' if developer_id else 'local',
                        verified_after_extraction=True, notarization=notarization, files=files)
        (output / 'PACKAGE-INFO.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
