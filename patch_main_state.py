import re

with open('js/main.js', 'r') as f:
    content = f.read()

# Add state variables directly into the return { ... } block if they are missing.
# We will inject them right before modals: { ... }
search_state = "        modals: { newEmployee: false, editEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false, notifications: false, recycleBin: false, logistics: false, outsourced: false, forceChangePassword: false, resetPassword: false, finishAnalysis: false, fornecedor: false, supplierPurchase: false },"

replace_state = """        // Scheduling State
        schedulePanelOpen: false,
        schedulePanelMode: '', // 'analysis' or 'repair'
        scheduleAvailabilityLoading: false,
        scheduleAvailabilityData: null,
        selectedAnalysisAppointment: null,
        selectedRepairAppointment: null,
        scheduleCurrentWeekStart: null,

        modals: { newEmployee: false, editEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false, notifications: false, recycleBin: false, logistics: false, outsourced: false, forceChangePassword: false, resetPassword: false, finishAnalysis: false, fornecedor: false, supplierPurchase: false },"""

if "schedulePanelOpen: false," not in content:
    content = content.replace(search_state, replace_state)

with open('js/main.js', 'w') as f:
    f.write(content)
