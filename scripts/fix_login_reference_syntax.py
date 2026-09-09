from pathlib import Path
p=Path('centralos-mobile-login-reference.js')
s=p.read_text(encoding='utf-8')
bad="const form=card.querySelector('form[x-show=\"authMode === 'employee'\"]');remember(form);extras(card,form);return true"
good='const form=card.querySelector("form[x-show=\\"authMode === \\\'employee\\\'\\"]");remember(form);extras(card,form);return true'
if bad not in s:
    raise SystemExit('bad selector syntax not found')
s=s.replace(bad,good,1)
p.write_text(s,encoding='utf-8')
# cleanup
for x in [Path('scripts/fix_login_reference_syntax.py'),Path('.github/workflows/one-time-login-reference-syntax.yml')]:
    if x.exists(): x.unlink()
