export const ALLOWED_ORIGINS = [
  'https://oliverlleo.github.io',
  'https://centralos.pages.dev',
  'https://techassist.pages.dev'
];

export const corsHeaders = {
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-employee-token',
  'Access-Control-Max-Age': '86400',
};

export function getCorsHeaders(origin: string | null) {
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    return {
      ...corsHeaders,
      'Access-Control-Allow-Origin': origin,
      'Vary': 'Origin',
    };
  }
  return {
    ...corsHeaders,
    'Vary': 'Origin',
  };
}
