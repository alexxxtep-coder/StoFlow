/** Normalize a phone number for the tenant-scoped customer lookup. */
export function normalizePhone(input) {
  const raw = String(input ?? "").trim();
  const digits = raw.replace(/\D/g, "");
  const normalized = raw.replace(/[^0-9+]/g, "").replace(/(?!^)\+/g, "");
  if (digits.length < 5) {
    throw new Error("Телефон должен содержать не менее пяти цифр.");
  }
  return { digits, normalized };
}
