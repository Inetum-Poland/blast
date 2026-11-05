# BLAST

[![License: Apache 2.0](https://img.shields.io/github/license/Inetum-Poland/blast?logo=apache&color=purple)](https://github.com/Inetum-Poland/blast?tab=Apache-2.0-1-ov-file#)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](#)
[![MDM: Jamf Pro](https://img.shields.io/badge/MDM-Jamf%20Pro-blue)](#)
[![GitHub Release](https://img.shields.io/github/v/release/Inetum-Poland/blast)](https://github.com/Inetum-Poland/blast/releases)
[![Swift](https://img.shields.io/badge/language-Swift-orange)](#)

**Blueprint Legacy Accessibility Settings Transformer**

A macOS application for migrating PPPC Accessibility permissions from Jamf Pro configuration profiles to Declarative Device Management blueprints.

Apple deprecated Accessibility management through the `com.apple.TCC.configuration-profile-policy` payload in macOS 26.2 and removed it in macOS 27. BLAST scans macOS configuration profiles for PPPC Accessibility grants, maps each application to a `com.apple.configuration.app.settings` declaration keyed by its bundle ID and designated requirement, and creates the corresponding blueprints through the Jamf Platform API.

Profiles can also be scanned read-only against a Jamf Pro server using an API role or a local account. Creating blueprints still requires a Platform API integration.

---

## What BLAST does

1. Connects with either a Jamf Platform API integration or Jamf Pro credentials
2. Lists macOS configuration profiles that grant Accessibility through PPPC
3. Lets you pick profiles, combined or separate blueprints, and a device group
4. Creates (but does not deploy) typed App Settings blueprints in Jamf Pro

---

## Building

Open `BLAST.xcodeproj` in Xcode, or from the repo root:

```bash
xcodebuild -project BLAST.xcodeproj -scheme BLAST -configuration Release build
```

Release builds are signed with Developer ID, notarized, and published as a DMG from GitHub Actions on tags matching `v*.*.*`.

---

## License

Apache License 2.0. See [LICENSE](LICENSE).
