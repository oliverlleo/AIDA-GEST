
# Hardening Verification Checklist

## Admin Workflows
- [ ] **Login**: Admin can login successfully.
- [ ] **Dashboard**: KPIs load correctly (`get_dashboard_kpis`).
- [ ] **Create Ticket**: Admin can create a ticket.
- [ ] **Kanban**: Admin can view Kanban board.
- [ ] **Manage Employees**:
    - [ ] Create Technician (`create_employee`).
    - [ ] Edit Technician (`update_employee`).
    - [ ] Reset Password (`reset_employee_password`).
    - [ ] List Employees (`get_employees_for_workspace`).

## Employee Workflows
- [ ] **Login**: Employee can login (`employee_login`).
- [ ] **Dashboard**: KPIs and Operational Alerts load (`get_operational_alerts`).
- [ ] **View Tickets**: Employee can view their assigned tickets.

## Public Tracking
- [ ] **Valid Link**: `acompanhar.html?id=...&token=...` loads ticket details (`get_client_ticket_details_public`).
- [ ] **Invalid Link**: Access without token or invalid token fails gracefully.

## Storage & Assets
- [ ] **Admin Ticket Photo**:
    - Upload photo -> Save.
    - Reload ticket -> Image appears (Signed URL generated).
- [ ] **Employee Ticket Photo**:
    - Upload photo (`x-employee-token` present) -> Save.
    - Reload ticket -> Image appears (Signed URL works for anon+token).
- [ ] **Workspace Logo**:
    - Admin can upload logo.
    - Logo preview works (Public bucket).
    - Anon CANNOT upload logo (Policy restricted).

## Technical Verification (Automated)
- [ ] **RPC EXECUTE**: `PUBLIC` has 0 grants.
- [ ] **Table Grants**: `anon`/`authenticated` have NO `TRUNCATE`, `TRIGGER`, `REFERENCES`.
- [ ] **Security Definer**: All SD functions have `SET search_path`.
- [ ] **Employee Sessions**: Locked down (No direct access for anon/auth).
