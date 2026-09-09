(() => {
    const CARD_DEFINITIONS = [
        { match: 'aguardando início', cls: 'centralos-queue-tech', icon: 'fa-user-gear' },
        { match: 'pendente envio', cls: 'centralos-queue-outsourced-send', icon: 'fa-paper-plane' },
        { match: 'aguardando retorno', cls: 'centralos-queue-outsourced-return', icon: 'fa-rotate-left' },
        { match: 'aguardando compra', cls: 'centralos-queue-supplier-purchase', icon: 'fa-cart-shopping' },
        { match: 'aguardando recebimento', cls: 'centralos-queue-supplier-receipt', icon: 'fa-box-open' },
        { match: 'aguardando teste final', cls: 'centralos-queue-final-test', icon: 'fa-flask' },
        { match: 'sem agendamento', cls: 'centralos-queue-unscheduled', icon: 'fa-calendar-xmark' }
    ];

    const SECTION_DEFINITIONS = [
        { match: 'pendências com técnico', icon: 'fa-user-gear' },
        { match: 'pendências com terceirizado', icon: 'fa-handshake' },
        { match: 'pendências com fornecedor', icon: 'fa-truck-fast' }
    ];

    const normalize = (value) => String(value || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .trim();

    const getDashboard = () => [...document.querySelectorAll('main [x-show]')].find((el) => {
        const expr = el.getAttribute('x-show') || '';
        return expr.includes("view === 'dashboard'");
    }) || null;

    const getCurrentView = () => {
        try {
            return window.Alpine?.$data?.(document.body)?.view || '';
        } catch (_) {
            return '';
        }
    };

    const isDashboardActive = (dashboard) => {
        const view = getCurrentView();
        if (view) return view === 'dashboard';
        return !!dashboard && window.getComputedStyle(dashboard).display !== 'none';
    };

    const directChildren = (element, selector) => [...element.children].filter((child) => child.matches(selector));

    const ensureLayoutFixStyles = () => {
        document.getElementById('centralos-layout-fixes-v2')?.remove();
        document.getElementById('centralos-layout-fixes-v3')?.remove();
        if (document.getElementById('centralos-layout-fixes-v4')) return;

        const style = document.createElement('style');
        style.id = 'centralos-layout-fixes-v4';
        style.textContent = `
            /* Desktop: título, filtros e ação na mesma linha e alinhados. */
            @media (min-width: 768px) {
                body.centralos-enhanced .centralos-dashboard > header {
                    display: grid !important;
                    grid-template-columns: max-content minmax(0, 1fr) max-content !important;
                    align-items: center !important;
                    column-gap: 18px !important;
                    row-gap: 0 !important;
                    flex-wrap: nowrap !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .aida-operational-filter {
                    width: 100% !important;
                    min-width: 0 !important;
                    padding-left: 0 !important;
                    padding-right: 0 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header .centralos-period-filter {
                    margin-bottom: 0 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .aida-split-action {
                    align-self: center !important;
                    margin: 0 !important;
                }
            }

            /* Mobile da Início: usa SOMENTE o Abrir Chamado original.
               Ele fica dentro da Início, acima dos filtros, com o mesmo padrão da aba Chamados. */
            @media (max-width: 767px) {
                body.centralos-dashboard-active .centralos-mobile-action-strip {
                    display: none !important;
                }

                body.centralos-enhanced .centralos-dashboard > header {
                    display: flex !important;
                    flex-direction: column !important;
                    align-items: stretch !important;
                    margin-bottom: 14px !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > div:first-child {
                    order: 1 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .aida-split-action {
                    order: 2 !important;
                    width: 100% !important;
                    margin: 14px 0 0 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .aida-operational-filter {
                    order: 3 !important;
                    display: block !important;
                    width: 100% !important;
                    min-width: 0 !important;
                    margin-top: 14px !important;
                    padding: 0 !important;
                    overflow: hidden !important;
                }

                body.centralos-enhanced .centralos-dashboard .centralos-period-filter {
                    display: flex !important;
                    width: 100% !important;
                    grid-template-columns: none !important;
                    gap: 8px !important;
                    padding: 0 0 4px !important;
                    margin: 0 !important;
                    overflow-x: auto !important;
                    overflow-y: hidden !important;
                    border: 0 !important;
                    border-radius: 0 !important;
                    background: transparent !important;
                    box-shadow: none !important;
                    scroll-snap-type: x proximity;
                    scrollbar-width: none;
                    -webkit-overflow-scrolling: touch;
                }

                body.centralos-enhanced .centralos-dashboard .centralos-period-filter::-webkit-scrollbar {
                    display: none;
                }

                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button {
                    flex: 0 0 auto !important;
                    width: auto !important;
                    min-width: 0 !important;
                    min-height: 37px !important;
                    padding: 7px 13px !important;
                    border: 1px solid #dfe3e8 !important;
                    border-radius: 999px !important;
                    background: #fff !important;
                    color: #68717d !important;
                    font-size: 12px !important;
                    font-weight: 650 !important;
                    white-space: nowrap !important;
                    box-shadow: none !important;
                    scroll-snap-align: start;
                }

                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-brand-50,
                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-red-50,
                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-gray-100,
                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-black {
                    background: linear-gradient(135deg, #ff6500, #ff7410) !important;
                    border-color: #ff6500 !important;
                    color: #fff !important;
                    box-shadow: 0 5px 12px rgba(255,101,0,.16) !important;
                }

                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button span:last-child {
                    min-width: 21px !important;
                    height: 21px !important;
                    padding: 0 6px !important;
                    border-radius: 999px !important;
                    background: #f1f3f5 !important;
                    color: #6e7681 !important;
                    font-weight: 800 !important;
                }

                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-brand-50 span:last-child,
                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-red-50 span:last-child,
                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-gray-100 span:last-child,
                body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button.bg-black span:last-child {
                    background: rgba(255,255,255,.2) !important;
                    color: #fff !important;
                }
            }
        `;
        document.head.appendChild(style);
    };

    const applyUploadedLogo = () => {
        const target = 'logo.png';

        const navLogo = document.querySelector('nav img[alt="CentralOS"]');
        if (navLogo) {
            if (!navLogo.src.endsWith('/logo.png')) navLogo.src = target;
            navLogo.dataset.centralosBrandLogo = 'logo.png';
        }

        const loginLogo = document.querySelector('img[src="logologin.png"], img[src*="/logologin.png"]');
        if (loginLogo) {
            if (!loginLogo.src.endsWith('/logo.png')) loginLogo.src = target;
            loginLogo.alt = 'CentralOS';
            loginLogo.dataset.centralosBrandLogo = 'logo.png';
        }
    };

    const configureDashboardAction = (dashboard) => {
        const header = dashboard?.querySelector(':scope > header');
        if (!header) return;

        /* Limpa a implementação errada anterior, caso ainda exista no DOM atual. */
        const legacyStrip = document.querySelector('.centralos-dashboard-mobile-action-strip');
        const legacyAction = legacyStrip?.querySelector(':scope > .aida-split-action');
        if (legacyAction && legacyAction.parentElement !== header) {
            header.appendChild(legacyAction);
        }
        legacyStrip?.remove();
        header.querySelectorAll(':scope > .centralos-dashboard-action-anchor').forEach((el) => el.remove());

        const action = header.querySelector(':scope > .aida-split-action');
        if (!action) return;

        /* Reutiliza exatamente o botão original; só aplica as classes visuais do Chamados mobile. */
        action.classList.add('centralos-mobile-action-inner');
        action.querySelector(':scope > button:first-of-type')?.classList.add('centralos-mobile-new-ticket');
        action.querySelector(':scope > button:nth-of-type(2)')?.classList.add('centralos-mobile-new-ticket-more');

        document.body.classList.toggle('centralos-dashboard-active', isDashboardActive(dashboard));
    };

    const decorateSectionHeadings = (dashboard) => {
        [...dashboard.querySelectorAll('h3')].forEach((heading) => {
            const text = normalize(heading.textContent);
            const def = SECTION_DEFINITIONS.find((item) => text.includes(normalize(item.match)));
            if (!def) return;

            heading.classList.add('centralos-section-heading', 'centralos-section-heading-complete');

            const nativeIcons = directChildren(heading, 'i:not(.centralos-section-icon)');
            const injectedIcons = directChildren(heading, 'i.centralos-section-icon');

            if (nativeIcons.length) {
                injectedIcons.forEach((icon) => icon.remove());
                nativeIcons.forEach((icon) => {
                    icon.classList.add('centralos-section-icon-native');
                    icon.setAttribute('aria-hidden', 'true');
                });
                heading.dataset.centralosSectionHeading = 'true';
                return;
            }

            if (!injectedIcons.length) {
                const icon = document.createElement('i');
                icon.className = `fa-solid ${def.icon} centralos-section-icon`;
                icon.setAttribute('aria-hidden', 'true');
                heading.prepend(icon);
            }
            heading.dataset.centralosSectionHeading = 'true';
        });
    };

    const decorateOperationalCards = (dashboard) => {
        [...dashboard.querySelectorAll('h4')].forEach((heading) => {
            const text = normalize(heading.textContent);
            const def = CARD_DEFINITIONS.find((item) => text.includes(normalize(item.match)));
            if (!def) return;

            const card = heading.closest('.bg-white');
            if (!card) return;

            card.classList.add('centralos-queue', 'centralos-queue--extended', def.cls);
            heading.classList.add('centralos-queue-title');

            let icon = heading.querySelector(':scope > .centralos-queue-icon');
            if (!icon) {
                icon = document.createElement('span');
                icon.className = 'centralos-queue-icon';
                icon.setAttribute('aria-hidden', 'true');
                icon.innerHTML = `<i class="fa-solid ${def.icon}"></i>`;
                heading.prepend(icon);
            }
        });
    };

    const decorate = () => {
        ensureLayoutFixStyles();
        applyUploadedLogo();
        const dashboard = getDashboard();
        if (!dashboard) {
            document.body.classList.remove('centralos-dashboard-active');
            return;
        }
        configureDashboardAction(dashboard);
        decorateSectionHeadings(dashboard);
        decorateOperationalCards(dashboard);
    };

    let scheduled = false;
    const schedule = () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            decorate();
        });
    };

    const start = () => {
        ensureLayoutFixStyles();
        decorate();
        window.setTimeout(decorate, 100);
        window.setTimeout(decorate, 250);
        window.setTimeout(decorate, 900);
        document.addEventListener('click', () => window.setTimeout(decorate, 0), { passive: true });
        new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
