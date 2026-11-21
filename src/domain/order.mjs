export const ORDER_STATUSES = [
  "new", "accepted", "diagnostics", "awaiting_approval", "awaiting_parts",
  "in_progress", "quality_check", "ready", "completed", "cancelled"
];

const transitions = {
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

export function canTransitionOrder(from, to) {
  return Boolean(transitions[from]?.includes(to));
}

export function assertOrderTransition(from, to) {
  if (!canTransitionOrder(from, to)) throw new Error(`Недопустимый переход заказа: ${from} → ${to}`);
}

// All amounts are integer minor units (kopecks), never floating-point BYN.
export function calculateOrderEconomicsMinor({
  laborRevenue = 0, partsRevenue = 0, discounts = 0,
  laborDirectCost = 0, partsPurchaseCost = 0, otherDirectCosts = 0
}) {
  const values = [laborRevenue, partsRevenue, discounts, laborDirectCost, partsPurchaseCost, otherDirectCosts];
  if (values.some(v => !Number.isSafeInteger(v) || v < 0)) throw new Error("Суммы должны быть целыми неотрицательными копейками");
  const revenue = laborRevenue + partsRevenue - discounts;
  const directCosts = laborDirectCost + partsPurchaseCost + otherDirectCosts;
  return { revenue, directCosts, grossProfit: revenue - directCosts };
}

/** Parse a non-negative decimal into integer minor units without binary-float drift. */
export function moneyToMinorUnits(value) {
  const raw = String(value ?? "").trim();
  const match = /^(\d+)(?:\.(\d+))?$/.exec(raw);
  if (!match) throw new Error("Некорректная денежная сумма");
  const fraction = match[2] ?? "";
  const kept = fraction.slice(0, 2).padEnd(2, "0");
  let minor = BigInt(match[1]) * 100n + BigInt(kept || "0");
  if (fraction.length > 2 && Number(fraction[2]) >= 5) minor += 1n;
  if (minor > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Денежная сумма превышает безопасный диапазон");
  return Number(minor);
}

export function sumMoneyMinor(values = []) {
  const total = values.reduce((sum, value) => sum + BigInt(moneyToMinorUnits(value)), 0n);
  if (total > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Сумма превышает безопасный диапазон");
  return Number(total);
}

/**
 * Calculate billed/paid/balance values for an order in integer kopecks.
 * Quantities use the database's three decimal places; prices/allocations use two.
 */
export function calculateOrderFinancialState(lines = [], allocations = []) {
  const totalThousandthMinor = lines.reduce((sum, line) => {
    const quantityRaw = String(line.quantity ?? "").trim();
    const match = /^(\d+)(?:\.(\d+))?$/.exec(quantityRaw);
    if (!match) throw new Error("Некорректное количество в строке заказ-наряда");
    const fraction = match[2] ?? "";
    const kept = fraction.slice(0, 3).padEnd(3, "0");
    let quantityMilli = BigInt(match[1]) * 1000n + BigInt(kept || "0");
    if (fraction.length > 3 && Number(fraction[3]) >= 5) quantityMilli += 1n;
    if (quantityMilli <= 0n) throw new Error("Количество в строке должно быть положительным");
    if (line.unitPrice === null || line.unitPrice === undefined) {
      throw new Error("Для строки заказ-наряда не задана цена клиента");
    }
    const unitPriceMinor = BigInt(moneyToMinorUnits(line.unitPrice));
    return sum + quantityMilli * unitPriceMinor;
  }, 0n);
  const totalMinorBig = (totalThousandthMinor + 500n) / 1000n;
  if (totalMinorBig > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Сумма заказ-наряда превышает безопасный диапазон расчёта");
  const totalMinor = Number(totalMinorBig);
  const paidMinor = sumMoneyMinor(allocations.map(allocation => allocation.amount ?? 0));
  return { totalMinor, paidMinor, balanceMinor: Math.max(0, totalMinor - paidMinor) };
}
