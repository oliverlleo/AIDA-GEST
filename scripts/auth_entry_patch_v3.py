from pathlib import Path

app = Path('app.html')
html = app.read_text(encoding='utf-8')

marker = '/* AUTH FIRST-PAINT GATE */'
if marker not in html:
    css_anchor = "        [x-cloak] { display: none !important; }\n        body { font-family: 'Inter', sans-serif; }"
    css_new = """        [x-cloak] { display: none !important; }
        /* AUTH FIRST-PAINT GATE */
        html.boot-anon #initial-auth-loading { display: none !important; }
        html.boot-anon:not(.auth-runtime) #app-shell { visibility: hidden; }
        html.boot-anon:not(.auth-runtime) #login-screen {
            visibility: visible !important;
            display: block !important;
        }
        html.boot-auth #login-screen { display: none !important; }
        body { font-family: 'Inter', sans-serif; }"""
    if css_anchor not in html:
        raise SystemExit('CSS anchor not found')
    html = html.replace(css_anchor, css_new, 1)

    head_anchor = '</style>\n</head>'
    boot_script = """</style>
    <script>
        (() => {
            let hasAuthHint = false;
            try {
                hasAuthHint = !!localStorage.getItem('techassist_employee');
                if (!hasAuthHint) {
                    for (let i = 0; i < localStorage.length; i++) {
                        const key = localStorage.key(i) || '';
                        if (key.startsWith('sb-') && key.endsWith('-auth-token')) {
                            const raw = localStorage.getItem(key);
                            if (raw && raw !== 'null' && raw !== '{}') {
                                hasAuthHint = true;
                                break;
                            }
                        }
                    }
                }
            } catch (_) {}
            document.documentElement.classList.add(hasAuthHint ? 'boot-auth' : 'boot-anon');
        })();
    </script>
</head>"""
    if head_anchor not in html:
        raise SystemExit('Head anchor not found')
    html = html.replace(head_anchor, boot_script, 1)

loading_old = '<div x-show="loading" class="fixed inset-0 bg-white z-[99] flex items-center justify-center bg-opacity-90 transition-opacity" x-transition.opacity>'
loading_new = '<div id="initial-auth-loading" x-show="loading" class="fixed inset-0 bg-white z-[99] flex items-center justify-center bg-opacity-90 transition-opacity">'
if loading_old in html:
    html = html.replace(loading_old, loading_new, 1)
elif 'id="initial-auth-loading"' not in html:
    raise SystemExit('Loading overlay anchor not found')

shell_old = '<!-- MAIN LAYOUT -->\n    <div class="min-h-screen flex flex-col">'
shell_new = '<!-- MAIN LAYOUT -->\n    <div id="app-shell" class="min-h-screen flex flex-col">'
if shell_old in html:
    html = html.replace(shell_old, shell_new, 1)
elif 'id="app-shell"' not in html:
    raise SystemExit('App shell anchor not found')

login_old = '<div x-show="!session && !employeeSession && !registrationSuccess && view !== \'setup_required\'" class="fixed inset-0 bg-white z-[10000] overflow-y-auto">'
login_new = '<div id="login-screen" x-show="!session && !employeeSession && !registrationSuccess && view !== \'setup_required\'" class="fixed inset-0 bg-white z-[10000] overflow-y-auto">'
if login_old in html:
    html = html.replace(login_old, login_new, 1)
elif 'id="login-screen"' not in html:
    raise SystemExit('Login screen anchor not found')

app.write_text(html, encoding='utf-8')

main = Path('js/main.js')
js = main.read_text(encoding='utf-8')
if "classList.add('auth-runtime')" not in js:
    finally_old = """            } finally {
                // Hard visual gate: the static app shell stays physically covered until
                // the initial Supabase/employee-session check is fully resolved.
                this.loading = false;
                this.initInFlight = false;
            }"""
    finally_new = """            } finally {
                const root = document.documentElement;
                root.classList.remove('boot-auth', 'boot-anon');
                root.classList.add((this.session || this.employeeSession) ? 'boot-auth' : 'boot-anon');
                root.classList.add('auth-runtime');
                this.loading = false;
                this.initInFlight = false;
            }"""
    if finally_old not in js:
        raise SystemExit('Init finally anchor not found')
    js = js.replace(finally_old, finally_new, 1)
    main.write_text(js, encoding='utf-8')

h = app.read_text(encoding='utf-8')
j = main.read_text(encoding='utf-8')
assert 'AUTH FIRST-PAINT GATE' in h
assert 'id="initial-auth-loading"' in h
assert 'html.boot-anon #initial-auth-loading { display: none !important; }' in h
assert 'id="app-shell"' in h
assert 'id="login-screen"' in h
assert "classList.add('auth-runtime')" in j

for cleanup in [
    Path('.github/workflows/one-time-auth-entry-stable.yml'),
    Path('.github/workflows/one-time-auth-entry-stable-v3.yml'),
    Path('scripts/auth_entry_patch_v3.py'),
]:
    if cleanup.exists():
        cleanup.unlink()
