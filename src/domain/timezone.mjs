const formatterCache = new Map();

function formatter(timeZone) {
  if (!formatterCache.has(timeZone)) {
    formatterCache.set(timeZone, new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
      hourCycle: "h23"
    }));
  }
  return formatterCache.get(timeZone);
}

function partsAt(date, timeZone) {
  const parts = Object.fromEntries(formatter(timeZone).formatToParts(date).map(part => [part.type, part.value]));
  return {
    year: Number(parts.year), month: Number(parts.month), day: Number(parts.day),
    hour: Number(parts.hour), minute: Number(parts.minute), second: Number(parts.second)
  };
}

function validCalendarDate(year, month, day, hour, minute) {
  if (![year, month, day, hour, minute].every(Number.isInteger)) return false;
  if (year < 1900 || year > 2200 || month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59) return false;
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/** Convert a datetime-local wall-clock value into an ISO instant in the tenant timezone. */
export function localDateTimeToIso(value, timeZone) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(String(value ?? ""));
  if (!match) throw new Error("Укажите корректные дату и время.");
  const [year, month, day, hour, minute] = match.slice(1).map(Number);
  if (!validCalendarDate(year, month, day, hour, minute)) throw new Error("Укажите существующую дату и время.");

  const desiredUtc = Date.UTC(year, month - 1, day, hour, minute);
  let instant = desiredUtc;
  try {
    for (let i = 0; i < 4; i += 1) {
      const zoned = partsAt(new Date(instant), timeZone);
      const representedUtc = Date.UTC(zoned.year, zoned.month - 1, zoned.day, zoned.hour, zoned.minute, zoned.second);
      const delta = desiredUtc - representedUtc;
      if (delta === 0) break;
      instant += delta;
    }
    const check = partsAt(new Date(instant), timeZone);
    if (check.year !== year || check.month !== month || check.day !== day || check.hour !== hour || check.minute !== minute) {
      throw new Error("Это местное время не существует из-за перехода часового пояса.");
    }
  } catch (error) {
    if (error instanceof RangeError) throw new Error("В настройках организации указан некорректный часовой пояс.");
    throw error;
  }
  return new Date(instant).toISOString();
}

/** Format an instant as a datetime-local value in the supplied timezone. */
export function toDateTimeLocalValue(value, timeZone) {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error("Некорректная дата.");
  const p = partsAt(date, timeZone);
  return `${String(p.year).padStart(4, "0")}-${String(p.month).padStart(2, "0")}-${String(p.day).padStart(2, "0")}T${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

export function formatInTimeZone(value, timeZone, options = {}) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "—";
  return new Intl.DateTimeFormat("ru-RU", { timeZone, ...options }).format(date);
}

export function isValidTimeZone(timeZone) {
  try { new Intl.DateTimeFormat("en-US", { timeZone }).format(new Date(0)); return true; }
  catch { return false; }
}

/** Return the current calendar date in the tenant timezone as YYYY-MM-DD. */
export function dateOnlyInTimeZone(value = new Date(), timeZone = "Europe/Minsk") {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error("Некорректная дата.");
  const p = partsAt(date, timeZone);
  return `${String(p.year).padStart(4, "0")}-${String(p.month).padStart(2, "0")}-${String(p.day).padStart(2, "0")}`;
}

/** Format a SQL DATE without shifting it through a timezone conversion. */
export function formatDateOnly(value, locale = "ru-RU") {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? ""));
  if (!match) return "—";
  const [, year, month, day] = match.map(Number);
  if (!validCalendarDate(year, month, day, 0, 0)) return "—";
  return new Intl.DateTimeFormat(locale, { timeZone: "UTC", dateStyle: "short" }).format(new Date(Date.UTC(year, month - 1, day)));
}

export function isValidDateOnly(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? ""));
  if (!match) return false;
  const [, year, month, day] = match.map(Number);
  return validCalendarDate(year, month, day, 0, 0);
}
