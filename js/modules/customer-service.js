// Customer registry service.
// Keeps customer and customer-ticket queries bounded and isolated from the
// global ticket board state.

(function () {
    const PAGE_SIZE = 20;
    const LOOKUP_LIMIT = 8;

    function emptyForm() {
        return {
            id: null,
            name: '',
            person_type: 'person',
            document_number: '',
            phone: '',
            whatsapp: '',
            email: '',
            birth_date: '',
            postal_code: '',
            address_line: '',
            address_number: '',
            address_complement: '',
            neighborhood: '',
            city: '',
            state: '',
            notes: ''
        };
    }

    function normalizeForm(customer = {}) {
        const form = emptyForm();
        Object.keys(form).forEach((key) => {
            if (key === 'person_type') {
                form[key] = customer[key] === 'company' ? 'company' : 'person';
            } else if (key === 'id') {
                form[key] = customer[key] || null;
            } else {
                form[key] = customer[key] == null ? '' : String(customer[key]);
            }
        });
        return form;
    }

    function mergeUnique(current, incoming) {
        const known = new Set(current.map(item => item.id));
        return [...current, ...incoming.filter(item => !known.has(item.id))];
    }

    window.AIDACustomerService = {
        PAGE_SIZE,
        LOOKUP_LIMIT,
        emptyForm,
        normalizeForm,

        async fetchCustomerPage(deps, { reset = false } = {}) {
            const { state, supabaseFetch } = deps;
            const management = state.customerManagement;
            if ((management.loading && !reset) || (!reset && !management.hasMore)) return;

            const requestId = ++management.requestId;
            management.loading = true;
            if (reset) {
                management.items = [];
                management.nextCursor = null;
                management.hasMore = true;
            }

            try {
                const response = await supabaseFetch('rpc/get_customer_page', 'POST', {
                    p_search: String(management.search || '').trim() || null,
                    p_limit: PAGE_SIZE,
                    p_cursor: reset ? null : management.nextCursor,
                    p_include_total: reset
                });
                if (requestId !== management.requestId) return;

                const incoming = Array.isArray(response?.items) ? response.items : [];
                management.items = reset ? incoming : mergeUnique(management.items, incoming);
                if (response?.total !== null && response?.total !== undefined) {
                    management.total = Number(response.total || 0);
                }
                management.hasMore = Boolean(response?.has_more);
                management.nextCursor = response?.next_cursor || null;

                if (management.selected?.id) {
                    const refreshed = management.items.find(item => item.id === management.selected.id);
                    if (refreshed) management.selected = refreshed;
                }
            } finally {
                if (requestId === management.requestId) management.loading = false;
            }
        },

        async fetchCustomerTickets(deps, { reset = false } = {}) {
            const { state, supabaseFetch } = deps;
            const management = state.customerManagement;
            const customerId = management.selected?.id;
            if (!customerId || (management.ticketsLoading && !reset) || (!reset && !management.ticketsHasMore)) return;

            const requestId = ++management.ticketRequestId;
            management.ticketsLoading = true;
            if (reset) {
                management.tickets = [];
                management.ticketsNextCursor = null;
                management.ticketsHasMore = true;
            }

            try {
                const response = await supabaseFetch('rpc/get_customer_ticket_page', 'POST', {
                    p_customer_id: customerId,
                    p_search: String(management.ticketSearch || '').trim() || null,
                    p_limit: PAGE_SIZE,
                    p_cursor: reset ? null : management.ticketsNextCursor,
                    p_include_total: reset
                });
                if (requestId !== management.ticketRequestId || management.selected?.id !== customerId) return;

                const incoming = Array.isArray(response?.items) ? response.items : [];
                management.tickets = reset ? incoming : mergeUnique(management.tickets, incoming);
                if (response?.total !== null && response?.total !== undefined) {
                    management.ticketsTotal = Number(response.total || 0);
                }
                management.ticketsHasMore = Boolean(response?.has_more);
                management.ticketsNextCursor = response?.next_cursor || null;
            } finally {
                if (requestId === management.ticketRequestId) management.ticketsLoading = false;
            }
        },

        async lookupCustomers(deps, query) {
            const { state, supabaseFetch } = deps;
            const lookup = state.customerLookup;
            const normalizedQuery = String(query || '').trim();
            const requestId = ++lookup.requestId;

            if (normalizedQuery.length < 2) {
                lookup.items = [];
                lookup.loading = false;
                lookup.open = false;
                return [];
            }

            lookup.loading = true;
            lookup.open = true;
            try {
                const response = await supabaseFetch('rpc/get_customer_page', 'POST', {
                    p_search: normalizedQuery,
                    p_limit: LOOKUP_LIMIT,
                    p_cursor: null,
                    p_include_total: false
                });
                if (requestId !== lookup.requestId) return [];
                lookup.items = Array.isArray(response?.items) ? response.items : [];
                return lookup.items;
            } finally {
                if (requestId === lookup.requestId) lookup.loading = false;
            }
        },

        async saveCustomer(deps, customerForm) {
            const { supabaseFetch } = deps;
            return await supabaseFetch('rpc/save_customer', 'POST', {
                p_customer: {
                    id: customerForm.id || null,
                    name: String(customerForm.name || '').trim(),
                    person_type: customerForm.person_type === 'company' ? 'company' : 'person',
                    document_number: String(customerForm.document_number || '').trim() || null,
                    phone: String(customerForm.phone || '').trim() || null,
                    whatsapp: String(customerForm.whatsapp || '').trim() || null,
                    email: String(customerForm.email || '').trim() || null,
                    birth_date: customerForm.birth_date || null,
                    postal_code: String(customerForm.postal_code || '').trim() || null,
                    address_line: String(customerForm.address_line || '').trim() || null,
                    address_number: String(customerForm.address_number || '').trim() || null,
                    address_complement: String(customerForm.address_complement || '').trim() || null,
                    neighborhood: String(customerForm.neighborhood || '').trim() || null,
                    city: String(customerForm.city || '').trim() || null,
                    state: String(customerForm.state || '').trim().toUpperCase() || null,
                    notes: String(customerForm.notes || '').trim() || null
                }
            });
        }
    };
})();
