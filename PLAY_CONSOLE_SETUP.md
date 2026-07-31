# ExamSaathi Play Console Setup

## Release artifact

- Upload file: `build/app/outputs/bundle/release/app-release.aab`
- SHA-256: `198e0285c6bc4a0441293e10f480bfa949e142b75952dc07f2590f803d5955ec`
- Package name: `com.myexamsaathi`
- App name: `ExamSaathi`
- Version name: `1.0.0`
- Version code: `12`
- Target SDK: `35`
- Min SDK: `21`

## Create app

- Default language: `English (United States)` or `English (India)`
- App or game: `App`
- Free or paid: `Free`
- Declarations: accept Developer Program Policies and US export laws.

## Play App Signing

- Use the default Play App Signing option for a new app.
- The uploaded bundle is signed with the local upload key alias `examsaathi`.
- Do not upload `android/keystore.properties` or `android/app/keystore.jks` anywhere except secure backups/password manager storage.

## Firebase package configuration

The Android package is now `com.myexamsaathi`.

Firebase has a registered Android app for this package:

- Firebase project: `exam-saathi-student`
- Firebase Android app id: `1:888079860458:android:e38a82f16223ddf95e0d93`
- Android package name: `com.myexamsaathi`
- App nickname: `ExamSaathi Android`
- Upload-key SHA-1:
  `C9:74:A5:21:A1:50:C6:61:8C:B6:59:B8:87:AE:80:D7:54:6B:9F:5B`

The generated config files are:

- `android/app/google-services.json`
- `lib/firebase_options.dart`

## Recommended first release track

Start with `Testing > Internal testing`.

- Create tester list with your email first.
- Create a release.
- Upload `build/app/outputs/bundle/release/app-release.aab`.
- Release name: `1.0.0 (12)`
- Release notes:

```text
Initial ExamSaathi test release.

- Track exam preparation progress
- Manage selected exams and subjects
- Use offline-first study progress sync
- Take topic mock tests
- Enable optional daily study reminders
```

After Play processes the release, copy the opt-in link and install from Google Play as a tester.

## Current release permissions

Play-facing merged manifest includes:

- `android.permission.INTERNET`
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.ACCESS_NETWORK_STATE`
- `android.permission.WAKE_LOCK`
- `android.permission.VIBRATE`
- `android.permission.USE_BIOMETRIC`
- `android.permission.USE_FINGERPRINT`
- `com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE`

It does not include:

- Advertising ID / AdServices permissions
- `android.permission.SCHEDULE_EXACT_ALARM`

## Production checks already completed

- Release AAB builds successfully.
- Bundle signature verifies.
- Backend health endpoint responds over HTTPS.
- Public exam catalog endpoint responds.
- Firebase Android config matches package `com.myexamsaathi`.
- Verify Google Sign-In on the first internal testing install.
- Flutter smoke test passes.
