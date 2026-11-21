import test from "node:test";
import assert from "node:assert/strict";
import { assertOrderTransition, canTransitionOrder, calculateOrderEconomicsMinor } from "./order.mjs";

test("valid order transitions are accepted", () => {
  assert.equal(canTransitionOrder("accepted", "diagnostics"), true);
  assert.doesNotThrow(() => assertOrderTransition("quality_check", "ready"));
});

test("invalid and terminal transitions are rejected", () => {
  assert.equal(canTransitionOrder("completed", "in_progress"), false);
  assert.throws(() => assertOrderTransition("new", "completed"));
});

test("gross profit is calculated in integer kopecks", () => {
  const result = calculateOrderEconomicsMinor({
    laborRevenue: 8000, partsRevenue: 12000, discounts: 0,
    laborDirectCost: 3200, partsPurchaseCost: 9500, otherDirectCosts: 1000
  });
  assert.deepEqual(result, { revenue: 20000, directCosts: 13700, grossProfit: 6300 });
});

test("negative, fractional or unsafe monetary values are rejected", () => {
  assert.throws(() => calculateOrderEconomicsMinor({ laborRevenue: -1 }));
  assert.throws(() => calculateOrderEconomicsMinor({ partsRevenue: 1.5 }));
  assert.throws(() => calculateOrderEconomicsMinor({ partsRevenue: Number.MAX_SAFE_INTEGER + 1 }));
});

test("all database-supported order transitions match the domain transition graph", () => {
  const expected = {
    new: ["accepted", "cancelled"],
    accepted: ["diagnostics", "awaiting_approval", "awaiting_parts", "in_progress", "cancelled"],
    diagnostics: ["awaiting_approval", "awaiting_parts", "in_progress", "cancelled"],
    awaiting_approval: ["awaiting_parts", "in_progress", "cancelled"],
    awaiting_parts: ["in_progress", "cancelled"],
    in_progress: ["awaiting_approval", "awaiting_parts", "quality_check", "cancelled"],
    quality_check: ["in_progress", "ready"],
    ready: ["completed", "in_progress"],
    completed: [],
    cancelled: []
  };
  for (const [from, targets] of Object.entries(expected)) {
    for (const to of ["new", "accepted", "diagnostics", "awaiting_approval", "awaiting_parts", "in_progress", "quality_check", "ready", "completed", "cancelled"]) {
      assert.equal(canTransitionOrder(from, to), targets.includes(to), `${from} -> ${to}`);
    }
  }
});

test("completed order finance state keeps billed, partially paid and fully paid orders visible", async () => {
  const { calculateOrderFinancialState } = await import("./order.mjs");
  assert.deepEqual(calculateOrderFinancialState(
    [{ quantity: 2, unitPrice: 19.99 }, { quantity: 1, unitPrice: 10 }],
    [{ amount: 20 }]
  ), { totalMinor: 4998, paidMinor: 2000, balanceMinor: 2998 });
  assert.deepEqual(calculateOrderFinancialState(
    [{ quantity: 1, unitPrice: 50 }], [{ amount: 50 }]
  ), { totalMinor: 5000, paidMinor: 5000, balanceMinor: 0 });
});


test("financial state refuses to treat a missing price record as a zero-price line", async () => {
  const { calculateOrderFinancialState } = await import("./order.mjs");
  assert.throws(() => calculateOrderFinancialState([{ quantity: 1 }], []), /не задана цена/);
});


test("money conversion avoids binary floating-point drift", async () => {
  const { moneyToMinorUnits, sumMoneyMinor } = await import("./order.mjs");
  assert.equal(moneyToMinorUnits("19.99"), 1999);
  assert.equal(moneyToMinorUnits("1.005"), 101);
  assert.equal(sumMoneyMinor(["0.10", "0.20", "0.30"]), 60);
});
