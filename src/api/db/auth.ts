import { Surreal } from "surrealdb";
import { DB_ACCESS, DB_REST_DB, DB_REST_NS, withApi } from "@/api/db/settings.ts";

export type LoginMethod = 'pin' | 'form';

const TOKEN_KEY = 'posr.db.token';

/** Raised when the database blocks sign-in after too many failed attempts. */
export class TooManyAttemptsError extends Error {
  constructor() {
    super('Too many failed login attempts');
    this.name = 'TooManyAttemptsError';
  }
}

/** Raised when the user/login and PIN/password do not match an active user. */
export class InvalidCredentialsError extends Error {
  constructor() {
    super('Invalid credentials');
    this.name = 'InvalidCredentialsError';
  }
}

export const readStoredToken = (): string | undefined => {
  try {
    return localStorage.getItem(TOKEN_KEY) ?? undefined;
  } catch {
    return undefined;
  }
};

export const storeToken = (token: string | undefined) => {
  try {
    if (token) {
      localStorage.setItem(TOKEN_KEY, token);
    } else {
      localStorage.removeItem(TOKEN_KEY);
    }
  } catch {
    // Storage unavailable (private mode): the session just won't survive a reload.
  }
};

const toAuthError = (error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes('too_many_attempts')) {
    return new TooManyAttemptsError();
  }
  return new InvalidCredentialsError();
};

/**
 * Signs `client` in as a staff member and returns the access token.
 *
 * `subject` identifies who is signing in: the user's record key (from
 * login_directory) for PIN login, the username for form login.
 */
export const signInUser = async (
  client: Surreal,
  subject: string,
  password: string,
  method: LoginMethod,
): Promise<string> => {
  try {
    const tokens = await client.signin({
      access: DB_ACCESS,
      namespace: DB_REST_NS,
      database: DB_REST_DB,
      variables: method === 'pin'
        ? { user: subject, password, method }
        : { login: subject, password, method },
    });
    return tokens.access;
  } catch (error) {
    throw toAuthError(error);
  }
};

/** Returns the record id of the user the client is signed in as. */
export const fetchAuthUserId = async (client: Surreal): Promise<string | undefined> => {
  const [auth] = await client.query<[unknown]>('RETURN $auth').collect<[unknown]>();
  return auth ? String(auth) : undefined;
};

/**
 * Checks credentials without touching the main connection, e.g. for a manager
 * approving an action or unlocking a locked terminal. Returns the user with
 * role and shift fetched; throws InvalidCredentialsError / TooManyAttemptsError.
 */
export const verifyCredentials = async <T = any>(
  subject: string,
  password: string,
  method: LoginMethod,
): Promise<T> => {
  const client = new Surreal();
  try {
    await client.connect(withApi(''), { namespace: DB_REST_NS, database: DB_REST_DB });
    await signInUser(client, subject, password, method);
    const [user] = await client
      .query<[T]>('SELECT * FROM ONLY $auth FETCH user_role, user_shift')
      .collect<[T]>();
    if (!user) {
      throw new InvalidCredentialsError();
    }
    return user;
  } finally {
    void client.close();
  }
};

/**
 * Headers for calls to our own services (print, payment, tracking, AI). They
 * check the staff session token with the database before doing anything.
 */
/** Record key of a user id such as `user:abc` / RecordId, as PIN sign-in expects it. */
export const userKey = (id: unknown): string => {
  if (id && typeof id === 'object' && 'id' in id) {
    return String((id as { id: unknown }).id);
  }
  const value = String(id ?? '');
  const key = value.includes(':') ? value.slice(value.indexOf(':') + 1) : value;
  return key.replace(/^[⟨`](.*)[⟩`]$/, '$1');
};

/** A PIN user as listed on the login screen. */
export interface LoginDirectoryEntry {
  key: string;
  first_name?: string;
  last_name?: string;
}

/**
 * Names of the users who log in with a PIN. Readable before sign-in (the
 * database runs with --allow-guests and only exposes this view to guests).
 */
export const fetchLoginDirectory = async (client: Surreal): Promise<LoginDirectoryEntry[]> => {
  const [rows] = await client
    .query<[{ id: unknown; first_name?: string; last_name?: string }[]]>(
      'SELECT id, first_name, last_name FROM login_directory ORDER BY first_name, last_name',
    )
    .collect<[{ id: unknown; first_name?: string; last_name?: string }[]]>();
  return (rows ?? []).map(row => ({
    key: userKey(row.id),
    first_name: row.first_name,
    last_name: row.last_name,
  }));
};

export const staffAuthHeaders = (): Record<string, string> => {
  const token = readStoredToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
};
