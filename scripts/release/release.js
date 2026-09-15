#!/usr/bin/env node
// scripts/release/release.js
//
// One command that does everything the Admin Dashboard's "App update"
// button does, minus the manual clicking:
//   1. Bump pubspec.yaml's build number (versionCode) — and optionally the
//      semantic version too (--bump=patch|minor|major).
//   2. `flutter build apk --release`.
//   3. Upload the built APK to Firebase Storage (releases/app-v{code}.apk).
//   4. Write config/appUpdate in Firestore so every running app picks up
//      the new version on next launch (services/app_update_service.dart).
//
// One-time setup (this script talks to Firebase as a service account, not
// via your interactive `firebase login` session, so it can run completely
// unattended):
//   1. Firebase Console → Project settings → Service accounts →
//      "Generate new private key" for project kaammitra-87e38.
//   2. Save the downloaded JSON as scripts/release/service-account.json
//      (already gitignored — never commit this file).
//   3. cd scripts/release && npm install
//
// Usage (from the repo root, or from scripts/release):
//   node scripts/release/release.js
//   node scripts/release/release.js --notes="Fixed call drops" --force
//   node scripts/release/release.js --bump=minor --notes="New chat ticks"
//   node scripts/release/release.js --dry-run
//
// Flags:
//   --notes="..."      release notes shown in the update dialog
//   --force            mark this update as non-dismissible ("Later" hidden)
//   --bump=patch|minor|major   also bump the semantic version (versionName);
//                       default: keep versionName, only bump the build number
//   --service-account=path   override the default service-account.json path
//   --dry-run           do everything except the actual build/upload/publish;
//                       just prints what would happen (useful to sanity-check
//                       the version bump first)
'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PUBSPEC_PATH = path.join(REPO_ROOT, 'pubspec.yaml');
const APK_PATH = path.join(
  REPO_ROOT,
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-release.apk',
);
const STORAGE_BUCKET = 'kaammitra-87e38.firebasestorage.app';

function parseArgs(argv) {
  const args = { notes: '', force: false, bump: null, dryRun: false, serviceAccount: null };
  for (const raw of argv) {
    if (raw === '--force' || raw === '--force=true') args.force = true;
    else if (raw === '--dry-run') args.dryRun = true;
    else if (raw.startsWith('--notes=')) args.notes = raw.slice('--notes='.length);
    else if (raw.startsWith('--bump=')) args.bump = raw.slice('--bump='.length);
    else if (raw.startsWith('--service-account=')) {
      args.serviceAccount = raw.slice('--service-account='.length);
    }
  }
  // 'none'/'' both mean "just bump the build number" — lets a VS Code task
  // input always pass --bump=<value> without needing a conditional arg.
  if (args.bump === 'none' || args.bump === '') args.bump = null;
  if (args.bump && !['patch', 'minor', 'major'].includes(args.bump)) {
    throw new Error(`--bump must be patch, minor, or major (got "${args.bump}")`);
  }
  return args;
}

/** pubspec.yaml `version: X.Y.Z+N` — bumps N always, optionally X/Y/Z too. */
function bumpPubspecVersion(bump) {
  const original = fs.readFileSync(PUBSPEC_PATH, 'utf8');
  const re = /^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$/m;
  const match = original.match(re);
  if (!match) {
    throw new Error('Could not find a `version: X.Y.Z+N` line in pubspec.yaml');
  }
  let [, major, minor, patch, code] = match.map(Number);
  code += 1;
  if (bump === 'patch') patch += 1;
  else if (bump === 'minor') { minor += 1; patch = 0; }
  else if (bump === 'major') { major += 1; minor = 0; patch = 0; }

  const versionName = `${major}.${minor}.${patch}`;
  const newLine = `version: ${versionName}+${code}`;
  fs.writeFileSync(PUBSPEC_PATH, original.replace(re, newLine));
  return { versionCode: code, versionName };
}

function buildReleaseApk() {
  console.log('\n▶ flutter build apk --release');
  execSync('flutter build apk --release', { cwd: REPO_ROOT, stdio: 'inherit' });
  if (!fs.existsSync(APK_PATH)) {
    throw new Error(`Build finished but APK not found at ${APK_PATH}`);
  }
}

function loadServiceAccount(explicitPath) {
  const candidate = explicitPath
    ? path.resolve(explicitPath)
    : path.join(__dirname, 'service-account.json');
  if (!fs.existsSync(candidate)) {
    throw new Error(
      `Service account key not found at ${candidate}.\n` +
      'See the setup steps at the top of scripts/release/release.js:\n' +
      'Firebase Console → Project settings → Service accounts → Generate new private key,\n' +
      'save it as scripts/release/service-account.json.',
    );
  }
  return candidate;
}

async function uploadApkAndPublish({ versionCode, versionName, notes, force, serviceAccountPath }) {
  const admin = require('firebase-admin');
  admin.initializeApp({
    credential: admin.credential.cert(require(serviceAccountPath)),
    storageBucket: STORAGE_BUCKET,
  });

  const destPath = `releases/app-v${versionCode}.apk`;
  console.log(`\n▶ Uploading ${path.basename(APK_PATH)} → gs://${STORAGE_BUCKET}/${destPath}`);
  await admin.storage().bucket().upload(APK_PATH, {
    destination: destPath,
    metadata: { contentType: 'application/vnd.android.package-archive' },
  });

  // storage.rules allows public read on releases/** (see storage.rules), so
  // the plain `?alt=media` REST URL works without a download token —
  // exactly the URL the app's plain `http.get()` download expects.
  const apkUrl =
    `https://firebasestorage.googleapis.com/v0/b/${STORAGE_BUCKET}/o/` +
    `${encodeURIComponent(destPath)}?alt=media`;

  console.log('▶ Writing config/appUpdate in Firestore');
  await admin.firestore().collection('config').doc('appUpdate').set({
    latestVersionCode: versionCode,
    versionName,
    apkUrl,
    releaseNotes: notes,
    forceUpdate: force,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return apkUrl;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  console.log(`Bumping pubspec.yaml version${args.bump ? ` (${args.bump})` : ' (build number only)'}...`);
  const { versionCode, versionName } = bumpPubspecVersion(args.bump);
  console.log(`  → version: ${versionName}+${versionCode}`);

  if (args.dryRun) {
    console.log('\n--dry-run: stopping here. pubspec.yaml has been updated;');
    console.log('re-run without --dry-run to actually build, upload, and publish.');
    return;
  }

  buildReleaseApk();

  const serviceAccountPath = loadServiceAccount(args.serviceAccount);
  const apkUrl = await uploadApkAndPublish({
    versionCode,
    versionName,
    notes: args.notes,
    force: args.force,
    serviceAccountPath,
  });

  console.log('\n✔ Release published.');
  console.log(`  versionCode : ${versionCode}`);
  console.log(`  versionName : ${versionName}`);
  console.log(`  apkUrl      : ${apkUrl}`);
  console.log(`  forceUpdate : ${args.force}`);
  console.log('\nDon\'t forget to commit the pubspec.yaml version bump:');
  console.log('  git add pubspec.yaml && git commit -m "Bump version"');
}

main().catch((err) => {
  console.error(`\n✘ Release failed: ${err.message}`);
  process.exit(1);
});
