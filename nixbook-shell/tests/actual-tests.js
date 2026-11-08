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
  { id: "pt2", name: "", transfer_acct: "a2" },
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
  if (open === true) open = {};
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
      // The rest of the public API: recorded, answered like Actual.
      case "api/schedules-get":
        if (open.schedulesApi === false)
          throw { message: "Unknown method: api/schedules-get" };
        return [
          {
            id: "s1",
            name: "Rent",
            next_date: "2026-12-01",
            completed: false,
            posts_transaction: true,
            payee: "p3",
            account: "a1",
            amount: -120000,
            amountOp: "is",
            date: {
              frequency: "monthly",
              interval: 1,
              start: "2026-01-01",
              endMode: "never",
            },
          },
        ];
      case "api/schedule-create":
        if (open.schedulesApi === false)
          throw { message: "Unknown method: api/schedule-create" };
        writes.push([name, args]);
        return "s" + next++;
      case "schedule/create":
        writes.push([name, args]);
        return "s" + next++;
      case "api/rules-get":
        return [
          {
            id: "r1",
            stage: null,
            conditionsOp: "and",
            conditions: [{ field: "payee", op: "is", value: "p1" }],
            actions: [{ field: "category", op: "set", value: "c1" }],
          },
        ];
      case "api/account-create":
        writes.push([name, args]);
        return "a" + next++;
      case "api/rule-create":
        writes.push([name, args]);
        return { id: "r9" };
      case "api/category-group-create":
        writes.push([name, args]);
        return "g" + next++;
      case "api/transactions-get":
        writes.push([name, args]);
        return [];
      case "api/schedule-update":
      case "api/schedule-delete":
      case "schedule/skip-next-date":
      case "schedule/post-transaction":
      case "api/rule-update":
      case "api/rule-delete":
      case "api/budget-set-carryover":
      case "api/budget-hold-for-next-month":
      case "api/budget-reset-hold":
      case "api/category-update":
      case "api/category-delete":
      case "api/category-group-update":
      case "api/category-group-delete":
      case "api/account-update":
      case "api/account-close":
      case "api/account-reopen":
      case "api/account-delete":
      case "api/payee-update":
      case "api/payee-delete":
      case "api/payees-merge":
      case "api/sync":
      case "api/bank-sync":
        writes.push([name, args]);
        return null;
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

  r = await s.run("export_budget", {});
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

  // Transfers and splits.
  s.writes.length = 0;
  r = await s.run("add", { amount: -100, transfer_to: "savings" });
  ok(
    s.writes[0][1].transactions[0].payee === "pt2" &&
      s.writes[0][1].runTransfers === true,
    "add: a transfer, through the account's transfer payee",
    s.writes[0],
  );
  s.writes.length = 0;
  r = await s.run("add", {
    splits: [
      { amount: -30, category: "grocery" },
      { amount: -12, category: "restaurants" },
    ],
    payee: "Market",
  });
  ok(
    s.writes[0][1].transactions[0].amount === -4200 &&
      s.writes[0][1].transactions[0].subtransactions
        .map((x) => x.category)
        .join() === "c1,c2",
    "add: splits, the amount their sum",
    s.writes[0],
  );
  r = await s.run("add", { amount: -50, splits: [{ amount: -30 }] });
  ok(/add up/.test(r.error || ""), "add: splits that don't add up refused", r);

  // Schedules.
  r = await s.run("schedules", {});
  ok(
    r.schedules[0].id === "s1" &&
      r.schedules[0].amount === -1200 &&
      r.schedules[0].payee === "Employer" &&
      r.schedules[0].account === "Checking" &&
      r.schedules[0].date.frequency === "monthly",
    "schedules: listed with names and amounts",
    r,
  );
  s.writes.length = 0;
  r = await s.run("schedule_create", {
    name: "Netflix",
    amount: -13.49,
    payee: "Netflix",
    account: "checking",
    frequency: "monthly",
    start: "2026-11-15",
    skip_weekend: true,
    weekend: "before",
    auto_post: true,
  });
  const sc = s.writes.find((w) => w[0] === "api/schedule-create");
  ok(
    sc &&
      sc[1].amount === -1349 &&
      sc[1].amountOp === "is" &&
      sc[1].account === "a1" &&
      sc[1].date.frequency === "monthly" &&
      sc[1].date.start === "2026-11-15" &&
      sc[1].date.skipWeekend === true &&
      sc[1].date.weekendSolveMode === "before" &&
      sc[1].posts_transaction === true &&
      r.created,
    "schedule_create: through the public API, a monthly one",
    [r, s.writes],
  );
  r = await s.run("schedule_create", {
    amount: -10,
    amount_op: "isbetween",
    amount_to: -20,
    date: "2026-12-24",
  });
  const sb = s.writes.filter((w) => w[0] === "api/schedule-create").pop();
  ok(
    sb[1].amount.num1 === -1000 &&
      sb[1].amount.num2 === -2000 &&
      sb[1].date === "2026-12-24",
    "schedule_create: one date, an amount range",
    sb,
  );
  r = await s.run("schedule_create", { amount: -10 });
  ok(/or frequency/.test(r.error || ""), "schedule_create: no date said", r);
  r = await s.run("schedule_update", { id: "s1", amount: -1250 });
  ok(
    s.writes.some(
      (w) => w[0] === "api/schedule-update" && w[1].fields.amount === -125000,
    ),
    "schedule_update: the fields",
    [r, s.writes],
  );
  r = await s.run("schedule_skip", { id: "s1" });
  ok(
    r.skipped === "s1" &&
      s.writes.some((w) => w[0] === "schedule/skip-next-date"),
    "schedule_skip: its next date",
    r,
  );
  r = await s.run("schedule_post", { id: "s1" });
  ok(
    s.writes.some(
      (w) => w[0] === "schedule/post-transaction" && w[1].id === "s1",
    ),
    "schedule_post: now",
    r,
  );
  r = await s.run("schedule_delete", { id: "nope" });
  ok(
    /no schedule "nope"/.test(r.error || ""),
    "schedule_delete: an unknown id said",
    r,
  );
  r = await s.run("schedule_delete", { id: "s1" });
  ok(
    s.writes.some((w) => w[0] === "api/schedule-delete" && w[1] === "s1"),
    "schedule_delete: by id",
    r,
  );
  // An Actual without the schedules API: the handlers its own screens use.
  const old = sandbox({ schedulesApi: false });
  r = await old.run("schedule_create", {
    amount: -9.99,
    payee: "carrefour",
    frequency: "weekly",
    approx_date: true,
  });
  const internal = old.writes.find((w) => w[0] === "schedule/create");
  ok(
    internal &&
      internal[1].conditions.some(
        (c) =>
          c.field === "date" &&
          c.op === "isapprox" &&
          c.value.frequency === "weekly",
      ) &&
      internal[1].conditions.some(
        (c) => c.field === "amount" && c.value === -999,
      ) &&
      internal[1].conditions.some(
        (c) => c.field === "payee" && c.value === "p1",
      ),
    "schedule_create: an older Actual, schedule/create with its conditions",
    [r, old.writes],
  );

  // Rules: names and units turned into ids and cents.
  r = await s.run("rules", {});
  ok(r.rules[0].id === "r1", "rules: listed", r);
  r = await s.run("rule_create", {
    conditions: [
      { field: "payee", op: "is", value: "carrefour" },
      { field: "amount", op: "lt", value: -100 },
    ],
    actions: [{ field: "category", value: "groceries" }],
  });
  const rc = s.writes.find((w) => w[0] === "api/rule-create");
  ok(
    rc &&
      rc[1].rule.conditions[0].value === "p1" &&
      rc[1].rule.conditions[1].value === -10000 &&
      rc[1].rule.actions[0].op === "set" &&
      rc[1].rule.actions[0].value === "c1" &&
      r.created === "r9",
    "rule_create: payee and category by name, amount in cents",
    [r, rc],
  );
  r = await s.run("rule_delete", { id: "r1" });
  ok(
    s.writes.some((w) => w[0] === "api/rule-delete" && w[1] === "r1"),
    "rule_delete: by id",
    r,
  );

  // Accounts, categories, groups, payees, budget.
  r = await s.run("account_create", {
    name: "Livret A",
    offbudget: true,
    balance: 1500,
  });
  ok(
    s.writes.some(
      (w) =>
        w[0] === "api/account-create" &&
        w[1].account.offbudget === true &&
        w[1].initialBalance === 150000,
    ),
    "account_create: off budget, a starting balance",
    r,
  );
  r = await s.run("account_create", { name: "checking" });
  ok(
    r.exists && r.exists.id === "a1",
    "account_create: one already there said",
    r,
  );
  r = await s.run("account_close", {
    account: "savings",
    transfer_account: "checking",
  });
  ok(
    s.writes.some(
      (w) =>
        w[0] === "api/account-close" &&
        w[1].id === "a2" &&
        w[1].transferAccountId === "a1",
    ),
    "account_close: what's left moved",
    r,
  );
  r = await s.run("account_update", { account: "checking", name: "Main" });
  ok(
    s.writes.some(
      (w) => w[0] === "api/account-update" && w[1].fields.name === "Main",
    ),
    "account_update: renamed",
    r,
  );
  r = await s.run("category_update", {
    category: "rent",
    group: "food",
    hidden: true,
  });
  ok(
    s.writes.some(
      (w) =>
        w[0] === "api/category-update" &&
        w[1].fields.group_id === "g1" &&
        w[1].fields.hidden === true,
    ),
    "category_update: moved and hidden",
    r,
  );
  r = await s.run("category_delete", {
    category: "restaurants",
    transfer: "groceries",
  });
  ok(
    s.writes.some(
      (w) =>
        w[0] === "api/category-delete" &&
        w[1].id === "c2" &&
        w[1].transferCategoryId === "c1",
    ),
    "category_delete: its budget moved",
    r,
  );
  r = await s.run("group_create", { name: "Fun" });
  ok(
    r.created &&
      s.writes.some(
        (w) =>
          w[0] === "api/category-group-create" && w[1].group.name === "Fun",
      ),
    "group_create",
    r,
  );
  r = await s.run("payee_update", {
    payee: "carrefour",
    name: "Carrefour Market",
  });
  ok(
    s.writes.some((w) => w[0] === "api/payee-update" && w[1].id === "p1"),
    "payee_update: renamed",
    r,
  );
  r = await s.run("payee_merge", {
    payee: "carrefour",
    merge: ["Le Petit Bistrot"],
  });
  ok(
    s.writes.some(
      (w) =>
        w[0] === "api/payees-merge" &&
        w[1].targetId === "p1" &&
        w[1].mergeIds[0] === "p2",
    ),
    "payee_merge",
    r,
  );
  r = await s.run("set_carryover", {
    category: "groceries",
    flag: true,
    month: "2026-11",
  });
  ok(
    s.writes.some(
      (w) => w[0] === "api/budget-set-carryover" && w[1].flag === true,
    ),
    "set_carryover",
    r,
  );
  r = await s.run("hold", { amount: 100, month: "2026-11" });
  ok(
    s.writes.some(
      (w) => w[0] === "api/budget-hold-for-next-month" && w[1].amount === 10000,
    ),
    "hold: for next month",
    r,
  );
  r = await s.run("bank_sync", { account: "checking" });
  ok(
    s.writes.some((w) => w[0] === "api/bank-sync" && w[1].accountId === "a1"),
    "bank_sync: one account",
    r,
  );
  r = await s.run("sync", {});
  ok(r.synced && s.writes.some((w) => w[0] === "api/sync"), "sync", r);

  // Any other public API handler, never the budget file.
  r = await s.run("call", {
    handler: "api/transactions-get",
    args: { accountId: "a1" },
  });
  ok(
    r.handler === "api/transactions-get" && Array.isArray(r.result),
    "call: another api/ handler",
    r,
  );
  for (const h of [
    "api/load-budget",
    "api/download-budget",
    "api/close-budget",
    "api/delete-budget",
    "api/transactions-import",
    "load-prefs",
    "api/../x",
  ]) {
    r = await s.run("call", { handler: h });
    ok(/refused|handler:/.test(r.error || ""), `call: ${h} refused`, r);
  }

  // Only Actual's public API: never an import or the budget file.
  const writing = new Set(s.writes.map((w) => w[0]));
  ok(
    [...writing].every(
      (n) => n.startsWith("api/") || n.startsWith("schedule/"),
    ),
    "writes: through Actual's public API (and its schedule handlers) only",
    [...writing],
  );
  const named = [...code.matchAll(/\bsend\(\s*"([^"]+)"/g)].map((m) => m[1]);
  ok(
    named.every(
      (n) =>
        n.startsWith("api/") ||
        n.startsWith("schedule/") ||
        n === "load-prefs" ||
        n === "get-budget-bounds",
    ) &&
      !named.some((n) =>
        /import|load-budget|download-budget|close-budget|delete-budget/.test(n),
      ),
    "the code names no import or budget file handler",
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
