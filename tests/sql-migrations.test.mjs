import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = (name) => readFileSync(new URL(`../supabase/migrations/${name}`, import.meta.url), "utf8");

test("migration 0002 drops the old RPC signature before recreating the named-argument contract", () => {
  const sql = migration("0002_transactional_operations.sql");
  const dropAt = sql.indexOf("drop function if exists public.create_lead_with_context(uuid,text,text,text,text,text,text,text,text)");
  const createAt = sql.indexOf("create function public.create_lead_with_context(");
  assert.ok(dropAt >= 0 && createAt > dropAt, "old function signature must be dropped before create");
  assert.match(sql, /drop policy if exists resources_insert on public\.resources/);
  assert.match(sql, /drop policy if exists resources_update on public\.resources/);
  assert.match(sql, /drop policy if exists customers_insert on public\.customers/);
  assert.match(sql, /drop policy if exists vehicles_insert on public\.vehicles/);
  assert.match(sql, /drop policy if exists leads_insert on public\.leads/);
  assert.match(sql, /has_tenant_role\(p_tenant_id, array\['owner','admin','service_manager','service_advisor'\]::public\.app_role\[\]\)/);
  for (const name of ["p_tenant_id", "p_customer_name", "p_phone", "p_vehicle_make", "p_vehicle_model", "p_plate", "p_vin", "p_description", "p_source"]) {
    assert.ok(sql.slice(createAt, createAt + 700).includes(name), `missing named RPC argument ${name}`);
  }
});

test("migration 0003 protects order balance and payment allocation under row locks", () => {
  const sql = migration("0003_financial_integrity.sql");
  assert.match(sql, /create_payment_with_allocation[\s\S]*?for update[\s\S]*?outstanding := order_total - already_allocated[\s\S]*?p_amount > outstanding/);
  assert.match(sql, /payment_allocation_limit_guard/);
  assert.match(sql, /before insert or update of amount, payment_id, tenant_id, work_order_id/);
  assert.match(sql, /Allocations exceed work order total/);
  assert.match(sql, /Payment customer does not match work order customer/);
});

test("migration 0003 enforces payment currency and completion timestamps in PostgreSQL", () => {
  const sql = migration("0003_financial_integrity.sql");
  assert.match(sql, /Payment currency does not match workspace currency/);
  assert.match(sql, /new\.completed_at := coalesce\(new\.completed_at, now\(\)\)/);
  assert.match(sql, /update public\.work_orders wo[\s\S]*?set completed_at/);
});

test("migration 0003 hardens SECURITY DEFINER search paths and grants only required helper execution", () => {
  const sql = migration("0003_financial_integrity.sql");
  assert.match(sql, /alter function public\.has_tenant_role\(uuid, public\.app_role\[\]\) set search_path = pg_catalog, public, pg_temp/);
  assert.match(sql, /alter function public\.create_workspace\(text\) set search_path = pg_catalog, public, pg_temp/);
  assert.match(sql, /revoke all on function public\.audit_work_order_insert\(\) from public, anon, authenticated/);
  assert.match(sql, /grant execute on function public\.has_tenant_role\(uuid, public\.app_role\[\]\) to authenticated/);
});

test("migration 0003 prevents post-handover mutations and incomplete-price allocations", () => {
  const sql = migration("0003_financial_integrity.sql");
  assert.match(sql, /Cannot change lines of a completed or cancelled work order/);
  assert.match(sql, /Cannot change financial lines of a completed or cancelled work order/);
  assert.match(sql, /tasks_work_order_status_guard/);
  assert.match(sql, /part_requests_work_order_status_guard/);
  assert.match(sql, /Work order has lines with missing financial prices/);
  assert.match(sql, /A work-order line cannot be moved between orders or tenants/);
  assert.match(sql, /Financial data cannot be moved between work-order lines or tenants/);
  assert.match(sql, /Updated work-order total cannot be lower than allocated payments/);
  assert.match(sql, /function public\.assert_order_allocations_within_total\(\)[\s\S]*?security definer[\s\S]*?set search_path = pg_catalog, public, pg_temp/);
  assert.match(sql, /User already belongs to an active workspace/);
  assert.match(sql, /Cannot add lines to a completed or cancelled work order/);
  assert.match(sql, /p_quantity <> round\(p_quantity,3\)/);
  assert.match(sql, /p_customer_unit_price <> round\(p_customer_unit_price,2\)/);
});


test("migration 0004 blocks unsafe supplier offers and invalid purchases at the database boundary", () => {
  const sql = migration("0004_procurement_safety.sql");
  assert.match(sql, /Purchase price must be non-negative and have at most two decimal places/);
  assert.match(sql, /Offer currency must match workspace currency/);
  assert.match(sql, /Cannot add an offer to a received or cancelled part request/);
  assert.match(sql, /Cannot purchase an offer for a received or cancelled part request/);
  assert.match(sql, /Cannot purchase an offer marked as not fitting the vehicle/);
  assert.match(sql, /Cannot purchase an offer marked out of stock/);
  assert.match(sql, /Purchase price is required before creating a purchase/);
  assert.match(sql, /Idempotent retry: return the purchase already created for this offer/);
  assert.match(sql, /A purchase already exists for this part request/);
  assert.match(sql, /create or replace function public\.guard_purchase_insert\(\)/);
  assert.match(sql, /create trigger purchases_guard_insert/);
  assert.match(sql, /create trigger purchases_prevent_mutation/);
  assert.match(sql, /revoke all on function public\.create_purchase_from_offer\(uuid,uuid\) from public, anon/);
});
