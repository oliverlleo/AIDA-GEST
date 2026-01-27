select n.nspname, p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where pg_get_functiondef(p.oid) ilike '%plain_password%'
and n.nspname not in ('pg_catalog', 'information_schema');