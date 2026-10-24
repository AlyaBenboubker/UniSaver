# Firebase account setup

## Connected resources

- Project: `gen-lang-client-0388206332`
- Apple app: `1:805954223213:ios:b2c1f375862feafc169364`
- Bundle ID: `alyaben.UniSaver`
- Firestore: `unisaver`, Enterprise native mode, `europe-west1` (Belgium)
- Providers: Email/password and Google Sign-In

The previous AI Studio database is not used by the Apple app.

## Apple configuration

FirebaseCore, FirebaseAuth, FirebaseFirestore, FirebaseStorage and GoogleSignIn are linked to the UniSaver app target. Firebase 12.19.2 is the newest compatible release: Firebase 13 and GoogleSignIn 10 currently have conflicting AppCheck dependencies. See the official FirebaseCore changelog.

`Configuration/GoogleService-Info.plist` inside the app source folder is included by Xcode folder synchronization. `Configuration/UniSaver-Info.plist` at the project level supplies the Google callback URL scheme. The app configures Firebase at startup before any Auth or Firestore use. Network client access, keychain access groups and `-ObjC` linker flags are configured.

No server credentials belong in the bundle. Personal AI provider keys stay local.

## Authentication

Settings → UniSaver account supports email sign-up, email sign-in, Google sign-in, password reset, sign-out and session restoration. Sign-in does not depend on a successful Firestore write.

## Firestore sync

All database calls explicitly target `Firestore.firestore(database: "unisaver")`.

The existing Sync now action uploads courses, tasks and completed work-session records under `users/{uid}`. It counts remote records; it does not yet merge those records into another device's SwiftData store. Full two-way sync remains future work.

The existing attachment upload code uses Cloud Storage. Storage provisioning and its rules are separate from the requested Authentication/Firestore setup; file uploads require that bucket to be configured.

## Security rules

`Firebase/firestore.rules` restricts reads and deletes to the path owner and validates creates/updates against the sync schemas. Record IDs, ownership and creation dates are protected; unknown fields and oversized strings/arrays are rejected. Imported historic date strings remain allowed. Each sync record requires an existing user profile.

These are prototype rules requiring review before broad release. The CLI dry run verifies compilation. Emulator behavioral tests require a Java runtime, which is not installed on this machine.

## Manual verification

1. Run the signed app from Xcode on macOS or iOS.
2. In Settings, create an email/password account, sign out and sign back in.
3. Request a password reset and verify the received email.
4. Sign out, continue with Google and complete the browser authorization.
5. Create a course/task and use Sync now without file attachments.
6. Confirm records in the `unisaver` database under `users/{uid}`.
7. Restart the app and confirm session restoration.
8. Verify a second account cannot access the first account's records.
