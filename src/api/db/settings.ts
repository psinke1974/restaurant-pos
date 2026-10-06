export const DB_REST_API = import.meta.env.VITE_DB_WEBDOCKET;
export const DB_REST_DB = 'posr'; // database name
export const DB_REST_NS = 'posr'; // namespace
// Record access staff sign in through (see migrations/2026_10_06_record_access.surql).
// The frontend holds no database credentials of its own.
export const DB_ACCESS = 'pos';

export const withApi = (path: string) => {
  return DB_REST_API + path;
}
