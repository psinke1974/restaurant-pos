-- Per-user database access for the POS frontend.
--
-- Before this migration the browser signed in as the SurrealDB root user, so
-- anyone who could load the app (or reach port 8000) had full control over the
-- database. Staff now sign in through the `pos` record access with their own
-- PIN or password; the frontend no longer knows any database credentials.
--
-- Server-side services (payments, printing, sync, tracking, migrations) keep
-- using the root credentials from the environment.
--
-- The `pos` access below is replaced by 2026_10_06_name_pin_login.surql (name +
-- PIN sign-in with per-user lockout); always apply that file after this one.
--
-- Every table the app uses must grant record users access, otherwise queries
-- from the frontend silently return nothing. When adding a table, add it to
-- the default section below (src/api/db/__tests__/access-migration.test.ts
-- checks this against the Tables enum).

-- ------------------------------
-- Failed sign-in throttle
-- ------------------------------
-- PIN login identifies the user by the PIN itself, so failures cannot be
-- counted per user. Instead all failures are counted: more than 10 in a minute
-- or 30 in 15 minutes blocks every PIN/password sign-in until they age out.

DEFINE TABLE IF NOT EXISTS login_failure TYPE NORMAL SCHEMALESS PERMISSIONS NONE;
DEFINE INDEX IF NOT EXISTS login_failure_at ON login_failure FIELDS at;

DEFINE ACCESS OVERWRITE pos ON DATABASE TYPE RECORD
  SIGNIN {
    LET $short = (SELECT count() AS c FROM login_failure WHERE at > time::now() - 1m GROUP ALL)[0].c ?? 0;
    LET $long = (SELECT count() AS c FROM login_failure WHERE at > time::now() - 15m GROUP ALL)[0].c ?? 0;
    IF $short >= 10 OR $long >= 30 {
      THROW "too_many_attempts";
    };

    LET $user = IF $method = 'form' {
      (SELECT * FROM user
        WHERE login = $login AND deleted_at = NONE AND login_method = 'form'
          AND crypto::bcrypt::compare(password, $password) = true
        LIMIT 1)[0]
    } ELSE {
      (SELECT * FROM user
        WHERE login = $login AND deleted_at = NONE AND (login_method = 'pin' OR login_method = NONE)
          AND crypto::bcrypt::compare(password, $password) = true
        LIMIT 1)[0]
    };

    IF $user = NONE {
      -- Returning NONE (instead of THROW) keeps this write: a THROW would roll it back.
      CREATE login_failure SET at = time::now();
      DELETE login_failure WHERE at < time::now() - 1d;
      RETURN NONE;
    };

    RETURN $user.id;
  }
  DURATION FOR TOKEN 16h, FOR SESSION NONE;

-- ------------------------------
-- Tables with stricter rules
-- ------------------------------

DEFINE TABLE IF NOT EXISTS _schema_migration TYPE NORMAL SCHEMAFULL PERMISSIONS NONE;
ALTER TABLE _schema_migration PERMISSIONS NONE;

-- Staff can see colleagues (names are used across reports), but only users
-- with the "Users" permission can create or change accounts, and nobody can
-- read password hashes.
DEFINE TABLE IF NOT EXISTS user TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE user PERMISSIONS
  FOR select WHERE $auth.id != NONE,
  FOR create, update, delete WHERE $auth.user_role.roles CONTAINS 'Users' OR $auth.roles CONTAINS 'Users';
DEFINE FIELD OVERWRITE password ON user TYPE none | string | null PERMISSIONS
  FOR select NONE,
  FOR create, update WHERE $auth.user_role.roles CONTAINS 'Users' OR $auth.roles CONTAINS 'Users';

DEFINE TABLE IF NOT EXISTS user_role TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE user_role PERMISSIONS
  FOR select WHERE $auth.id != NONE,
  FOR create, update, delete WHERE $auth.user_role.roles CONTAINS 'Roles' OR $auth.roles CONTAINS 'Roles';

-- Orders are fiscal records: they are cancelled or refunded, never deleted.
DEFINE TABLE IF NOT EXISTS order TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order PERMISSIONS
  FOR select, create, update WHERE $auth.id != NONE,
  FOR delete NONE;

-- ------------------------------
-- Default: any signed-in staff member
-- ------------------------------

