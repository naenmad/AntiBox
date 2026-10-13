# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.2.x   | :white_check_mark: |
| < 1.2.0 | :x:                |

## Security Architecture

ZedGravity is engineered with strict local-first security principles:

1. **Local-Only Storage**: Refresh tokens and credentials are stored strictly on your local disk at `~/Library/Application Support/ZedGravity/` with POSIX `0600` permissions (readable only by your user account).
2. **Zero Third-Party Relays**: ZedGravity does not run telemetry, analytics, or proxy servers. All API traffic routes directly between your machine and official Google Cloud endpoints (`oauth2.googleapis.com` and `cloudcode-pa.googleapis.com`).
3. **No Root Privileges**: The application never requests `sudo` or runs root daemons.

## Reporting a Vulnerability

If you discover a security issue or vulnerability:

1. **Do not create a public issue**.
2. Report the vulnerability privately via GitHub Security Advisories or email `security@naenmad.com`.
3. Provide a clear description, reproduction steps, and impact assessment.

We take all security reports seriously and will acknowledge receipt within 48 hours.
