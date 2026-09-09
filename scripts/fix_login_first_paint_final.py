from pathlib import Path
import re

app_path = Path('app.html')
js_path = Path('centralos-mobile-login-reference.js')
app = app_path.read_text(encoding='utf-8')
js = js_path.read_text(encoding='utf-8')

# 1) Export the already-approved mobile login CSS to a real stylesheet so it is
# available before the body is painted (instead of being injected after DOMContentLoaded).
css_match = re.search(r"s\.textContent=`(.*?)`; document\.head\.appendChild\(s\);", js, re.S)
if not css_match:
    raise SystemExit('Could not extract approved mobile login CSS')
css = css_match.group(1).strip() + '\n'
Path('centralos-mobile-login-firstpaint.css').write_text(css, encoding='utf-8')

# 2) Load that CSS in <head>, before any login HTML can paint.
link = '    <link rel="stylesheet" href="centralos-mobile-login-firstpaint.css?v=1">\n'
if 'centralos-mobile-login-firstpaint.css' not in app:
    anchor = '    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">\n'
    if anchor not in app:
        raise SystemExit('Head font anchor not found')
    app = app.replace(anchor, anchor + link, 1)

# 3) Make the final login structure exist in the HTML itself, so there is no
# raw Tailwind/Alpine frame before the mobile decorator runs.
old_open = '''                <div id="login-screen" x-show="!session && !employeeSession && !registrationSuccess && view !== 'setup_required'" class="fixed inset-0 bg-white z-[10000] overflow-y-auto">\n                    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">\n                        <div class="max-w-md w-full bg-white p-8 rounded-2xl shadow-xl border border-gray-100">\n                            <div class="text-center mb-8">'''
new_open = '''                <div id="login-screen" x-show="!session && !employeeSession && !registrationSuccess && view !== 'setup_required'" class="centralos-login-ref fixed inset-0 bg-white z-[10000] overflow-y-auto">\n                    <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4">\n                        <section class="centralos-login-hero" aria-hidden="true">\n                            <img class="centralos-login-logo" src="logologin.png" alt="">\n                            <div class="centralos-login-title"><h1>Bem-vindo de volta</h1><p>Acesse sua central de assistência técnica.</p></div>\n                            <div class="centralos-login-side">Tudo encontra<br>seu lugar.</div>\n                            <div class="centralos-login-metrics">\n                                <div class="centralos-login-metric"><i class="fa-solid fa-chart-simple"></i><span>Mais<br>organização</span></div>\n                                <div class="centralos-login-metric"><i class="fa-regular fa-clock"></i><span>Mais<br>produtividade</span></div>\n                                <div class="centralos-login-metric"><i class="fa-solid fa-user-group"></i><span>Mais<br>resultados</span></div>\n                            </div>\n                        </section>\n                        <div class="centralos-login-card max-w-md w-full bg-white p-8 rounded-2xl shadow-xl border border-gray-100">\n                            <div class="centralos-login-oldhead text-center mb-8">'''
if old_open in app:
    app = app.replace(old_open, new_open, 1)
elif 'class="centralos-login-ref fixed inset-0' not in app:
    raise SystemExit('Login opening structure not found')

# 4) Hide inactive auth modes before Alpine starts. Alpine removes x-cloak and
# then owns x-show normally, so switching tabs still works.
app = app.replace('<form x-show="authMode === \'admin_login\'" @submit.prevent="loginAdmin" class="space-y-4">',
                  '<form x-cloak x-show="authMode === \'admin_login\'" @submit.prevent="loginAdmin" class="space-y-4">', 1)
app = app.replace('<form x-show="authMode === \'admin_register\'" @submit.prevent="registerAdmin" class="space-y-4">',
                  '<form x-cloak x-show="authMode === \'admin_register\'" @submit.prevent="registerAdmin" class="space-y-4">', 1)

