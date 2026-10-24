# Publication preparation — 24 October 2026

## Local result

Prepared the existing Apple repository on `codex/lot-4-study-studio`. No remote was configured. The separate parent web repository was left unchanged. Existing local source changes were preserved and included, together with resources, Swift package pins, backend rule files and shareable configuration. Backend rules were neither changed nor deployed by this publication preparation.

Updated README and architecturedoc.md from source inspection. Kept older scope documents as dated records; the current architecture explicitly separates delivered revision behaviour from the broader requested exam-preparation map.

Ignored actual Firebase client configuration, local deployment contact configuration, credentials, databases, private supplied teacher material, personal diagnostics, screenshots, worktrees and personal Xcode state. The previously tracked Xcode user scheme settings were removed from the index only; the local file remains. A synthetic 140-question fixture replaces the private fixture in parser tests. A placeholder Firebase client plist and firebase.example.json describe required configuration.

## Checks

- Scanned 251 historical Git blobs and candidate/staged content for common private-key, provider-token and Google API-key patterns. No matching credentials were found in committed history or publication candidates. This is a pattern audit, not a guarantee against every secret format.
- Confirmed private Firebase configuration, supplied fixture and local worktrees/screenshots are ignored.
- `git diff --cached --check` passed after whitespace cleanup.
- macOS Xcode 26.6 focused test command from README: **TEST SUCCEEDED**, 43 unique passing test cases; 1 unique skipped cases. The live provider test is opt-in and was not exercised. Test runner output can repeat cases across workers; counts here are unique names.
- Test output: `/tmp/unisaver-publication-tests-final.log` (local, not published). Tests built the macOS Debug application with signing disabled and used isolated stores. No fresh UI run, release signing, iPad run, production Firebase deployment, live AI request or complete-suite pass is claimed.
- Initial sandboxed Xcode attempt could not access compiler/package caches. The authorised rerun succeeded. An initial synthetic-fixture run exposed one test selecting a private prompt; it now selects the synthetic prompt and the final rerun passes.

## Publication blocked

The GitHub connector identifies a login but returns no accessible repositories. Repository search for that account returns an access/validation error. It exposes no repository-creation operation in this environment. GitHub CLI is unavailable, and the in-app browser redirects github.com/new to sign-in. No remote URL can therefore be confirmed, no private repository can be created, and no push or pull request has occurred.

To finish: establish GitHub access that can create/access the intended private UniSaver repository, confirm its URL, add it as the remote of this Apple repository, and push the prepared commit without force. If an existing repository is supplied, inspect its history before integrating; do not overwrite it. If its main branch is protected, push a dedicated branch and open a pull request. No repository/commit web link should be fabricated before this succeeds.
