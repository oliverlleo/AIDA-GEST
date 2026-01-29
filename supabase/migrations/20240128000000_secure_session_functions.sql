
-- Force SECURITY DEFINER and strict search_path for session functions

ALTER FUNCTION public.employee_login(text, text, text) SECURITY DEFINER;
ALTER FUNCTION public.employee_login(text, text, text) SET search_path = public, extensions, pg_catalog;

ALTER FUNCTION public.validate_employee_session(uuid) SECURITY DEFINER;
ALTER FUNCTION public.validate_employee_session(uuid) SET search_path = public, extensions, pg_catalog;

ALTER FUNCTION public.employee_logout(uuid) SECURITY DEFINER;
ALTER FUNCTION public.employee_logout(uuid) SET search_path = public, extensions, pg_catalog;

ALTER FUNCTION public.employee_change_password(uuid, text, text) SECURITY DEFINER;
ALTER FUNCTION public.employee_change_password(uuid, text, text) SET search_path = public, extensions, pg_catalog;

ALTER FUNCTION public.current_employee_from_token() SECURITY DEFINER;
ALTER FUNCTION public.current_employee_from_token() SET search_path = public, extensions, pg_catalog;
