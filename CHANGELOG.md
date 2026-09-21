# Changelog

## 0.1.0 - 2026-09-21

### Added
* **ses:** `Alumna::SES < Alumna::Mailer`. `send` posts SES API v2 `SendEmail` (text, optional html, optional reply-to) with Signature Version 4. Success returns `nil`. HTTP, network, and TLS failures return `Alumna::MailError`.
* **ses:** `Alumna::SES.from_env` reads `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optional `AWS_SESSION_TOKEN`.
* **ses:** Empty region, empty keys, an empty session token, or a bad endpoint raise `ArgumentError`. `MailError` text does not include the secret, the access key, or the session token.
* **ci:** Format, spec, `preview_mt` with `execution_context`, and kcov 100% on `src/`. Default CI does not call Amazon.
