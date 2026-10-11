# Security Policy

## Supported versions

This repository has no tagged releases yet. Only the latest commit on `main` is supported; fixes land there.

| Version | Supported |
|---|---|
| `main` (latest commit) | Yes |
| Anything older | No |

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Report it privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**
(private vulnerability reporting). Include what you found, how to reproduce it, and the impact you see.

You can expect an acknowledgement within 7 days. Once the issue is confirmed, a fix is published on `main` and
described in [`CHANGELOG.md`](CHANGELOG.md) under **Security**.

## Scope

This repository holds terminal configuration and a small Go tool (`herdr-ctl`) that runs on the owner's Mac. It must
never contain secrets, tokens, passwords or local network details; if you find any, report it the same way.
