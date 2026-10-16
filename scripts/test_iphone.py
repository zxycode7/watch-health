#!/usr/bin/env python3
"""Run the native flow on an explicitly selected physical iPhone; no permission toggles or pairing secrets."""
import argparse, plistlib, shutil, subprocess
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--device',required=True)
parser.add_argument('--team',required=True)
parser.add_argument('--output',type=Path,default=repo/'build/DeviceChecks')
args=parser.parse_args()
root=args.output.resolve();root.mkdir(parents=True,exist_ok=True)
(root/'DeviceUI.xcodeproj/xcshareddata/xcschemes').mkdir(parents=True,exist_ok=True)
shutil.copy2(repo/'tests/PhoneFlowTests.swift',root/'DeviceUITests.swift')
ids={name:f'{n:024X}' for n,name in enumerate(['project','group','products','source','product','buildfile','sources','frameworks','resources','target','projectconfig','targetconfig','projectdebug','targetdebug'],1)}
def ref(name):return ids[name]
objects={}
def add(key,isa,**kw):objects[ref(key)]={'isa':isa,**kw}
add('source','PBXFileReference',lastKnownFileType='sourcecode.swift',path='DeviceUITests.swift',sourceTree='<group>')
add('product','PBXFileReference',explicitFileType='wrapper.cfbundle',path='DeviceUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex='0')
add('buildfile','PBXBuildFile',fileRef=ref('source'))
add('group','PBXGroup',children=[ref('source'),ref('products')],sourceTree='<group>')
add('products','PBXGroup',name='Products',children=[ref('product')],sourceTree='<group>')
add('sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=[ref('buildfile')],runOnlyForDeploymentPostprocessing='0')
for name in ['frameworks','resources']:add(name,'PBX'+name.title()+'BuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
add('target','PBXNativeTarget',buildConfigurationList=ref('targetconfig'),buildPhases=[ref('sources'),ref('frameworks'),ref('resources')],buildRules=[],dependencies=[],name='DeviceUITests',productName='DeviceUITests',productReference=ref('product'),productType='com.apple.product-type.bundle.ui-testing')
add('project','PBXProject',attributes={'LastUpgradeCheck':'2700','TargetAttributes':{ref('target'):{'CreatedOnToolsVersion':'27.1'}}},buildConfigurationList=ref('projectconfig'),compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=ref('group'),productRefGroup=ref('products'),projectDirPath='',projectRoot='',targets=[ref('target')])
for name,config in [('projectconfig','projectdebug'),('targetconfig','targetdebug')]:add(name,'XCConfigurationList',buildConfigurations=[ref(config)],defaultConfigurationIsVisible='0',defaultConfigurationName='Debug')
settings={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','SWIFT_OPTIMIZATION_LEVEL':'-Onone','CLANG_ENABLE_MODULES':'YES','DEBUG_INFORMATION_FORMAT':'dwarf'}
add('projectdebug','XCBuildConfiguration',name='Debug',buildSettings=settings)
add('targetdebug','XCBuildConfiguration',name='Debug',buildSettings={**settings,'PRODUCT_BUNDLE_IDENTIFIER':'local.watchbridge.deviceuitests','PRODUCT_NAME':'$(TARGET_NAME)','CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos','TEST_TARGET_NAME':'','TESTING_TARGET_SUPPORTS_UI_TESTING':'YES'})
(root/'DeviceUI.xcodeproj/project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':ref('project')}))
scheme=f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="DeviceUITests.xctest" BlueprintName="DeviceUITests" ReferencedContainer="container:DeviceUI.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="DeviceUITests.xctest" BlueprintName="DeviceUITests" ReferencedContainer="container:DeviceUI.xcodeproj"/></TestableReference></Testables></TestAction></Scheme>'''
(root/'DeviceUI.xcodeproj/xcshareddata/xcschemes/DeviceUI.xcscheme').write_text(scheme)

subprocess.run(['xcodebuild','-project',str(root/'DeviceUI.xcodeproj'),'-scheme','DeviceUI','-configuration','Debug','-destination','id='+args.device,'-derivedDataPath',str(root/'DerivedData'),'DEVELOPMENT_TEAM='+args.team,'-allowProvisioningUpdates','-parallel-testing-enabled','NO','test'],check=True)
