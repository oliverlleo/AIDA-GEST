# Authorization audit

The browser is untrusted. Auth UID and an existing Auth session identify the caller; an active workspace membership and the employee's current database roles determine access. User metadata, profile fields and the selected workspace header cannot grant privileges.

This migration closes direct REST writes that bypassed workflow actions. Technicians cannot change customer identity, budgets, purchases or deleted state. Technical clocks and repair completion use the existing guarded RPCs. Final test completion uses `conclude_ticket_test`, which validates the configured test role, assigned technician where applicable, active company, stage and allowed fields before updating. A tester receives only the transition acknowledgement when the ticket leaves their readable stage.

The trigger remains SECURITY INVOKER. Explicit SECURITY DEFINER workflow functions validate their own identity, active role, selected company and target objects before performing the derived updates. The two warranty workflows retain these explicit guards and run as definers so their legitimate derived changes do not require direct field privileges. Null technician assignments do not satisfy an assigned-technician check.

Notifications are selected by their real recipient as well as ticket visibility. The authenticated role can acknowledge `is_read`; it cannot invent notifications or replace message/destination fields. Deleted tickets and their dependent notes/photos/notifications remain hidden from nonadministrators. Photo upload validates the actual ticket when it exists; a hidden existing ticket cannot be treated as a new draft.

The public tracking token remains an intentional capability. Both public RPCs respect the company's public tracker switch. Previously issued signed Storage URLs remain usable until their expiry; denying future requests does not erase a downloaded file.

## Verification

Run `supabase/tests/run-auth-tests.ps1` against the task's portable PostgreSQL runtime and schema-only recovery directory. It creates a new synthetic database, never resets an existing one and never contacts production. Provide the local test password through a password file rather than a command argument. The suite covers current roles, forged metadata, other companies, blocked/revoked access, direct field writes, mixed roles, legitimate workflow RPCs and simultaneous invitation acceptance. It then rolls back this audit and the earlier Auth changes and compares the original metadata exactly.

JavaScript tests run through Node's test runner using the `*.test.js` and `*.test.mjs` files in `tests/`. They verify request payloads, workspace/JWT headers, agenda upsert, tester checklists and transitions, error behavior and application initialization.

Additional audit artifacts outside the repository record all public/private function signatures and privileges, 75 live relations and their columns, public frontend call sites, local HTTP role matrices and real unsigned/tampered-token rejection. They distinguish synthetic runtime tests from live schema/source verification. No real employee password or production employee session is required by those automated matrices.

## Recovery

Use `rollback_full_authorization_audit.sql` only to reverse this audit. It does not undo Supabase Auth, memberships or the earlier current-role correction. It restores the former permissions, including the weaknesses this change fixes. The schema-only recovery package and the complete pre-audit Git bundle are kept locally in the task's `outputs/` directory. No business rows, Auth accounts, Storage files or production credentials are copied.
