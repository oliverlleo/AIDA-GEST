(() => {
    'use strict';

    const MOBILE_QUERY = '(max-width: 767px)';
    const mq = window.matchMedia(MOBILE_QUERY);

    const normalize = (value) => String(value || '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/\s+/g, ' ')
        .trim();

    const alpineData = () => {
        try {
            return window.Alpine?.$data?.(document.body) || null;
        } catch (_) {
            return null;
        }
    };

    const getSessionNav = () => [...document.querySelectorAll('nav[x-show]')].find((el) =>
        (el.getAttribute('x-show') || '').includes('session')
    ) || null;

    const getSidebar = () => [...document.querySelectorAll('aside[x-show]')].find((el) =>
        (el.getAttribute('x-show') || '').includes('session')
    ) || null;

    const getKanban = () => [...document.querySelectorAll('main [x-show]')].find((el) =>
        normalize(el.getAttribute('x-show')).includes("view === 'kanban'")
    ) || null;

    const isElementAlpineVisible = (el) => !!el && el.style.display !== 'none' && !el.hasAttribute('hidden');

    const findButtonByClick = (root, piece) => [...(root?.querySelectorAll('button') || [])].find((button) =>
        (button.getAttribute('@click') || '').includes(piece)
    ) || null;

    const currentView = () => alpineData()?.view || '';

    const syncMobileVisibility = () => {
        const sessionNav = getSessionNav();
        const sessionActive = mq.matches && isElementAlpineVisible(sessionNav);
        const kanbanActive = sessionActive && currentView() === 'kanban';
        document.body.classList.toggle('centralos-mobile-session-active', sessionActive);
        document.body.classList.toggle('centralos-mobile-kanban-active', kanbanActive);

        document.querySelector('.centralos-mobile-action-strip')?.toggleAttribute('data-visible', kanbanActive);
        document.querySelector('.centralos-mobile-bottom-nav')?.toggleAttribute('data-visible', sessionActive);
        syncBottomNav();
    };

    const ensureTopAccountChevron = () => {
        const nav = getSessionNav();
        if (!nav || nav.querySelector('.centralos-mobile-account-chevron')) return;
        const actions = nav.lastElementChild;
        if (!actions) return;

        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'centralos-mobile-account-chevron centralos-mobile-only';
        button.setAttribute('aria-label', 'Abrir menu');
        button.innerHTML = '<i class="fa-solid fa-chevron-down"></i>';
        button.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            openMoreSheet();
        });
        actions.appendChild(button);
    };

    const ensureActionStrip = () => {
        const nav = getSessionNav();
        if (!nav || document.querySelector('.centralos-mobile-action-strip')) return;

        const strip = document.createElement('div');
        strip.className = 'centralos-mobile-action-strip centralos-mobile-only';
        strip.innerHTML = `
            <div class="centralos-mobile-action-inner">
                <button type="button" class="centralos-mobile-new-ticket">
                    <i class="fa-solid fa-plus"></i>
                    <span>Novo Chamado</span>
                </button>
                <button type="button" class="centralos-mobile-new-ticket-more" aria-label="Outras formas de abertura">
                    <i class="fa-solid fa-chevron-right"></i>
                </button>
            </div>
            <div class="centralos-mobile-new-ticket-menu" hidden>
                <button type="button" data-action="warranty">
                    <span class="centralos-mobile-menu-icon"><i class="fa-solid fa-shield-halved"></i></span>
                    <span><strong>Retorno em garantia</strong><small>Vincular à OS original</small></span>
                </button>
            </div>
        `;

        nav.insertAdjacentElement('afterend', strip);

        strip.querySelector('.centralos-mobile-new-ticket')?.addEventListener('click', () => {
            const original = findButtonByClick(getKanban(), 'openNewTicketModal()');
            if (original) original.click();
            else alpineData()?.openNewTicketModal?.();
        });

        const moreButton = strip.querySelector('.centralos-mobile-new-ticket-more');
        const menu = strip.querySelector('.centralos-mobile-new-ticket-menu');
        moreButton?.addEventListener('click', () => {
            const kanban = getKanban();
            const warrantyOriginal = findButtonByClick(kanban, "openNewTicketModal('warranty')");
            const originalToggle = findButtonByClick(kanban, 'newTicketMenuOpen = !newTicketMenuOpen');
            if (!warrantyOriginal || !isElementAlpineVisible(originalToggle)) {
                const original = findButtonByClick(kanban, 'openNewTicketModal()');
                if (original) original.click();
                else alpineData()?.openNewTicketModal?.();
                return;
            }
            menu.hidden = !menu.hidden;
        });

        strip.querySelector('[data-action="warranty"]')?.addEventListener('click', () => {
            const original = findButtonByClick(getKanban(), "openNewTicketModal('warranty')");
            if (original) original.click();
            else alpineData()?.openNewTicketModal?.('warranty');
            menu.hidden = true;
        });
    };

    const ensureKanbanHeading = (kanban) => {
        const header = kanban?.firstElementChild;
        const firstRow = header?.firstElementChild;
        const heading = firstRow?.querySelector('h2');
        if (!heading) return;

        heading.classList.add('centralos-mobile-kanban-title');
        const nativeIcon = heading.querySelector(':scope > i');
        nativeIcon?.classList.add('centralos-mobile-kanban-title-icon');

        if (!firstRow.querySelector('.centralos-mobile-kanban-subtitle')) {
            const subtitle = document.createElement('p');
            subtitle.className = 'centralos-mobile-kanban-subtitle centralos-mobile-only';
            subtitle.textContent = 'Acompanhe e gerencie os chamados da sua assistência.';
            heading.insertAdjacentElement('afterend', subtitle);
        }
    };

    const ensureMobileSearchControls = (kanban) => {
        const header = kanban?.firstElementChild;
        const firstRow = header?.firstElementChild;
        if (!firstRow) return;

        const input = firstRow.querySelector('input[x-model="searchQuery"]');
        const searchBox = input?.parentElement;
        const controls = searchBox?.parentElement;
        if (!searchBox || !controls) return;

        searchBox.classList.add('centralos-mobile-search-box');
        controls.classList.add('centralos-mobile-kanban-controls');

        if (!controls.querySelector('.centralos-mobile-filter-toggle')) {
            const toggle = document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'centralos-mobile-filter-toggle centralos-mobile-only';
            toggle.setAttribute('aria-label', 'Mais filtros');
            toggle.setAttribute('aria-expanded', 'false');
            toggle.innerHTML = '<i class="fa-solid fa-sliders"></i>';
            toggle.addEventListener('click', () => {
                const open = kanban.classList.toggle('centralos-mobile-filters-open');
                toggle.setAttribute('aria-expanded', String(open));
            });
            searchBox.insertAdjacentElement('afterend', toggle);
        }

        const newTicketButton = findButtonByClick(controls, 'openNewTicketModal()');
        newTicketButton?.closest('.relative.flex')?.classList.add('centralos-mobile-native-new-ticket');

        findButtonByClick(controls, 'showFinalized = !showFinalized')?.classList.add('centralos-mobile-extra-filter-control');
        [...controls.querySelectorAll('button')].find((button) =>
            (button.getAttribute('@click') || '').includes('clearFilters()')
        )?.classList.add('centralos-mobile-extra-filter-control');
    };

    const decorateOperationalFilters = (kanban) => {
        const header = kanban?.firstElementChild;
        const firstRow = header?.firstElementChild;
        const operational = firstRow?.nextElementSibling;
        if (!operational) return;

        operational.classList.add('centralos-mobile-operational-filter');
        const row = operational.firstElementChild;
        row?.classList.add('centralos-mobile-window-row');
        operational.lastElementChild?.classList.add('centralos-mobile-basis-row');
    };

    const decorateCalendar = (kanban) => {
        const calendarTitle = [...(kanban?.querySelectorAll('h3') || [])].find((el) =>
            normalize(el.textContent).includes('cronograma de entregas')
        );
        if (!calendarTitle) return;

        const card = calendarTitle.closest('.bg-white');
        const wrapper = card?.parentElement;
        card?.classList.add('centralos-mobile-calendar-card');
        wrapper?.classList.add('centralos-mobile-calendar-wrap');
        calendarTitle.classList.add('centralos-mobile-calendar-title');

        const button = card?.querySelector('button');
        if (button) {
            button.classList.add('centralos-mobile-calendar-link');
            if (!button.dataset.centralosMobileLabel) {
                button.dataset.centralosMobileLabel = 'true';
                const icon = button.querySelector('i');
                button.childNodes.forEach((node) => {
                    if (node.nodeType === Node.TEXT_NODE) node.textContent = '';
                });
                const label = document.createElement('span');
                label.className = 'centralos-mobile-calendar-label';
                label.textContent = 'Ver calendário';
                button.prepend(label);
                if (icon) {
                    icon.className = 'fa-solid fa-chevron-right';
                    icon.classList.add('centralos-mobile-calendar-chevron');
                }
            }
        }

        card?.querySelectorAll('.grid.grid-cols-7 > div').forEach((day) => {
            day.classList.add('centralos-mobile-calendar-day');
            const weekday = day.querySelector('.text-center span:first-child');
            if (weekday && mq.matches) {
                const cleaned = weekday.textContent.replace('.', '').trim();
                if (weekday.textContent !== cleaned) weekday.textContent = cleaned;
            }
        });
    };

    const toneForStatus = (label) => {
        const text = normalize(label);
        if (text.includes('terceir')) return 'outsourced';
        if (text.includes('analise')) return 'analysis';
        if (text.includes('aprov')) return 'approval';
        if (text.includes('liberado') || text.includes('retirada') || text.includes('exped')) return 'released';
        if (text.includes('compra')) return 'purchase';
        if (text.includes('reparo')) return 'repair';
        if (text.includes('teste')) return 'test';
        if (text.includes('finalizado')) return 'finished';
        return 'open';
    };

    const textAfterLabel = (row, label) => {
        if (!row) return '';
        const full = row.textContent.replace(/\s+/g, ' ').trim();
        return full.replace(new RegExp(`^${label}\\s*`, 'i'), '').trim();
    };

    const decorateTicketCard = (card) => {
        if (!card) return;
        card.classList.add('centralos-mobile-ticket-card');

        const direct = [...card.children];
        const top = direct.find((el) => el.matches('div.flex.justify-between.items-start'));
        const device = direct.find((el) => el.tagName === 'H4');
        const client = direct.find((el) => el.tagName === 'P');
        const meta = direct.find((el) => el.matches('div.mt-3.pt-2'));
        const actions = direct.find((el) => el.matches('div.mt-3.pt-3'));

        [top, device, client, meta].filter(Boolean).forEach((el) => el.classList.add('centralos-mobile-native-meta'));
        actions?.classList.add('centralos-mobile-actions');

        let summary = direct.find((el) => el.classList?.contains('centralos-mobile-card-summary'));
        if (!summary) {
            summary = document.createElement('div');
            summary.className = 'centralos-mobile-card-summary centralos-mobile-only';
            actions ? card.insertBefore(summary, actions) : card.appendChild(summary);
        }

        const prioritySource = top?.querySelector('span.text-xs.font-bold');
        const osSource = [...(top?.querySelectorAll('span') || [])].find((el) => normalize(el.textContent).startsWith('os:'));
        const deadlineLabel = [...(meta?.querySelectorAll('span') || [])].find((el) => normalize(el.textContent).startsWith('prazo de entrega'));
        const deadlineRow = deadlineLabel?.parentElement;
        const deadlineValue = deadlineRow?.querySelector('div')?.textContent?.replace(/\s+/g, ' ').trim() || 'S/ Prazo';
        const techRow = [...(meta?.querySelectorAll('div') || [])].find((el) => normalize(el.textContent).startsWith('tecnico:'));
        const techValue = textAfterLabel(techRow, 'Técnico:') || 'Todos';

        const priorityText = prioritySource?.textContent?.trim() || '';
        const osText = osSource?.textContent?.trim() || '';
        const deviceText = device?.textContent?.trim() || 'Aparelho';
        const clientText = client?.textContent?.trim() || '—';
        const signature = [priorityText, osText, deviceText, clientText, deadlineValue, techValue].join('|');
        if (summary.dataset.centralosMobileSignature === signature) return;
        summary.dataset.centralosMobileSignature = signature;

        summary.innerHTML = '';
        const left = document.createElement('div');
        left.className = 'centralos-mobile-card-left';
        const badges = document.createElement('div');
        badges.className = 'centralos-mobile-card-badges';
        if (prioritySource) {
            const priority = prioritySource.cloneNode(true);
            priority.removeAttribute(':class');
            priority.classList.add('centralos-mobile-priority-badge');
            badges.appendChild(priority);
        }
        const os = document.createElement('span');
        os.className = 'centralos-mobile-os';
        os.textContent = osText;
        badges.appendChild(os);
        left.appendChild(badges);

        const deviceEl = document.createElement('strong');
        deviceEl.className = 'centralos-mobile-device';
        deviceEl.textContent = deviceText;
        left.appendChild(deviceEl);

        const clientEl = document.createElement('span');
        clientEl.className = 'centralos-mobile-client';
        clientEl.textContent = `Cliente: ${clientText}`;
        left.appendChild(clientEl);

        const right = document.createElement('div');
        right.className = 'centralos-mobile-card-right';
        const deadline = document.createElement('span');
        deadline.className = 'centralos-mobile-deadline';
        deadline.innerHTML = '<i class="fa-regular fa-calendar-days"></i><span>Prazo de entrega:</span>';
        const deadlineStrong = document.createElement('strong');
        deadlineStrong.textContent = deadlineValue;
        deadline.appendChild(deadlineStrong);
        right.appendChild(deadline);

        const tech = document.createElement('span');
        tech.className = 'centralos-mobile-technician';
        tech.innerHTML = '<span>Técnico:</span>';
        const techStrong = document.createElement('strong');
        techStrong.textContent = techValue;
        tech.appendChild(techStrong);
        right.appendChild(tech);

        summary.append(left, right);
    };

    const decorateColumns = (kanban) => {
        const content = kanban?.querySelector('#kanban-content');
        if (!content) return;
        content.classList.add('centralos-mobile-columns');

        const columns = [...content.children].filter((el) => (el.getAttribute('x-data') || '').includes('initColumnFilter'));
        let hasExpanded = columns.some((col) => col.classList.contains('centralos-mobile-expanded'));

        columns.forEach((column, index) => {
            column.classList.add('centralos-mobile-column');
            const header = column.firstElementChild;
            const cardsArea = header?.nextElementSibling;
            if (!header || !cardsArea) return;

            header.classList.add('centralos-mobile-column-header');
            cardsArea.classList.add('centralos-mobile-column-cards');

            const label = header.querySelector('h3');
            const labelText = label?.textContent || '';
            column.dataset.centralosMobileTone = toneForStatus(labelText);

            const nativeCount = header.querySelector('span.bg-white');
            if (nativeCount) {
                nativeCount.classList.add('centralos-mobile-native-count');
                let count = header.querySelector(':scope > .centralos-mobile-count');
                if (!count) {
                    count = document.createElement('span');
                    count.className = 'centralos-mobile-count centralos-mobile-only';
                    header.prepend(count);
                }
                const countText = nativeCount.textContent.trim();
                if (count.textContent !== countText) count.textContent = countText;
            }

            if (!header.querySelector('.centralos-mobile-column-chevron')) {
                const chevron = document.createElement('span');
                chevron.className = 'centralos-mobile-column-chevron centralos-mobile-only';
                chevron.innerHTML = '<i class="fa-solid fa-chevron-down"></i>';
                header.appendChild(chevron);
            }

            if (!header.dataset.centralosMobileToggle) {
                header.addEventListener('click', (event) => {
                    if (!mq.matches) return;
                    if (event.target.closest('button, input, select, option')) return;
                    const willOpen = !column.classList.contains('centralos-mobile-expanded');
                    column.classList.toggle('centralos-mobile-expanded', willOpen);
                });
                header.dataset.centralosMobileToggle = 'true';
            }

            if (!hasExpanded && (normalize(labelText).includes('aberto') || index === 0)) {
                column.classList.add('centralos-mobile-expanded');
                hasExpanded = true;
            }

            cardsArea.querySelectorAll(':scope > div[id^="ticket-card-"]').forEach(decorateTicketCard);
        });

        kanban.querySelector('[x-ref="kanbanTop"]')?.classList.add('centralos-mobile-top-scrollbar');
        kanban.querySelector('[x-ref="kanbanBottom"]')?.classList.add('centralos-mobile-kanban-scroll');
    };

    const ensureBottomNav = () => {
        if (document.querySelector('.centralos-mobile-bottom-nav')) return;
        const nav = document.createElement('nav');
        nav.className = 'centralos-mobile-bottom-nav centralos-mobile-only';
        nav.setAttribute('aria-label', 'Navegação principal mobile');
        nav.innerHTML = `
            <button type="button" data-view="dashboard"><i class="fa-solid fa-house"></i><span>Início</span></button>
            <button type="button" data-view="kanban"><i class="fa-regular fa-rectangle-list"></i><span>Chamados</span></button>
            <button type="button" data-view="customers"><i class="fa-solid fa-users"></i><span>Clientes</span></button>
            <button type="button" data-view="more"><i class="fa-solid fa-table-cells-large"></i><span>Mais</span></button>
        `;
        document.body.appendChild(nav);

        nav.querySelectorAll('button[data-view]').forEach((button) => {
            button.addEventListener('click', () => {
                const view = button.dataset.view;
                if (view === 'more') {
                    openMoreSheet();
                    return;
                }
                const sidebar = getSidebar();
                const labelMap = { dashboard: 'inicio', kanban: 'chamados', customers: 'clientes' };
                const original = [...(sidebar?.querySelectorAll('a') || [])].find((anchor) =>
                    normalize(anchor.textContent) === labelMap[view]
                );
                if (original) original.click();
                else if (alpineData()) alpineData().view = view;
                window.setTimeout(syncMobileVisibility, 0);
            });
        });
    };

    const ensureMoreSheet = () => {
        if (document.querySelector('.centralos-mobile-more-sheet')) return;
        const sheet = document.createElement('div');
        sheet.className = 'centralos-mobile-more-sheet centralos-mobile-only';
        sheet.hidden = true;
        sheet.innerHTML = `
            <button type="button" class="centralos-mobile-more-backdrop" aria-label="Fechar menu"></button>
            <section class="centralos-mobile-more-panel" role="dialog" aria-modal="true" aria-label="Mais opções">
                <div class="centralos-mobile-more-handle"></div>
                <div class="centralos-mobile-more-heading"><strong>Mais</strong><button type="button" aria-label="Fechar"><i class="fa-solid fa-xmark"></i></button></div>
                <div class="centralos-mobile-more-items"></div>
            </section>
        `;
        document.body.appendChild(sheet);
        sheet.querySelector('.centralos-mobile-more-backdrop')?.addEventListener('click', closeMoreSheet);
        sheet.querySelector('.centralos-mobile-more-heading button')?.addEventListener('click', closeMoreSheet);
    };

    const buildMoreSheetItems = () => {
        ensureMoreSheet();
        const container = document.querySelector('.centralos-mobile-more-items');
        if (!container) return;
        container.innerHTML = '';

        const excluded = new Set(['inicio', 'chamados', 'clientes']);
        [...(getSidebar()?.querySelectorAll('a') || [])].forEach((anchor) => {
            const label = anchor.querySelector('span')?.textContent?.trim() || anchor.textContent.trim();
            if (!label || excluded.has(normalize(label)) || anchor.style.display === 'none') return;
            const iconClass = anchor.querySelector('i')?.className || 'fa-solid fa-circle';
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'centralos-mobile-more-item';
            button.innerHTML = `<i class="${iconClass}"></i><span></span><i class="fa-solid fa-chevron-right centralos-mobile-more-arrow"></i>`;
            button.querySelector('span').textContent = label;
            button.addEventListener('click', () => {
                closeMoreSheet();
                anchor.click();
                window.setTimeout(syncMobileVisibility, 0);
            });
            container.appendChild(button);
        });

        const nav = getSessionNav();
        const notes = [...(nav?.querySelectorAll('button') || [])].find((btn) => normalize(btn.title).includes('notas'));
        const logout = [...(nav?.querySelectorAll('button') || [])].find((btn) => normalize(btn.title) === 'sair');

        if (notes) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'centralos-mobile-more-item';
            button.innerHTML = '<i class="fa-solid fa-note-sticky"></i><span>Notas Gerais</span><i class="fa-solid fa-chevron-right centralos-mobile-more-arrow"></i>';
            button.addEventListener('click', () => { closeMoreSheet(); notes.click(); });
            container.appendChild(button);
        }
        if (logout) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'centralos-mobile-more-item centralos-mobile-more-item-danger';
            button.innerHTML = '<i class="fa-solid fa-power-off"></i><span>Sair</span><i class="fa-solid fa-chevron-right centralos-mobile-more-arrow"></i>';
            button.addEventListener('click', () => { closeMoreSheet(); logout.click(); });
            container.appendChild(button);
        }
    };

    function openMoreSheet() {
        if (!mq.matches) return;
        buildMoreSheetItems();
        const sheet = document.querySelector('.centralos-mobile-more-sheet');
        if (!sheet) return;
        sheet.hidden = false;
        document.body.classList.add('centralos-mobile-sheet-open');
    }

    function closeMoreSheet() {
        const sheet = document.querySelector('.centralos-mobile-more-sheet');
        if (!sheet) return;
        sheet.hidden = true;
        document.body.classList.remove('centralos-mobile-sheet-open');
    }

    const syncBottomNav = () => {
        const nav = document.querySelector('.centralos-mobile-bottom-nav');
        if (!nav) return;
        const view = currentView();
        nav.querySelectorAll('button[data-view]').forEach((button) => {
            const active = button.dataset.view === view;
            button.classList.toggle('is-active', active);
            button.setAttribute('aria-current', active ? 'page' : 'false');
        });
    };

    const decorate = () => {
        document.body?.classList.add('centralos-mobile-ready');
        ensureTopAccountChevron();
        ensureActionStrip();
        ensureBottomNav();
        ensureMoreSheet();

        const kanban = getKanban();
        if (kanban) {
            kanban.classList.add('centralos-mobile-kanban');
            ensureKanbanHeading(kanban);
            ensureMobileSearchControls(kanban);
            decorateOperationalFilters(kanban);
            decorateCalendar(kanban);
            decorateColumns(kanban);
        }
        syncMobileVisibility();
    };

    let scheduled = false;
    const schedule = () => {
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
        window.setTimeout(decorate, 1800);

        new MutationObserver(schedule).observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
        });

        mq.addEventListener?.('change', () => {
            closeMoreSheet();
            schedule();
        });
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') closeMoreSheet();
        });
        window.setInterval(syncMobileVisibility, 800);
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
