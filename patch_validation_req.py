import re

with open('js/main.js', 'r') as f:
    content = f.read()

search_val = """                if (field.type === 'is_outsourced') {
                    if (ticketData.is_outsourced && !ticketData.outsourced_company_id) isValid = false;
                } else {
                    isValid = !!ticketData[field.id];
                }"""

replace_val = """                if (field.type === 'is_outsourced') {
                    if (ticketData.is_outsourced && !ticketData.outsourced_company_id) isValid = false;
                } else if (field.id === 'analysis_schedule') {
                    // Specific logic for analysis_schedule: must have a selected appointment
                    if (!this.selectedAnalysisAppointment) isValid = false;
                } else {
                    isValid = !!ticketData[field.id];
                }"""

if "analysis_schedule" not in search_val:
    content = content.replace(search_val, replace_val)

with open('js/main.js', 'w') as f:
    f.write(content)
