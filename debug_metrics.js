
const metrics = {
    getDefectList(defectReported) {
        if (!defectReported) return [];
        if (Array.isArray(defectReported)) {
            return defectReported.map(defect => defect.trim()).filter(Boolean);
        }
        return String(defectReported)
            .split(',')
            .map(defect => defect.trim())
            .filter(Boolean);
    },
    getTopItems(items, limit = 4) {
        return Object.entries(items)
            .sort((a, b) => b[1].total - a[1].total)
            .slice(0, limit)
            .map(([label, stats]) => ({ label, ...stats }));
    },
    run() {
        const filteredTickets = [
            { defect_reported: 'Tela, Bateria', repair_successful: true, device_model: 'iPhone 11' },
            { defect_reported: 'Tela', repair_successful: false, device_model: 'iPhone 11' },
            { defect_reported: 'Conector', repair_successful: null, device_model: 'Samsung' }
        ];

        const defectsMap = {};

        filteredTickets.forEach(ticket => {
            const defects = this.getDefectList(ticket.defect_reported);
            defects.forEach(defect => {
                if (!defectsMap[defect]) defectsMap[defect] = { total: 0, success: 0, fail: 0 };
                defectsMap[defect].total++;
                if (ticket.repair_successful === true) defectsMap[defect].success++;
                if (ticket.repair_successful === false) defectsMap[defect].fail++;
            });
        });

        const enhanceStats = (list) => list.map(item => ({
            ...item,
            successRate: item.total ? Math.round((item.success / item.total) * 100) : 0,
            failRate: item.total ? Math.round((item.fail / item.total) * 100) : 0
        }));

        const topDefects = enhanceStats(this.getTopItems(defectsMap, 50));
        console.log("Top Defects:", JSON.stringify(topDefects, null, 2));
    }
};

metrics.run();
