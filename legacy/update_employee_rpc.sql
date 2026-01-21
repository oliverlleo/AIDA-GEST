
CREATE OR REPLACE FUNCTION update_employee(
    p_id UUID,
    p_name TEXT,
    p_username TEXT,
    p_password TEXT,
    p_roles TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE employees
    SET
        name = p_name,
        username = p_username,
        password_hash = CASE WHEN p_password IS NOT NULL AND p_password <> '' THEN crypt(p_password, gen_salt('bf')) ELSE password_hash END,
        plain_password = CASE WHEN p_password IS NOT NULL AND p_password <> '' THEN p_password ELSE plain_password END,
        roles = p_roles
    WHERE id = p_id;
END;
$$;
