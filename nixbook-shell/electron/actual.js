// nixbook's Actual Budget operations (the `budget` tool of
// nixbook-desktop-mcp), run by the Electron bridge (scripts/electron-bridge.py)
// in Actual's page, through the client Actual itself exposes there:
// window.$send (its backend's handlers, the same ones its own screens and
// its public API use: `api/budget-month`, `api/accounts-get`…) and
// window.$query / window.$q (its query language, AQL). Only the handlers
// named here are ever called (nothing a request says is), and the bridge
// accepts only the operations below.
//
//   nixbookApp(op, args) → a plain object, or {error}
//
// Reading (the `budget` tool): status, accounts, month {month?}, categories
// {query, month?}, transactions {query?, category?, account?, from?, to?,
// limit?} (each with its id), schedules, rules, payees.
// Writing (the `budget_edit` tool), through Actual's public API handlers
// (the ones @actual-app/api uses), and the schedule handlers its own
// screens use where the API has none:
//   transactions: add {account?, date?, amount?, payee?, category?, notes?,
//     cleared?, transfer_to?, splits?: [{amount, category?, notes?}]},
//     update {id, …}, delete {id};
//   budget: set_budget {category, amount, month?}, move_budget {from, to,
//     amount, month?}, set_carryover {category, flag, month?}, hold {amount,
//     month?}, reset_hold {month?};
//   categories: create_category {name, group}, category_update {category,
//     name?, hidden?, group?}, category_delete {category, transfer?},
//     group_create {name, income?}, group_update {group, name?, hidden?},
//     group_delete {group, transfer?};
//   accounts: account_create {name, offbudget?, balance?}, account_update
//     {account, name?, offbudget?}, account_close {account, transfer_account?,
//     transfer_category?}, account_reopen {account}, account_delete {account};
//   payees: payee_create {name}, payee_update {payee, name}, payee_delete
//     {payee}, payee_merge {payee, merge: [names]};
//   schedules: schedule_create {name?, payee?, account?, amount, amount_op?
//     (is|isapprox|isbetween, amount_to), date (one date) or frequency
//     (daily|weekly|monthly|yearly), interval?, start?, end_date?,
//     occurrences?, skip_weekend?, weekend? (before|after), approx_date?,
//     auto_post?}, schedule_update {id, the same}, schedule_delete {id},
//     schedule_skip {id}, schedule_post {id};
//   rules: rule_create {stage?, conditions_op?, conditions: [{field, op,
//     value}], actions: [{field, op?, value}]}, rule_update {id, …},
//     rule_delete {id};
//   sync {} (the sync server), bank_sync {account?};
//   call {handler: "api/…", args}: any other public API handler, as
//     @actual-app/api documents it (ids and cents), but those loading,
//     closing, deleting, importing or downloading a budget file.
// Accounts, categories, groups and payees are given by name, found loosely,
// and refused when unsure (the names given back).
// Amounts are in the budget's currency units (Actual keeps cents: divided
// by 100 here, multiplied back when writing); spending is negative, as in
// Actual.
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

  function cents(v, what) {
    const n = typeof v === "string" ? Number(v.replace(",", ".")) : Number(v);
    if (!Number.isFinite(n) || Math.abs(n) > 1e9)
      throw {
        nixbook: `${what}: a number in the budget's currency (spending negative)`,
      };
    return Math.round(n * 100);
  }
  // The one entry of `list` (id → name) the user meant, or an error naming
  // them: the best score, alone at it.
  function one(list, want, kind) {
    const words = fold(want).split(" ").filter(Boolean);
    const scored = list
      .map((x) => [score(x.name, words), x])
      .filter((x) => x[0] > 0)
      .sort((a, b) => b[0] - a[0]);
    const names = list
      .map((x) => x.name)
      .slice(0, 80)
      .join(", ");
    if (!words.length || !scored.length)
      throw {
        nixbook: `no ${kind} in Actual is called ${JSON.stringify(String(want || ""))}; its ${kind}s: ${names}`,
      };
    if (scored.length > 1 && scored[1][0] === scored[0][0])
      throw {
        nixbook: `${JSON.stringify(String(want))} could be ${scored
          .filter((x) => x[0] === scored[0][0])
          .map((x) => x[1].name)
          .slice(0, 8)
          .join(" or ")}: say which ${kind}`,
      };
    return scored[0][1];
  }
  async function accountFor(want) {
    const open = ((await send("api/accounts-get")) || []).filter(
      (a) => !a.closed,
    );
    if (want) return one(open, want, "account");
    const on = open.filter((a) => !a.offbudget);
    if (on.length === 1) return on[0];
    throw {
      nixbook: `which account? ${open.map((a) => a.name).join(", ")}`,
    };
  }
  async function categoryFor(want) {
    const cats = ((await send("api/categories-get")) || []).filter(
      (c) => !c.hidden,
    );
    return one(cats, want, "category");
  }
  // A payee by name: the existing one (same name, case and accents aside),
  // else created.
  async function payeeFor(name) {
    const want = fold(name);
    const found = ((await send("api/payees-get")) || []).find(
      (p) => fold(p.name) === want && !p.transfer_acct,
    );
    if (found) return found.id;
    return await send("api/payee-create", {
      payee: { name: String(name).trim().slice(0, 100) },
    });
  }
  // The public API's handler, else (an older Actual: "Unknown method") the
  // one its own screens use.
  async function sendFirst(calls) {
    let last;
    for (const [name, args] of calls) {
      try {
        return await send(name, args);
      } catch (e) {
        last = e;
        const m = String((e && (e.message || e.reason)) || e);
        if (!/unknown method|no handler/i.test(m)) throw e;
      }
    }
    throw last;
  }
  async function allAccounts() {
    return (await send("api/accounts-get")) || [];
  }
  async function anyAccountFor(want) {
    return one(await allAccounts(), want, "account");
  }
  async function groupsAll() {
    return (await send("api/category-groups-get")) || [];
  }
  async function groupFor(want) {
    return one(await groupsAll(), want, "group");
  }
  async function payeesAll() {
    return (await send("api/payees-get")) || [];
  }
  async function existingPayee(want) {
    return one(
      (await payeesAll()).filter((p) => !p.transfer_acct),
      want,
      "payee",
    );
  }
  // The payee that moves money to that account (Actual's transfer payee).
  async function transferPayee(account) {
    const p = (await payeesAll()).find((x) => x.transfer_acct === account.id);
    if (!p) throw { nixbook: `no transfer payee for ${account.name}` };
    return p.id;
  }
  function bool(v) {
    return v === true || v === "true";
  }
  // A schedule's date: one day, or how it repeats (Actual's RecurConfig).
  function scheduleDate(o) {
    if (o.frequency === undefined) {
      const d = dateOf(o.date, null);
      if (!d)
        throw {
          nixbook:
            "date (YYYY-MM-DD) for one payment, or frequency (daily, weekly, monthly, yearly)",
        };
      return d;
    }
    const f = String(o.frequency).toLowerCase();
    if (!["daily", "weekly", "monthly", "yearly"].includes(f))
      throw { nixbook: "frequency: daily, weekly, monthly or yearly" };
    const r = {
      frequency: f,
      interval: Math.max(1, Math.min(999, Number(o.interval) || 1)),
      start: dateOf(o.start || o.date, today()),
    };
    if (o.end_date) {
      r.endMode = "on_date";
      r.endDate = dateOf(o.end_date, null);
      if (!r.endDate) throw { nixbook: "end_date: YYYY-MM-DD" };
    } else if (o.occurrences) {
      r.endMode = "after_n_occurrences";
      r.endOccurrences = Math.max(
        1,
        Math.min(9999, Number(o.occurrences) || 1),
      );
    } else r.endMode = "never";
    if (o.skip_weekend !== undefined) r.skipWeekend = bool(o.skip_weekend);
    if (o.weekend)
      r.weekendSolveMode = String(o.weekend) === "before" ? "before" : "after";
    return r;
  }
  function scheduleAmount(o) {
    const op = String(o.amount_op || "is");
    if (!["is", "isapprox", "isbetween"].includes(op))
      throw { nixbook: "amount_op: is, isapprox or isbetween" };
    if (op === "isbetween")
      return [
        op,
        {
          num1: cents(o.amount, "amount"),
          num2: cents(o.amount_to, "amount_to"),
        },
      ];
    return [op, cents(o.amount, "amount")];
  }
  async function scheduleFields(o) {
    const f = {};
    if (o.name !== undefined)
      f.name = String(o.name || "").slice(0, 100) || null;
    if (o.auto_post !== undefined) f.posts_transaction = bool(o.auto_post);
    if (o.completed !== undefined) f.completed = bool(o.completed);
    if (o.payee !== undefined)
      f.payee = o.payee ? await payeeFor(o.payee) : null;
    if (o.account !== undefined)
      f.account = o.account ? (await anyAccountFor(o.account)).id : null;
    if (o.amount !== undefined) [f.amountOp, f.amount] = scheduleAmount(o);
    if (o.date !== undefined || o.frequency !== undefined) {
      f.date = scheduleDate(o);
      f.dateOp = bool(o.approx_date) ? "isapprox" : "is";
    }
    return f;
  }
  // The same as the conditions its own screens save.
  function scheduleConditions(f, old) {
    const conds = (old || []).filter(
      (c) =>
        !["payee", "account", "amount", "date"].includes(c.field) ||
        f[c.field] === undefined,
    );
    if (f.payee) conds.push({ op: "is", field: "payee", value: f.payee });
    if (f.account) conds.push({ op: "is", field: "account", value: f.account });
    if (f.amount !== undefined)
      conds.push({ op: f.amountOp, field: "amount", value: f.amount });
    if (f.date !== undefined)
      conds.push({ op: f.dateOp, field: "date", value: f.date });
    return conds;
  }
  async function schedulesAll() {
    try {
      const r = await send("api/schedules-get");
      if (Array.isArray(r)) return r;
    } catch (e) {
      /* an older Actual: its query */
    }
    const r = await query(q("schedules").select("*"));
    return (r && r.data) || [];
  }
  async function scheduleById(id) {
    const s = (await schedulesAll()).find((x) => x.id === String(id || ""));
    if (!s)
      throw {
        nixbook: `no schedule ${JSON.stringify(String(id || ""))} (its id from budget schedules)`,
      };
    return s;
  }
  // Rule values said by name (payee, category, account) or in units
  // (amount) as Actual keeps them (ids, cents).
  async function ruleItems(list, kind) {
    if (!Array.isArray(list) || !list.length)
      throw { nixbook: `${kind}: a list of {field, op, value}` };
    const payees = await payeesAll();
    const cats = (await send("api/categories-get")) || [];
    const accts = await allAccounts();
    const idOf = (field, v) => {
      if (typeof v !== "string") return v;
      const pool =
        field === "payee"
          ? payees
          : field === "category"
            ? cats
            : field === "account"
              ? accts
              : null;
      if (!pool) return v;
      if (pool.some((x) => x.id === v)) return v;
      return one(pool, v, field).id;
    };
    const out = [];
    for (const it of list.slice(0, 20)) {
      if (!it || typeof it.field !== "string")
        throw { nixbook: `${kind}: each one {field, op, value}` };
      const x = {
        field: it.field,
        op: String(it.op || (kind === "actions" ? "set" : "is")),
      };
      let v = it.value;
      if (it.field === "amount" && typeof v === "number")
        v = Math.round(v * 100);
      else if (Array.isArray(v)) v = v.map((y) => idOf(it.field, y));
      else v = idOf(it.field, v);
      x.value = v;
      if (it.options) x.options = it.options;
      out.push(x);
    }
    return out;
  }

  async function transactionById(id) {
    const r = await query(
      q("transactions")
        .filter({ id: String(id || "") })
        .select([
          "id",
          "date",
          "amount",
          "payee",
          "category",
          "account",
          "notes",
          "cleared",
        ]),
    );
    const t = r && r.data && r.data[0];
    if (!t)
      throw {
        nixbook: `no transaction ${JSON.stringify(String(id || ""))} (its id from budget transactions)`,
      };
    return t;
  }
  function described(t, names) {
    return {
      id: t.id,
      date: t.date,
      amount: money(t.amount),
      payee: names.payee || "",
      category: names.category || "",
      account: names.account || "",
      notes: String(t.notes || "").slice(0, 200),
    };
  }
  async function budgetedOf(month, categoryId) {
    const m = await send("api/budget-month", { month });
    for (const g of m.categoryGroups || [])
      for (const c of g.categories || [])
        if (c.id === categoryId) return c.budgeted || 0;
    return 0;
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
            id: t.id,
            date: t.date,
            amount: money(t.amount),
            payee: payee[t.payee] || "",
            category: category[t.category] || "",
            account: account[t.account] || "",
            notes: String(t.notes || "").slice(0, 200),
          })),
        };
      }
      case "add": {
        const account = await accountFor(o.account);
        const splits = Array.isArray(o.splits) ? o.splits.slice(0, 50) : null;
        const subtransactions = [];
        for (const sp of splits || []) {
          const st = {
            amount: cents(sp && sp.amount, "splits amount"),
            notes: String((sp && sp.notes) || "").slice(0, 500),
          };
          if (sp && sp.category)
            st.category = (await categoryFor(sp.category)).id;
          subtransactions.push(st);
        }
        const amount =
          o.amount === undefined && subtransactions.length
            ? subtransactions.reduce((a, b) => a + b.amount, 0)
            : cents(o.amount, "amount");
        if (
          subtransactions.length &&
          subtransactions.reduce((a, b) => a + b.amount, 0) !== amount
        )
          throw { nixbook: "the splits must add up to the amount" };
        const date = dateOf(o.date, today());
        const tx = { date, amount, notes: String(o.notes || "").slice(0, 500) };
        if (subtransactions.length) tx.subtransactions = subtransactions;
        if (o.cleared !== undefined) tx.cleared = o.cleared === true;
        const names = { account: account.name };
        if (o.transfer_to) {
          const to = await anyAccountFor(o.transfer_to);
          if (to.id === account.id)
            throw { nixbook: "a transfer goes to another account" };
          tx.payee = await transferPayee(to);
          names.payee = `transfer to ${to.name}`;
        }
        if (o.category) {
          const c = await categoryFor(o.category);
          tx.category = c.id;
          names.category = c.name;
        }
        if (o.payee && !o.transfer_to) {
          tx.payee_name = String(o.payee).trim().slice(0, 100);
          names.payee = tx.payee_name;
        }
        // Its id, for an update: the one like it that wasn't there before.
        const alike = async () => {
          const r = await query(
            q("transactions")
              .filter({ account: account.id, date, amount })
              .select(["id", "date", "amount", "notes"]),
          );
          return (r && r.data) || [];
        };
        const before = new Set((await alike()).map((x) => x.id));
        await send("api/transactions-add", {
          accountId: account.id,
          transactions: [tx],
          runTransfers: !!o.transfer_to,
        });
        const t = (await alike()).find((x) => !before.has(x.id)) || {
          date,
          amount,
        };
        return { currency: cur, added: described(t, names) };
      }
      case "update": {
        const t = await transactionById(o.id);
        const fields = {};
        if (o.date !== undefined) {
          const d = dateOf(o.date, null);
          if (!d) throw { nixbook: "date: YYYY-MM-DD" };
          fields.date = d;
        }
        if (o.amount !== undefined) fields.amount = cents(o.amount, "amount");
        if (o.notes !== undefined)
          fields.notes = String(o.notes || "").slice(0, 500);
        if (o.cleared !== undefined) fields.cleared = o.cleared === true;
        if (o.category !== undefined)
          fields.category = o.category
            ? (await categoryFor(o.category)).id
            : null;
        if (o.payee !== undefined)
          fields.payee = o.payee ? await payeeFor(o.payee) : null;
        if (!Object.keys(fields).length)
          throw {
            nixbook:
              "nothing to change: date, amount, payee, category, notes or cleared",
          };
        await send("api/transaction-update", { id: t.id, fields });
        return { currency: cur, updated: t.id, changed: Object.keys(fields) };
      }
      case "delete": {
        const t = await transactionById(o.id);
        await send("api/transaction-delete", { id: t.id });
        return {
          currency: cur,
          deleted: { id: t.id, date: t.date, amount: money(t.amount) },
        };
      }
      case "set_budget": {
        const month = monthOf(o.month);
        const c = await categoryFor(o.category);
        const amount = cents(o.amount, "amount");
        const before = await budgetedOf(month, c.id);
        await send("api/budget-set-amount", {
          month,
          categoryId: c.id,
          amount,
        });
        return {
          currency: cur,
          month,
          category: c.name,
          budgeted: money(amount),
          before: money(before),
        };
      }
      case "move_budget": {
        const month = monthOf(o.month);
        const amount = cents(o.amount, "amount");
        if (amount <= 0) throw { nixbook: "amount: what to move, positive" };
        const from = await categoryFor(o.from);
        const to = await categoryFor(o.to);
        if (from.id === to.id)
          throw { nixbook: "from and to are the same category" };
        const a = await budgetedOf(month, from.id);
        const b = await budgetedOf(month, to.id);
        await send("api/budget-set-amount", {
          month,
          categoryId: from.id,
          amount: a - amount,
        });
        await send("api/budget-set-amount", {
          month,
          categoryId: to.id,
          amount: b + amount,
        });
        return {
          currency: cur,
          month,
          moved: money(amount),
          from: { category: from.name, budgeted: money(a - amount) },
          to: { category: to.name, budgeted: money(b + amount) },
        };
      }
      case "create_category": {
        const name = String(o.name || "")
          .trim()
          .slice(0, 100);
        if (!name) throw { nixbook: "name: the new category's" };
        const groups = (await send("api/category-groups-get")) || [];
        const g = one(groups, o.group, "group");
        const existing = (g.categories || []).find(
          (c) => fold(c.name) === fold(name),
        );
        if (existing)
          return {
            currency: cur,
            exists: { id: existing.id, name: existing.name, group: g.name },
          };
        const id = await send("api/category-create", {
          category: { name, group_id: g.id, is_income: !!g.is_income },
        });
        return { currency: cur, created: { id, name, group: g.name } };
      }
      // -- reading: schedules, rules, payees ----------------------------
      case "schedules": {
        const [list, payees, accts] = await Promise.all([
          schedulesAll(),
          payeesAll(),
          allAccounts(),
        ]);
        const name = (pool, id) =>
          (pool.find((x) => x.id === id) || {}).name || "";
        return {
          currency: cur,
          schedules: list.slice(0, 200).map((x) => {
            const amount = x.amount !== undefined ? x.amount : x._amount;
            const date = x.date !== undefined ? x.date : x._date;
            return {
              id: x.id,
              name: x.name || "",
              next_date: x.next_date || "",
              completed: !!x.completed,
              auto_post: !!x.posts_transaction,
              payee: name(payees, x.payee !== undefined ? x.payee : x._payee),
              account: name(
                accts,
                x.account !== undefined ? x.account : x._account,
              ),
              amount_op: x.amountOp || x._amountOp || "is",
              amount:
                amount && typeof amount === "object"
                  ? { from: money(amount.num1), to: money(amount.num2) }
                  : money(amount),
              date,
            };
          }),
        };
      }
      case "rules": {
        const rules = (await send("api/rules-get")) || [];
        return { currency: cur, rules: rules.slice(0, 200) };
      }
      case "payees": {
        const words = fold(o.query).split(" ").filter(Boolean);
        const accts = await allAccounts();
        return {
          payees: (await payeesAll())
            .filter((p) => !words.length || score(p.name, words) > 0)
            .slice(0, 300)
            .map((p) => ({
              id: p.id,
              name: p.name,
              transfer: p.transfer_acct
                ? (accts.find((a) => a.id === p.transfer_acct) || {}).name ||
                  true
                : undefined,
            })),
        };
      }

      // -- budget ----------------------------------------------------------
      case "set_carryover": {
        const month = monthOf(o.month);
        const c = await categoryFor(o.category);
        await send("api/budget-set-carryover", {
          month,
          categoryId: c.id,
          flag: bool(o.flag),
        });
        return { month, category: c.name, carryover: bool(o.flag) };
      }
      case "hold": {
        const month = monthOf(o.month);
        const amount = cents(o.amount, "amount");
        await send("api/budget-hold-for-next-month", { month, amount });
        return { currency: cur, month, held: money(amount) };
      }
      case "reset_hold": {
        const month = monthOf(o.month);
        await send("api/budget-reset-hold", { month });
        return { month, hold: "reset" };
      }

      // -- categories and groups -------------------------------------------
      case "category_update": {
        const c = await categoryFor(o.category);
        const fields = {};
        if (o.name) fields.name = String(o.name).trim().slice(0, 100);
        if (o.hidden !== undefined) fields.hidden = bool(o.hidden);
        if (o.group) fields.group_id = (await groupFor(o.group)).id;
        if (!Object.keys(fields).length)
          throw { nixbook: "nothing to change: name, hidden or group" };
        await send("api/category-update", { id: c.id, fields });
        return { category: c.name, changed: Object.keys(fields) };
      }
      case "category_delete": {
        const c = await categoryFor(o.category);
        const transfer = o.transfer ? (await categoryFor(o.transfer)).id : null;
        await send("api/category-delete", {
          id: c.id,
          transferCategoryId: transfer,
        });
        return { deleted: c.name, budgetMovedTo: o.transfer || null };
      }
      case "group_create": {
        const name = String(o.name || "")
          .trim()
          .slice(0, 100);
        if (!name) throw { nixbook: "name: the new group's" };
        const existing = (await groupsAll()).find(
          (g) => fold(g.name) === fold(name),
        );
        if (existing)
          return { exists: { id: existing.id, name: existing.name } };
        const id = await send("api/category-group-create", {
          group: { name, is_income: bool(o.income) },
        });
        return { created: { id, name } };
      }
      case "group_update": {
        const g = await groupFor(o.group);
        const fields = {};
        if (o.name) fields.name = String(o.name).trim().slice(0, 100);
        if (o.hidden !== undefined) fields.hidden = bool(o.hidden);
        if (!Object.keys(fields).length)
          throw { nixbook: "nothing to change: name or hidden" };
        await send("api/category-group-update", { id: g.id, fields });
        return { group: g.name, changed: Object.keys(fields) };
      }
      case "group_delete": {
        const g = await groupFor(o.group);
        const transfer = o.transfer ? (await categoryFor(o.transfer)).id : null;
        await send("api/category-group-delete", {
          id: g.id,
          transferCategoryId: transfer,
        });
        return { deleted: g.name, budgetMovedTo: o.transfer || null };
      }

      // -- accounts --------------------------------------------------------
      case "account_create": {
        const name = String(o.name || "")
          .trim()
          .slice(0, 100);
        if (!name) throw { nixbook: "name: the new account's" };
        const existing = (await allAccounts()).find(
          (a) => fold(a.name) === fold(name) && !a.closed,
        );
        if (existing)
          return { exists: { id: existing.id, name: existing.name } };
        const id = await send("api/account-create", {
          account: { name, offbudget: bool(o.offbudget) },
          initialBalance:
            o.balance === undefined ? null : cents(o.balance, "balance"),
        });
        return {
          currency: cur,
          created: { id, name, offBudget: bool(o.offbudget) },
        };
      }
      case "account_update": {
        const a = await anyAccountFor(o.account);
        const fields = {};
        if (o.name) fields.name = String(o.name).trim().slice(0, 100);
        if (o.offbudget !== undefined) fields.offbudget = bool(o.offbudget);
        if (!Object.keys(fields).length)
          throw { nixbook: "nothing to change: name or offbudget" };
        await send("api/account-update", { id: a.id, fields });
        return { account: a.name, changed: Object.keys(fields) };
      }
      case "account_close": {
        const a = await anyAccountFor(o.account);
        const ta = o.transfer_account
          ? (await anyAccountFor(o.transfer_account)).id
          : null;
        const tc = o.transfer_category
          ? (await categoryFor(o.transfer_category)).id
          : null;
        await send("api/account-close", {
          id: a.id,
          transferAccountId: ta,
          transferCategoryId: tc,
        });
        return { closed: a.name };
      }
      case "account_reopen": {
        const a = await anyAccountFor(o.account);
        await send("api/account-reopen", { id: a.id });
        return { reopened: a.name };
      }
      case "account_delete": {
        const a = await anyAccountFor(o.account);
        await send("api/account-delete", { id: a.id });
        return { deleted: a.name };
      }

      // -- payees ----------------------------------------------------------
      case "payee_create": {
        const name = String(o.name || "")
          .trim()
          .slice(0, 100);
        if (!name) throw { nixbook: "name: the new payee's" };
        return { payee: { id: await payeeFor(name), name } };
      }
      case "payee_update": {
        const p = await existingPayee(o.payee);
        const name = String(o.name || "")
          .trim()
          .slice(0, 100);
        if (!name) throw { nixbook: "name: the payee's new name" };
        await send("api/payee-update", { id: p.id, fields: { name } });
        return { renamed: p.name, to: name };
      }
      case "payee_delete": {
        const p = await existingPayee(o.payee);
        await send("api/payee-delete", { id: p.id });
        return { deleted: p.name };
      }
      case "payee_merge": {
        const target = await existingPayee(o.payee);
        const merge = [];
        for (const m of Array.isArray(o.merge) ? o.merge.slice(0, 50) : []) {
          const p = await existingPayee(m);
          if (p.id !== target.id) merge.push(p);
        }
        if (!merge.length)
          throw { nixbook: "merge: the payees to fold into it, by name" };
        await send("api/payees-merge", {
          targetId: target.id,
          mergeIds: merge.map((p) => p.id),
        });
        return { into: target.name, merged: merge.map((p) => p.name) };
      }

      // -- schedules -------------------------------------------------------
      case "schedule_create": {
        const f = await scheduleFields(o);
        if (f.amount === undefined)
          throw { nixbook: "amount: the payment's (spending negative)" };
        if (f.date === undefined)
          throw {
            nixbook: "date (one payment) or frequency (a repeating one)",
          };
        const ext = {
          name: f.name || null,
          posts_transaction: !!f.posts_transaction,
          payee: f.payee || null,
          account: f.account || null,
          amount: f.amount,
          amountOp: f.amountOp,
          date: f.date,
        };
        const id = await sendFirst([
          ["api/schedule-create", ext],
          [
            "schedule/create",
            {
              schedule: {
                name: ext.name,
                posts_transaction: ext.posts_transaction,
              },
              conditions: scheduleConditions(f, []),
            },
          ],
        ]);
        return { currency: cur, created: { id, name: ext.name || "" } };
      }
      case "schedule_update": {
        const old = await scheduleById(o.id);
        const f = await scheduleFields(o);
        if (!Object.keys(f).length) throw { nixbook: "nothing to change" };
        const fields = { ...f };
        delete fields.dateOp;
        await sendFirst([
          [
            "api/schedule-update",
            { id: old.id, fields, resetNextDate: f.date !== undefined },
          ],
          [
            "schedule/update",
            {
              schedule: {
                id: old.id,
                ...(f.name !== undefined ? { name: f.name } : {}),
                ...(f.posts_transaction !== undefined
                  ? { posts_transaction: f.posts_transaction }
                  : {}),
                ...(f.completed !== undefined
                  ? { completed: f.completed }
                  : {}),
              },
              conditions: scheduleConditions(f, old._conditions),
              resetNextDate: f.date !== undefined,
            },
          ],
        ]);
        return { updated: old.id, changed: Object.keys(fields) };
      }
      case "schedule_delete": {
        const old = await scheduleById(o.id);
        await sendFirst([
          ["api/schedule-delete", old.id],
          ["schedule/delete", { id: old.id }],
        ]);
        return { deleted: { id: old.id, name: old.name || "" } };
      }
      case "schedule_skip": {
        const old = await scheduleById(o.id);
        await send("schedule/skip-next-date", { id: old.id });
        return { skipped: old.id, was: old.next_date || "" };
      }
      case "schedule_post": {
        const old = await scheduleById(o.id);
        await send("schedule/post-transaction", { id: old.id });
        return { posted: old.id };
      }

      // -- rules -----------------------------------------------------------
      case "rule_create":
      case "rule_update": {
        const rule = {
          stage: o.stage === "pre" || o.stage === "post" ? o.stage : null,
          conditionsOp: o.conditions_op === "or" ? "or" : "and",
          conditions: await ruleItems(o.conditions, "conditions"),
          actions: await ruleItems(o.actions, "actions"),
        };
        if (op === "rule_update") {
          if (!o.id) throw { nixbook: "id: the rule's (budget rules)" };
          rule.id = String(o.id);
          await send("api/rule-update", { rule });
          return { updated: rule.id };
        }
        const r = await send("api/rule-create", { rule });
        return { created: (r && r.id) || r };
      }
      case "rule_delete": {
        if (!o.id) throw { nixbook: "id: the rule's (budget rules)" };
        await send("api/rule-delete", String(o.id));
        return { deleted: String(o.id) };
      }

      // -- sync ------------------------------------------------------------
      case "sync": {
        await send("api/sync");
        return { synced: true };
      }
      case "bank_sync": {
        const a = o.account ? await anyAccountFor(o.account) : null;
        await send("api/bank-sync", a ? { accountId: a.id } : {});
        return { bankSynced: a ? a.name : "every linked account" };
      }

      // -- any other public API handler -----------------------------------
      case "call": {
        const h = String(o.handler || "");
        if (!/^api\/[a-z][a-z-]{1,60}$/.test(h))
          throw {
            nixbook:
              "handler: an `api/…` handler of Actual's public API (e.g. api/transactions-get)",
          };
        if (
          /budget-?(load|close|delete|download|create)|(^|\/|-)(load|download|close|delete|create)-budget|import|batch|init|shutdown/.test(
            h,
          )
        )
          throw { nixbook: `refused: ${h} acts on the budget file itself` };
        const r = await send(h, o.args === undefined ? undefined : o.args);
        return { handler: h, result: r === undefined ? null : r };
      }
      default:
        return { error: `unknown operation ${op}` };
    }
  } catch (e) {
    if (e && typeof e.nixbook === "string") return { error: e.nixbook };
    const msg =
      (e && (e.message || e.reason)) ||
      (typeof e === "string" ? e : JSON.stringify(e));
    return { error: `Actual said: ${String(msg)}`.slice(0, 300) };
  }
}
