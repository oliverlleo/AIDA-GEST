import re

with open('js/main.js', 'r') as f:
    content = f.read()

search_reset = """        openNewTicketModal() {
            this.ticketForm = {"""

replace_reset = """        openNewTicketModal() {
            // Reset Scheduling State
            this.schedulePanelOpen = false;
            this.schedulePanelMode = '';
            this.scheduleAvailabilityLoading = false;
            this.scheduleAvailabilityData = null;
            this.selectedAnalysisAppointment = null;
            this.selectedRepairAppointment = null;
            this.scheduleCurrentWeekStart = null;

            this.ticketForm = {"""

if "this.schedulePanelOpen = false;" not in content.split("openNewTicketModal() {")[1]:
    content = content.replace(search_reset, replace_reset)

with open('js/main.js', 'w') as f:
    f.write(content)
