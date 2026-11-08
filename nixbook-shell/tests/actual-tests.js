// nixbook's Actual Budget operations (electron/actual.js, the `budget`
// tool's adapter), run here under node against a fake of what Actual's page
// exposes (window.$send, $query, $q): the month's summary, a category found
// by a loose name ("food", "grocery"), transactions searched and summed, the
// accounts' balances, no budget open; the reads call no writing handler,
// and the writes (add, update, delete, set_budget, move_budget,
// create_category) only Actual's public API's. Run by actual.sh.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const code = fs.readFileSync(
  path.join(__dirname, "..", "electron", "actual.js"),
  "utf8",
);
let failures = 0;
function ok(cond, what, detail) {
  if (cond) console.log(`ok   - ${what}`);
  else {
    failures++;
    console.log(
      `FAIL - ${what}${detail !== undefined ? "\n       " + JSON.stringify(detail) : ""}`,
    );
  }
}

// The fake budget (amounts in cents, as Actual keeps them).
const accounts = [
  { id: "a1", name: "Checking", offbudget: false, closed: false },
  { id: "a2", name: "Savings", offbudget: true, closed: false },
];
const payees = [
  { id: "p1", name: "Carrefour" },
  { id: "p2", name: "Le Petit Bistrot" },
  { id: "p3", name: "Employer" },
];
const categories = [
  { id: "c1", name: "Groceries", group_id: "g1" },
  { id: "c2", name: "Restaurants", group_id: "g1" },
  { id: "c3", name: "Rent", group_id: "g2" },
  { id: "c4", name: "Salary", group_id: "g3" },
];
const transactions = [
  {
    id: "t1",
    date: "2026-11-01",
    amount: -4250,
    payee: "p1",
    category: "c1",
    account: "a1",
    notes: "weekly shop",
  },
  {
    id: "t2",
    date: "2026-11-02",
    amount: -2800,
    payee: "p2",
    category: "c2",
    account: "a1",
    notes: "",
  },
  {
    id: "t3",
    date: "2026-10-30",
    amount: -1990,
    payee: "p1",
    category: "c1",
    account: "a1",
    notes: "",
  },
  {
    id: "t4",
    date: "2026-11-01",
    amount: 250000,
    payee: "p3",
    category: "c4",
    account: "a1",
    notes: "november",
  },
  {
    id: "t5",
    date: "2026-11-01",
    amount: 100000,
    payee: null,
    category: null,
    account: "a2",
    notes: "",
  },
];
const month = {
  month: "2026-11",
  totalIncome: 250000,
  totalBudgeted: -180000,
  totalSpent: -7050,
  totalBalance: 172950,
  toBudget: 70000,
  categoryGroups: [
    {
      id: "g1",
      name: "Food",
      is_income: false,
      budgeted: 60000,
      spent: -7050,
      balance: 52950,
      categories: [
        {
          id: "c1",
          name: "Groceries",
          budgeted: 40000,
          spent: -4250,
          balance: 35750,
        },
        {
          id: "c2",
          name: "Restaurants",
          budgeted: 20000,
          spent: -2800,
          balance: 17200,
        },
      ],
    },
    {
      id: "g2",
      name: "Housing",
      is_income: false,
      budgeted: 120000,
      spent: 0,
      balance: 120000,
      categories: [
        { id: "c3", name: "Rent", budgeted: 120000, spent: 0, balance: 120000 },
      ],
    },
    {
      id: "g3",
      name: "Income",
      is_income: true,
      received: 250000,
      categories: [{ id: "c4", name: "Salary", received: 250000 }],
    },
  ],
};

function makeQ(table) {
  const st = {
    table,
    filters: [],
    calc: null,
    sel: null,
    order: null,
    lim: null,
  };
  const api = {
    filter(f) {
      st.filters.push(f);
      return api;
    },
    calculate(c) {
      st.calc = c;
      return api;
    },
    select(s) {
      st.sel = s;
      return api;
    },
    orderBy(o) {
      st.order = o;
      return api;
    },
    limit(n) {
      st.lim = n;
      return api;
    },
    _st: st,
  };
  return api;
}
function matches(t, f) {
  if (f.$and) return f.$and.every((g) => matches(t, g));
  return Object.entries(f).every(([k, v]) => {
    if (v && typeof v === "object") {
      if ("$gte" in v && !(t[k] >= v.$gte)) return false;
      if ("$lte" in v && !(t[k] <= v.$lte)) return false;
      return true;
    }
    return t[k] === v;
  });
}

