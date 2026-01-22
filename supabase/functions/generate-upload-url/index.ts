
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-employee-token',
};

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', // Use Service Role for Admin actions
      { auth: { persistSession: false } }
    );

    // 1. Get Inputs
    const { ticket_id, filename, file_type, storage_bucket } = await req.json();
    const employeeToken = req.headers.get('x-employee-token');

    if (!employeeToken) {
      throw new Error("Token de funcionário ausente.");
    }
    if (!ticket_id || !filename) {
      throw new Error("Dados do arquivo incompletos.");
    }

    // 2. Validate Employee Session & Get Context
    // We call the DB RPC directly or query the table using Service Role
    // RPC 'validate_employee_session' is perfect.
    const { data: sessionData, error: sessionError } = await supabaseClient
      .rpc('validate_employee_session', { p_token: employeeToken });

    if (sessionError || !sessionData || sessionData.length === 0 || !sessionData[0].valid) {
      return new Response(
        JSON.stringify({ error: 'Sessão inválida ou expirada.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { workspace_id } = sessionData[0];

    // 3. Verify Ticket Ownership (Optional but secure)
    // Ensure the ticket belongs to the workspace
    const { data: ticket, error: ticketError } = await supabaseClient
      .from('tickets')
      .select('id')
      .eq('id', ticket_id)
      .eq('workspace_id', workspace_id)
      .single();

    if (ticketError || !ticket) {
       return new Response(
        JSON.stringify({ error: 'Chamado não encontrado ou acesso negado.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 4. Generate Signed Upload URL
    // Path: workspace_id/ticket_id/timestamp_filename
    // Sanitizing filename slightly
    const safeFilename = filename.replace(/[^a-zA-Z0-9.\-_]/g, '');
    const path = `${workspace_id}/${ticket_id}/${Date.now()}_${safeFilename}`;
    const bucket = storage_bucket || 'ticket_photos'; // Default

    const { data: signData, error: signError } = await supabaseClient
      .storage
      .from(bucket)
      .createSignedUploadUrl(path);

    if (signError) {
      throw signError;
    }

    // 5. Return the URL and Token
    return new Response(
      JSON.stringify({
        signedUrl: signData.signedUrl,
        token: signData.token, -- Usually internal token
        path: signData.path,
        fullPath: signData.signedUrl -- Usually contains query params
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
