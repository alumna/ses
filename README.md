# Alumna SES

[![Crystal CI](https://github.com/alumna/ses/actions/workflows/ci.yml/badge.svg)](https://github.com/alumna/ses/actions/workflows/ci.yml) ![Dynamic YAML Badge](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Falumna%2Fses%2Frefs%2Fheads%2Fmaster%2Fshard.yml&query=version&prefix=v&label=version) ![GitHub License](https://img.shields.io/github/license/alumna/ses)

Amazon SES mailer for the [Alumna Backend Framework](https://github.com/alumna/backend). Published at [alumna/ses](https://github.com/alumna/ses) **0.1.0**.

`Alumna::SES` implements `Alumna::Mailer`. The only method is `send`. This shard is not a Service adapter.

`send` posts SES API v2 `SendEmail` (`POST /v2/email/outbound-emails`). The body is text plus optional HTML. The shard signs the request with Signature Version 4 and stdlib `HTTP::Client`. There is no AWS SDK.

See [ROADMAP.md](ROADMAP.md).

---

## Table of Contents

1. [Installation](#1-installation)
2. [Credentials](#2-credentials)
3. [Send](#3-send)
4. [Endpoint](#4-endpoint)
5. [Errors](#5-errors)
6. [Security](#6-security)
7. [Testing](#7-testing)
8. [License](#8-license)

---

## 1. Installation

Add it to your `shard.yml`:

```yaml
dependencies:
  alumna:
    github: alumna/backend
    version: ~> 0.10.0
  alumna-ses:
    github: alumna/ses
    version: ~> 0.1.0
```

Then run `shards install`.

```crystal
require "alumna-ses"
```

Needs Alumna Backend **0.10.0** (`Alumna::Mailer`). Crystal **1.20.2** or later.

For development purposes, you can use a gitignored `shard.override.yml` that refers to a locally changed Alumna Backend, like with:

```yaml
dependencies:
  alumna:
    path: ../backend
```

`shard.yml` keeps `github: alumna/backend`. Do not put `path:` in `shard.yml`.

---

## 2. Credentials

Pass the region and keys to `new`, or read process `ENV` with `from_env`. There is no dotenv parser. Do not commit secrets.

| Name | Role |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access key |
| `AWS_SECRET_ACCESS_KEY` | Secret |
| `AWS_REGION` | Region, for example `sa-east-1` |
| `AWS_SESSION_TOKEN` | Optional session token |

```crystal
mailer = Alumna::SES.from_env

mailer = Alumna::SES.new(
  region: ENV["AWS_REGION"],
  access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  session_token: ENV["AWS_SESSION_TOKEN"]?,
)
```

`from` on the message is required. SES does not choose a from-address.

A missing or empty `AWS_REGION`, `AWS_ACCESS_KEY_ID`, or `AWS_SECRET_ACCESS_KEY` raises `ArgumentError` in `from_env`. An empty `AWS_SESSION_TOKEN` raises `ArgumentError`. Omit that variable when there is no session token.

The region is a lowercase token (`sa-east-1`). Any other shape raises `ArgumentError`.

---

## 3. Send

```crystal
require "alumna-ses"

mailer = Alumna::SES.from_env
mail = Alumna::Mail.new(
  from: "noreply@example.com",
  to: ["a@example.com", "b@example.com"],
  subject: "Verify your email",
  text: "Open this link.",
  html: "<p>Open this link.</p>",
  reply_to: "reply@example.com",
)
result = mailer.send(mail)
if result.is_a?(Alumna::MailError)
  # The send failed. Do not log the secret.
end
```

The JSON body is `Content.Simple`:

| Mail field | SES field | Rule |
|---|---|---|
| `from` | `FromEmailAddress` | Required. |
| `to` | `Destination.ToAddresses` | One or more addresses. |
| `subject` | `Content.Simple.Subject` | Charset `UTF-8`. |
| `text` | `Content.Simple.Body.Text` | Charset `UTF-8`. `""` is sent. |
| `html` | `Content.Simple.Body.Html` | Optional. `nil` and `""` omit the HTML part. |
| `reply_to` | `ReplyToAddresses` | Optional. One address. |

`nil` means SES accepted the message (HTTP 2xx). `Alumna::MailError` means SES rejected it, or the HTTP connection or TLS handshake failed. `send` returns that struct. The call does not raise it.

Call `send` from `after_commit` when the message must follow a successful write. Keep cache and the logger on `before` and `after`. If the rule returns `ServiceError`, the client sees an error. The adapter write already completed.

```crystal
app.after_commit on: :mutate do |ctx|
  failed = mailer.send(mail)
  next Alumna::ServiceError.internal(failed.message) if failed.is_a?(Alumna::MailError)
end
```

This release has no attachments. `SendRawEmail` is later. See [ROADMAP.md](ROADMAP.md).

---

## 4. Endpoint

The default URL is `https://email.{region}.amazonaws.com/v2/email/outbound-emails`.

Pass `endpoint:` for a VPC endpoint or another host. `http` and `https` are accepted. A URL with userinfo or a query string raises `ArgumentError`. An empty path or `/` receives the `SendEmail` path. Any other path is kept.

```crystal
Alumna::SES.new(
  region: "sa-east-1",
  access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  endpoint: "https://vpce.example.com/custom",
)
```

The signed `Host` header is the host the client uses. A port other than 80 (HTTP) or 443 (HTTPS) is included (`127.0.0.1:8443`). The default ports are omitted.

---

## 5. Errors

`Alumna::MailError` is a struct with `message`. `to_s` writes that message. It is not `StoreError` and it is not an exception. Map it to `ServiceError.internal` when the HTTP response must fail.

| Result | When |
|---|---|
| `nil` | HTTP 2xx |
| `MailError` `"SES send failed (status): …"` | HTTP status outside 2xx, with the SES `message` or `Message` field |
| `MailError` `"SES send failed (status)"` | HTTP status outside 2xx, and the body has no string message |
| `MailError` `"mail send failed"` | Connection or TLS failure |
| `ArgumentError` | Empty or invalid region, empty keys, empty session token, or a bad endpoint |

`MailError` text does not include the secret access key, the access key id, or the session token.

Empty `from`, empty `to`, empty `subject`, or empty `reply_to` raises `ArgumentError` in `Mail.new`, before `send`.

---

## 6. Security

- Do not log the secret access key, the session token, or the `Authorization` header.
- Do not log the message body. It can contain private text.
- `MailError` replaces the secret, the access key id, and the session token with `[redacted]`.
- Keep credentials in process `ENV`. Do not commit them.
- Use `https` for Amazon and for any endpoint that is not on the same machine.

---

## 7. Testing

Application specs use `Alumna::MemoryMailer` from Backend. They do not need this shard or Amazon.

Specs in this repository post to a fake HTTP transport. One spec posts to a local HTTP server through `HTTP::Client`. Default CI does not call Amazon and does not read AWS secrets.

Set `AWS_SES_LIVE=1` plus `AWS_SES_FROM` and `AWS_SES_TO` to run the live example. It stays pending when the flag is unset. `from_env` then also needs `AWS_REGION`, `AWS_ACCESS_KEY_ID`, and `AWS_SECRET_ACCESS_KEY`.

GitHub Actions on [alumna/ses](https://github.com/alumna/ses/actions/workflows/ci.yml):

- Format check
- Specs
- Specs with `preview_mt` and `execution_context`
- kcov on `src/` (line-rate 1.000)

---

## 8. License

MIT
