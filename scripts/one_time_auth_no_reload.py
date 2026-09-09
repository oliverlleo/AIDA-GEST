from pathlib import Path

# 1) Passive employee-session restore must never call logout()/reload.
main_path = Path('js/main.js')
js = main_path.read_text(encoding='utf-8')

old_invalid = """                                if (!freshSession) {
                                    this.logout();
                                    return;
                                }"""
new_invalid = """                                if (!freshSession) {
                                    throw new Error('STORED_EMPLOYEE_SESSION_INVALID');
                                }"""
if old_invalid not in js:
    raise SystemExit('invalid-session restore anchor not found')
js = js.replace(old_invalid, new_invalid, 1)

old_legacy = """                            } else {
                                // Legacy session without token
                                console.warn(\"Legacy session detected. Logging out.\");
                                this.logout();
                                return;
                            }"""
new_legacy = """                            } else {
                                // Legacy local session: clear it silently. Never reload during boot.
                                throw new Error('STORED_EMPLOYEE_SESSION_LEGACY');
                            }"""
if old_legacy not in js:
    raise SystemExit('legacy-session restore anchor not found')
js = js.replace(old_legacy, new_legacy, 1)

old_catch = """                        } catch (e) {
                            console.error(\"Session restore error:\", e);
                            localStorage.removeItem('techassist_employee');
                        }"""
new_catch = """                        } catch (e) {
                            const restoreCode = String(e?.message || '');
                            if (!restoreCode.startsWith('STORED_EMPLOYEE_SESSION_')) {
                                console.error(\"Session restore error:\", e);
                            }
                            localStorage.removeItem('techassist_employee');
                            this.employeeSession = null;
                            this.user = null;
                        }"""
if old_catch not in js:
    raise SystemExit('restore catch anchor not found')
js = js.replace(old_catch, new_catch, 1)
main_path.write_text(js, encoding='utf-8')

# 2) Explicit logout should switch to login in-place, not reload the document.
auth_path = Path('js/modules/auth-session-service.js')
auth = auth_path.read_text(encoding='utf-8')
old_logout_tail = """        state.view = 'dashboard';
        setLoading(false);
        window.location.reload();
    },"""
new_logout_tail = """        state.view = 'dashboard';
        state.registrationSuccess = false;
        setLoading(false);

        // Keep the same document. The login view becomes the visible shell immediately.
        const root = document.documentElement;
        root.classList.remove('boot-auth');
        root.classList.add('boot-anon', 'auth-runtime');
    },"""
if old_logout_tail not in auth:
    raise SystemExit('logout reload anchor not found')
auth = auth.replace(old_logout_tail, new_logout_tail, 1)
auth_path.write_text(auth, encoding='utf-8')

# 3) First paint: employee localStorage is NOT trusted as an authenticated hint.
# Anonymous/stale employee sessions therefore see the real login immediately, while
# a non-expired Supabase admin session may keep the authenticated boot path.
app_path = Path('app.html')
html = app_path.read_text(encoding='utf-8')
old_boot = """        (() => {
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
        })();"""
new_boot = """        (() => {
            let hasAuthHint = false;
            try {
                // Only a non-expired Supabase admin token is trusted synchronously.
                // Employee sessions are server-validated asynchronously, so they start
                // on the real login shell instead of causing loader/reload flashes.
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i) || '';
                    if (!key.startsWith('sb-') || !key.endsWith('-auth-token')) continue;
                    const raw = localStorage.getItem(key);
                    if (!raw || raw === 'null' || raw === '{}') continue;
                    try {
                        const saved = JSON.parse(raw);
                        const accessToken = saved?.access_token || saved?.currentSession?.access_token;
                        const expiresAt = Number(saved?.expires_at || saved?.currentSession?.expires_at || 0);
                        if (accessToken && expiresAt * 1000 > Date.now() + 5000) {
                            hasAuthHint = true;
                            break;
                        }
                    } catch (_) {}
                }
            } catch (_) {}
            document.documentElement.classList.add(hasAuthHint ? 'boot-auth' : 'boot-anon');
        })();"""
if old_boot not in html:
    raise SystemExit('first-paint boot script anchor not found')
html = html.replace(old_boot, new_boot, 1)
app_path.write_text(html, encoding='utf-8')

# Verification
main_verify = main_path.read_text(encoding='utf-8')
auth_verify = auth_path.read_text(encoding='utf-8')
app_verify = app_path.read_text(encoding='utf-8')
assert "this.logout();\n                                    return;" not in main_verify
assert "STORED_EMPLOYEE_SESSION_INVALID" in main_verify
assert "STORED_EMPLOYEE_SESSION_LEGACY" in main_verify
assert "window.location.reload();" not in auth_verify
assert "Employee sessions are server-validated asynchronously" in app_verify

# Remove this one-time machinery from the resulting branch.
for p in [Path('.github/workflows/one-time-auth-no-reload.yml'), Path('scripts/one_time_auth_no_reload.py')]:
    if p.exists():
        p.unlink()
