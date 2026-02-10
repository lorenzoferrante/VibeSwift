# Release Automation

This repository now automates branch-to-TestFlight delivery with agent guidance plus GitHub Actions.

## Agent command phrase

Use a request like:

- `Commit these changes to a new branch, push, and open a PR.`

The agent rule in `.cursor/rules/branch-pr-release-flow.mdc` enforces this sequence:

1. local iOS build first
2. branch creation and commit
3. push to `origin`
4. PR creation

If the local build fails, the flow stops before push/PR.

## Branch naming convention

Use one of:

- `feature/<short-description>`
- `fix/<short-description>`
- `chore/<short-description>`

Examples:

- `feature/testflight-automation`
- `fix/pr-build-signing`

## GitHub workflows

- `.github/workflows/pr-build.yml`
  - Trigger: pull requests targeting `main`
  - Action: resolve packages + build for iOS Simulator without signing
- `.github/workflows/testflight-release.yml`
  - Trigger: push to `main` (merged PR)
  - Action: archive signed app, export IPA, upload to TestFlight

## One-time setup

1. Ensure `origin` remote exists for PR automation:
   - `git remote -v`
2. Add these repository secrets:
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_PRIVATE_KEY` (full `.p8` content)
3. In App Store Connect, grant the API key permissions to upload builds.
4. Enable branch protection on `main` and require status check `PR Build`.
5. Confirm the shared scheme exists at:
   - `VibeSwift.xcodeproj/xcshareddata/xcschemes/VibeSwift.xcscheme`

## Failure handling

- **Local build fails (agent step)**: no commit/push/PR is performed.
- **PR build workflow fails**: fix branch and push updates; PR check reruns automatically.
- **TestFlight workflow fails**:
  1. inspect `testflight-release` workflow logs
  2. verify signing/API secrets
  3. retry by pushing a fix commit to `main`

## Notes

- This project uses `IPHONEOS_DEPLOYMENT_TARGET = 26.2`; ensure GitHub runner Xcode version supports that SDK.
- Export behavior is pinned in `ci/ExportOptions.plist`.
