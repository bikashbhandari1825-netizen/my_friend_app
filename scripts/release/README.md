# Release script

One command that replaces the manual "build APK → upload to Storage → fill
in the Admin Dashboard form" loop with a single script run.

It bumps `pubspec.yaml`'s build number, runs `flutter build apk --release`,
uploads the APK to Firebase Storage, and writes `config/appUpdate` in
Firestore — the same document `services/app_update_service.dart` checks on
every app launch.

## One-time setup

1. Firebase Console → **Project settings** → **Service accounts** →
   *Generate new private key* (project `kaammitra-87e38`).
2. Save the downloaded JSON as `scripts/release/service-account.json`.
   This file is gitignored — it is a credential, never commit it.
3. `cd scripts/release && npm install`

## Usage

From VS Code: **Command Palette → "Tasks: Run Task"** → pick one of:

- **Release: Publish App Update** — prompts for release notes, a version
  bump type, and whether to force the update, then does everything.
- **Release: Dry Run** — only bumps `pubspec.yaml` and prints what would
  happen; nothing is built, uploaded, or published. Useful to sanity-check
  the version number before committing to a real build.
- **Release: Install script dependencies** — `npm install` for this folder.

From a terminal:

```sh
cd scripts/release
node release.js                                  # bump build number only
node release.js --notes="Fixed call drops"
node release.js --bump=minor --notes="New chat ticks"
node release.js --force                           # non-dismissible update
node release.js --dry-run --bump=patch             # preview only
```

After a successful run, commit the `pubspec.yaml` version bump:

```sh
git add pubspec.yaml && git commit -m "Bump version to <name>+<code>"
```

## What it touches

- `pubspec.yaml` — `version: X.Y.Z+N` line, build number always incremented.
- Firebase Storage: `releases/app-v{code}.apk` (public read, per
  `storage.rules`).
- Firestore: `config/appUpdate` (`latestVersionCode`, `versionName`,
  `apkUrl`, `releaseNotes`, `forceUpdate`).
