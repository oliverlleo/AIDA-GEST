// Shared presentation tokens. Business rules and customer-selected tracker colors
// remain in their existing modules. Keep this after the Tailwind CDN script.
tailwind.config = {
    theme: {
        extend: {
            colors: {
                brand: {
                    50: '#fff5ed', 100: '#ffe7d4', 200: '#ffd0ac',
                    300: '#ffad76', 400: '#f5823d', 500: '#c4510b',
                    600: '#a94108', 700: '#87360d', 800: '#6e3011', 900: '#1d1d1f'
                },
                gray: {
                    50: '#f5f5f7', 100: '#eeeef1', 200: '#dedee3',
                    300: '#c5c5cc', 400: '#85858e', 500: '#686872',
                    600: '#51515b', 700: '#3a3a43', 800: '#29292f', 900: '#1d1d1f'
                }
            },
            fontFamily: {
                sans: ['-apple-system', 'BlinkMacSystemFont', 'Inter', 'Segoe UI', 'sans-serif']
            }
        }
    }
};
