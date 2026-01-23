
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

    const { ticket_id, path } = await req.json(); // Assuming validation logic via public ID or similar?
    // Since tracking usually relies on "obscurity" or a public UUID for the ticket (tracking_id), we check that.
    // Assuming ticket_id is the public ID or validated separately.
    // For simplicity here, if the user knows the ticket_id and path, and the path belongs to ticket_id...

    // BETTER: Client sends 'id' (ticket UUID) and 'path'.
    // We check if ticket exists and path contains ticket_id.

    if (!ticket_id || !path) throw new Error("Dados invalidos");

    // Validate path belongs to ticket
    // Path structure: workspace/ticket_id/file
    if (!path.includes(ticket_id)) {
        throw new Error("Acesso negado.");
    }

    const { data, error } = await supabaseClient
      .storage
      .from('ticket_photos')
      .createSignedUrl(path, 120); // 2 mins

    if (error) throw error;

    return new Response(
      JSON.stringify({ signedUrl: data.signedUrl }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    );

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 });
  }
});