# 5) Pre-render the mobile-only elements that used to be inserted after load.
# They remain hidden on desktop by the approved CSS.
remember_html = '''                                <div class="centralos-login-remember">\n                                    <label><input type="checkbox"><span>Lembrar de mim</span></label>\n                                    <button type="button" class="centralos-login-forgot">Esqueci minha senha?</button>\n                                </div>\n'''
employee_submit = '                                <button type="submit" class="w-full bg-brand-500 text-white font-bold py-3 rounded-lg hover:bg-brand-600 transition-colors shadow-lg shadow-orange-500/30">Entrar</button>\n'
if 'centralos-login-remember' not in app:
    if employee_submit not in app:
        raise SystemExit('Employee submit anchor not found')
    app = app.replace(employee_submit, remember_html + employee_submit, 1)

extras_html = '''\n                            <div class="centralos-login-extras">\n                                <div class="centralos-login-divider">OU</div>\n                                <button type="button" class="centralos-login-code"><i class="fa-solid fa-qrcode"></i><span>Entrar com código</span><b>›</b></button>\n                                <div class="centralos-login-info" aria-disabled="true">\n                                    <div class="centralos-login-finger"><i class="fa-solid fa-fingerprint"></i></div>\n                                    <div><strong>Acesso mais rápido</strong><span>Use sua biometria para entrar no CentralOS.</span></div>\n                                    <span class="centralos-login-soon">Em breve</span>\n                                </div>\n                                <div class="centralos-login-support">\n                                    <div class="centralos-login-headset"><i class="fa-solid fa-headset"></i></div>\n                                    <div><strong>Precisa de ajuda?</strong><span>Fale com o responsável pela sua assistência.</span></div>\n                                    <button type="button">Falar com suporte ›</button>\n                                </div>\n                                <p class="centralos-login-tag">Tudo encontra seu lugar.</p>\n                            </div>'''
register_end = '''                                <p class="text-center text-sm text-gray-500 mt-4 cursor-pointer hover:text-brand-500" @click="authMode = 'admin_login'">Voltar ao Login</p>\n                            </form>'''
if 'class="centralos-login-extras"' not in app:
    if register_end not in app:
        raise SystemExit('Register form end anchor not found')
    app = app.replace(register_end, register_end + extras_html, 1)

# 6) Keep the existing JS only for behavior/bindings. It must no longer be
# responsible for creating the visual structure after first paint.
remember_fn = r'''function remember\(form\)\{.*?\}\n  function extras'''
remember_new = '''function remember(form){\n    if(!form)return;\n    const submit=form.querySelector('button[type=submit]');if(!submit)return;\n    let r=form.querySelector('.centralos-login-remember');\n    if(!r){r=document.createElement('div');r.className='centralos-login-remember';r.innerHTML=`<label><input type="checkbox"><span>Lembrar de mim</span></label><button type="button" class="centralos-login-forgot">Esqueci minha senha?</button>`;form.insertBefore(r,submit)}\n    if(r.dataset.bound==='1')return;r.dataset.bound='1';\n    const check=r.querySelector('input'),company=form.querySelector('input[x-model="loginForm.company_code"]'),user=form.querySelector('input[x-model="loginForm.username"]');\n    try{const v=JSON.parse(localStorage.getItem('centralos_remember_login')||'null');if(v&&v.company_code&&v.username){check.checked=true;company.value=v.company_code;user.value=v.username;company.dispatchEvent(new Event('input',{bubbles:true}));user.dispatchEvent(new Event('input',{bubbles:true}))}}catch(_){}\n    form.addEventListener('submit',()=>{try{check.checked?localStorage.setItem('centralos_remember_login',JSON.stringify({company_code:company?.value||'',username:user?.value||''})):localStorage.removeItem('centralos_remember_login')}catch(_){}});\n    r.querySelector('button')?.addEventListener('click',()=>alert('Solicite ao administrador da sua assistência a redefinição da senha.'))\n  }\n  function extras'''
js, count = re.subn(remember_fn, remember_new, js, count=1, flags=re.S)
if count != 1:
    raise SystemExit('remember() function patch failed')

