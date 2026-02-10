# Xcode Engineering Scaffold

This directory defines the Xcode project scaffold for ExoSentry with fixed bundle IDs and signing/entitlement files.

## Target Mapping

- `ExoSentryApp` -> `Sources/ExoSentryApp` (macOS app)
- `ExoSentryCore` -> `Sources/ExoSentryCore` (framework)
- `ExoSentryXPC` -> `Sources/ExoSentryXPC` (XPC service)
- `ExoSentryHelper` -> `Sources/ExoSentryHelper` (helper tool)

## Fixed Bundle IDs

- `com.exosentry.app`
- `com.exosentry.core`
- `com.exosentry.xpc`
- `com.exosentry.helper`

## Files

- Project spec: `Xcode/project.yml`
- Build settings: `Xcode/xcconfigs/*.xcconfig`
- Entitlements: `Xcode/Entitlements/*.entitlements`
- Info.plist files: `Xcode/InfoPlists/*-Info.plist`
- LaunchDaemon template: `Xcode/LaunchDaemons/com.exosentry.helper.plist`

## SMJobBless Notes

- `SMPrivilegedExecutables` is set in `ExoSentryApp-Info.plist`.
- `SMAuthorizedClients` is set in `ExoSentryHelper-Info.plist`.
- Replace requirement strings with TeamID-specific designated requirements before release.

## Generate Xcode Project

`xcodegen` is required.

```bash
brew install xcodegen
Scripts/materialize_signing_requirements.sh
xcodegen generate --spec Xcode/project.yml
xcodebuild -list -project ExoSentry.xcodeproj
```
