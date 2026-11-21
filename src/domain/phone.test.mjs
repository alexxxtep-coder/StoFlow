import test from "node:test";
import assert from "node:assert/strict";
import { normalizePhone } from "./phone.mjs";

test("phone normalization accepts formatted international numbers", () => {
  assert.deepEqual(normalizePhone("+375 (29) 123-45-67"), {
    digits: "375291234567",
    normalized: "+375291234567"
  });
});

test("phone normalization rejects values with fewer than five digits", () => {
  assert.throws(() => normalizePhone("+1 (2)"), /пяти цифр/);
});
