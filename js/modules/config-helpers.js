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
        return !!trackerConfig?.enable_required_ticket_fields;
    },

    isFieldRequired(trackerConfig, key) {
        if (!this.isRequiredFieldsEnabled(trackerConfig)) {
            // Default legacy requirements (Updated to include Deadlines)
            const defaults = ['client_name', 'os_number', 'device_model', 'defect_reported', 'responsible', 'analysis_deadline', 'deadline'];
            return defaults.includes(key);
        }
        return !!trackerConfig?.required_ticket_fields?.[key];
    }
};
