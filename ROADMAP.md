# Alumna SES — roadmap

Official Amazon SES implementation of `Alumna::Mailer`. Published at [alumna/ses](https://github.com/alumna/ses) **0.1.0**.

Not a Service adapter. No `AdapterSuite`. SMTP is a different shard.

## 0.1.0

* `Alumna::SES < Alumna::Mailer`. One method: `send`.
* SES API v2 `SendEmail` (text, optional html, optional reply-to).
* Signature Version 4 with stdlib `HTTP::Client`. No AWS SDK.
* `from_env` reads `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optional `AWS_SESSION_TOKEN`.
* Config mistakes raise `ArgumentError`. HTTP, network, and TLS failures return `Alumna::MailError`.
* Specs use a fake HTTP transport. One spec posts to a local HTTP server. Default CI does not call Amazon.
* GitHub CI: format, spec, `preview_mt` + `execution_context`, kcov 100% on `src/`.

## Later

* `SendRawEmail` and attachments.
* SMTP stays a different shard.
