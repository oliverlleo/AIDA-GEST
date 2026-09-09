// Shared presentation tokens. Business rules and customer-selected tracker colors
// remain in their existing modules. Keep this after the Tailwind CDN script.
tailwind.config = {
    theme: {
        extend: {
            colors: {
                brand: {
                    50: '#fff4e8', 100: '#ffe7cc', 200: '#ffd09a',
                    300: '#ffad5c', 400: '#ff8b2c', 500: '#FF6B00',
                    600: '#E65100', 700: '#b84000', 800: '#923500', 900: '#1a1a1a'
                }
            },
            fontFamily: {
                sans: ['-apple-system', 'BlinkMacSystemFont', 'Inter', 'Segoe UI', 'sans-serif']
            }
        }
    }
};
