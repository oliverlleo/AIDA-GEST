from pathlib import Path
import re

APP = Path('app.html')
MAIN = Path('js/main.js')

html = APP.read_text(encoding='utf-8')
js = MAIN.read_text(encoding='utf-8')

# 1) Remove the previous boot hint gate entirely. It could intentionally paint a
# blank/loader state before auth resolution.
css_block = re.compile(
    r"\n\s*/\* AUTH FIRST-PAINT GATE \*/\n"
    r"\s*html\.boot-anon #initial-auth-loading \{ display: none !important; \}\n"
    r"\s*html\.boot-anon:not\(\.auth-runtime\) #app-shell \{ visibility: hidden; \}\n"
    r"\s*html\.boot-anon:not\(\.auth-runtime\) #login-screen \{\n"
    r"\s*visibility: visible !important;\n"
    r"\s*display: block !important;\n"
    r"\s*\}\n"
    r"\s*html\.boot-auth #login-screen \{ display: none !important; \}",
    re.M,
)
html, n_css = css_block.subn('', html, count=1)
if n_css != 1:
    raise SystemExit('AUTH FIRST-PAINT GATE CSS not found exactly once')

boot_script = re.compile(
    r"\n\s*<script>\n\s*\(\(\) => \{\n\s*let hasAuthHint = false;.*?"
    r"document\.documentElement\.classList\.add\(hasAuthHint \? 'boot-auth' : 'boot-anon'\);\n"
    r"\s*\}\)\(\);\n\s*</script>",
    re.S,
)
html, n_boot = boot_script.subn('', html, count=1)
if n_boot != 1:
    raise SystemExit('boot auth hint script not found exactly once')

# 2) Move the REAL login screen to the beginning of <body>. This is the key fix:
# before this patch the browser had to parse thousands of lines of the app shell
# before it even reached the login markup, so an anonymous visitor could see a
# completely blank page during first paint.
comment = '<!-- VIEW: LOGIN/REGISTER (If not logged in) -->'
comment_start = html.find(comment)
if comment_start < 0:
    raise SystemExit('login comment not found')

div_start = html.find('<div id="login-screen"', comment_start)
if div_start < 0:
    raise SystemExit('login-screen opening div not found')

tag_re = re.compile(r'</?div\b[^>]*>', re.I)
depth = 0
div_end = None
for m in tag_re.finditer(html, div_start):
    tag = m.group(0)
    if tag.lower().startswith('</div'):
        depth -= 1
        if depth == 0:
            div_end = m.end()
            break
    else:
        depth += 1

if div_end is None:
    raise SystemExit('could not find login-screen closing div')

login_block = html[comment_start:div_end]
html = html[:comment_start] + html[div_end:]

body_match = re.search(r'<body\b[^>]*>', html, re.I)
if not body_match:
    raise SystemExit('body tag not found')
insert_at = body_match.end()
html = html[:insert_at] + '\n\n    ' + login_block.strip() + '\n' + html[insert_at:]

# 3) Internal app shell must never paint before Alpine has a real authenticated
# state. The real login is outside this shell and remains immediately visible.
old_shell = '<div id="app-shell" class="min-h-screen flex flex-col">'
new_shell = '<div id="app-shell" x-cloak x-show="session || employeeSession || view === \'setup_required\'" class="min-h-screen flex flex-col">'
if old_shell in html:
    html = html.replace(old_shell, new_shell, 1)
elif new_shell not in html:
    raise SystemExit('app-shell anchor not found')

# The global loader must not exist on first paint. It can still be used after
# Alpine starts (login submission, data operations, etc.).
old_loader = '<div id="initial-auth-loading" x-show="loading" class="fixed inset-0 bg-white z-[99] flex items-center justify-center bg-opacity-90 transition-opacity">'
new_loader = '<div id="initial-auth-loading" x-show="loading" x-cloak class="fixed inset-0 bg-white z-[99] flex items-center justify-center bg-opacity-90 transition-opacity">'
if old_loader in html:
    html = html.replace(old_loader, new_loader, 1)
elif new_loader not in html:
    raise SystemExit('initial loader anchor not found')

# 4) Auth is checked silently behind the already-visible login. No bootstrap
# loader, no white validation page, no visual redirect.
if 'loading: true,' not in js:
    raise SystemExit('initial loading:true not found')
js = js.replace('loading: true,', 'loading: false,', 1)

init_loading = '            console.log("App initializing...");\n            this.loading = true;'
init_no_loading = '            console.log("App initializing...");\n            // Auth bootstrap is silent: the real login is already the first paint.\n            this.loading = false;'
if init_loading not in js:
    raise SystemExit('init loading anchor not found')
js = js.replace(init_loading, init_no_loading, 1)

old_finally = '''            } finally {
                const root = document.documentElement;
                root.classList.remove('boot-auth', 'boot-anon');
                root.classList.add((this.session || this.employeeSession) ? 'boot-auth' : 'boot-anon');
                root.classList.add('auth-runtime');
                this.loading = false;
                this.initInFlight = false;
            }'''
new_finally = '''            } finally {
                this.loading = false;
                this.initInFlight = false;
            }'''
if old_finally not in js:
    raise SystemExit('boot class finally block not found')
js = js.replace(old_finally, new_finally, 1)

APP.write_text(html, encoding='utf-8')
MAIN.write_text(js, encoding='utf-8')

# Verification
h = APP.read_text(encoding='utf-8')
j = MAIN.read_text(encoding='utf-8')
assert 'boot-auth' not in h
assert 'boot-anon' not in h
assert 'auth-runtime' not in h
assert "classList.add('auth-runtime')" not in j
assert h.index('id="login-screen"') < h.index('id="initial-auth-loading"') < h.index('id="app-shell"')
assert 'id="app-shell" x-cloak x-show="session || employeeSession || view === \'setup_required\'"' in h
assert 'id="initial-auth-loading" x-show="loading" x-cloak' in h
assert 'loading: false,' in j
assert 'Auth bootstrap is silent' in j

# Cleanup one-time patch files/workflows.
for p in [
    Path('.github/workflows/one-time-first-paint-login.yml'),
    Path('scripts/fix_first_paint_login.py'),
]:
    if p.exists():
        p.unlink()
