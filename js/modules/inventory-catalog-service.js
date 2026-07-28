(function () {
    function normalizeNumber(value, fallback = 0) {
        const parsed = Number(String(value ?? '').replace(',', '.'));
        return Number.isFinite(parsed) ? parsed : fallback;
    }

    function itemPayload(form = {}) {
        return {
            id: form.id || null,
            name: String(form.name || '').trim(),
            sku: String(form.sku || '').trim() || null,
            universal_code: String(form.universal_code || '').trim() || null,
            category: String(form.category || '').trim() || null,
            brand: String(form.brand || '').trim() || null,
            description: String(form.description || '').trim() || null,
            internal_notes: String(form.internal_notes || '').trim() || null,
            image_url: String(form.image_url || '').trim() || null,
            active: form.active !== false,
            unit_code: form.unit_code || 'un',
            custom_unit_name: String(form.custom_unit_name || '').trim() || null,
            allow_decimal: Boolean(form.allow_decimal),
            track_stock: form.track_stock !== false,
            minimum_quantity: normalizeNumber(form.minimum_quantity),
            ideal_quantity: normalizeNumber(form.ideal_quantity),
            default_location_id: form.default_location_id || null
        };
    }

    window.AIDAInventoryCatalogService = {
        emptyItem() {
            return {
                id: null,
                name: '',
                sku: '',
                universal_code: '',
                category: '',
                brand: '',
                description: '',
                internal_notes: '',
                image_url: '',
                active: true,
                model_ids: [],
                suppliers: [],
                relations: [],
                unit_code: 'un',
                custom_unit_name: '',
                allow_decimal: false,
                track_stock: true,
                minimum_quantity: 0,
                ideal_quantity: 0,
                default_location_id: '',
                location_ids: [],
                pending_image_file: null,
                image_preview: ''
            };
        },

        emptyLocation() {
            return {
                id: null,
                name: '',
                normalized_address: '',
                scheme_id: null,
                address_components: {}
            };
        },

        validateItem(form) {
            if (String(form?.name || '').trim().length < 2) {
                return 'Informe um nome com pelo menos 2 caracteres.';
            }
            if (form?.unit_code === 'custom'
                && !String(form?.custom_unit_name || '').trim()) {
                return 'Informe o nome da unidade personalizada.';
            }
            const minimum = normalizeNumber(form?.minimum_quantity, -1);
            const ideal = normalizeNumber(form?.ideal_quantity, -1);
            if (minimum < 0 || ideal < 0) {
                return 'Os limites de estoque não podem ser negativos.';
            }
            if (!form?.allow_decimal
                && (!Number.isInteger(minimum) || !Number.isInteger(ideal))) {
                return 'Esta unidade aceita apenas quantidades inteiras.';
            }
            return null;
        },

        async saveItem(deps, form) {
            const error = this.validateItem(form);
            if (error) throw new Error(error);
            const itemId = await deps.supabaseFetch('rpc/save_inventory_item', 'POST', { p_item: itemPayload(form) });
            await deps.supabaseFetch('rpc/set_inventory_item_locations', 'POST', { p_item_id: itemId, p_location_ids: Array.isArray(form.location_ids) ? form.location_ids : [], p_default_location_id: form.default_location_id || null });
            return itemId;
        },

        async saveLocationScheme(deps, form) {
            if (String(form?.name || '').trim().length < 2) throw new Error('Informe o nome do padrão.');
            const components = Array.isArray(form?.component_labels) ? form.component_labels : [];
            if (form.mode === 'structured' && !components.length) throw new Error('Adicione ao menos uma parte ao padrão.');
            return await deps.supabaseFetch('rpc/save_inventory_location_scheme', 'POST', {
                p_scheme: {
                    id: form.id || null,
                    name: String(form.name).trim(),
                    mode: form.mode || 'free',
                    component_labels: components.map(component => ({
                        type: component.type,
                        label: String(component.label || '').trim(),
                        value: String(component.value || ''),
                        options: Array.isArray(component.options)
                            ? component.options
                            : String(component.options_text || '').split(',').map(value => value.trim()).filter(Boolean)
                    }))
                }
            });
        },
        async saveLocation(deps, form) {
            const name = String(form?.name || '').trim();
            const address = String(form?.normalized_address || name).trim();
            if (name.length < 2 || address.length < 2) {
                throw new Error('Informe um nome e um endereço válidos.');
            }
            return await deps.supabaseFetch('rpc/save_inventory_location', 'POST', {
                p_location: {
                    id: form.id || null,
                    name,
                    normalized_address: address,
                    scheme_id: form.scheme_id || null,
                    address_components: form.address_components || {}
                }
            });
        },

        async registerEntry(deps, form) {
            const quantity = normalizeNumber(form?.quantity, -1);
            const unitCost = String(form?.unit_cost ?? '').trim() === '' ? null : normalizeNumber(form.unit_cost, -1);
            if (!form?.item_id || !form?.location_id) throw new Error('Selecione o item e a localização.');
            if (quantity <= 0 || (unitCost != null && unitCost < 0)) throw new Error('Informe quantidade e custo válidos.');
            if (String(form?.reason || '').trim().length < 5) throw new Error('Explique o motivo da entrada.');
            return await deps.supabaseFetch('rpc/register_inventory_entry', 'POST', {
                p_item_id: form.item_id,
                p_location_id: form.location_id,
                p_quantity: quantity,
                p_unit_cost: unitCost,
                p_reason: String(form.reason).trim()
            });
        },
        async adjustStock(deps, form) {
            const quantity = normalizeNumber(form?.physical_quantity, -1);
            if (!form?.item_id || !form?.location_id) {
                throw new Error('Selecione o item e a localização.');
            }
            if (quantity < 0) throw new Error('O saldo não pode ser negativo.');
            if (String(form?.reason || '').trim().length < 5) {
                throw new Error('Explique o motivo do ajuste.');
            }
            return await deps.supabaseFetch('rpc/adjust_inventory_stock', 'POST', {
                p_item_id: form.item_id,
                p_location_id: form.location_id,
                p_new_physical_quantity: quantity,
                p_reason: String(form.reason).trim()
            });
        }
    };
})();
