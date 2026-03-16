import re

with open('index.html', 'r') as f:
    content = f.read()

search = """            <div class="inline-block align-bottom bg-white rounded-2xl text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full">"""

replace = """            <div class="inline-block align-bottom bg-white rounded-2xl text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full duration-300 ease-in-out" :class="schedulePanelOpen ? '-translate-x-32 sm:-translate-x-48' : ''">"""

content = content.replace(search, replace)

with open('index.html', 'w') as f:
    f.write(content)
