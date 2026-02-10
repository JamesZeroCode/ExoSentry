# Release Hardening Checklist

1. Replace placeholder designated requirements in:
   - `Xcode/InfoPlists/ExoSentryApp-Info.plist` (`SMPrivilegedExecutables`)
   - `Xcode/InfoPlists/ExoSentryHelper-Info.plist` (`SMAuthorizedClients`)
   - or run `Scripts/materialize_signing_requirements.sh`
2. Ensure helper label is consistent across:
   - `Xcode/LaunchDaemons/com.exosentry.helper.plist`
   - `Sources/ExoSentryXPC/PrivilegedXPCClient.swift`
   - `Xcode/Entitlements/ExoSentryApp.entitlements`
3. Run:
   - `Scripts/release_hardening_check.sh`
   - `Scripts/mvp_acceptance.sh`
4. Validate privileged flow on signed build:
   - SMJobBless install
   - NSXPC connection to helper mach service
   - disablesleep set/reset via helper only
5. Confirm local API remains localhost-only and does not expose privileged internals.