extras_fn = r'''function extras\(card,form\)\{.*?\}\n  function decorate'''
extras_new = '''function extras(card,form){\n    if(!card)return;\n    let e=card.querySelector('.centralos-login-extras');\n    if(!e){e=document.createElement('div');e.className='centralos-login-extras';e.innerHTML=`<div class="centralos-login-divider">OU</div><button type="button" class="centralos-login-code"><i class="fa-solid fa-qrcode"></i><span>Entrar com código</span><b>›</b></button><div class="centralos-login-info" aria-disabled="true"><div class="centralos-login-finger"><i class="fa-solid fa-fingerprint"></i></div><div><strong>Acesso mais rápido</strong><span>Use sua biometria para entrar no CentralOS.</span></div><span class="centralos-login-soon">Em breve</span></div><div class="centralos-login-support"><div class="centralos-login-headset"><i class="fa-solid fa-headset"></i></div><div><strong>Precisa de ajuda?</strong><span>Fale com o responsável pela sua assistência.</span></div><button type="button">Falar com suporte ›</button></div><p class="centralos-login-tag">Tudo encontra seu lugar.</p>`;card.appendChild(e)}\n    if(e.dataset.bound==='1')return;e.dataset.bound='1';\n    e.querySelector('.centralos-login-code')?.addEventListener('click',()=>{const b=[...card.querySelectorAll('button')].find(x=>(x.getAttribute('@click')||'').includes("authMode = 'employee'"));b?.click();setTimeout(()=>form?.querySelector('input[x-model="loginForm.company_code"]')?.focus(),40)});\n    e.querySelector('.centralos-login-support button')?.addEventListener('click',()=>alert('Para recuperar o acesso, fale com o administrador responsável pela sua assistência técnica.'))\n  }\n  function decorate'''
js, count = re.subn(extras_fn, extras_new, js, count=1, flags=re.S)
if count != 1:
    raise SystemExit('extras() function patch failed')

decorate_fn = r'''function decorate\(\)\{.*?\}\n  function boot'''
decorate_new = '''function decorate(){\n    const root=[...document.querySelectorAll('div[x-show]')].find(e=>{const x=e.getAttribute('x-show')||'';return x.includes('!session')&&x.includes('!employeeSession')&&x.includes('registrationSuccess')});if(!root)return false;\n    const shell=root.firstElementChild,card=shell?.querySelector('.centralos-login-card')||shell?.lastElementChild;if(!shell||!card)return false;\n    root.classList.add(ROOT);card.classList.add('centralos-login-card');card.querySelector('.text-center.mb-8')?.classList.add('centralos-login-oldhead');\n    if(!shell.querySelector('.centralos-login-hero'))shell.insertBefore(hero(),card);\n    const form=card.querySelector('form[x-show="authMode === \'employee\'"]');remember(form);extras(card,form);return true\n  }\n  function boot'''
js, count = re.subn(decorate_fn, decorate_new, js, count=1, flags=re.S)
if count != 1:
    raise SystemExit('decorate() function patch failed')

app_path.write_text(app, encoding='utf-8')
js_path.write_text(js, encoding='utf-8')

# Verification: the very first mobile paint now already has the final structure,
# while inactive forms are hidden before Alpine initializes.
h = app_path.read_text(encoding='utf-8')
j = js_path.read_text(encoding='utf-8')
assert 'centralos-mobile-login-firstpaint.css?v=1' in h
assert 'class="centralos-login-ref fixed inset-0' in h
assert '<section class="centralos-login-hero"' in h
assert 'class="centralos-login-card ' in h
assert 'class="centralos-login-oldhead ' in h
assert 'x-cloak x-show="authMode === \'admin_login\'"' in h
assert 'x-cloak x-show="authMode === \'admin_register\'"' in h
assert 'class="centralos-login-remember"' in h
assert 'class="centralos-login-extras"' in h
assert 'dataset.bound' in j

# Remove one-time patch files in the resulting commit.
for p in [Path('scripts/fix_login_first_paint_final.py'), Path('.github/workflows/one-time-login-firstpaint-final.yml')]:
    if p.exists():
        p.unlink()
