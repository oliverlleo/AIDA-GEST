import re

with open('js/main.js', 'r') as f:
    content = f.read()

# Add analysis_schedule to TICKET_REQUIRED_FIELDS
search_req = "            { key: 'photos', label: 'Fotos', col: 'photos_urls', type: 'array' }"
replace_req = "            { key: 'photos', label: 'Fotos', col: 'photos_urls', type: 'array' },\n            { key: 'analysis_schedule', label: 'Agendamento de Análise', col: 'analysis_schedule', type: 'schedule' }"

if "analysis_schedule" not in search_req:
    content = content.replace(search_req, replace_req)


# Handle the 'schedule' type in validateTicketRequirements
search_val = """                    } else if (field.type === 'id_check') {
                        if (ticketData.is_outsourced) {
                            if (!ticketData.outsourced_company_id) isValid = false;
                        } else {
                            if (!val) isValid = false; // Must have specific technician (Not NULL)
                        }
                    }"""

replace_val = """                    } else if (field.type === 'id_check') {
                        if (ticketData.is_outsourced) {
                            if (!ticketData.outsourced_company_id) isValid = false;
                        } else {
                            if (!val) isValid = false; // Must have specific technician (Not NULL)
                        }
                    } else if (field.type === 'schedule') {
                        if (field.key === 'analysis_schedule') {
                            if (!this.selectedAnalysisAppointment) isValid = false;
                        }
                    }"""

if "schedule" not in search_val:
    content = content.replace(search_val, replace_val)


with open('js/main.js', 'w') as f:
    f.write(content)
