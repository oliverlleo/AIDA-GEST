// This hint controls presentation only. Supabase and the backend still validate access.
(() => {
    let storageKey;
    let pending = true;
    try {
        const project = new URL(window.SUPABASE_CONFIG.URL).hostname.split('.')[0];
        storageKey = `sb-${project}-auth-token`;
        pending = false;
        // Check key names only: never read or parse credentials to decide what to paint.
        for (let index = 0; index < localStorage.length; index++) {
            if (localStorage.key(index) === storageKey) { pending = true; break; }
        }
    } catch (_) { pending = true; /* Wait for the actual session check if storage is unavailable. */ }
    if (pending) document.documentElement.setAttribute('data-auth-pending', 'true');
    window.AIDAAuthFirstPaint = Object.freeze({
        storageKey,
        release() { document.documentElement.removeAttribute('data-auth-pending'); }
    });
})();
