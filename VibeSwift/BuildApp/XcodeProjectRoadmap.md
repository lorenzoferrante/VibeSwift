# Xcodeproj Export Roadmap

This file captures the planned follow-up for emitting a full `.xcodeproj` from Build App mode after the current SwiftPM-first export.

## Phase A - Deterministic PBX Skeleton

- Emit a minimal `project.pbxproj` with:
  - one app target
  - one sources build phase
  - one resources build phase
  - default Debug/Release build settings
- Keep object IDs deterministic based on stable hashes of path + role.

## Phase B - Asset and Info.plist Support

- Emit `Info.plist` into project and wire plist build setting.
- Emit `Assets.xcassets` skeleton and resource references.
- Add app icon slots in generated `Contents.json`.

## Phase C - User Metadata and Signing Hooks

- Allow user-provided bundle identifier, team id placeholder, and deployment target.
- Keep signing mode automatic by default.
- Provide override points in `manifest.json` for custom build settings.

## Phase D - Validation and Snapshot Coverage

- Snapshot-test generated `.pbxproj` for stable ordering and IDs.
- Validate generated project with `xcodebuild -list` and `xcodebuild build` on CI mac hosts.

## Non-goals

- No private Xcode project APIs.
- No on-device code signing or binary compilation.
