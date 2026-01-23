
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-employee-token',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } }
    );

    const { path } = await req.json();
    if (!path) throw new Error("Path required");

    const employeeToken = req.headers.get('x-employee-token');
    const authHeader = req.headers.get('authorization');
    let workspace_id;

    // 1. Auth & Context
    if (authHeader && authHeader.startsWith('Bearer ')) {
       const token = authHeader.split(' ')[1];
       const { data: { user }, error } = await supabaseClient.auth.getUser(token);
       if (error || !user) throw new Error("Admin invalido");

       const { data: ws } = await supabaseClient.from('workspaces').select('id').eq('owner_id', user.id).single();
       if (!ws) throw new Error("Workspace nao encontrado");
       workspace_id = ws.id;
    } else if (employeeToken) {
       const { data: sessionData } = await supabaseClient.rpc('validate_employee_session', { p_token: employeeToken });
       if (!sessionData?.[0]?.valid) throw new Error("Sessao invalida");
       workspace_id = sessionData[0].workspace_id;
    } else {
       throw new Error("Unauthorized");
    }

    // 2. Validate Access to File
    // Check if file path starts with workspace_id
    if (!path.startsWith(workspace_id)) {
        throw new Error("Acesso negado ao arquivo.");
    }

    // 3. Generate Signed URL
    const { data, error } = await supabaseClient
      .storage
      .from('ticket_photos')
      .createSignedUrl(path, 60 * 60); // 1 hour

    if (error) throw error;

    return new Response(
      JSON.stringify({ signedUrl: data.signedUrl }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    );

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 });
  }
});
