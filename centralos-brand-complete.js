(() => {
    const ICONS = {
        open: 'fa-file-lines',
        analysis: 'fa-clock',
        approval: 'fa-clipboard-check',
        pickup: 'fa-bag-shopping'
    };

    const QUEUES = [
        { match: 'aguardando envio de orçamento', cls: 'centralos-queue-budget', icon: 'fa-paper-plane' },
        { match: 'aguardando aprovação', cls: 'centralos-queue-approval', icon: 'fa-clipboard-check' },
        { match: 'logística e expedição', cls: 'centralos-queue-logistics', icon: 'fa-truck' },
        { match: 'gerar rastreio', cls: 'centralos-queue-tracking', icon: 'fa-box' },
        { match: 'liberado', cls: 'centralos-queue-released', icon: 'fa-circle-check' },
        { match: 'atenção necessária', cls: 'centralos-queue-attention', icon: 'fa-triangle-exclamation' },
        { match: 'últimas atividades', cls: 'centralos-queue-activity', icon: 'fa-cube' }
    ];

    const normalize = (value) => String(value || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .trim();

    const getDashboard = () => {
        return [...document.querySelectorAll('main [x-show]')].find((el) => {
            const expr = el.getAttribute('x-show') || '';
            return expr.includes("view === 'dashboard'");
        }) || null;
    };

    const decorateTitle = (dashboard) => {
        const title = dashboard?.querySelector(':scope > header h1');
        if (!title || title.dataset.centralosDecorated) return;
        if (normalize(title.textContent) !== 'visao geral') return;

        title.classList.add('centralos-dashboard-title');
        title.innerHTML = '<span>Visão</span><span class="centralos-title-accent">Geral</span>';
        title.dataset.centralosDecorated = 'true';
    };

    const decorateStats = (dashboard) => {
        if (!dashboard) return;

        const definitions = [
            ['homeStatusCounts.open', 'open'],
            ['homeStatusCounts.analysis', 'analysis'],
            ['homeStatusCounts.approval', 'approval'],
            ['homeStatusCounts.pickup', 'pickup']
        ];

        definitions.forEach(([binding, tone]) => {
            const value = dashboard.querySelector(`[x-text="${binding}"]`);
            if (!value) return;
            const card = value.closest('.bg-white');
            if (!card || card.dataset.centralosStat) return;

            card.classList.add('centralos-stat-card');
            card.dataset.centralosTone = tone;
            card.dataset.centralosStat = 'true';

            const label = value.previousElementSibling;
            if (label) label.classList.add('centralos-stat-label');

            const icon = document.createElement('span');
            icon.className = 'centralos-stat-icon';
            icon.setAttribute('aria-hidden', 'true');
            icon.innerHTML = `<i class="fa-solid ${ICONS[tone]}"></i>`;

            const arrow = document.createElement('span');
            arrow.className = 'centralos-stat-arrow';
            arrow.setAttribute('aria-hidden', 'true');
            arrow.innerHTML = '<i class="fa-solid fa-chevron-right"></i>';

            card.append(icon, arrow);
        });
    };

    const decoratePeriodFilter = (dashboard) => {
        if (!dashboard) return;
        const buttons = [...dashboard.querySelectorAll('button')].filter((button) => {
            const names = button.getAttributeNames ? button.getAttributeNames() : [];
            return names.some((name) => {
                const value = button.getAttribute(name) || '';
                return value.includes('applyHomeOperationalWindow');
            });
        });

        if (buttons.length < 2) return;
        buttons.forEach((button) => button.classList.add('centralos-period-button'));

        const parent = buttons[0].parentElement;
        if (parent && buttons.every((button) => button.parentElement === parent)) {
            parent.classList.add('centralos-period-filter');
        }
    };

    const decorateQueues = (dashboard) => {
        if (!dashboard) return;

        [...dashboard.querySelectorAll('h3, h4')].forEach((heading) => {
            const text = normalize(heading.textContent);

            if (text.includes('pendencias com tecnico')) {
                if (!heading.dataset.centralosSectionHeading) {
                    heading.classList.add('centralos-section-heading');
                    const icon = document.createElement('i');
                    icon.className = 'fa-solid fa-user-gear centralos-section-icon';
                    icon.setAttribute('aria-hidden', 'true');
                    heading.prepend(icon);
                    heading.dataset.centralosSectionHeading = 'true';
                }
                return;
            }

            const def = QUEUES.find((item) => normalize(item.match) && text.includes(normalize(item.match)));
            if (!def) return;

            const card = heading.closest('.bg-white');
            if (!card) return;

            card.classList.add('centralos-queue', def.cls);
            heading.classList.add('centralos-queue-title');

            if (!heading.querySelector('.centralos-queue-icon')) {
                const icon = document.createElement('span');
                icon.className = 'centralos-queue-icon';
                icon.setAttribute('aria-hidden', 'true');
                icon.innerHTML = `<i class="fa-solid ${def.icon}"></i>`;
                heading.prepend(icon);
            }
        });
    };

    const addSidebarPromo = () => {
        const aside = [...document.querySelectorAll('aside[x-show]')].find((el) => {
            const expr = el.getAttribute('x-show') || '';
            return expr.includes('session');
        });
        if (!aside || aside.querySelector('.centralos-sidebar-promo')) return;

        const promo = document.createElement('section');
        promo.className = 'centralos-sidebar-promo';
        promo.setAttribute('aria-label', 'Identidade Centralos');
        promo.innerHTML = `
            <div class="centralos-sidebar-promo-mark" aria-hidden="true">
                <svg viewBox="0 0 180 128" xmlns="http://www.w3.org/2000/svg">
                    <path d="M55 17C26 17 9 38 9 64s17 47 46 47h46V90H58c-17 0-28-10-28-26 0-15 11-26 28-26h43V17H55z" fill="#20242b"/>
                    <rect x="69" y="38" width="65" height="15" rx="7.5" fill="#ff6500"/>
                    <rect x="57" y="58" width="77" height="15" rx="7.5" fill="#ff6500"/>
                    <rect x="69" y="78" width="65" height="15" rx="7.5" fill="#ff6500"/>
                    <path d="M45 28C24 37 16 49 16 64c0 19 11 33 31 41" fill="none" stroke="#2a2f36" stroke-width="8" stroke-linecap="round" opacity=".75"/>
                </svg>
            </div>
            <div class="centralos-sidebar-promo-copy">
                <span>Mais<br>organização</span>
                <span>Mais<br>produtividade</span>
                <span>Mais<br>resultados</span>
            </div>
            <div class="centralos-sidebar-promo-line"></div>
        `;

        const footer = document.createElement('div');
        footer.className = 'centralos-sidebar-brand-footer';
        footer.innerHTML = '<strong>Centralos</strong><span>Sua assistência técnica em ordem</span>';

        aside.append(promo, footer);
    };

    const addTopSlogan = () => {
        const nav = [...document.querySelectorAll('nav[x-show]')].find((el) => {
            const expr = el.getAttribute('x-show') || '';
            return expr.includes('session');
        });
        if (!nav || nav.querySelector('.centralos-top-slogan')) return;

        const logout = nav.querySelector('button[title="Sair"]');
        const actions = logout?.parentElement || nav.lastElementChild;
        if (!actions) return;

        const slogan = document.createElement('div');
        slogan.className = 'centralos-top-slogan';
        slogan.setAttribute('aria-hidden', 'true');
        slogan.innerHTML = '<span>Tudo encontra<br>seu lugar.</span>';
        actions.appendChild(slogan);
    };

    const addTopSearch = () => {
        const nav = [...document.querySelectorAll('nav[x-show]')].find((el) => {
            const expr = el.getAttribute('x-show') || '';
            return expr.includes('session');
        });
        if (!nav || nav.querySelector('.centralos-top-search')) return;

        const left = nav.firstElementChild;
        if (!left) return;

        const search = document.createElement('label');
        search.className = 'centralos-top-search';
        search.innerHTML = `
            <i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>
            <input type="search" placeholder="Buscar chamados, clientes, OS..." aria-label="Buscar chamados, clientes e ordens de serviço">
        `;

        left.insertAdjacentElement('afterend', search);
        const input = search.querySelector('input');
        if (!input) return;

        const syncFromState = () => {
            try {
                const data = window.Alpine?.$data?.(document.body);
                if (data && typeof data.searchQuery !== 'undefined' && input.value !== String(data.searchQuery || '')) {
                    input.value = String(data.searchQuery || '');
                }
            } catch (_) {}
        };

        input.addEventListener('input', () => {
            try {
                const data = window.Alpine?.$data?.(document.body);
                if (data && typeof data.searchQuery !== 'undefined') {
                    data.searchQuery = input.value;
                }
            } catch (_) {}
        });

        input.addEventListener('focus', syncFromState);
        document.addEventListener('click', () => window.setTimeout(syncFromState, 0), { passive: true });
        window.setTimeout(syncFromState, 350);
        window.setTimeout(syncFromState, 1100);
    };

    const decorate = () => {
        document.body?.classList.add('centralos-enhanced');
        addSidebarPromo();
        addTopSearch();
        addTopSlogan();

        const dashboard = getDashboard();
        if (dashboard) {
            dashboard.classList.add('centralos-dashboard');
            decorateTitle(dashboard);
            decorateStats(dashboard);
            decoratePeriodFilter(dashboard);
            decorateQueues(dashboard);
        }
    };

    let scheduled = false;
    const scheduleDecorate = () => {
        if (scheduled) return;
        scheduled = true;
        window.requestAnimationFrame(() => {
            scheduled = false;
            decorate();
        });
    };

    const start = () => {
        decorate();
        window.setTimeout(decorate, 250);
        window.setTimeout(decorate, 900);

        const observer = new MutationObserver(scheduleDecorate);
        observer.observe(document.body, { childList: true, subtree: true });
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
