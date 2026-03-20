const fs = require('fs');
let content = fs.readFileSync('js/main.js', 'utf8');

// The file currently has:
//        logout() {
//            return await window.AIDAAuthSessionService.logout(this._getAuthDeps());
//        },

content = content.replace(
    /\blogout\(\) \{(\s*return await)/,
    "async logout() {$1"
);

fs.writeFileSync('js/main.js', content, 'utf8');
console.log("Fixed logout() async syntax");
