// Mirrors private.is_edu_email() in supabase/migrations/20261030000003_signup.sql. The database is the authority.
export const isEduEmail = (email: string) => /^[^@\s]+@([a-z0-9-]+\.)+edu$/.test(email.toLowerCase());
