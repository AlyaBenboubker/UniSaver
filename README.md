# UniSaver

UniSaver is a native study workspace for courses, tasks, resources, flashcards and exam practice. It saves revision attempts and provides optional evidence-based AI coaching.

## Open and run

1. Use macOS with Xcode supporting the configured macOS/iPadOS 26.5 deployment targets and SwiftData.
2. Open `UniSaver.xcodeproj` and select the `UniSaver` scheme and My Mac. Resolve Swift packages using the committed `Package.resolved`.
3. Obtain the authorised Firebase Apple configuration for bundle `alyaben.UniSaver`. Place it at `UniSaver/Configuration/GoogleService-Info.plist`, using the adjacent example as a field guide. The real file is ignored. The app configures Firebase at startup, so an example with placeholders cannot run it.
4. Existing shareable URL configuration is in `Configuration/UniSaver-Info.plist`; it must match the authorised Google OAuth client. Keep project identity and signing unchanged unless your development environment requires a signing adjustment.
5. Run the app. Configure optional AI and Moodle credentials in Settings; credentials belong in Keychain, never source files.

Dependencies include Firebase and Google Sign-In, pinned through Swift Package Manager. Backend configuration targets project `gen-lang-client-0388206332`, named Firestore database `unisaver`. No backend deployment is needed just to inspect or build the source. Deployment requires separate authorised access and review. Copy `firebase.example.json` to the ignored `firebase.json` and supply your authorised support contact only if you need backend deployment.

## Study and persistence

Study has Practice, Mock exams and History. Objective grading uses stored keys; written AI feedback is provisional. Teacher papers preserve their original content. Attempts, retries and unfinished sessions are saved locally. Revision history is scoped to account identity, but revision sync is not implemented; existing account sync covers only part of the academic workspace. Other local academic records are not fully isolated between accounts.

## Verify

```sh
xcodebuild -project UniSaver.xcodeproj -scheme UniSaver \
  -destination 'platform=macOS' -derivedDataPath /tmp/UniSaverBuild test \
  -only-testing:UniSaverTests/RevisionHistoryTests \
  -only-testing:UniSaverTests/ExamLabTests \
  -only-testing:UniSaverTests/QuestionBankTests \
  -only-testing:UniSaverTests/RevisionTopicTests \
  -only-testing:UniSaverTests/RevisionCoachingTests CODE_SIGNING_ALLOWED=NO
```

Use isolated test stores. Provider/live suites are optional and can send data or incur charges. A focused pass does not establish that the whole suite passes. iPad runtime, production sync and all historical store migrations remain unverified. Private supplied course fixtures are excluded; parser tests use a synthetic replacement.

See [architecture and verification boundaries](architecturedoc.md), [product scope](PRODUCT_SCOPE.md), [revision history](REVISION_HISTORY.md), [Exam Lab](EXAM_LAB.md), [coaching](REVISION_COACHING.md) and [publication status](PUBLICATION_STATUS.md).
