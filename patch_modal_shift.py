import re

with open('index.html', 'r') as f:
    content = f.read()

# Make sure we add the shift class to the main `modals.ticket` block.
search_ticket_modal = """    <div x-show="modals.ticket" class="fixed inset-0 z-[60] overflow-y-auto" x-cloak>
        <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <div class="fixed inset-0 transition-opacity bg-gray-900 bg-opacity-75" @click="modals.ticket = false"></div>
            <span class="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>
            <div class="relative bg-white rounded-lg w-full max-w-4xl max-h-[90vh] flex flex-col shadow-xl my-4 mx-auto" @click.stop>"""

replace_ticket_modal = """    <div x-show="modals.ticket" class="fixed inset-0 z-[60] overflow-y-auto" x-cloak>
        <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <div class="fixed inset-0 transition-opacity bg-gray-900 bg-opacity-75" @click="modals.ticket = false"></div>
            <span class="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>
            <div class="relative bg-white rounded-lg w-full max-w-4xl max-h-[90vh] flex flex-col shadow-xl my-4 mx-auto transition-transform duration-300 ease-in-out" :class="schedulePanelOpen ? '-translate-x-32 sm:-translate-x-48' : ''" @click.stop>"""

if "translate-x-32" not in content:
    content = content.replace(search_ticket_modal, replace_ticket_modal)

with open('index.html', 'w') as f:
    f.write(content)
