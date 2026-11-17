# Room — installed iOS app

This is a native Xcode app project that installs as **Room**, with an app icon, UIKit container, WKWebView room interface, native camera/microphone permission checks, and AVAudioSession speaker/default-receiver routing. It is an installed app, not an Add to Home Screen/PWA package.

The interface loads `https://nexusagent.shop/app/`. The room host must be running and configured for that exact app origin. The web interface is shared with Room's existing clients. This version requires iOS 15 or later and keeps website/session storage nonpersistent. Native messages and capture permissions are accepted only from the main frame at the exact trusted HTTPS origin. WebKit's normal HTTPS certificate validation stays enabled.

Screen sharing is explicitly unavailable in this iOS build. Sharing other apps requires a ReplayKit Broadcast Upload Extension; a recording of the current Room app is not substituted. Calls stop when Room goes into the background in this minimal version. Keep Room open while calling.

## Build an unsigned IPA

The included `.github/workflows/build-ios.yml` is **manual only**. It runs Xcode on a macOS GitHub runner, archives with `CODE_SIGNING_ALLOWED=NO`, and packages `Room-unsigned.ipa` as an artifact. It requires no Apple Developer signing certificate or provisioning secrets. GitHub Actions availability and runner billing must be checked before running it.

Publish the contents of this folder at a repository root, then manually run **Build unsigned Room iOS app**. No workflow has been published or run as part of preparing these sources.

Alternatively, on a Mac with Xcode:

```sh
xcodebuild -project Room.xcodeproj -scheme Room -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/Room.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" archive
```

## Install from Windows

An **unsigned IPA cannot be installed directly**. After the build succeeds, download its IPA and locally re-sign/install it using Sideloadly or AltStore/AltServer with your own free Apple ID and connected iPhone. Keep Apple ID credentials in the signing tool; they are not needed in this project or CI.

Free personal signing typically expires after seven days and has Apple-imposed app/device limits, so the app needs refreshing/re-signing. A paid Apple Developer account is needed for normal App Store/TestFlight distribution. This project does not bypass Apple's signing rules.

## Verification status

The project structure, scheme, asset metadata, plist privacy entries, and source were inspected on Windows. **No Mac/Xcode build, IPA, signing, or iPhone run is claimed.** The workflow provides the build path; its result still needs to be checked. Native camera, audio routing and WKWebView calls need a real iPhone test after installation.
