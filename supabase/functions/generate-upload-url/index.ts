
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_ORIGINS = [
  'https://oliverlleo.github.io',
  'https://centralos.pages.dev',
  'https://techassist.pages.dev'
];

const getCorsHeaders = (origin: string | null) => {
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    return {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-employee-token',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Max-Age': '86400',
      'Vary': 'Origin',
    };
  }
  return {};
};

serve(async (req) => {
  const origin = req.headers.get('origin');
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS Preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders, status: 200 });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } }
    );

    const { ticket_id, filename, file_type, storage_bucket } = await req.json();
    const employeeToken = req.headers.get('x-employee-token');
    const authHeader = req.headers.get('authorization');

    let workspace_id;

    // A. Validate User
    if (authHeader && authHeader.startsWith('Bearer ')) {
       // ADMIN Flow (Supabase Auth)
       const token = authHeader.split(' ')[1];
       const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);

       if (userError || !user) throw new Error("Admin não autenticado.");

       // Get Admin Workspace
       const { data: ws, error: wsError } = await supabaseClient
         .from('workspaces')
         .select('id')
         .eq('owner_id', user.id)
         .single();

       if (wsError || !ws) throw new Error("Workspace não encontrado para este Admin.");
       workspace_id = ws.id;

    } else if (employeeToken) {
       // EMPLOYEE Flow
       const { data: sessionData, error: sessionError } = await supabaseClient
         .rpc('validate_employee_session', { p_token: employeeToken });

       if (sessionError || !sessionData || sessionData.length === 0 || !sessionData[0].valid) {
         throw new Error("Sessão de funcionário inválida.");
       }
       workspace_id = sessionData[0].workspace_id;

    } else {
       throw new Error("Token ausente.");
    }

    if (!ticket_id || !filename) {
      throw new Error("Dados do arquivo incompletos.");
    }

    // B. Validate Ticket Ownership
    // Ticket must belong to workspace
    const { data: ticket, error: ticketError } = await supabaseClient
      .from('tickets')
      .select('id')
      .eq('id', ticket_id)
      .eq('workspace_id', workspace_id)
      .single();

    if (ticketError || !ticket) {
       throw new Error("Chamado não pertence ao workspace.");
    }

    // C. Generate Signed URL
    const safeFilename = filename.replace(/[^a-zA-Z0-9.\-_]/g, '');
    const path = `${workspace_id}/${ticket_id}/${Date.now()}_${safeFilename}`;
    const bucket = storage_bucket || 'ticket_photos';

    const { data: signData, error: signError } = await supabaseClient
      .storage
      .from(bucket)
      .createSignedUploadUrl(path);

    if (signError) throw signError;

    return new Response(
      JSON.stringify({
        signedUrl: signData.signedUrl,
        path: signData.path, // This is the storage path to save in DB
        token: signData.token
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400
      }
    );
  }
});
