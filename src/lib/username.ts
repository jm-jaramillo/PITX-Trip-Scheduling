/**
 * Supabase Auth identities need an email-shaped address. Accounts here log
 * in with a plain username instead, so we map it to a synthetic address in
 * a fixed internal domain. Usernames are unique (enforced in `profiles`),
 * so the resulting "emails" are unique too. This address is never used to
 * send mail.
 */
const USERNAME_DOMAIN = "pitx.local";

export function usernameToEmail(username: string): string {
  return `${username.trim().toLowerCase()}@${USERNAME_DOMAIN}`;
}

const USERNAME_PATTERN = /^[a-z0-9._-]{3,32}$/i;

export function isValidUsername(username: string): boolean {
  return USERNAME_PATTERN.test(username.trim());
}
