import test from "node:test";
import assert from "node:assert/strict";
import { hasDecimalPrecision } from "./precision.mjs";

test("monetary inputs are limited to two decimal places", () => {
  assert.equal(hasDecimalPrecision("12.34", 2), true);
  assert.equal(hasDecimalPrecision("12.345", 2), false);
  assert.equal(hasDecimalPrecision("0.1", 2), true);
});

test("work quantities are limited to three decimal places", () => {
  assert.equal(hasDecimalPrecision("1.125", 3), true);
  assert.equal(hasDecimalPrecision("1.1255", 3), false);
  assert.equal(hasDecimalPrecision("0.001", 3), true);
});
