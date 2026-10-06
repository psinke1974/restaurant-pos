-- Atomic, gap-free numbering for orders.
--
-- Before: the browser computed max(number) + 1, so two terminals taking an
-- order at the same moment could get the same number, and nothing assigned a
-- legally valid invoice number (Spain requires a unique, consecutive number
-- per series for every factura simplificada).
--
-- - number_sequence holds one counter per key; fn::next_number bumps it inside
--   the caller's transaction, so concurrent callers conflict instead of
--   sharing a number.
-- - order.invoice_number stays the daily ticket number shown to staff and
--   kitchen (key `ticket:<business day>`); order.auto_id is a global counter.
-- - When an order becomes Paid it gets fiscal_series (`T<year>`) and
--   fiscal_number, consecutive within the series and never reused. Numbers are
--   only consumed by paid orders, so cancelled tickets leave no gaps.

DEFINE TABLE IF NOT EXISTS number_sequence TYPE NORMAL SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD OVERWRITE value ON number_sequence TYPE int DEFAULT 0;
ALTER TABLE number_sequence PERMISSIONS FOR select, create, update WHERE $auth.id != NONE, FOR delete NONE;

-- Bumps counter $key and returns the new value, never lower than $floor + 1
-- ($floor lets a counter pick up where numbers assigned before it left off).
DEFINE FUNCTION OVERWRITE fn::next_number($key: string, $floor: int) -> int {
  LET $row = UPSERT ONLY type::record('number_sequence', $key)
    SET value = math::max([value ?? 0, $floor]) + 1
    RETURN AFTER;
  RETURN $row.value;
} PERMISSIONS WHERE $auth.id != NONE;

-- Hours added to UTC to decide the fiscal year. Mainland Spain and the
-- Balearics are UTC+1 at New Year; set to 0h for the Canary Islands.
DEFINE PARAM IF NOT EXISTS $fiscal_utc_offset VALUE 1h PERMISSIONS FULL;

-- Set once by the event below, then frozen. Staff can't write them directly.
DEFINE FIELD OVERWRITE fiscal_series ON order TYPE option<string>
  VALUE IF $before != NONE { $before } ELSE { $value }
  PERMISSIONS FOR select WHERE $auth.id != NONE, FOR create, update NONE;
DEFINE FIELD OVERWRITE fiscal_number ON order TYPE option<int>
  VALUE IF $before != NONE { $before } ELSE { $value }
  PERMISSIONS FOR select WHERE $auth.id != NONE, FOR create, update NONE;
DEFINE FIELD OVERWRITE fiscal_issued_at ON order TYPE option<datetime>
  VALUE IF $before != NONE { $before } ELSE { $value }
  PERMISSIONS FOR select WHERE $auth.id != NONE, FOR create, update NONE;
DEFINE INDEX IF NOT EXISTS order_fiscal_number ON order FIELDS fiscal_series, fiscal_number UNIQUE;
DEFINE INDEX IF NOT EXISTS order_auto_id ON order FIELDS auto_id;

DEFINE EVENT OVERWRITE assign_fiscal_number ON order
  WHEN $before.status != 'Paid' AND $after.status = 'Paid' AND $after.fiscal_number = NONE
  THEN {
    LET $issued_at = time::now();
    LET $series = 'T' + time::format($issued_at + $fiscal_utc_offset, '%Y');
    LET $key = 'fiscal:' + $series;
    -- A new counter continues after numbers already in the series (e.g. restored data).
    LET $floor = IF type::record('number_sequence', $key).value = NONE {
      math::max(array::push((SELECT VALUE fiscal_number FROM order WHERE fiscal_series = $series AND fiscal_number != NONE), 0))
    } ELSE { 0 };
    UPDATE $after.id SET
      fiscal_series = $series,
      fiscal_number = fn::next_number($key, $floor),
      fiscal_issued_at = $issued_at;
  };
