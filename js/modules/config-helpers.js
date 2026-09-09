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

    isInventoryEnabled(trackerConfig) {
        return this.isPartsControlEnabled(trackerConfig)
            && this.isModuleEnabled(trackerConfig, 'inventory');
    },

    isWarrantyEnabled(trackerConfig) {
        const customersEnabled = this.isModuleEnabled(trackerConfig, 'customers');
        return customersEnabled && (window.AIDAFeatureConfig
            ? window.AIDAFeatureConfig.isWorkflowEnabled(trackerConfig, 'warranty_control')
            : true);
    },

    getWarrantyDays(trackerConfig) {
        const days = Number(window.AIDAFeatureConfig?.normalize(trackerConfig)?.workflow?.warranty_days);
        return Number.isInteger(days) ? Math.max(1, Math.min(730, days)) : 90;
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

// Centralos visual brand layer — isolada da lógica de negócio e dos fluxos do sistema.
(() => {
    const applyCentralosBrandLayer = () => {
        if (!document.querySelector('link[data-centralos-brand]')) {
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = 'centralos-brand.css?v=1';
            link.dataset.centralosBrand = 'true';
            document.head.appendChild(link);
        }

        if (!document.querySelector('link[data-centralos-brand-complete]')) {
            const completeLink = document.createElement('link');
            completeLink.rel = 'stylesheet';
            completeLink.href = 'centralos-brand-complete.css?v=2';
            completeLink.dataset.centralosBrandComplete = 'true';
            document.head.appendChild(completeLink);
        }

        if (!document.querySelector('link[data-centralos-brand-operational]')) {
            const operationalLink = document.createElement('link');
            operationalLink.rel = 'stylesheet';
            operationalLink.href = 'centralos-brand-operational.css?v=1';
            operationalLink.dataset.centralosBrandOperational = 'true';
            document.head.appendChild(operationalLink);
        }

        if (!document.querySelector('link[data-centralos-mobile-login-contrast]')) {
            const mobileLoginContrast = document.createElement('link');
            mobileLoginContrast.rel = 'stylesheet';
            mobileLoginContrast.href = 'centralos-mobile-login-contrast.css?v=1';
            mobileLoginContrast.dataset.centralosMobileLoginContrast = 'true';
            document.head.appendChild(mobileLoginContrast);
        }

        if (!document.querySelector('script[data-centralos-brand-complete]')) {
            const completeScript = document.createElement('script');
            completeScript.src = 'centralos-brand-complete.js?v=2';
            completeScript.dataset.centralosBrandComplete = 'true';
            document.head.appendChild(completeScript);
        }

        if (!document.querySelector('script[data-centralos-brand-operational]')) {
            const operationalScript = document.createElement('script');
            operationalScript.src = 'centralos-brand-operational.js?v=1';
            operationalScript.dataset.centralosBrandOperational = 'true';
            document.head.appendChild(operationalScript);
        }

        // Camada mobile isolada: só atua até 767px e reaproveita as ações existentes.
        if (!document.querySelector('link[data-centralos-mobile-kanban]')) {
            const mobileLink = document.createElement('link');
            mobileLink.rel = 'stylesheet';
            mobileLink.href = 'centralos-mobile-kanban.css?v=1';
            mobileLink.dataset.centralosMobileKanban = 'true';
            document.head.appendChild(mobileLink);
        }

        if (!document.querySelector('script[data-centralos-mobile-kanban]')) {
            const mobileScript = document.createElement('script');
            mobileScript.src = 'centralos-mobile-kanban.js?v=1';
            mobileScript.dataset.centralosMobileKanban = 'true';
            document.head.appendChild(mobileScript);
        }

        // Wordmark vetorial aplicado apenas à imagem visual do topo.
        // O arquivo logo.png original permanece intacto no repositório.
        const navLogo = document.querySelector('nav img[alt="CentralOS"]');
        if (navLogo && !navLogo.dataset.centralosBrandLogo) {
            const svg = `
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 112">
                    <g transform="translate(4 9)">
                        <path fill="#f7f7f7" d="M82 1C41 1 10 22 10 48s31 47 72 47h24V73H82c-25 0-43-10-43-25 0-14 18-25 43-25h24V1H82z"/>
                        <rect x="67" y="24" width="56" height="14" rx="7" fill="#ff6500"/>
                        <rect x="55" y="43" width="68" height="14" rx="7" fill="#ff6500"/>
                        <rect x="67" y="62" width="56" height="14" rx="7" fill="#ff6500"/>
                    </g>
                    <text x="142" y="69" fill="#f7f7f7" font-family="Inter,Arial,sans-serif" font-size="58" font-weight="800" letter-spacing="-2.5">Central</text>
                    <text x="380" y="69" fill="#ff6500" font-family="Inter,Arial,sans-serif" font-size="58" font-weight="800" letter-spacing="-2.5">os</text>
                    <text x="146" y="91" fill="#bfc3ca" font-family="Inter,Arial,sans-serif" font-size="9" font-weight="600" letter-spacing="4.1">SUA ASSISTÊNCIA TÉCNICA EM ORDEM</text>
                </svg>`;
            navLogo.src = `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`;
            navLogo.dataset.centralosBrandLogo = 'true';
        }
    };

    if (document.head) {
        applyCentralosBrandLayer();
    } else {
        document.addEventListener('DOMContentLoaded', applyCentralosBrandLayer, { once: true });
    }
})();
