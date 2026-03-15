const fs = require('fs');
const file = 'js/modules/workspace-config-service.js';
let content = fs.readFileSync(file, 'utf8');

content = content.replace(
    /await deps\.supabaseFetch\(`workspaces\?id=eq\.\$\{deps\.state\.user\.workspace_id\}`,\s*'PATCH',\s*\{\s*whatsapp_number:\s*deps\.state\.whatsappNumber\s*\}\);/g,
    "await deps.supabaseFetch('rpc/update_workspace_company_config', 'POST', { p_whatsapp_number: deps.state.whatsappNumber });"
);

content = content.replace(
    /const res = await deps\.supabaseFetch\(`workspaces\?id=eq\.\$\{deps\.state\.user\.workspace_id\}`,\s*'PATCH',\s*\{\s*tracker_config:\s*deps\.state\.trackerConfig\s*\}\);/g,
    "const res = await deps.supabaseFetch('rpc/update_workspace_tracker_config', 'POST', { p_config: deps.state.trackerConfig });"
);

// We should remove the Array length check because RPC returns null/void normally on success,
// and throws on error, whereas the PATCH returned the rows updated.
content = content.replace(
    /\/\/ Check if update actually happened\s*if \(Array\.isArray\(res\) && res\.length === 0\) \{\s*throw new Error\("Permissão negada ou workspace não encontrado\."\);\s*\}/g,
    "// Check if update actually happened\n            // Since it's an RPC, it throws if not found/unauthorized, so success implies it worked"
);

fs.writeFileSync(file, content);
