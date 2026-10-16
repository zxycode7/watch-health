#!/usr/bin/env python3
"""Build the native desktop app using only Apple SDKs and the Swift standard toolchain."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT/'build/Veyra.app')
    parser.add_argument('--scratch-path',type=Path,default=ROOT/'build/MacDerived')
    args=parser.parse_args()
    app=args.output.resolve()
    if app.exists():
        plist=app/'Contents/Info.plist'
        if not plist.exists() or plistlib.loads(plist.read_bytes()).get('CFBundleIdentifier')!='local.watchbridge.desktop':
            raise SystemExit('目标已存在且不是维律 App，未覆盖。')
        shutil.rmtree(app)
    subprocess.run(['xcrun','swift','build','-c','release','--product','Veyra','--scratch-path',str(args.scratch_path)],cwd=ROOT,check=True)
    binary_path=subprocess.check_output(['xcrun','swift','build','-c','release','--show-bin-path','--scratch-path',str(args.scratch_path)],cwd=ROOT,text=True).strip()
    contents=app/'Contents';resources=contents/'Resources';macos=contents/'MacOS'
    macos.mkdir(parents=True);resources.mkdir()
    shutil.copy2(Path(binary_path)/'Veyra',macos/'Veyra')
    master=ROOT/'assets/brand/VeyraMaster.png'
    iconset=args.scratch_path/'Veyra.iconset';iconset.mkdir(exist_ok=True)
    for size in [16,32,128,256,512]:
        for scale in [1,2]:
            name=f'icon_{size}x{size}'+('@2x' if scale==2 else '')+'.png'
            subprocess.run(['/usr/bin/sips','-z',str(size*scale),str(size*scale),str(master),'--out',str(iconset/name)],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/iconutil','-c','icns',str(iconset),'-o',str(resources/'AppIcon.icns')],check=True)
    shutil.copy2(ROOT/'ios/WatchBridge/Assets.xcassets/BrandMark.imageset/BrandMark.png',resources/'BrandMark.png')
    service=resources/'Service';(service/'scripts').mkdir(parents=True)
    shutil.copytree(ROOT/'watchbridge',service/'watchbridge',ignore=shutil.ignore_patterns('__pycache__'))
    for name in ['run.py','pair.py','PairingQR.swift','install_mac.py']:shutil.copy2(ROOT/'scripts'/name,service/'scripts'/name)
    (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.watchbridge.desktop','CFBundleExecutable':'Veyra','CFBundleName':'Veyra','CFBundleDisplayName':'维律 Veyra','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.0','CFBundleVersion':'2','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSLocalNetworkUsageDescription':'检测你自己的 Mac 接收服务，并管理 iPhone 的本地连接。'}))
    subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(app)],check=True)
    print(str(app))
if __name__=='__main__':main()
