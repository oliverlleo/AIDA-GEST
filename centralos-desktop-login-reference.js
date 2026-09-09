(function () {
  'use strict';

  const ROOT_CLASS = 'centralos-login-ref';
  const DESKTOP_CLASS = 'centralos-desktop-login-ready';
  const STYLE_ID = 'centralos-desktop-login-reference-style';

  function injectStyles() {
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
.centralos-desktop-panel,
.centralos-desktop-heading,
.centralos-desktop-badge,
.centralos-desktop-version { display: none !important; }

@media (min-width: 768px) {
  .${ROOT_CLASS}.${DESKTOP_CLASS} {
    inset: 0 !important;
    padding: 18px !important;
    background: #111315 !important;
    overflow: auto !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} > div {
    width: min(1280px, calc(100vw - 36px)) !important;
    min-height: min(760px, calc(100vh - 36px)) !important;
    height: calc(100vh - 36px) !important;
    max-height: 820px !important;
    margin: 0 auto !important;
    padding: 0 !important;
    display: grid !important;
    grid-template-columns: minmax(0, 55%) minmax(420px, 45%) !important;
    align-items: stretch !important;
    justify-content: stretch !important;
    border: 1px solid rgba(255,255,255,.18) !important;
    border-radius: 16px !important;
    overflow: hidden !important;
    background: #07090b !important;
    box-shadow: 0 24px 70px rgba(0,0,0,.42) !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-hero {
    display: none !important;
  }

  .centralos-desktop-panel {
    display: flex !important;
    position: relative;
    min-width: 0;
    min-height: 100%;
    padding: 54px 64px 42px;
    flex-direction: column;
    justify-content: flex-start;
    overflow: hidden;
    isolation: isolate;
    color: #fff;
    background:
      linear-gradient(90deg, rgba(5,7,9,.96) 0%, rgba(5,7,9,.80) 44%, rgba(5,7,9,.30) 100%),
      linear-gradient(180deg, rgba(0,0,0,.12), rgba(0,0,0,.42)),
      url('backgorundlogin.png?v=1') center center / cover no-repeat;
  }

  .centralos-desktop-panel::before {
    content: '';
    position: absolute;
    inset: 0;
    z-index: -1;
    background:
      linear-gradient(118deg, transparent 0 61%, rgba(255,90,0,.15) 61.2% 61.8%, transparent 62%),
      radial-gradient(circle at 86% 26%, rgba(255,90,0,.16), transparent 34%);
    pointer-events: none;
  }

  .centralos-desktop-brand {
    width: min(330px, 70%);
    height: 86px;
    object-fit: contain;
    object-position: left center;
    filter: drop-shadow(0 10px 20px rgba(0,0,0,.36));
  }

  .centralos-desktop-copy {
    width: min(480px, 82%);
    margin-top: 36px;
  }

  .centralos-desktop-copy h1 {
    margin: 0;
    color: #fff !important;
    font-size: clamp(38px, 3.5vw, 58px);
    line-height: 1.05;
    letter-spacing: -.045em;
    font-weight: 850;
  }

  .centralos-desktop-copy h1 span {
    color: #ff5a00;
  }

  .centralos-desktop-copy > p {
    width: min(390px, 90%);
    margin: 20px 0 0;
    color: #d5d8dc !important;
    font-size: 16px;
    line-height: 1.55;
    font-weight: 450;
  }

  .centralos-desktop-benefits {
    display: grid;
    gap: 15px;
    margin-top: 30px;
  }

  .centralos-desktop-benefit {
    display: flex;
    align-items: center;
    gap: 15px;
  }

  .centralos-desktop-benefit-icon {
    width: 48px;
    height: 48px;
    flex: 0 0 48px;
    display: grid;
    place-items: center;
    border: 1px solid rgba(255,255,255,.15);
    border-radius: 10px;
    background: rgba(8,10,12,.58);
    color: #ff5a00;
    font-size: 20px;
    box-shadow: inset 0 0 0 1px rgba(255,90,0,.05);
  }

  .centralos-desktop-benefit strong {
    display: block;
    color: #fff;
    font-size: 14px;
    line-height: 1.15;
  }

  .centralos-desktop-benefit span {
    display: block;
    margin-top: 4px;
    color: #bdc2c8;
    font-size: 12px;
    line-height: 1.3;
  }

  .centralos-desktop-footer {
    margin-top: auto;
    display: flex;
    align-items: center;
    gap: 22px;
    color: #f4f5f6;
    font-size: 14px;
    font-weight: 700;
    letter-spacing: .01em;
  }

  .centralos-desktop-footer::before {
    content: '';
    width: 76px;
    height: 5px;
    border-radius: 999px;
    background: #ff5a00;
    box-shadow: 0 0 16px rgba(255,90,0,.36);
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-card {
    position: relative !important;
    width: 100% !important;
    max-width: none !important;
    min-width: 0 !important;
    height: 100% !important;
    margin: 0 !important;
    padding: 0 72px !important;
    display: flex !important;
    flex-direction: column !important;
    justify-content: center !important;
    border: 0 !important;
    border-radius: 0 !important;
    background: #fff !important;
    box-shadow: none !important;
    color: #151922 !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-oldhead {
    display: none !important;
  }

  .centralos-desktop-badge {
    display: flex !important;
    position: absolute;
    top: 28px;
    right: 30px;
    min-width: 208px;
    height: 56px;
    padding: 8px 13px;
    align-items: center;
    gap: 11px;
    border: 1px solid #e2e6eb;
    border-radius: 13px;
    background: #f8f9fb;
    box-shadow: 0 5px 16px rgba(22,29,37,.04);
  }

  .centralos-desktop-badge img {
    width: 34px;
    height: 34px;
    border-radius: 8px;
  }

  .centralos-desktop-badge strong {
    display: block;
    color: #1c2129;
    font-size: 12px;
    line-height: 1.2;
  }

  .centralos-desktop-badge span {
    display: block;
    margin-top: 3px;
    color: #8b929c;
    font-size: 9px;
    line-height: 1.2;
  }

  .centralos-desktop-heading {
    display: block !important;
    margin-bottom: 22px;
  }

  .centralos-desktop-heading h2 {
    margin: 0;
    color: #11151a;
    font-size: clamp(28px, 2.25vw, 36px);
    line-height: 1.05;
    letter-spacing: -.035em;
    font-weight: 850;
  }

  .centralos-desktop-heading p {
    margin: 7px 0 0;
    color: #6f7782;
    font-size: 14px;
    line-height: 1.4;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-card > .flex.mb-6 {
    width: fit-content;
    margin: 0 0 18px !important;
    padding: 4px !important;
    gap: 4px;
    border: 1px solid #e1e5ea;
    border-radius: 11px !important;
    background: #f3f5f7 !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-card > .flex.mb-6 button {
    min-width: 108px;
    min-height: 34px;
    padding: 0 14px !important;
    border-radius: 8px !important;
    font-size: 11px !important;
    font-weight: 750 !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form {
    margin: 0 !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form.space-y-4 > :not([hidden]) ~ :not([hidden]) {
    margin-top: 12px !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form > input,
  .${ROOT_CLASS}.${DESKTOP_CLASS} form > div > input {
    width: 100% !important;
    min-height: 54px !important;
    padding: 0 16px 0 48px !important;
    border: 1px solid #d8dee6 !important;
    border-radius: 12px !important;
    background-color: #f8fafc !important;
    background-repeat: no-repeat !important;
    background-position: 16px center !important;
    background-size: 20px !important;
    color: #161b22 !important;
    font-size: 14px !important;
    font-weight: 520 !important;
    outline: none !important;
    box-shadow: inset 0 1px 0 rgba(255,255,255,.9) !important;
    transition: border-color .18s ease, box-shadow .18s ease, background-color .18s ease !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form input::placeholder {
    color: #7d8794 !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form input:focus {
    border-color: #ff6a16 !important;
    background-color: #fff !important;
    box-shadow: 0 0 0 3px rgba(255,90,0,.10) !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form[x-show="authMode === 'employee'"] > input:nth-of-type(1) {
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%235f6975' stroke-width='1.8'%3E%3Crect x='4' y='3' width='16' height='18' rx='2'/%3E%3Cpath d='M8 8h8M8 12h8M8 16h5'/%3E%3C/svg%3E") !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form[x-show="authMode === 'employee'"] > input:nth-of-type(2),
  .${ROOT_CLASS}.${DESKTOP_CLASS} form[x-show="authMode === 'admin_login'"] > input:nth-of-type(1) {
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%235f6975' stroke-width='1.8'%3E%3Cpath d='M4 6.5l8 6 8-6'/%3E%3Crect x='3' y='5' width='18' height='14' rx='2'/%3E%3C/svg%3E") !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form input[type='password'] {
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%235f6975' stroke-width='1.8'%3E%3Crect x='5' y='10' width='14' height='11' rx='2'/%3E%3Cpath d='M8 10V7a4 4 0 018 0v3'/%3E%3C/svg%3E") !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-remember {
    display: flex !important;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-top: 13px !important;
    color: #242a32;
    font-size: 11px;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-remember label {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: 650;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-remember input {
    width: 20px;
    height: 20px;
    accent-color: #ff6500;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-forgot {
    border: 0;
    background: transparent;
    color: #1d232b;
    font-size: 11px;
    font-weight: 700;
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form > button[type='submit'] {
    width: 100% !important;
    min-height: 54px !important;
    margin-top: 16px !important;
    border: 0 !important;
    border-radius: 12px !important;
    background: linear-gradient(90deg, #ff6200 0%, #ff7618 100%) !important;
    color: #fff !important;
    font-size: 14px !important;
    font-weight: 800 !important;
    box-shadow: 0 10px 22px rgba(255,98,0,.20) !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form > button[type='submit']::after {
    content: '  →';
    font-size: 18px;
    font-weight: 500;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form > p {
    margin-top: 18px !important;
    color: #68717d !important;
    font-size: 11px !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} form > p:hover {
    color: #ff5a00 !important;
  }

  .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-extras {
    display: none !important;
  }

  .centralos-desktop-contact {
    margin: 27px 0 0;
    text-align: center;
    color: #8a929c;
    font-size: 11px;
  }

  .centralos-desktop-contact strong {
    color: #242a32;
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  .centralos-desktop-version {
    display: block !important;
    position: absolute;
    right: 24px;
    bottom: 18px;
    color: #c4c8ce;
    font-size: 10px;
    font-weight: 650;
    letter-spacing: .04em;
  }

  @media (max-width: 1020px) {
    .${ROOT_CLASS}.${DESKTOP_CLASS} > div {
      grid-template-columns: minmax(0, 50%) minmax(400px, 50%) !important;
    }
    .centralos-desktop-panel { padding: 44px 42px 38px; }
    .centralos-desktop-copy { width: 92%; }
    .centralos-desktop-copy h1 { font-size: 40px; }
    .${ROOT_CLASS}.${DESKTOP_CLASS} .centralos-login-card { padding-inline: 46px !important; }
  }
}
`;
    document.head.appendChild(style);
  }

  function createPanel() {
    const panel = document.createElement('section');
    panel.className = 'centralos-desktop-panel';
    panel.setAttribute('aria-hidden', 'true');
    panel.innerHTML = `
      <img class="centralos-desktop-brand" src="logologin.png" alt="">
      <div class="centralos-desktop-copy">
        <h1>Sua assistência<br>técnica <span>em ordem.</span></h1>
        <p>Mais controle, mais produtividade e mais resultados para o seu negócio.</p>
        <div class="centralos-desktop-benefits">
          <div class="centralos-desktop-benefit">
            <div class="centralos-desktop-benefit-icon"><i class="fa-solid fa-grip"></i></div>
            <div><strong>Mais organização</strong><span>Processos claros e eficientes</span></div>
          </div>
          <div class="centralos-desktop-benefit">
            <div class="centralos-desktop-benefit-icon"><i class="fa-regular fa-clock"></i></div>
            <div><strong>Mais produtividade</strong><span>Ganhe tempo no dia a dia</span></div>
          </div>
          <div class="centralos-desktop-benefit">
            <div class="centralos-desktop-benefit-icon"><i class="fa-solid fa-chart-column"></i></div>
            <div><strong>Mais resultados</strong><span>Sua assistência em outro nível</span></div>
          </div>
        </div>
      </div>
      <div class="centralos-desktop-footer">Tudo encontra seu lugar.</div>`;
    return panel;
  }

  function createHeading() {
    const heading = document.createElement('div');
    heading.className = 'centralos-desktop-heading';
    heading.innerHTML = '<h2>Bem-vindo de volta</h2><p>Entre para continuar no CentralOS</p>';
    return heading;
  }

  function createBadge() {
    const badge = document.createElement('div');
    badge.className = 'centralos-desktop-badge';
    badge.setAttribute('aria-hidden', 'true');
    badge.innerHTML = '<img src="favicon.svg" alt=""><div><strong>Sistema CentralOS</strong><span>Seguro, rápido. Sempre com você.</span></div>';
    return badge;
  }

  function decorate() {
    const root = [...document.querySelectorAll('div[x-show]')].find((el) => {
      const expr = el.getAttribute('x-show') || '';
      return expr.includes('!session') && expr.includes('!employeeSession') && expr.includes('registrationSuccess');
    });
    if (!root) return false;

    const shell = root.firstElementChild;
    if (!shell) return false;

    let card = shell.querySelector('.centralos-login-card');
    if (!card) {
      card = [...shell.children].find((el) => el.querySelector && el.querySelector("form[x-show=\"authMode === 'employee'\"]"));
    }
    if (!card) return false;

    root.classList.add(ROOT_CLASS, DESKTOP_CLASS);
    card.classList.add('centralos-login-card');

    const oldHead = card.querySelector('.text-center.mb-8');
    if (oldHead) oldHead.classList.add('centralos-login-oldhead');

    if (!shell.querySelector('.centralos-desktop-panel')) {
      shell.insertBefore(createPanel(), card);
    }

    if (!card.querySelector('.centralos-desktop-heading')) {
      const tabs = card.querySelector(':scope > .flex.mb-6');
      const heading = createHeading();
      if (tabs) card.insertBefore(heading, tabs);
      else card.prepend(heading);
    }

    if (!card.querySelector('.centralos-desktop-badge')) {
      card.prepend(createBadge());
    }

    if (!card.querySelector('.centralos-desktop-contact')) {
      const contact = document.createElement('p');
      contact.className = 'centralos-desktop-contact';
      contact.innerHTML = 'Não tem uma conta? <strong>Falar com o administrador</strong>';
      card.appendChild(contact);
    }

    if (!card.querySelector('.centralos-desktop-version')) {
      const version = document.createElement('span');
      version.className = 'centralos-desktop-version';
      version.textContent = 'v1.0.0';
      card.appendChild(version);
    }

    return true;
  }

  function boot() {
    injectStyles();
    if (decorate()) return;

    const observer = new MutationObserver(() => {
      if (decorate()) observer.disconnect();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => observer.disconnect(), 15000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
})();
