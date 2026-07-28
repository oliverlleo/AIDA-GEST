const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');
const featureConfig = fs.readFileSync(path.join(root, 'js', 'modules', 'feature-config.js'), 'utf8');
const actions = fs.readFileSync(path.join(root, 'js', 'modules', 'ticket-actions.js'), 'utf8');
const warrantyService = fs.readFileSync(path.join(root, 'js', 'modules', 'warranty-service.js'), 'utf8');

test('warranty is on by default and can be disabled in management', () => {
    assert.match(featureConfig, /warranty_control:\s*true/);
    assert.match(featureConfig, /warranty_days:\s*90/);
    assert.match(html, /Controle de garantia/);
    assert.match(html, /trackerConfig\.workflow\.warranty_control/);
    assert.match(html, /trackerConfig\.workflow\.warranty_days/);
    assert.match(main, /isWarrantyEnabled\(\)/);
});

test('new-ticket split action and customer history expose contextual warranty opening', () => {
    assert.match(html, /Retorno em garantia/);
    assert.match(html, /openNewTicketModal\('warranty'\)/);
    assert.match(html, /customerManagement\.warrantyEligibility\[ticket\.id\]\?\.eligible/);
    assert.match(html, /openWarrantyClaim\(ticket\)/);
    assert.match(main, /warranty_origin_ticket_id:\s*null/);
    assert.match(main, /selectWarrantyOrigin\(ticket\)/);
});

test('analysis modal captures coverage, diagnosis, cause, evidence and parts', () => {
    assert.match(html, /Defeito coberto pela garantia/);
    assert.match(html, /analysisForm\.warrantyCovered/);
    assert.match(html, /analysisForm\.warrantyDiagnosis/);
    assert.match(html, /analysisForm\.warrantyCause/);
    assert.match(html, /analysisForm\.warrantyEvidence/);
    assert.match(warrantyService, /DIAGNÓSTICO TÉCNICO/);
    assert.match(warrantyService, /EVIDÊNCIAS DE MAU USO OU CAUSA EXTERNA/);
    assert.match(actions, /rpc\/complete_warranty_analysis/);
});

test('a rejected warranty opens a separate linked normal OS instead of moving the claim to repair', () => {
    assert.match(actions, /ticket\.warranty_claim && ticket\.warranty_status === 'not_covered'/);
    assert.match(actions, /openPaidServiceFromWarranty\(ticket\)/);
    assert.match(main, /ticketForm\.warranty_source_claim_id = claim\.id/);
    assert.match(actions, /rpc\/link_warranty_paid_ticket/);
    assert.match(html, /Cliente aceitou — criar nova OS/);
});

test('warranty metadata is hydrated in bounded batches and full report stays modal-only', () => {
    assert.match(warrantyService, /index \+= 50/);
    assert.match(warrantyService, /get_warranty_ticket_summaries/);
    assert.match(html, /getWarrantyBadge\(ticket\)/);
    assert.match(html, /selectedTicket\.warranty_technical_report/);
});
