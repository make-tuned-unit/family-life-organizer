async function getBudgetStats(db, groupId, months = 6) {
    const stats = await db.getSpendingStats(groupId, months);
    const budgetVsActual = await db.getBudgetSummary(stats.thisMonth, groupId);

    // Derived figures the iOS Stats view renders as insight cards.
    const series = stats.monthly;
    const curr = series.length ? series[series.length - 1].total : 0;
    const prev = series.length > 1 ? series[series.length - 2].total : 0;
    const momPct = prev > 0 ? Math.round(((curr - prev) / prev) * 100) : null;
    const avg = series.length ? series.reduce((s, m) => s + m.total, 0) / series.length : 0;

    // Run-rate projection for the current month + remaining fixed commitments.
    const now = new Date();
    const dayOfMonth = now.getDate();
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const runRate = dayOfMonth > 0 ? (curr / dayOfMonth) * daysInMonth : curr;
    const projectedMonthEnd = Math.round(Math.max(runRate, curr));

    const overBudget = budgetVsActual.filter(b => b.monthly_limit > 0 && b.spent > b.monthly_limit)
      .map(b => ({ category: b.category, spent: b.spent, limit: b.monthly_limit }));
    const fixed = Math.round(stats.recurringMonthly);
    const variable = Math.round(Math.max(0, curr - fixed));

    return {
      month: stats.thisMonth,
      monthly: series,                 // [{ ym, total }] oldest -> newest
      byCategory: stats.byCategory,    // [{ category, spent }] current month, desc
      budgetVsActual,                  // [{ category, monthly_limit, color, spent }]
      currentTotal: Math.round(curr),
      previousTotal: Math.round(prev),
      momPct,
      trailingAvg: Math.round(avg),
      projectedMonthEnd,
      recurringMonthly: fixed,
      variableThisMonth: variable,
      overBudget,
    };
}
module.exports = { getBudgetStats };
