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

    const directChildren = (element, selector) => [...element.children].filter((child) => child.matches(selector));

    const decorateSectionHeadings = (dashboard) => {
        [...dashboard.querySelectorAll('h3')].forEach((heading) => {
            const text = normalize(heading.textContent);
            const def = SECTION_DEFINITIONS.find((item) => text.includes(normalize(item.match)));
            if (!def) return;

            heading.classList.add('centralos-section-heading', 'centralos-section-heading-complete');

            const nativeIcons = directChildren(heading, 'i:not(.centralos-section-icon)');
            const injectedIcons = directChildren(heading, 'i.centralos-section-icon');

            // A tela original já possui ícone nestes títulos. O complemento anterior
            // adicionava outro no caso de "Pendências com Técnico". Mantemos somente um.
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
        const dashboard = getDashboard();
        if (!dashboard) return;
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
        decorate();
        window.setTimeout(decorate, 250);
        window.setTimeout(decorate, 900);
        new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
