# MARK6 Security Plan

## Biggest MARK5 Issue

MARK5 writes login credentials to cookies:

```text
Set-Cookie: user=<name>
Set-Cookie: pwd=<password>
```

The admin area then reads those cookies and verifies them against `dat/user.cgi`.

MARK6 must not store user names and passwords as client-side authentication state.

## MARK6 Authentication Policy

Use server-side session files:

1. User submits login form over HTTPS.
2. Server verifies password.
3. Server creates a random session id.
4. Server writes `dat/sessions/<session_id>.json`.
5. Browser receives only the opaque session id.

Cookie use is limited to the session id only. It must never contain password data.

Recommended cookie flags:

```text
HttpOnly
Secure
SameSite=Strict
Path=/
```

If the deployment truly needs zero cookies, support an optional admin-only URL token mode later, but do not make that the default because URLs leak through logs and history.

Implementation starts in `lib/Mark6/Auth.pm`.

## Password Hashing

Prefer a modern hash:

- Argon2id if available.
- bcrypt if Argon2id is unavailable.
- PBKDF2-HMAC-SHA256 as the minimal portable fallback.

Do not use Perl `crypt()` as the MARK6 default.

The first MARK6 implementation uses PBKDF2-HMAC-SHA256 as the portable baseline. Argon2id or bcrypt can be added later when deployment dependencies are known.

## CSRF

Every admin write form should include a CSRF token.

Store only the token hash in the session file.

## Rate Limiting

Add simple file-based login throttling:

```text
dat/security/login_attempts.json
```

Throttle by normalized user name and IP hash.

## File Uploads

Uploader requirements:

- Deny executable extensions by default.
- Normalize filenames.
- Prevent path traversal.
- Enforce max file size.
- Store uploads outside CGI executable directories when possible.
- Never trust MIME type from the browser.

## Permissions

Recommended production permissions:

- CGI files: readable/executable by web server.
- `dat/`, `file/`, `img/`: writable by web server.
- `dat/sessions/`: not web-readable.
