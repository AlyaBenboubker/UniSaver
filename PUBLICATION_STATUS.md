# Publication preparation — 24 October 2026

## Local result

Prepared the existing Apple repository on `codex/lot-4-study-studio`. No remote was configured at initial preparation; the user later supplied `https://github.com/AlyaBenboubker/UniSaver.git`, now configured as origin. The separate parent web repository was left unchanged. Existing local source changes were preserved and included, together with resources, Swift package pins, backend rule files and shareable configuration. Backend rules were neither changed nor deployed by this publication preparation.

Updated README and architecturedoc.md from source inspection. Kept older scope documents as dated records; the current architecture explicitly separates delivered revision behaviour from the broader requested exam-preparation map.

Ignored actual Firebase client configuration, local deployment contact configuration, credentials, databases, private supplied teacher material, personal diagnostics, screenshots, worktrees and personal Xcode state. The previously tracked Xcode user scheme settings were removed from the index only; the local file remains. A synthetic 140-question fixture replaces the private fixture in parser tests. A placeholder Firebase client plist and firebase.example.json describe required configuration.

## Checks

- Scanned 251 historical Git blobs and candidate/staged content for common private-key, provider-token and Google API-key patterns. No matching credentials were found in committed history or publication candidates. This is a pattern audit, not a guarantee against every secret format.
- Confirmed private Firebase configuration, supplied fixture and local worktrees/screenshots are ignored.
- `git diff --cached --check` passed after whitespace cleanup.
- macOS Xcode 26.6 focused test command from README: **TEST SUCCEEDED**, 43 unique passing test cases; 1 unique skipped cases. The live provider test is opt-in and was not exercised. Test runner output can repeat cases across workers; counts here are unique names.
- Test output: `/tmp/unisaver-publication-tests-final.log` (local, not published). Tests built the macOS Debug application with signing disabled and used isolated stores. No fresh UI run, release signing, iPad run, production Firebase deployment, live AI request or complete-suite pass is claimed.
- Initial sandboxed Xcode attempt could not access compiler/package caches. The authorised rerun succeeded. An initial synthetic-fixture run exposed one test selecting a private prompt; it now selects the synthetic prompt and the final rerun passes.

## GitHub publication — 24 October 2026

Repository: [AlyaBenboubker/UniSaver](https://github.com/AlyaBenboubker/UniSaver).

The initial GitHub connector/browser access blocker was bypassed using the existing authenticated Git transport after the user supplied the repository URL. A network-enabled `git ls-remote` succeeded and returned no refs: the repository was empty, so there was no remote history to overwrite. The connector still returns 404; repository privacy and connector permissions were not verified through that API.

The prepared source and session logs are published as the initial `main` branch using an ordinary push from local `codex/lot-4-study-studio`, without renaming the local branch or force-pushing. Publication verification compares the remote main ref with local HEAD. No pull request is needed for an empty repository's initial branch.

Prepared commits include `babb377` (source and publication documentation) and `43c5c37` (consolidated session logs). This follow-up updates the publication record. The macOS focused test result remains 43 passing cases and one opt-in live-provider skip; no new application code or test run was introduced by configuring the remote.
