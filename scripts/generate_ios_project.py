"""Deterministic Xcode project. Python standard library; no project-generator dependency."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "iOS"
PROJECT = IOS / "iLedBikeMobile.xcodeproj"
PROJECT.mkdir(exist_ok=True)
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def q(value): return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
objects = []
def obj(key, isa, **fields):
    objects.append(f'{uid(key)} = {{isa = {isa}; ' + ' '.join(f'{k} = {v};' for k,v in fields.items()) + ' };')
    return uid(key)
def arr(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
shared = ["Protocol.swift", "Design.swift", "PixelPreview.swift", "PixelDrawing.swift", "Bluetooth.swift"]
phone = ["PhoneStudio.swift", "LibraryStore.swift", "DesignDocument.swift", "HalloweenDesigns.swift"]
tests = ["MobileTests.swift"]
for category, files, prefix in [("Shared", shared, "../Sources/"), ("Phone", phone, "iLedBikeMobile/"), ("Tests", tests, "iLedBikeMobileTests/")]:
    refs = []
    for file in files:
        name = category + file
        refs.append(obj(name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=q(prefix+file), sourceTree=q("<group>")))
        obj("build"+name, "PBXBuildFile", fileRef=uid(name))
    obj(category, "PBXGroup", children=arr(refs), name=q(category), sourceTree=q("<group>"))
obj("config", "PBXFileReference", lastKnownFileType="text.xcconfig", path=q("Config.xcconfig"), sourceTree=q("<group>"))
obj("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path=q("iLedBikeMobile/Assets.xcassets"), sourceTree=q("<group>"))
obj("buildassets", "PBXBuildFile", fileRef=uid("assets"))
for target in ["iLedBikeMobile", "iLedBikeMobileTests"]:
    app = target == "iLedBikeMobile"
    obj(target+"product", "PBXFileReference", explicitFileType=q("wrapper.application" if app else "wrapper.cfbundle"), path=q(target+(".app" if app else ".xctest")), sourceTree="BUILT_PRODUCTS_DIR")
    files = [uid("buildShared"+f) for f in shared] + [uid("buildPhone"+f) for f in phone] if app else [uid("buildTests"+f) for f in tests]
    obj(target+"sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=arr(files), runOnlyForDeploymentPostprocessing="0")
    obj(target+"frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files="()", runOnlyForDeploymentPostprocessing="0")
    obj(target+"resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=arr([uid("buildassets")]) if app else "()", runOnlyForDeploymentPostprocessing="0")
    for config in ["Debug", "Release"]:
        settings = {"PRODUCT_NAME":q("$(TARGET_NAME)"), "PRODUCT_BUNDLE_IDENTIFIER":q("local.iledbike.studio.mobile" + (".tests" if not app else "")), "SWIFT_VERSION":"5.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0", "TARGETED_DEVICE_FAMILY":q("1,2"), "SDKROOT":"iphoneos", "SUPPORTED_PLATFORMS":q("iphoneos iphonesimulator"), "CODE_SIGN_STYLE":"Automatic", "SWIFT_OPTIMIZATION_LEVEL":q("-Onone" if config == "Debug" else "-O"), "SWIFT_ACTIVE_COMPILATION_CONDITIONS":q("DEBUG" if config == "Debug" else ""), "GENERATE_INFOPLIST_FILE":"NO" if app else "YES"}
        if app: settings.update({"INFOPLIST_FILE":q("iLedBikeMobile/Info.plist"), "ASSETCATALOG_COMPILER_APPICON_NAME":q("AppIcon"), "ENABLE_PREVIEWS":"YES", "SUPPORTS_MACCATALYST":"NO"})
        else: settings.update({"TEST_HOST":q("$(BUILT_PRODUCTS_DIR)/iLedBikeMobile.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/iLedBikeMobile"), "BUNDLE_LOADER":q("$(TEST_HOST)")})
        obj(target+config, "XCBuildConfiguration", baseConfigurationReference=uid("config"), buildSettings="{"+' '.join(k+' = '+v+';' for k,v in settings.items())+'}', name=q(config))
    obj(target+"configs", "XCConfigurationList", buildConfigurations=arr([uid(target+c) for c in ["Debug","Release"]]), defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
    obj(target, "PBXNativeTarget", buildConfigurationList=uid(target+"configs"), buildPhases=arr([uid(target+x) for x in ["sources","frameworks","resources"]]), buildRules="()", dependencies="()" if app else arr([uid("dependency")]), name=q(target), productName=q(target), productReference=uid(target+"product"), productType=q("com.apple.product-type.application" if app else "com.apple.product-type.bundle.unit-test"))
obj("proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType="1", remoteGlobalIDString=uid("iLedBikeMobile"), remoteInfo=q("iLedBikeMobile"))
obj("dependency", "PBXTargetDependency", target=uid("iLedBikeMobile"), targetProxy=uid("proxy"))
obj("products", "PBXGroup", children=arr([uid(t+"product") for t in ["iLedBikeMobile","iLedBikeMobileTests"]]), name="Products", sourceTree=q("<group>"))
obj("main", "PBXGroup", children=arr([uid(x) for x in ["Shared","Phone","Tests","assets","config","products"]]), sourceTree=q("<group>"))
for config in ["Debug", "Release"]:
    obj("project"+config, "XCBuildConfiguration", buildSettings="{CLANG_ENABLE_MODULES = YES; ENABLE_TESTABILITY = YES; GCC_C_LANGUAGE_STANDARD = gnu17; }", name=q(config))
obj("projectconfigs", "XCConfigurationList", buildConfigurations=arr([uid("project"+c) for c in ["Debug","Release"]]), defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
obj("project", "PBXProject", attributes="{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }", buildConfigurationList=uid("projectconfigs"), compatibilityVersion=q("Xcode 14.0"), developmentRegion="en", hasScannedForEncodings="0", knownRegions=arr(["en","Base"]), mainGroup=uid("main"), productRefGroup=uid("products"), projectDirPath=q(""), projectRoot=q(""), targets=arr([uid("iLedBikeMobile"),uid("iLedBikeMobileTests")]))
(PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid("project")+'; }\n')
schemes = PROJECT / "xcshareddata/xcschemes"; schemes.mkdir(parents=True, exist_ok=True)
def reference(target):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{target}{".app" if target == "iLedBikeMobile" else ".xctest"}" BlueprintName="{target}" ReferencedContainer="container:iLedBikeMobile.xcodeproj"/>'
(schemes / "iLedBikeMobile.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("iLedBikeMobile")}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference("iLedBikeMobileTests")}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("iLedBikeMobile")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("iLedBikeMobile")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''')
print("Generated deterministic iPhone Xcode project and shared scheme.")
