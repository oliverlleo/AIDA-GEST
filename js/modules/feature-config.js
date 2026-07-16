// Configuração central de recursos por workspace.
// Mantém defaults retrocompatíveis e separa visibilidade de obrigatoriedade.

(function () {
    const FIELD_MODES = ['disabled', 'optional', 'required'];
    const CORE_REQUIRED_FIELDS = ['client_name', 'os_number', 'device_model'];
    const LEGACY_REQUIRED_FIELDS = [
        'client_name', 'os_number', 'device_model', 'defect_reported',
        'responsible', 'analysis_deadline', 'deadline'
    ];
    const FIELD_KEYS = [
        'client_name', 'contact_info', 'os_number', 'serial_number', 'priority',
        'device_model', 'analysis_deadline', 'deadline', 'device_condition',
        'responsible', 'defect_reported', 'checklist_entry', 'checklist_exit',
        'photos', 'analysis_schedule', 'repair_schedule'
    ];

    const DEFAULT_WORKFLOW = Object.freeze({
        parts_control: true,
        final_test: true,
        analysis_timer: true,
        repair_timer: true,
        delivery_mode: 'complete',
        priority_requests: true
    });

    const DEFAULT_MODULES = Object.freeze({
        agenda: true,
        suppliers: true,
        manager_dashboard: true,
        public_tracker: true
    });

    const DEFAULT_OVERVIEW = Object.freeze({
        awaiting_start: true,
        awaiting_budget: true,
        parts_purchase: true,
        parts_receipt: true,
        tests: true,
        pickup: true,
        overdue: true,
        unscheduled: true,
        priority: true
    });

    function legacyFieldModes(config) {
        const strict = !!config?.enable_required_ticket_fields;
        const required = config?.required_ticket_fields || {};
        return FIELD_KEYS.reduce((result, key) => {
            const isRequired = strict ? !!required[key] : LEGACY_REQUIRED_FIELDS.includes(key);
            result[key] = isRequired ? 'required' : 'optional';
            return result;
        }, {});
    }

    function normalize(config = {}) {
        const legacyModes = legacyFieldModes(config);
        const configuredModes = config.ticket_field_modes || {};
        const ticketFieldModes = {};

        FIELD_KEYS.forEach((key) => {
            const requestedMode = configuredModes[key];
            ticketFieldModes[key] = FIELD_MODES.includes(requestedMode)
                ? requestedMode
                : legacyModes[key];
        });
        CORE_REQUIRED_FIELDS.forEach((key) => { ticketFieldModes[key] = 'required'; });

        const workflow = {
            ...DEFAULT_WORKFLOW,
            ...(config.workflow || {})
        };
        workflow.delivery_mode = workflow.delivery_mode === 'simple' ? 'simple' : 'complete';

        return {
            ...config,
            ticket_field_modes: ticketFieldModes,
            workflow,
            modules: {
                ...DEFAULT_MODULES,
                ...(config.modules || {})
            },
            overview_sections: {
                ...DEFAULT_OVERVIEW,
                ...(config.overview_sections || {})
            }
        };
    }

    function fieldMode(config, key) {
        if (CORE_REQUIRED_FIELDS.includes(key)) return 'required';
        return normalize(config).ticket_field_modes[key] || 'optional';
    }

    function moduleEnabled(config, key) {
        const normalized = normalize(config);
        if (key === 'suppliers' && normalized.workflow.parts_control === false) return false;
        return normalized.modules[key] !== false;
    }

    window.AIDAFeatureConfig = {
        FIELD_MODES,
        CORE_REQUIRED_FIELDS,
        FIELD_KEYS,
        DEFAULT_WORKFLOW,
        DEFAULT_MODULES,
        DEFAULT_OVERVIEW,

        normalize,

        getFieldMode(config, key) {
            if (!moduleEnabled(config, 'agenda') && ['analysis_schedule', 'repair_schedule'].includes(key)) {
                return 'disabled';
            }
            return fieldMode(config, key);
        },

        isFieldVisible(config, key) {
            return this.getFieldMode(config, key) !== 'disabled';
        },

        isFieldRequired(config, key) {
            return this.getFieldMode(config, key) === 'required';
        },

        setFieldMode(config, key, mode) {
            const normalized = normalize(config);
            if (CORE_REQUIRED_FIELDS.includes(key)) mode = 'required';
            normalized.ticket_field_modes[key] = FIELD_MODES.includes(mode) ? mode : 'optional';
            return normalized;
        },

        isWorkflowEnabled(config, key) {
            return normalize(config).workflow[key] !== false;
        },

        getDeliveryMode(config) {
            return normalize(config).workflow.delivery_mode;
        },

        isModuleEnabled(config, key) {
            return moduleEnabled(config, key);
        },

        isOverviewSectionEnabled(config, key) {
            return normalize(config).overview_sections[key] !== false;
        },

        isAppointmentTypeEnabled(config, type) {
            if (!moduleEnabled(config, 'agenda')) return false;
            const key = type === 'repair' ? 'repair_schedule' : 'analysis_schedule';
            return fieldMode(config, key) !== 'disabled';
        }
    };
})();