DEFINE TABLE IF NOT EXISTS account TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE account PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS account_group TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE account_group PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS account_journal_entry TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE account_journal_entry PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS account_journal_line TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE account_journal_line PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS auth_permission TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE auth_permission PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_consumption_log TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_consumption_log PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_guest_count TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_guest_count PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_menu TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_menu PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_menu_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_menu_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_production_batch TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_production_batch PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_session TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_session PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_stock_snapshot TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_stock_snapshot PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS buffet_waste_log TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE buffet_waste_log PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS category TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE category PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS cost_center TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE cost_center PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS coupon TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE coupon PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS coupon_redemption TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE coupon_redemption PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS customer TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE customer PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS customer_address TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE customer_address PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS day_closing TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE day_closing PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS department TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE department PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS discount TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE discount PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS discount_reason TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE discount_reason PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS document TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE document PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS employee TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE employee PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS employee_assignment_history TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE employee_assignment_history PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS employee_document TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE employee_document PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS employee_pay_profile TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE employee_pay_profile PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS employee_performance_note TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE employee_performance_note PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS extra TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE extra PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS extras TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE extras PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS floor TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE floor PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS floor_table TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE floor_table PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_execution_history TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_execution_history PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_installed_provider TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_installed_provider PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_order_fiscal TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_order_fiscal PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_provider TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_provider PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_provider_certificate TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_provider_certificate PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_provider_config TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_provider_config PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_provider_health TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_provider_health PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_provider_secret TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_provider_secret PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_provider_webhook TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_provider_webhook PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_queue TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_queue PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_queue_attempt TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_queue_attempt PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS integration_schedule TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE integration_schedule PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_adjustment TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_adjustment PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_adjustment_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_adjustment_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_category TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_category PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_issue TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_issue PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_issue_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_issue_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_issue_return TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_issue_return PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_issue_return_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_issue_return_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_item_group TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_item_group PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_item_group_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_item_group_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_item_waste TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_item_waste PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_item_waste_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_item_waste_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_ledger TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_ledger PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_location TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_location PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase_order TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase_order PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase_order_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase_order_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase_payment TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase_payment PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase_return TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase_return PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_purchase_return_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_purchase_return_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_store TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_store PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS inventory_supplier TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE inventory_supplier PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_complimentary_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_complimentary_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_reconciliation TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_reconciliation PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_reconciliation_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_reconciliation_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_reconciliation_revision TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_reconciliation_revision PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_staff_meal TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_staff_meal PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_stock_count TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_stock_count PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS kitchen_waste TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE kitchen_waste PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS labor_adjustment TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE labor_adjustment PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS labor_audit_log TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE labor_audit_log PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS labor_cost_event TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE labor_cost_event PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS labor_pay_rule TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE labor_pay_rule PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS labor_policy TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE labor_policy PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS leave_balance TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE leave_balance PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS leave_request TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE leave_request PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS leave_type TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE leave_type PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS menu TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE menu PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS menu_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE menu_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS menu_item_modifier_group TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE menu_item_modifier_group PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS menu_item_recipe TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE menu_item_recipe PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS menu_menu_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE menu_menu_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS menu_menu_item_tax TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE menu_menu_item_tax PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS modifier TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE modifier PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS modifier_group TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE modifier_group PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS notes TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE notes PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_coupon TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_coupon PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_discount TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_discount PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_extras TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_extras PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_item_kitchen TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_item_kitchen PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_merge TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_merge PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_meta TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_meta PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_payment TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_payment PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_refund TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_refund PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_split TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_split PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_tax TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_tax PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_type TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_type PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS order_void TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE order_void PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS payment_type TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE payment_type PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS payment_type_gateway_config TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE payment_type_gateway_config PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS payment_webhook TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE payment_webhook PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS payroll_period TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE payroll_period PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS payroll_run TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE payroll_run PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS payroll_snapshot TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE payroll_snapshot PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS position TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE position PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS printer TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE printer PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS production_batch TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE production_batch PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS production_batch_input TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE production_batch_input PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS production_batch_output TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE production_batch_output PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS public_holiday TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE public_holiday PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS recipe TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE recipe PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS recipe_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE recipe_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS recipe_output TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE recipe_output PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS role_discount_policy TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE role_discount_policy PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS schedule_template TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE schedule_template PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS scheduled_shift TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE scheduled_shift PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS setting TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE setting PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS shift TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE shift PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS shift_swap_request TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE shift_swap_request PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS stock_transfer TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE stock_transfer PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS stock_transfer_item TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE stock_transfer_item PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS tax TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE tax PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS time_entry TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE time_entry PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS time_entry_break TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE time_entry_break PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS tip_distribution TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE tip_distribution PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS tip_distribution_user_share TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE tip_distribution_user_share PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS tracking TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE tracking PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS work_schedule TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE work_schedule PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS workflow TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE workflow PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
DEFINE TABLE IF NOT EXISTS workflow_stage TYPE ANY SCHEMALESS PERMISSIONS NONE;
ALTER TABLE workflow_stage PERMISSIONS FOR select, create, update, delete WHERE $auth.id != NONE;
