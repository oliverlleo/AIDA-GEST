-- Remove the default PUBLIC execute privilege from internal warranty triggers.
-- Trigger execution continues normally because PostgreSQL invokes trigger
-- functions through the trigger owner, not through a client RPC call.

revoke all on function private.validate_warranty_tracker_config() from public;
revoke all on function private.enforce_ticket_warranty() from public;
