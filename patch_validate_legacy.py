import re

with open('js/main.js', 'r') as f:
    content = f.read()

search = """                if (ticketData.is_outsourced) {
                    if (!ticketData.outsourced_company_id) return { valid: false, missing: ['Empresa Parceira'] };
                } else {
                    // In legacy mode, technician_id can be NULL (Todos)
                }
                return { valid: true };"""

replace = """                if (ticketData.is_outsourced) {
                    if (!ticketData.outsourced_company_id) return { valid: false, missing: ['Empresa Parceira'] };
                } else {
                    // In legacy mode, technician_id can be NULL (Todos)
                }

                // Future-proof: if analysis_schedule becomes true in config, we could check here too,
                // but legacy mode doesn't check dynamic configs.
                return { valid: true };"""

content = content.replace(search, replace)

with open('js/main.js', 'w') as f:
    f.write(content)