function sandbox(open = true) {
  const calls = [];
  const writes = [];
  let next = 100;
  const send = async (name, args) => {
    calls.push(name);
    switch (name) {
      case "api/transactions-add":
        writes.push([name, args]);
        for (const t of args.transactions)
          transactions.push({
            id: "t" + next++,
            account: args.accountId,
            payee: null,
            category: null,
            ...t,
          });
        return "ok";
      case "api/transaction-update": {
        writes.push([name, args]);
        Object.assign(
          transactions.find((t) => t.id === args.id),
          args.fields,
        );
        return "ok";
      }
      case "api/transaction-delete":
        writes.push([name, args]);
        transactions.splice(
          transactions.findIndex((t) => t.id === args.id),
          1,
        );
        return "ok";
      case "api/payee-create":
        writes.push([name, args]);
        payees.push({ id: "p" + next, name: args.payee.name });
        return "p" + next++;
      case "api/budget-set-amount":
        writes.push([name, args]);
        for (const g of month.categoryGroups)
          for (const c of g.categories)
            if (c.id === args.categoryId) c.budgeted = args.amount;
        return null;
      case "api/category-groups-get":
        return month.categoryGroups.map((g) => ({
          id: g.id,
          name: g.name,
          is_income: g.is_income,
          categories: g.categories.map((c) => ({ id: c.id, name: c.name })),
        }));
      case "api/category-create":
        writes.push([name, args]);
        return "c" + next++;
      case "load-prefs":
        return open ? { id: "budget-1", budgetName: "Home" } : {};
      case "get-budget-bounds":
        return { start: "2025-01", end: "2027-01" };
      case "api/accounts-get":
        return accounts;
      case "api/payees-get":
        return payees;
      case "api/categories-get":
        return categories;
      case "api/budget-month":
        if (args.month !== "2026-11")
          throw {
            type: "APIError",
            message: "No budget exists for month: " + args.month,
          };
        return month;
      default:
        throw new Error("fake: no handler " + name);
    }
  };
  const query = async (qq) => {
    const st = qq._st;
    calls.push("query:" + st.table);
    if (st.table === "preferences")
      return { data: [{ id: "defaultCurrencyCode", value: "EUR" }] };
    let rows = transactions.filter((t) =>
      st.filters.every((f) => matches(t, f)),
    );
    if (st.calc) return { data: rows.reduce((s, t) => s + t.amount, 0) };
    if (st.order && st.order.date === "desc")
      rows = rows.slice().sort((a, b) => (a.date < b.date ? 1 : -1));
    return { data: rows.slice(0, st.lim || 1e9) };
  };
  const ctx = { $send: send, $query: query, $q: makeQ, console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(code, ctx);
  return { run: (op, args) => ctx.nixbookApp(op, args), calls, writes };
}

(async () => {
  let s = sandbox();
  let r = await s.run("status", {});
  ok(
    r.open === true &&
      r.budget === "Home" &&
      r.currency === "EUR" &&
      r.months.first === "2025-01",
    "status: the open budget",
    r,
  );

  r = await s.run("month", { month: "2026-11" });
  ok(
    r.spent === -70.5 &&
      r.income === 2500 &&
      r.toBudget === 700 &&
      r.currency === "EUR",
    "month: totals in units",
    r,
  );
  ok(
    r.groups[0].categories[0].balance === 357.5,
    "month: per category",
    r.groups[0],
  );
  ok(
    r.groups[2].income && r.groups[2].spent === 2500,
    "month: income group says what came in",
    r.groups[2],
  );

  r = await s.run("categories", { query: "food", month: "2026-11" });
  ok(
    r.matches[0].kind === "group" &&
      r.matches[0].name === "Food" &&
      r.matches[0].spent === -70.5,
    "categories: a group by name",
    r,
  );
  r = await s.run("categories", { query: "grocery", month: "2026-11" });
  ok(
    r.matches.length === 1 &&
      r.matches[0].name === "Groceries" &&
      r.matches[0].balance === 357.5,
    "categories: 'grocery' finds Groceries, what's left",
    r,
  );
  r = await s.run("categories", { query: "holidays", month: "2026-11" });
  ok(
    r.matches.length === 0 && r.names.includes("Rent"),
    "categories: nothing matched, the names given",
    r,
  );
  r = await s.run("categories", { query: "rent", month: "2019-01" });
  ok(
    /No budget exists/.test(r.error || ""),
    "categories: a month without a budget said",
    r,
  );

  r = await s.run("transactions", {
    query: "carrefour",
    from: "2026-10-01",
    to: "2026-11-30",
  });
  ok(
    r.count === 2 &&
      r.spent === -62.4 &&
      r.transactions[0].date === "2026-11-01" &&
      r.transactions[0].payee === "Carrefour" &&
      r.transactions[0].id === "t1",
    "transactions: by payee, newest first, summed, with their ids",
    r,
  );
  r = await s.run("transactions", {
    category: "groceries",
    from: "2026-11-01",
    to: "2026-11-30",
  });
  ok(
    r.count === 1 && r.total === -42.5 && r.categories[0] === "Groceries",
    "transactions: by category and dates",
    r,
  );
  r = await s.run("transactions", {
    category: "pets",
    from: "2026-11-01",
    to: "2026-11-30",
  });
  ok(
    /no category/.test(r.error || ""),
    "transactions: an unknown category said",
    r,
  );
  r = await s.run("transactions", {
    query: "november",
    from: "2026-11-01",
    to: "2026-11-30",
    limit: 1,
  });
  ok(
    r.count === 1 && r.received === 2500 && r.transactions.length === 1,
    "transactions: notes searched too",
    r,
  );

  r = await s.run("accounts", {});
  ok(
    r.accounts.length === 2 &&
      r.accounts[0].balance === 2409.6 &&
      r.accounts[1].offBudget,
    "accounts: balances",
    r,
  );

  r = await s.run("sync", {});
  ok(
    /unknown operation/.test(r.error || ""),
    "an operation not listed: refused",
    r,
  );

  // Reading calls no writing handler.
  const reading = new Set([
    "load-prefs",
    "get-budget-bounds",
    "api/accounts-get",
    "api/payees-get",
    "api/categories-get",
    "api/budget-month",
    "query:preferences",
    "query:transactions",
  ]);
  const others = s.calls.filter((c) => !reading.has(c));
  ok(
    others.length === 0 && s.writes.length === 0,
    "reads: no handler but reading ones",
    others,
  );

  // Writes: Actual's public API only, by names said loosely.
  r = await s.run("add", {
    amount: -12.5,
    payee: "Boulangerie",
    category: "grocery",
    date: "2026-11-05",
    notes: "bread",
  });
  const added = s.writes[0];
  ok(
    added[0] === "api/transactions-add" &&
      added[1].accountId === "a1" &&
      added[1].transactions[0].amount === -1250 &&
      added[1].transactions[0].category === "c1" &&
      added[1].transactions[0].payee_name === "Boulangerie",
    "add: the one on-budget account, cents, the category by a loose name, the payee by name",
    added,
  );
  ok(
    r.added &&
      r.added.id === "t100" &&
      r.added.amount === -12.5 &&
      r.added.category === "Groceries",
    "add: its id said back",
    r,
  );
  r = await s.run("add", { amount: -5, account: "nope" });
  ok(
    /no account in Actual is called "nope"; its accounts: Checking, Savings/.test(
      r.error || "",
    ),
    "add: an unknown account, the names given",
    r,
  );
  r = await s.run("add", { amount: "lots" });
  ok(/amount: a number/.test(r.error || ""), "add: a bad amount refused", r);
  r = await s.run("add", { amount: -5, category: "food" });
  ok(/no category/.test(r.error || ""), "add: a group isn't a category", r);
  r = await s.run("add", { amount: -5, category: "r" });
  ok(
    /no category|could be/.test(r.error || ""),
    "add: a category it can't be sure of refused",
    r,
  );

  r = await s.run("update", {
    id: "t100",
    amount: -13,
    payee: "Paul",
    category: "restaurants",
  });
  const upd = s.writes.find((w) => w[0] === "api/transaction-update");
  ok(
    upd &&
      upd[1].id === "t100" &&
      upd[1].fields.amount === -1300 &&
      upd[1].fields.category === "c2" &&
      upd[1].fields.payee === payees[payees.length - 1].id &&
      s.writes.some(
        (w) => w[0] === "api/payee-create" && w[1].payee.name === "Paul",
      ),
    "update: the fields asked, a new payee created",
    s.writes,
  );
  r = await s.run("update", { id: "t1", payee: "carrefour" });
  ok(
    s.writes.filter((w) => w[0] === "api/payee-create").length === 1 &&
      s.writes[s.writes.length - 1][1].fields.payee === "p1",
    "update: an existing payee reused",
    s.writes,
  );
  r = await s.run("update", { id: "nope", amount: 1 });
  ok(
    /no transaction "nope"/.test(r.error || ""),
    "update: an unknown id said",
    r,
  );
  r = await s.run("update", { id: "t1" });
  ok(
    /nothing to change/.test(r.error || ""),
    "update: nothing to change said",
    r,
  );

  r = await s.run("delete", { id: "t100" });
  ok(
    r.deleted &&
      r.deleted.id === "t100" &&
      !transactions.some((t) => t.id === "t100"),
    "delete: by id, what it was said",
    r,
  );

  r = await s.run("set_budget", {
    category: "groceries",
    amount: 450,
    month: "2026-11",
  });
  ok(
    r.budgeted === 450 && r.before === 400 && r.category === "Groceries",
    "set_budget: in cents, the amount before said",
    r,
  );
  r = await s.run("move_budget", {
    from: "rent",
    to: "restaurants",
    amount: 50,
    month: "2026-11",
  });
  ok(
    r.moved === 50 && r.from.budgeted === 1150 && r.to.budgeted === 250,
    "move_budget: from one category to another",
    r,
  );
  r = await s.run("move_budget", {
    from: "rent",
    to: "rent",
    amount: 5,
    month: "2026-11",
  });
  ok(/same category/.test(r.error || ""), "move_budget: to itself refused", r);

  r = await s.run("create_category", { name: "Coffee", group: "food" });
  ok(
    r.created &&
      r.created.group === "Food" &&
      s.writes.some(
        (w) =>
          w[0] === "api/category-create" && w[1].category.group_id === "g1",
      ),
    "create_category: in the group said",
    r,
  );
  r = await s.run("create_category", { name: "groceries", group: "food" });
  ok(
    r.exists && r.exists.id === "c1",
    "create_category: one already there is said, not doubled",
    r,
  );

  // Only Actual's public API: no sync, no import, no bank, no file.
  const writing = new Set(s.writes.map((w) => w[0]));
  ok(
    [...writing].every((n) => n.startsWith("api/")),
    "writes: through Actual's public API only",
    [...writing],
  );
  const named = [...code.matchAll(/\bsend\(\s*"([^"]+)"/g)].map((m) => m[1]);
  ok(
    named.every(
      (n) =>
        n.startsWith("api/") || n === "load-prefs" || n === "get-budget-bounds",
    ) &&
      !named.some((n) =>
        /sync|import|bank|close|delete-budget|account-(create|update|delete|close)/.test(
          n,
        ),
      ),
    "the code names no sync, import, bank link, account or file handler",
    named,
  );

  s = sandbox(false);
  r = await s.run("status", {});
  ok(r.ready && r.open === false, "status: no budget open", r);
  r = await s.run("month", {});
  ok(/no budget is open/.test(r.error || ""), "no budget open: said", r);

  const ctx = { console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(code, ctx);
  r = await ctx.nixbookApp("status", {});
  ok(
    /still loading/.test(r.error || ""),
    "Actual's client not there yet: said",
    r,
  );

  if (failures) {
    console.log(`${failures} failure(s)`);
    process.exit(1);
  }
})();
