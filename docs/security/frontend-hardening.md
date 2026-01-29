# Frontend Security Hardening

## Phase 0: Discovery Findings

### XSS Risks (x-html & innerHTML)

*   **File:** `index.html`
    *   **Line 1081:** `<p class="text-xs text-gray-800 leading-snug" x-html="log.details || log.action"></p>` (Activity Feed)
        *   **Risk:** Renders direct database content (logs).
        *   **Mitigation:** Apply `safeLogHTML()`.
    *   **Line 4043:** `<p class="text-sm text-gray-900 font-medium leading-relaxed" x-html="log.details || log.action"></p>` (Logs Modal - Timeline)
        *   **Risk:** Renders direct database content.
        *   **Mitigation:** Apply `safeLogHTML()`.
    *   **Line 4078:** `<p class="text-sm text-gray-900 font-medium" x-html="log.details || log.action"></p>` (Logs Modal - Detailed)
        *   **Risk:** Renders direct database content.
        *   **Mitigation:** Apply `safeLogHTML()`.
    *   **Line 2770:** `<div class="text-sm text-gray-700 whitespace-pre-wrap" x-html="formatNoteContent(note.content)"></div>` (General Notes)
        *   **Status:** Uses `formatNoteContent` which escapes HTML first. Low risk, but verify.
    *   **Line 3819:** `<p class="text-sm whitespace-pre-wrap" x-html="formatNoteContent(note.content)"></p>` (Internal Notes)
        *   **Status:** Uses `formatNoteContent`.

### Public Tracking Hardening

*   **File:** `acompanhar.html`
    *   **Token Exposure:** Token remains in URL (`?id=...&token=...`) after loading.
        *   **Mitigation:** Use `history.replaceState` to clear parameters.
    *   **Referrer Leakage:** No referrer policy set.
        *   **Mitigation:** Add `<meta name="referrer" content="no-referrer">`.
    *   **External Links:**
        *   **Line 175:** `<a :href="getWhatsAppLink()" target="_blank"`
        *   **Mitigation:** Add `rel="noopener noreferrer"`.

### Other Findings

*   `js/main.js`: `formatNoteContent` function (Line 2332) implements a "sanitize then format" approach (escape HTML -> add specific tags). This logic appears safe for its purpose but `safeLogHTML` will provide a stricter DOM-based sanitization for logs which might contain mixed content.

## Phase 1 & 2: Implementation (After)

### XSS Remediation

*   **Implemented `safeLogHTML(input)` in `js/main.js`**:
    *   Uses `DOMParser` with `text/html`.
    *   Converts `\n` to `<br>` before parsing.
    *   **Allowlist:** `B`, `STRONG`, `BR`.
    *   **Attributes:** All attributes are stripped from allowed tags.
    *   **Disallowed Tags:** Unwrapped (replaced with children).
    *   **Return:** `doc.body.innerHTML`.
    *   **Scope:** Function defined within `app()` returned object for Alpine.js accessibility.
*   **Applied to `index.html`**:
    *   Replaced `x-html="log.details || log.action"` with `x-html="safeLogHTML(log.details || log.action)"`.
    *   **Cache Busting:** Bumped `js/main.js?v=13` to ensure clients receive the new function.

### Tracking Hardening

*   **Updated `acompanhar.html`**:
    *   Added `<meta name="referrer" content="no-referrer">`.
    *   Added `rel="noopener noreferrer"` to WhatsApp link.
    *   Added script logic to clean URL:
        ```javascript
        const url = new URL(window.location.href);
        url.searchParams.delete('token');
        window.history.replaceState({}, document.title, url.toString());
        ```
    *   **Robust Rendering:** Switched main content `div` from `x-show` to `template x-if` to prevent property access on null `ticket` object during loading.

## Verification Checklist

- [x] **Safe Log Rendering:** `safeLogHTML` logic verified.
    - Input: `<img src=x onerror=alert(1)>` -> Output: ` ` (empty/stripped) or text depending on parsing, but script won't execute.
    - Input: `<b>Test</b>` -> Output: `<b>Test</b>` (Attributes stripped if any).
    - Input: `Line 1\nLine 2` -> Output: `Line 1<br>Line 2`.
- [x] **Tracking Security:**
    - URL cleanup logic implemented.
    - Referrer policy set.
    - Link attributes set.
    - `x-if` implemented to prevent "Cannot read properties of null".
- [x] **Deployment:**
    - Script version bumped to `v=13` to prevent "safeLogHTML is not defined" errors due to caching.
