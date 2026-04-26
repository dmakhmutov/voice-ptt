---
name: release
description: Cut a new GitHub release of VoicePTT (bump version, build, package zip, publish via gh).
---

# /release — publish a new version of VoicePTT

The user wants to ship a new release. There's already a `./release.sh` helper at the repo root that does the mechanical work. Your job is to gather the inputs, run pre-flight checks, run the script, and verify the result.

## Inputs

The user usually invokes this as `/release <version> [notes]`. If anything is missing, ask. Don't guess.

- **`version`** — semantic version string without the `v` prefix, e.g. `0.2`, `0.2.1`, `1.0`. Compare against the latest existing tag (`gh release list --limit 1`) and refuse to go backwards. Default convention: bump the patch (third) component for FluidAudio bumps and bug fixes; bump minor for new features.
- **`notes`** — short user-facing release notes. If the user doesn't supply notes, draft them yourself from `git log <last-tag>..HEAD --oneline` (one line per noteworthy commit) and confirm with the user before proceeding.

## Pre-flight (run in parallel where possible)

1. `git status --porcelain` — must be empty. If dirty, surface what's uncommitted and ask the user to commit/stash first.
2. `git rev-parse --abbrev-ref HEAD` — should be `main`. If not, ask the user to confirm releasing from a non-main branch.
3. `gh release view v<version>` — must fail (release shouldn't already exist).
4. `gh auth status` — must be logged in. If not, instruct the user to run `! gh auth login`.
5. `security find-certificate -c "VoicePTT Local"` — must succeed. The release uses stable signing so the Accessibility grant survives the swap. If the cert is missing, fall back to ad-hoc signing (build.sh handles this) but warn the user that downstream installs will require re-granting Accessibility.

## Run

```sh
./release.sh <version> "<notes>"
```

`release.sh` will:
1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`
2. `git commit -m "release: v<version>"` and push
3. Run `./build.sh` (swift build -c release + .app bundling + codesign)
4. `ditto -c -k --sequesterRsrc --keepParent VoicePTT.app VoicePTT-<version>.zip`
5. `gh release create v<version> VoicePTT-<version>.zip --title "v<version>" --notes "<notes>"`

The script aborts early if the working tree is dirty or the tag already exists, so you don't need to defensively rerun checks inside it.

## Verify

After it completes, confirm the result:

- `gh release view v<version> --json tagName,assets -q '.tagName + " — " + (.assets[0].name)'` — should print the tag and the attached zip.
- The release page URL is printed by the script. Surface it to the user as the final output.
- The local `VoicePTT.app` on disk is now the new version. The currently running app (if any) is still the old one until the user clicks **Download & install** in Settings → Updates.

## Common gotchas

- **`xcrun: error: unable to lookup item 'PlatformPath'`** during build — cosmetic warning from XCTest path probing on Command Line Tools. The build still succeeds. Ignore.
- **`gh release create` fails with "tag already exists"** — a previous failed run created the tag locally without pushing. Inspect with `git tag --list 'v*'`. If safe, delete with `git tag -d v<version>` and rerun.
- **Build fails with "incompatible tools version (6.0.0)"** — the Swift toolchain is older than 6.0 and the FluidAudio version in `Package.swift` requires Swift 6. Either bump CLT (`softwareupdate -i "Command Line Tools for Xcode-16.4"`) or pin FluidAudio to a Swift-5 compatible range.
- **Don't run `/release` for a version that just bumps `Package.swift`'s FluidAudio without rebuilding/testing locally first.** The point of releasing is shipping a tested binary; verify the new build at least starts and the menubar Status panel goes green before publishing.

## What this skill must not do

- Don't edit `Resources/Info.plist` manually — `release.sh` is the only thing that touches `CFBundleShortVersionString`.
- Don't create the git tag manually with `git tag` — `gh release create` does it.
- Don't push force, rebase, or rewrite history. Releases are immutable points in main's history.
- Don't delete previous releases without an explicit user request.
