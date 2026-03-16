import re

with open('index.html', 'r') as f:
    content = f.read()

# Add red asterisk indicator
search_btn = """                                        class="text-xs px-3 py-1.5 rounded border border-gray-300 bg-white hover:bg-gray-50 text-gray-700 font-medium transition-colors flex items-center justify-center gap-2">
                                    <i class="fa-regular fa-calendar text-brand-500"></i> Agendar Análise
                                </button>"""

replace_btn = """                                        class="text-xs px-3 py-1.5 rounded border border-gray-300 bg-white hover:bg-gray-50 text-gray-700 font-medium transition-colors flex items-center justify-center gap-2">
                                    <i class="fa-regular fa-calendar text-brand-500"></i> Agendar Análise
                                    <span x-show="isFieldRequired('analysis_schedule')" class="text-red-500 font-bold">*</span>
                                </button>"""

if "analysis_schedule" not in search_btn:
    content = content.replace(search_btn, replace_btn)

with open('index.html', 'w') as f:
    f.write(content)
