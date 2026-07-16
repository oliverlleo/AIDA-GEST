// Arquivo de configuração e helpers
// Parte da infraestrutura de módulos

window.AIDAConfigHelpers = {
    isLogisticsEnabled(trackerConfig) {
        return !!trackerConfig?.enable_logistics;
    },

    isOutsourcedEnabled(trackerConfig) {
        return !!trackerConfig?.enable_outsourced;
    },

    getTestFlowMode(trackerConfig) {
        return trackerConfig?.test_flow || 'kanban';
    },

    isAutoOSGenerationEnabled(trackerConfig) {
        return !!trackerConfig?.os_generation?.enabled;
    },

    isWhatsAppDisabled(trackerConfig) {
        return !!trackerConfig?.disable_whatsapp_actions;
    },

    isRequiredFieldsEnabled(trackerConfig) {
        return !!trackerConfig?.enable_required_ticket_fields || !!trackerConfig?.ticket_field_modes;
    },

    isFieldRequired(trackerConfig, key) {
        if (window.AIDAFeatureConfig) {
            return window.AIDAFeatureConfig.isFieldRequired(trackerConfig, key);
        }
        if (!this.isRequiredFieldsEnabled(trackerConfig)) {
            // Default legacy requirements (Updated to include Deadlines)
            const defaults = ['client_name', 'os_number', 'device_model', 'defect_reported', 'responsible', 'analysis_deadline', 'deadline'];
            return defaults.includes(key);
        }
        return !!trackerConfig?.required_ticket_fields?.[key];
    },

    isFieldVisible(trackerConfig, key) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isFieldVisible(trackerConfig, key)
            : true;
    },

    isPartsControlEnabled(trackerConfig) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isWorkflowEnabled(trackerConfig, 'parts_control')
            : true;
    },

    isFinalTestEnabled(trackerConfig) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isWorkflowEnabled(trackerConfig, 'final_test')
            : true;
    },

    isTimerEnabled(trackerConfig, type) {
        const key = type === 'analysis' ? 'analysis_timer' : 'repair_timer';
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isWorkflowEnabled(trackerConfig, key)
            : true;
    },

    getDeliveryMode(trackerConfig) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.getDeliveryMode(trackerConfig)
            : 'complete';
    },

    isPriorityRequestEnabled(trackerConfig) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isWorkflowEnabled(trackerConfig, 'priority_requests')
            : true;
    },

    isModuleEnabled(trackerConfig, key) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isModuleEnabled(trackerConfig, key)
            : true;
    },

    isOverviewSectionEnabled(trackerConfig, key) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isOverviewSectionEnabled(trackerConfig, key)
            : true;
    },

    isAppointmentTypeEnabled(trackerConfig, type) {
        return window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isAppointmentTypeEnabled(trackerConfig, type)
            : true;
    }
};

