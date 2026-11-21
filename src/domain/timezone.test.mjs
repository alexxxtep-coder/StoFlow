import test from "node:test";
import assert from "node:assert/strict";
import { dateOnlyInTimeZone, formatDateOnly, formatInTimeZone, isValidDateOnly, isValidTimeZone, localDateTimeToIso, toDateTimeLocalValue } from "./timezone.mjs";

test("Minsk wall-clock appointment time is stored as the correct UTC instant", () => {
  assert.equal(localDateTimeToIso("2026-11-19T10:30", "Europe/Minsk"), "2026-11-19T07:30:00.000Z");
});

test("datetime-local defaults are generated in the tenant timezone, not UTC", () => {
  assert.equal(toDateTimeLocalValue("2026-11-19T07:30:00.000Z", "Europe/Minsk"), "2026-11-19T10:30");
});

test("date formatting honors the configured timezone", () => {
  assert.equal(formatInTimeZone("2026-11-19T23:30:00.000Z", "Europe/Minsk", { dateStyle: "short" }), "20.11.2026");
});

test("invalid calendar values and timezones are rejected", () => {
  assert.throws(() => localDateTimeToIso("2026-02-30T10:00", "Europe/Minsk"), /существующую дату/);
  assert.throws(() => localDateTimeToIso("2026-11-19T10:00", "Not/A_Timezone"), /часовой пояс/);
});

test("timezone settings reject unknown IANA identifiers", () => {
  assert.equal(isValidTimeZone("Europe/Minsk"), true);
  assert.equal(isValidTimeZone("Not/A_Timezone"), false);
});

test("SQL DATE values are formatted without timezone day shifts", () => {
  assert.equal(formatDateOnly("2026-11-19"), "19.11.2026");
  assert.equal(formatDateOnly("2026-02-31"), "—");
});

test("date-only expense input rejects impossible calendar dates", () => {
  assert.equal(isValidDateOnly("2026-11-19"), true);
  assert.equal(isValidDateOnly("2026-02-31"), false);
  assert.equal(isValidDateOnly("19.11.2026"), false);
});

test("date-only defaults use the tenant calendar day rather than the UTC day", () => {
  assert.equal(dateOnlyInTimeZone("2026-11-19T21:30:00.000Z", "Europe/Minsk"), "2026-11-20");
  assert.equal(dateOnlyInTimeZone("2026-11-19T23:30:00.000Z", "Europe/Amsterdam"), "2026-11-20");
});
