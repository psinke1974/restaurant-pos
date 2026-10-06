import {getBusinessDayUnixRange} from "@/lib/datetime.ts";

type QueryableDb = {
  query: <R extends unknown[] = any[]>(sql: string, parameters?: Record<string, unknown>) => Promise<R>;
};

// Numbers come from database counters (fn::next_number, see
// migrations/2026_10_06_numbering.surql), so two terminals can't get the same
// number. A counter that doesn't exist yet starts after the highest number
// already in use. The legal invoice number (fiscal_series/fiscal_number) is
// assigned by the database when an order is paid.

/** Daily ticket number shown to staff and the kitchen; restarts every business day. */
export const generateNextInvoiceNumber = async (db: QueryableDb): Promise<number> => {
  const {day, startUnix, endUnix} = getBusinessDayUnixRange();
  const [next] = await db.query<[number]>(
    `RETURN fn::next_number($key, IF type::record('number_sequence', $key).value = NONE {
       <int> math::max(array::push((
         SELECT VALUE invoice_number FROM order
         WHERE invoice_number != NONE AND time::unix(created_at) >= $startUnix AND time::unix(created_at) < $endUnix
       ), 0))
     } ELSE { 0 })`,
    {key: `ticket:${day}`, startUnix, endUnix}
  );

  return Number(next);
};

/** Global, ever-increasing order id. */
export const getNextAutoId = async (db: QueryableDb): Promise<number> => {
  const [next] = await db.query<[number]>(
    `RETURN fn::next_number($key, IF type::record('number_sequence', $key).value = NONE {
       <int> math::max(array::push((SELECT VALUE auto_id FROM order WHERE auto_id != NONE), 0))
     } ELSE { 0 })`,
    {key: 'order_auto_id'}
  );

  return Number(next);
};
