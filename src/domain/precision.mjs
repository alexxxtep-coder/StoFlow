/** True when a finite numeric value fits the requested decimal scale. */
export function hasDecimalPrecision(value, places) {
  const number = Number(value);
  if (!Number.isFinite(number) || !Number.isInteger(places) || places < 0 || places > 8) return false;
  const scale = 10 ** places;
  return Math.abs(number * scale - Math.round(number * scale)) < 1e-8;
}
