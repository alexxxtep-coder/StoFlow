export function localDateTimeToIso(value: string, timeZone: string): string;
export function toDateTimeLocalValue(value: Date | string | number, timeZone: string): string;
export function formatInTimeZone(value: string | Date | number, timeZone: string, options?: Intl.DateTimeFormatOptions): string;
export function isValidTimeZone(timeZone: string): boolean;
export function formatDateOnly(value: string, locale?: string): string;
export function isValidDateOnly(value: string): boolean;
