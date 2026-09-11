function expandRecurrence(rule, origin, rangeStart, rangeEnd, endDate) {
  const dates = [];
  const originDate = new Date(origin);
  const anchorDay = originDate.getDate();
  const step = { daily: 1, weekly: 7, biweekly: 14 }[rule];
  // Jump close to the requested window: old daily/weekly series must remain
  // visible after their first 400 occurrences without scanning years of days.
  const months = (rangeStart.getFullYear() - originDate.getFullYear()) * 12 + rangeStart.getMonth() - originDate.getMonth();
  const offset = step ? Math.floor((rangeStart - originDate) / (step * 86400000))
    : rule === 'monthly' ? months : rule === 'yearly' ? Math.floor(months / 12) : 0;
  const first = Math.max(1, offset - 1);
  for (let i = first; i < first + 400; i++) {
    let cursor;
    if (step) {
      cursor = new Date(originDate);
      cursor.setDate(originDate.getDate() + i * step);
    } else if (rule === 'monthly' || rule === 'yearly') {
      // Anchor each occurrence to the origin's day-of-month rather than mutating
      // a cursor: setMonth on Jan 31 overflows to Mar 2/3 and the drift compounds
      // forever. Shift from day 1 to avoid overflow, then clamp the anchor day to
      // the target month's length so Jan 31 -> Feb 28/29 -> Mar 31, as expected.
      const monthsToAdd = rule === 'monthly' ? i : i * 12;
      cursor = new Date(originDate);
      cursor.setDate(1);
      cursor.setMonth(originDate.getMonth() + monthsToAdd);
      const daysInMonth = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0).getDate();
      cursor.setDate(Math.min(anchorDay, daysInMonth));
    } else {
      break;
    }
    if (endDate && cursor > endDate) break;
    if (cursor >= rangeEnd) break;
    if (cursor >= rangeStart) dates.push(new Date(cursor));
  }
  return dates;
}

module.exports = { expandRecurrence };
