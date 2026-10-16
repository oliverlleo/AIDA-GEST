# Local authentication migration verification

Run `run-auth-tests.ps1` against an existing local PostgreSQL 17 runtime. It requires the separately exported structural baseline and the local-only Auth/Storage bootstrap. It never connects to Supabase, sends email, resets a database, deletes business records, or stops processes.

```powershell
.\supabase\tests\run-auth-tests.ps1 `
  -PostgresBin 'C:\path\to\pgsql\bin' `
  -RecoveryDirectory 'C:\path\to\recovery\database' `
  -PasswordFile 'C:\path\to\local-test-password.txt'
```

Defaults resolve the portable runtime and recovery files beside the repository. The runner uses `127.0.0.1:54329`, creates a fresh database named `aida_auth_review_<timestamp>`, and retains it and its logs for inspection. It refuses an existing database. The scripts independently enforce loopback access. The test identities use reserved `example.invalid` addresses and synthetic sessions; they do not replace end-to-end tests against the Supabase Auth HTTP service.

The 31 stages include a loopback-guarded fixture that aligns two earlier audit functions with their production `postgres` ownership. This compensates for the separate portable bootstrap administrator without granting internal helpers to client roles or editing historical migrations.

Coverage:

- Confirmed email and real session checks, forged JWT metadata/email, protected profile writes and legacy authentication revocation.
- Owner of A as technician of B, tenant headers, role changes with an existing JWT, employee IDs and server-stamped attribution.
- Pending discovery, wrong account, expiry, cancellation, reissue, idempotent acceptance and fresh reinvitation after removal.
- Two real concurrent PostgreSQL processes accept the same invitation under the same verified identity. The first holds its transaction for one second; the runner observes the second connection waiting on a lock, verifies both return the same workspace, and asserts exactly one membership/employee and the correct accepted user.
- Authenticated technician photo upload/read/update, role restrictions, schedule creator XOR identity and inventory RPC isolation.
- Per-company blocking and session invalidation; refreshing the same session cannot bypass revocation, and access to another company remains independent.
- Direct self-promotion through employee roles, profiles, workspace ownership, memberships, invitations, administrative RPCs, catalogs and Storage is rejected even with forged admin metadata. The tests verify records remain unchanged.
- Retained ticket/appointment assignments do not preserve technician powers after a role downgrade. The same session is rejected for appointment start/completion and repair start; assigned technicians, attendants and owners retain their legitimate operations.
- Public tracker with a valid token, server-only delivery reservation/cooldown, outdated worker claims and safe failed configuration. No email is sent.
- Abuse protection: real result sets larger than default page limits, `NULL` pagination, duplicate and oversized location arrays, authenticated upload reservations, role/company isolation, image sizes/types, reservation expiry and restrictive Storage policies. These probes run inside a transaction that is rolled back.
- Abuse protection rollback compares fourteen metadata groups, including bucket configuration, GraphQL schema ACLs and the database-specific request hook, before the older authentication rollbacks continue. Frequency and read-only concurrency are verified separately through a loopback PostgREST in COMMIT mode; a transaction-rollback HTTP server cannot prove persisted counters.
- Rollback after new employee records, tickets, notes, photos, appointments and inventory were created. Eleven metadata groups are compared exactly: tables, columns, constraints, indexes, triggers, functions, policies, table privileges, column privileges, function privileges and schema privileges. Legacy hashes/deletion flags and operational employee IDs must remain unchanged.

Deployment still requires verified Auth confirmation/recovery URLs and an end-to-end controlled account test. Invitation acceptance works through the application and copied links while outbound mail is unconfigured.

The current-role correction has its own rollback, `supabase/rollback_current_role_operational_guards.sql`. It restores only three function definitions. For a complete reversal to the pre-Auth baseline, run this correction's rollback before `supabase/rollback_auth_workspace_memberships.sql`; the runner checks both reversals and exact baseline equivalence.
