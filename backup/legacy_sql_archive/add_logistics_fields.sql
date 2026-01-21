
-- Add logistics columns to tickets table
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS delivery_method TEXT; -- 'pickup' or 'carrier'
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS carrier_name TEXT;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS tracking_code TEXT;
