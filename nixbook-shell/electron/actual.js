// nixbook's Actual Budget operations (the `budget` tool of
// nixbook-desktop-mcp), run by the Electron bridge (scripts/electron-bridge.py)
// in Actual's page, through the client Actual itself exposes there:
// window.$send (its backend's handlers, the same ones its own screens and
// its public API use: `api/budget-month`, `api/accounts-get`…) and
// window.$query / window.$q (its query language, AQL). READ-ONLY: only
// handlers that read are named here (nothing a request says is ever called;
// no `api/*-update`, `-create`, `-delete`, no budget-set, no sync), and the
// bridge accepts only the operations below.
//
//   nixbookApp(op, args) → a plain object, or {error}
//
// Operations: status, accounts, month {month?}, categories {query, month?},
// transactions {query?, category?, account?, from?, to?, limit?}.
// Amounts are in the budget's currency units (Actual keeps cents: divided
// by 100 here); spending is negative, as in Actual.
"use strict";

async function nixbookApp(op, o) {
  const send = globalThis.$send;
  const query = globalThis.$query;
  const q = globalThis.$q;
  if (
    typeof send !== "function" ||
    typeof query !== "function" ||
    typeof q !== "function"
  )
    return {
      error:
        "Actual is still loading (its client isn't ready): try again in a moment",
    };
  o = o || {};

  function fold(s) {
    return String(s || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .trim();
  }
  function money(cents) {
    const n = Number(cents);
    return Number.isFinite(n) ? Math.round(n) / 100 : 0;
  }
  function pad(n) {
    return String(n).padStart(2, "0");
  }
  function today() {
    const d = new Date();
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }
  function thisMonth() {
    return today().slice(0, 7);
  }
  function monthOf(s) {
    const m = /^(\d{4})-(\d{2})$/.exec(String(s || "").trim());
    return m ? `${m[1]}-${m[2]}` : thisMonth();
  }
  function dateOf(s, fallback) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || "").trim());
    return m ? m[0] : fallback;
  }
  // A name matching the words asked: all of them, else one of them (a
  // category "Food & dining" for "food"; "groceries" for "grocery").
  function score(name, words) {
    const n = fold(name);
    if (!n || !words.length) return 0;
    const whole = words.join(" ");
    if (n === whole) return 4;
    if (n.includes(whole) || (whole.includes(n) && n.length >= 3)) return 3;
    const nw = n.split(" ");
    // The same word, or its stem (grocery / groceries, restaurant / restaurants).
    const stem = (a, b) => {
      let k = 0;
      while (k < a.length && k < b.length && a[k] === b[k]) k++;
      return k >= 4 && k >= Math.min(a.length, b.length) - 2;
    };
    const hit = (w) => nw.some((x) => x === w || stem(x, w));
    const hits = words.filter(hit).length;
    return hits === words.length ? 2 : hits ? 1 : 0;
  }
  async function opened() {
    try {
      const prefs = await send("load-prefs");
      return prefs && prefs.id ? prefs : null;
    } catch (e) {
      return null;
    }
  }
  async function currency() {
    try {
      const r = await query(
        q("preferences").filter({ id: "defaultCurrencyCode" }).select("*"),
      );
      return (r && r.data && r.data[0] && r.data[0].value) || "";
    } catch (e) {
      return "";
    }
  }
  async function monthSummary(month) {
    const m = await send("api/budget-month", { month });
    const groups = (m.categoryGroups || []).map((g) => ({
      id: g.id,
      name: g.name,
      income: !!g.is_income,
      hidden: !!g.hidden,
      budgeted: money(g.budgeted),
      spent: money(g.is_income ? g.received : g.spent),
      balance: money(g.balance),
      categories: (g.categories || []).map((c) => ({
        id: c.id,
        name: c.name,
        hidden: !!c.hidden,
        budgeted: money(c.budgeted),
        spent: money(g.is_income ? c.received : c.spent),
        balance: money(c.balance),
      })),
    }));
    return {
      month: m.month || month,
      income: money(m.totalIncome),
      budgeted: money(m.totalBudgeted),
      spent: money(m.totalSpent),
      balance: money(m.totalBalance),
      toBudget: money(m.toBudget),
      groups,
    };
  }

  try {
    if (op === "status") {
      const prefs = await opened();
      const out = {
        ready: true,
        open: !!prefs,
        budget: prefs ? prefs.budgetName || "" : "",
      };
      if (prefs) {
        try {
          const b = await send("get-budget-bounds");
          if (b) out.months = { first: b.start, last: b.end };
        } catch (e) {
          /* an old budget without bounds: left out */
        }
        out.currency = await currency();
      }
      return out;
    }
    if (!(await opened()))
      return {
        error:
          "no budget is open in Actual: ask the user to open theirs (Actual's budget list)",
      };
    const cur = await currency();

    switch (op) {
      case "accounts": {
        const accounts = (await send("api/accounts-get")) || [];
        const out = [];
        for (const a of accounts.slice(0, 100)) {
          const r = await query(
            q("transactions")
              .filter({ account: a.id })
              .calculate({ $sum: "$amount" }),
          );
          out.push({
            id: a.id,
            name: a.name,
            offBudget: !!a.offbudget,
            closed: !!a.closed,
            balance: money(r && r.data),
          });
        }
        return { currency: cur, accounts: out };
      }
      case "month": {
        return { currency: cur, ...(await monthSummary(monthOf(o.month))) };
      }
      case "categories": {
        const words = fold(o.query).split(" ").filter(Boolean);
        const s = await monthSummary(monthOf(o.month));
        const hits = [];
        for (const g of s.groups) {
          const gs = score(g.name, words);
          if (gs)
            hits.push([
              gs + 0.5,
              {
                kind: "group",
                ...g,
                categories: g.categories.map((c) => c.name),
              },
            ]);
          for (const c of g.categories) {
            const cs = score(c.name, words);
            if (cs)
              hits.push([
                cs,
                { kind: "category", group: g.name, income: g.income, ...c },
              ]);
          }
        }
        hits.sort((a, b) => b[0] - a[0]);
        const best = hits.length ? hits[0][0] : 0;
        return {
          currency: cur,
          month: s.month,
          query: String(o.query || ""),
          matches: hits
            .filter((h) => h[0] >= Math.min(best, 2))
            .slice(0, 8)
            .map((h) => h[1]),
          // Nothing matched: the names, to ask again with the right one.
          names: hits.length
            ? undefined
            : s.groups
                .flatMap((g) => [g.name, ...g.categories.map((c) => c.name)])
                .slice(0, 120),
        };
      }
      case "transactions": {
        const month = thisMonth();
        const from = dateOf(o.from, `${month}-01`);
        const to = dateOf(o.to, today());
        const limit = Math.max(1, Math.min(100, Number(o.limit) || 20));
        const [payees, categories, accounts] = await Promise.all([
          send("api/payees-get"),
          send("api/categories-get"),
          send("api/accounts-get"),
        ]);
        const names = (list) => {
          const m = {};
          for (const x of list || []) m[x.id] = x.name;
          return m;
        };
        const payee = names(payees);
        const category = names(categories);
        const account = names(accounts);
        // Only the categories / account asked for (by name).
        const pick = (map, want) => {
          const words = fold(want).split(" ").filter(Boolean);
          if (!words.length) return null;
          const scored = Object.keys(map)
            .map((id) => [score(map[id], words), id])
            .filter((x) => x[0] > 0);
          const best = Math.max(0, ...scored.map((x) => x[0]));
          return new Set(
            scored.filter((x) => x[0] >= Math.min(best, 2)).map((x) => x[1]),
          );
        };
        const cats = pick(category, o.category);
        const accts = pick(account, o.account);
        if (cats && !cats.size)
          return {
            error: `no category in Actual is called ${JSON.stringify(String(o.category))}`,
          };
        if (accts && !accts.size)
          return {
            error: `no account in Actual is called ${JSON.stringify(String(o.account))}`,
          };
        const r = await query(
          q("transactions")
            .filter({
              $and: [{ date: { $gte: from } }, { date: { $lte: to } }],
            })
            .select([
              "id",
              "date",
              "amount",
              "payee",
              "category",
              "account",
              "notes",
            ])
            .orderBy({ date: "desc" })
            .limit(5000),
        );
        const words = fold(o.query).split(" ").filter(Boolean);
        const rows = ((r && r.data) || []).filter((t) => {
          if (cats && !cats.has(t.category)) return false;
          if (accts && !accts.has(t.account)) return false;
          if (!words.length) return true;
          const hay = fold(
            [payee[t.payee], t.notes, category[t.category]].join(" "),
          );
          return words.every((w) => hay.includes(w));
        });
        let total = 0;
        let spent = 0;
        let received = 0;
        for (const t of rows) {
          total += t.amount || 0;
          if ((t.amount || 0) < 0) spent += t.amount;
          else received += t.amount || 0;
        }
        return {
          currency: cur,
          from,
          to,
          count: rows.length,
          total: money(total),
          spent: money(spent),
          received: money(received),
          categories: cats ? [...cats].map((id) => category[id]) : undefined,
          accounts: accts ? [...accts].map((id) => account[id]) : undefined,
          transactions: rows.slice(0, limit).map((t) => ({
            date: t.date,
            amount: money(t.amount),
            payee: payee[t.payee] || "",
            category: category[t.category] || "",
            account: account[t.account] || "",
            notes: String(t.notes || "").slice(0, 200),
          })),
        };
      }
      default:
        return { error: `unknown operation ${op}` };
    }
  } catch (e) {
    const msg =
      (e && (e.message || e.reason)) ||
      (typeof e === "string" ? e : JSON.stringify(e));
    return { error: `Actual said: ${String(msg)}`.slice(0, 300) };
  }
}
