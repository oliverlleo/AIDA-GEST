# Local authentication migration verification

Run `run-auth-tests.ps1` against an existing local PostgreSQL 17 runtime. It requires the separately exported structural baseline and the local-only Auth/Storage bootstrap. It never connects to Supabase, sends email, resets a database, deletes business records, or stops processes.

```powershell
.\supabase\tests\run-auth-tests.ps1 `
  -PostgresBin 'C:\path\to\pgsql\bin' `
  -RecoveryDirectory 'C:\path\to\recovery\database' `
  -PasswordFile 'C:\path\to\local-test-password.txt'
```

Defaults resolve the portable runtime and recovery files beside the repository. The runner uses `127.0.0.1:54329`, creates a fresh database named `aida_auth_review_<timestamp>`, and retains it and its logs for inspection. It refuses an existing database. The scripts independently enforce loopback access. The test identities use reserved `example.invalid` addresses and synthetic sessions; they do not replace end-to-end tests against the Supabase Auth HTTP service.

Coverage:

- Confirmed email and real session checks, forged JWT metadata/email, protected profile writes and legacy authentication revocation.
- Owner of A as technician of B, tenant headers, role changes with an existing JWT, employee IDs and server-stamped attribution.
- Pending discovery, wrong account, expiry, cancellation, reissue, idempotent acceptance and fresh reinvitation after removal.
- Two real concurrent PostgreSQL processes accept the same invitation under the same verified identity. The first holds its transaction for one second; the runner observes the second connection waiting on a lock, verifies both return the same workspace, and asserts exactly one membership/employee and the correct accepted user.
- Authenticated technician photo upload/read/update, role restrictions, schedule creator XOR identity and inventory RPC isolation.
- Per-company blocking and session invalidation; refreshing the same session cannot bypass revocation, and access to another company remains independent.
- Public tracker with a valid token, server-only delivery reservation/cooldown, outdated worker claims and safe failed configuration. No email is sent.
- Rollback after new employee records, tickets, notes, photos, appointments and inventory were created. Eleven metadata groups are compared exactly: tables, columns, constraints, indexes, triggers, functions, policies, table privileges, column privileges, function privileges and schema privileges. Legacy hashes/deletion flags and operational employee IDs must remain unchanged.

Deployment still requires verified Auth confirmation/recovery URLs and an end-to-end controlled account test. Invitation acceptance works through the application and copied links while outbound mail is unconfigured.
