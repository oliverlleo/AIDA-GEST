(() => {
    'use strict';

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

    const mobileQuery = window.matchMedia('(max-width: 767px)');
    const actionOrigins = new WeakMap();
    let activeMobileActionKey = '';
    let activeMobileActionNodes = [];

    const normalize = (value) => String(value || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/\s+/g, ' ')
        .trim();

    const getAppState = () => {
        try {
            return window.Alpine?.$data?.(document.body) || null;
        } catch (_) {
            return null;
        }
    };

    const getCurrentView = () => getAppState()?.view || '';

    const getViewRoot = (view) => [...document.querySelectorAll('main [x-show]')].find((el) => {
        const expr = el.getAttribute('x-show') || '';
        return expr.includes(`view === '${view}'`);
    }) || null;

    const getDashboard = () => getViewRoot('dashboard');

    const getSessionNav = () => [...document.querySelectorAll('nav[x-show]')].find((el) =>
        (el.getAttribute('x-show') || '').includes('session')
    ) || null;

    const hasActiveSession = () => {
        const state = getAppState();
        return !!state && !!(state.session || state.employeeSession) && state.view !== 'setup_required';
    };

    const directChildren = (element, selector) => [...element.children].filter((child) => child.matches(selector));

    const getClickExpression = (element) =>
        element?.getAttribute('@click') ||
        element?.getAttribute('x-on:click') ||
        element?.getAttribute('@click.prevent') ||
        element?.getAttribute('x-on:click.prevent') ||
        '';

    const findDirectChildContainingClick = (root, needle) => [...(root?.children || [])].find((child) =>
        [...child.querySelectorAll('button')].some((button) => getClickExpression(button).includes(needle))
    ) || null;

    const findDashboardFilter = (header) =>
        findDirectChildContainingClick(header, 'applyHomeOperationalWindow(');

    const findDashboardAction = (header) => {
        const inHeader = findDirectChildContainingClick(header, 'openNewTicketModal()');
        if (inHeader) return inHeader;

        const zone = document.querySelector('.centralos-mobile-view-action-zone');
        return findDirectChildContainingClick(zone, 'openNewTicketModal()');
    };

    const findButtonByExactText = (root, label) => {
        const wanted = normalize(label);
        return [...(root?.querySelectorAll('button') || [])].find((button) =>
            normalize(button.textContent) === wanted
        ) || null;
    };

    const ensureMobileActionZone = () => {
        if (!hasActiveSession()) return null;

        let zone = document.querySelector('.centralos-mobile-view-action-zone');
        if (zone) return zone;

        const nav = getSessionNav();
        if (!nav) return null;

        zone = document.createElement('div');
        zone.className = 'centralos-mobile-view-action-zone';
        zone.setAttribute('aria-label', 'Ações da tela atual');
        nav.insertAdjacentElement('afterend', zone);
        return zone;
    };

    const rememberOrigin = (node) => {
        if (!node || actionOrigins.has(node)) return;
        actionOrigins.set(node, {
            parent: node.parentNode,
            nextSibling: node.nextSibling,
            formAttribute: node.tagName === 'BUTTON' ? node.getAttribute('form') : null
        });
    };

    const preserveSubmitButtonForm = (button) => {
        if (!button || button.tagName !== 'BUTTON') return;
        const type = normalize(button.getAttribute('type') || 'submit');
        if (type !== 'submit') return;

        const form = button.closest('form');
        if (!form) return;

        if (!form.id) {
            form.id = `centralos-mobile-form-${Math.random().toString(36).slice(2, 10)}`;
            form.dataset.centralosGeneratedId = 'true';
        }
        button.setAttribute('form', form.id);
    };

    const restoreNode = (node) => {
        const origin = actionOrigins.get(node);
        if (!node || !origin?.parent?.isConnected) return;

        if (origin.nextSibling && origin.nextSibling.parentNode === origin.parent) {
            origin.parent.insertBefore(node, origin.nextSibling);
        } else {
            origin.parent.appendChild(node);
        }

        if (node.tagName === 'BUTTON') {
            if (origin.formAttribute === null) node.removeAttribute('form');
            else node.setAttribute('form', origin.formAttribute);
        }
    };

    const clearMobileActionClasses = (node) => {
        if (!node) return;
        node.classList.remove(
            'centralos-mobile-action-button',
            'centralos-mobile-action-primary',
            'centralos-mobile-action-secondary',
            'centralos-mobile-home-split'
        );
    };

    const restoreActiveMobileActions = () => {
        activeMobileActionNodes.forEach((node) => {
            clearMobileActionClasses(node);
            restoreNode(node);
        });
        activeMobileActionNodes = [];
        activeMobileActionKey = '';

        const zone = document.querySelector('.centralos-mobile-view-action-zone');
        if (zone) {
            zone.removeAttribute('data-visible');
            zone.removeAttribute('data-layout');
            zone.removeAttribute('data-view');
        }
    };

    const ensureLayoutFixStyles = () => {
        [
            'centralos-layout-fixes-v2',
            'centralos-layout-fixes-v3',
            'centralos-layout-fixes-v4',
            'centralos-layout-fixes-v5',
            'centralos-layout-fixes-v6',
            'centralos-layout-fixes-v7',
            'centralos-layout-fixes-v8'
        ].forEach((id) => document.getElementById(id)?.remove());

        if (document.getElementById('centralos-layout-fixes-v9')) return;

        const style = document.createElement('style');
        style.id = 'centralos-layout-fixes-v9';
        style.textContent = `
            .centralos-mobile-view-action-zone {
                display: none;
            }

            @media (min-width: 768px) {
                body.centralos-enhanced .centralos-dashboard > header {
                    display: grid !important;
                    grid-template-columns: max-content minmax(0, 1fr) max-content !important;
                    align-items: center !important;
                    column-gap: 18px !important;
                    row-gap: 0 !important;
                    flex-wrap: nowrap !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .centralos-dashboard-filter-shell {
                    width: 100% !important;
                    min-width: 0 !important;
                    padding-left: 0 !important;
                    padding-right: 0 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header .centralos-period-filter {
                    margin-bottom: 0 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .centralos-dashboard-open-action {
                    display: flex !important;
                    align-self: center !important;
                    width: auto !important;
                    margin: 0 !important;
                }

                body.centralos-enhanced .centralos-dashboard-open-more > i {
                    transform: none !important;
                }
            }

            @media (max-width: 767px) {
                .centralos-mobile-view-action-zone[data-visible] {
                    display: grid !important;
                    position: relative;
                    grid-template-columns: minmax(0, 1fr);
                    gap: 8px;
                    width: 100%;
                    background: #0b0e12;
                    padding: 0 14px 12px;
                    z-index: 55;
                }

                .centralos-mobile-view-action-zone[data-layout="pair"] {
                    grid-template-columns: minmax(0, .8fr) minmax(0, 1.2fr);
                }

                .centralos-mobile-view-action-zone > .centralos-mobile-action-button {
                    width: 100% !important;
                    min-width: 0 !important;
                    height: 50px !important;
                    min-height: 50px !important;
                    margin: 0 !important;
                    padding: 0 16px !important;
                    display: inline-flex !important;
                    align-items: center !important;
                    justify-content: center !important;
                    gap: 10px !important;
                    border-radius: 12px !important;
                    font-size: 15px !important;
                    font-weight: 800 !important;
                    line-height: 1 !important;
                    box-shadow: none !important;
                    white-space: nowrap !important;
                }

                .centralos-mobile-view-action-zone > .centralos-mobile-action-button[style*="display: none"] {
                    display: none !important;
                }

                .centralos-mobile-view-action-zone > .centralos-mobile-action-primary {
                    border: 1px solid #ff6500 !important;
                    background: linear-gradient(90deg, #ff6500 0%, #ff5a00 100%) !important;
                    color: #fff !important;
                    box-shadow: 0 10px 24px rgba(255,101,0,.18) !important;
                }

                .centralos-mobile-view-action-zone > .centralos-mobile-action-secondary {
                    border: 1px solid #343b45 !important;
                    background: #171b21 !important;
                    color: #fff !important;
                }

                .centralos-mobile-view-action-zone > .centralos-mobile-action-button i {
                    margin-right: 0 !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action {
                    display: grid !important;
                    grid-template-columns: minmax(0, 1fr) 50px !important;
                    align-items: stretch !important;
                    width: 100% !important;
                    min-width: 0 !important;
                    max-width: 100% !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    overflow: visible !important;
                    border-radius: 12px !important;
                    box-shadow: 0 10px 24px rgba(255,101,0,.18) !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action > .centralos-dashboard-open-primary {
                    grid-column: 1 !important;
                    width: 100% !important;
                    min-width: 0 !important;
                    max-width: none !important;
                    height: 50px !important;
                    min-height: 50px !important;
                    margin: 0 !important;
                    padding: 0 18px !important;
                    display: flex !important;
                    align-items: center !important;
                    justify-content: center !important;
                    gap: 14px !important;
                    border: 0 !important;
                    border-radius: 12px 0 0 12px !important;
                    background: linear-gradient(90deg, #ff6500 0%, #ff5a00 100%) !important;
                    color: #fff !important;
                    font-size: 17px !important;
                    font-weight: 800 !important;
                    line-height: 1 !important;
                    letter-spacing: -.01em !important;
                    box-shadow: none !important;
                    flex: none !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action > .centralos-dashboard-open-primary i {
                    margin-right: 0 !important;
                    font-size: 19px !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action > .centralos-dashboard-open-more:not([style*="display: none"]) {
                    grid-column: 2 !important;
                    width: 50px !important;
                    min-width: 50px !important;
                    max-width: 50px !important;
                    height: 50px !important;
                    min-height: 50px !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    display: inline-flex !important;
                    align-items: center !important;
                    justify-content: center !important;
                    border: 0 !important;
                    border-left: 1px solid rgba(255,255,255,.26) !important;
                    border-radius: 0 12px 12px 0 !important;
                    background: linear-gradient(90deg, #ff6500 0%, #ff5a00 100%) !important;
                    color: #fff !important;
                    font-size: 15px !important;
                    box-shadow: none !important;
                    flex: none !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action > .centralos-dashboard-open-more[style*="display: none"] {
                    display: none !important;
                }

                .centralos-mobile-view-action-zone .centralos-dashboard-open-more > i {
                    transform: rotate(-90deg) !important;
                    transform-origin: center !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action:has(> .centralos-dashboard-open-more[style*="display: none"]) {
                    grid-template-columns: 1fr !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action:has(> .centralos-dashboard-open-more[style*="display: none"]) > .centralos-dashboard-open-primary {
                    border-radius: 12px !important;
                }

                .centralos-mobile-view-action-zone > .centralos-dashboard-open-action > .centralos-dashboard-open-menu {
                    right: 0 !important;
                    top: calc(100% + 8px) !important;
                    z-index: 100 !important;
                }

                body.centralos-enhanced .centralos-dashboard > header {
                    display: flex !important;
                    flex-direction: column !important;
                    align-items: stretch !important;
                    width: 100% !important;
                    margin-bottom: 14px !important;
                }

                body.centralos-enhanced .centralos-dashboard > header > .centralos-dashboard-filter-shell {
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

    const prepareDashboardAction = (dashboard) => {
        dashboard?.classList.add('centralos-dashboard');

        const header = dashboard?.querySelector(':scope > header');
        if (!header) return null;

        const action = findDashboardAction(header);
        if (!action) return null;

        const primaryButton = [...action.children].find((child) =>
            child.tagName === 'BUTTON' && getClickExpression(child).includes('openNewTicketModal()')
        ) || null;
        const moreButton = [...action.children].find((child) =>
            child.tagName === 'BUTTON' && getClickExpression(child).includes('newTicketMenuOpen')
        ) || null;
        const warrantyMenu = [...action.children].find((child) =>
            (child.getAttribute?.('x-show') || '').includes('newTicketMenuOpen')
        ) || null;

        if (!primaryButton) return null;

        action.classList.add('centralos-dashboard-open-action');
        primaryButton.classList.add('centralos-dashboard-open-primary');
        moreButton?.classList.add('centralos-dashboard-open-more');
        warrantyMenu?.classList.add('centralos-dashboard-open-menu');

        const filter = findDashboardFilter(header);
        if (filter) filter.classList.add('centralos-dashboard-filter-shell');

        return { action, header, filter };
    };

    const getDesiredMobileActions = () => {
        if (!hasActiveSession()) return null;

        const view = getCurrentView();

        if (view === 'dashboard') {
            const dashboard = getDashboard();
            const prepared = prepareDashboardAction(dashboard);
            if (!prepared?.action) return null;
            return {
                key: 'dashboard',
                view,
                layout: 'single',
                nodes: [{ node: prepared.action, role: 'home' }]
            };
        }

        if (view === 'customers') {
            const root = getViewRoot('customers');
            const button = findButtonByExactText(root, 'Novo cliente');
            if (!button) return null;
            return {
                key: 'customers:new-client',
                view,
                layout: 'single',
                nodes: [{ node: button, role: 'primary' }]
            };
        }

        if (view === 'management_settings') {
            const root = getViewRoot('management_settings');
            const button = findButtonByExactText(root, 'Salvar alterações');
            if (!button) return null;
            return {
                key: 'management-settings:save',
                view,
                layout: 'single',
                nodes: [{ node: button, role: 'primary' }]
            };
        }

        if (view === 'tracker_settings') {
            const root = getViewRoot('tracker_settings');
            const reset = findButtonByExactText(root, 'Redefinir');
            const save = findButtonByExactText(root, 'Salvar alterações');
            const nodes = [
                reset ? { node: reset, role: 'secondary' } : null,
                save ? { node: save, role: 'primary' } : null
            ].filter(Boolean);

            if (!nodes.length) return null;
            return {
                key: `tracker-settings:${nodes.map((item) => item.role).join('+')}`,
                view,
                layout: nodes.length > 1 ? 'pair' : 'single',
                nodes
            };
        }

        return null;
    };

    const applyMobileViewActions = () => {
        const dashboard = getDashboard();
        const preparedDashboard = prepareDashboardAction(dashboard);

        if (!hasActiveSession()) {
            if (activeMobileActionNodes.length) restoreActiveMobileActions();
            const zone = document.querySelector('.centralos-mobile-view-action-zone');
            zone?.removeAttribute('data-visible');
            return;
        }

        if (!mobileQuery.matches) {
            if (activeMobileActionNodes.length) restoreActiveMobileActions();

            if (preparedDashboard?.action && preparedDashboard.action.parentElement !== preparedDashboard.header) {
                if (preparedDashboard.filter) {
                    preparedDashboard.filter.insertAdjacentElement('afterend', preparedDashboard.action);
                } else {
                    preparedDashboard.header.appendChild(preparedDashboard.action);
                }
            } else if (
                preparedDashboard?.action &&
                preparedDashboard.filter &&
                preparedDashboard.filter.nextElementSibling !== preparedDashboard.action
            ) {
                preparedDashboard.filter.insertAdjacentElement('afterend', preparedDashboard.action);
            }
            return;
        }

        const desired = getDesiredMobileActions();
        const zone = ensureMobileActionZone();

        if (!desired || !zone) {
            if (activeMobileActionNodes.length) restoreActiveMobileActions();
            return;
        }

        const desiredNodes = desired.nodes.map((item) => item.node);
        const alreadyApplied =
            activeMobileActionKey === desired.key &&
            activeMobileActionNodes.length === desiredNodes.length &&
            activeMobileActionNodes.every((node, index) =>
                node === desiredNodes[index] && node.parentElement === zone
            );

        if (alreadyApplied) {
            zone.setAttribute('data-visible', '');
            zone.dataset.layout = desired.layout;
            zone.dataset.view = desired.view;
            return;
        }

        if (activeMobileActionNodes.length) restoreActiveMobileActions();

        desired.nodes.forEach(({ node, role }) => {
            rememberOrigin(node);

            if (node.tagName === 'BUTTON') {
                preserveSubmitButtonForm(node);
                node.classList.add('centralos-mobile-action-button');
                node.classList.add(
                    role === 'secondary'
                        ? 'centralos-mobile-action-secondary'
                        : 'centralos-mobile-action-primary'
                );
            } else if (role === 'home') {
                node.classList.add('centralos-mobile-home-split');
            }

            zone.appendChild(node);
        });

        activeMobileActionNodes = desiredNodes;
        activeMobileActionKey = desired.key;
        zone.setAttribute('data-visible', '');
        zone.dataset.layout = desired.layout;
        zone.dataset.view = desired.view;
    };

    const decorateSectionHeadings = (dashboard) => {
        [...(dashboard?.querySelectorAll('h3') || [])].forEach((heading) => {
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
        [...(dashboard?.querySelectorAll('h4') || [])].forEach((heading) => {
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
        if (dashboard) {
            prepareDashboardAction(dashboard);
            decorateSectionHeadings(dashboard);
            decorateOperationalCards(dashboard);
        }

        applyMobileViewActions();
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
        document.querySelector('.centralos-home-mobile-action-zone')?.remove();
        ensureLayoutFixStyles();
        decorate();

        window.setTimeout(decorate, 100);
        window.setTimeout(decorate, 250);
        window.setTimeout(decorate, 900);

        document.addEventListener('click', () => window.setTimeout(decorate, 0), { passive: true });
        mobileQuery.addEventListener?.('change', decorate);

        new MutationObserver(schedule).observe(document.body, {
            childList: true,
            subtree: true
        });
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
