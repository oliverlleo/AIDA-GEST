from pathlib import Path

app = Path('app.html')
html = app.read_text(encoding='utf-8')

css_old = """        [x-cloak] { display: none !important; }
        body { font-family: 'Inter', sans-serif; }"""
css_new = """        [x-cloak] { display: none !important; }
        #auth-boot-shield {
            position: fixed;
            inset: 0;
            z-index: 2147483647;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #fff;
        }
        #auth-boot-shield .auth-boot-inner {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 16px;
            color: #6b7280;
            font: 600 13px/1.2 Inter, sans-serif;
        }
        #auth-boot-shield img { width: 190px; height: auto; }
        #auth-boot-shield .auth-boot-spinner {
            width: 30px;
            height: 30px;
            border: 3px solid #e5e7eb;
            border-top-color: #ff6b00;
            border-radius: 999px;
            animation: authBootSpin .8s linear infinite;
        }
        @keyframes authBootSpin { to { transform: rotate(360deg); } }
        html.auth-resolved #auth-boot-shield { display: none !important; }
        body { font-family: 'Inter', sans-serif; }"""
if css_old not in html:
    raise SystemExit('CSS anchor not found')
html = html.replace(css_old, css_new, 1)

body_old = '<body class="bg-gray-100 text-gray-900 antialiased" x-data="app()">'
body_new = '''<body class="bg-gray-100 text-gray-900 antialiased" x-data="app()">

    <div id="auth-boot-shield" aria-hidden="true">
        <div class="auth-boot-inner">
            <img src="logologin.png" alt="CentralOS">
            <div class="auth-boot-spinner"></div>
            <span>Verificando acesso...</span>
        </div>
    </div>'''
if body_old not in html:
    raise SystemExit('Body anchor not found')
html = html.replace(body_old, body_new, 1)

login_old = '<div x-show="!session && !employeeSession && !registrationSuccess && view !== \'setup_required\'" class="absolute inset-0 bg-white z-50 overflow-y-auto" x-cloak>'
login_new = '<div x-show="authResolved && !session && !employeeSession && !registrationSuccess && view !== \'setup_required\'" class="fixed inset-0 bg-white z-[10000] overflow-y-auto" x-cloak>'
count = html.count(login_old)
if count < 1:
    raise SystemExit('Login gate anchor not found')
html = html.replace(login_old, login_new)
app.write_text(html, encoding='utf-8')

main = Path('js/main.js')
js = main.read_text(encoding='utf-8')
state_old = """        loading: true,
        error: null,"""
state_new = """        loading: true,
        authResolved: false,
        error: null,"""
if state_old not in js:
    raise SystemExit('State anchor not found')
js = js.replace(state_old, state_new, 1)

finally_old = """            } finally {
                this.loading = false;
                this.initInFlight = false;
            }"""
finally_new = """            } finally {
                // Hard visual gate: the static app shell stays physically covered until
                // the initial Supabase/employee-session check is fully resolved.
                this.authResolved = true;
                document.documentElement.classList.add('auth-resolved');
                this.loading = false;
                this.initInFlight = false;
            }"""
if finally_old not in js:
    raise SystemExit('Init finally anchor not found')
js = js.replace(finally_old, finally_new, 1)
main.write_text(js, encoding='utf-8')

html_check = app.read_text(encoding='utf-8')
js_check = main.read_text(encoding='utf-8')
assert 'id="auth-boot-shield"' in html_check
assert 'html.auth-resolved #auth-boot-shield' in html_check
assert 'class="fixed inset-0 bg-white z-[10000] overflow-y-auto"' in html_check
assert 'authResolved && !session && !employeeSession' in html_check
assert 'authResolved: false' in js_check
assert "classList.add('auth-resolved')" in js_check
