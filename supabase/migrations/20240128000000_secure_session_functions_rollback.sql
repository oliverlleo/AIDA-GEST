
-- Rollback: Reset to SECURITY INVOKER (default) and default search_path

ALTER FUNCTION public.employee_login(text, text, text) SECURITY INVOKER;
ALTER FUNCTION public.employee_login(text, text, text) RESET search_path;

ALTER FUNCTION public.validate_employee_session(uuid) SECURITY INVOKER;
ALTER FUNCTION public.validate_employee_session(uuid) RESET search_path;

ALTER FUNCTION public.employee_logout(uuid) SECURITY INVOKER;
ALTER FUNCTION public.employee_logout(uuid) RESET search_path;

ALTER FUNCTION public.employee_change_password(uuid, text, text) SECURITY INVOKER;
ALTER FUNCTION public.employee_change_password(uuid, text, text) RESET search_path;

ALTER FUNCTION public.current_employee_from_token() SECURITY INVOKER;
ALTER FUNCTION public.current_employee_from_token() RESET search_path;
