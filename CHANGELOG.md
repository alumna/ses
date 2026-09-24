# Changelog

## Unreleased

### Changed
* **ci:** `actions/checkout@v7`, `actions/cache@v6`, and `codecov/codecov-action@v7`. The coverage job uploads kcov, unreachable, and macro coverage reports to Codecov, and uploads JUnit test results to Codecov Test Analytics. The 100% line coverage check on `src/` stays.
* **ses:** `Alumna::SES::SigV4` is a module, not a struct. It has only class methods, so the struct constructor was unreachable code (Codecov reported `src/ses/sig_v4.cr` line 14 as not covered). `SigV4.sign` does not change. The release build of `sign` is the same.

## 0.1.0 - 2026-09-21

### Added
* **ses:** `Alumna::SES < Alumna::Mailer`. `send` posts SES API v2 `SendEmail` (text, optional html, optional reply-to) with Signature Version 4. Success returns `nil`. HTTP, network, and TLS failures return `Alumna::MailError`.
* **ses:** `Alumna::SES.from_env` reads `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optional `AWS_SESSION_TOKEN`.
* **ses:** Empty region, empty keys, an empty session token, or a bad endpoint raise `ArgumentError`. `MailError` text does not include the secret, the access key, or the session token.
* **ci:** Format, spec, `preview_mt` with `execution_context`, and kcov 100% on `src/`. Default CI does not call Amazon.
