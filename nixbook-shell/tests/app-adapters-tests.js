// The Electron bridge's adapters for Discord (electron/discord.js), Slack
// (electron/slack.js) and YouTube Music (electron/youtube-music.js), each
// run under node against a fake of what its app's page exposes: Vencord's
// stores and Discord's REST client; Slack's localConfig_v2 and Web API;
// YouTube Music's network manager. What each operation asks of the app,
// and that the generic calls never reach the account's own secrets. Run by
// app-adapters.sh.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const dir = path.join(__dirname, "..", "electron");
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
function load(name, ctx) {
  ctx.globalThis = ctx;
  ctx.console = console;
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(dir, name), "utf8"), ctx);
  return (op, args) => ctx.nixbookApp(op, args);
}

// -- Discord -------------------------------------------------------------------
function discord() {
  const calls = [];
  const me = { id: "100000000000000001", username: "me", globalName: "Me" };
  const alice = {
    id: "100000000000000002",
    username: "alice",
    globalName: "Alice",
  };
  const channels = {
    "200000000000000001": {
      id: "200000000000000001",
      type: 0,
      name: "general",
      guild_id: "300000000000000001",
    },
    "200000000000000002": {
      id: "200000000000000002",
      type: 1,
      recipients: [alice.id],
    },
    "200000000000000003": {
      id: "200000000000000003",
      type: 2,
      name: "Voice",
      guild_id: "300000000000000001",
    },
  };
  const rest = (method) => async (req) => {
    calls.push([
      method,
      req.url,
      req.body,
      req.query,
      req.attachments && req.attachments.length,
    ]);
    if (req.url.endsWith("/pins"))
      return {
        body: [
          {
            id: "400000000000000001",
            author: alice,
            content: "pinned",
            timestamp: "2026-11-08T10:00:00Z",
          },
        ],
      };
    if (req.url.includes("/messages/search"))
      return {
        body: {
          total_results: 1,
          messages: [
            [
              {
                id: "400000000000000002",
                hit: true,
                author: alice,
                content: "found",
                channel_id: "200000000000000001",
                timestamp: "2026-11-08T10:00:00Z",
              },
            ],
          ],
        },
      };
    if (req.url.endsWith("/threads"))
      return { body: { id: "500000000000000001", name: req.body.name } };
    if (method === "post" && req.url.endsWith("/messages"))
      return { body: { id: "400000000000000009" } };
    return { body: {}, status: 200 };
  };
  const selected = [];
  const C = {
    UserStore: {
      getCurrentUser: () => me,
      getUser: (id) => ({ [me.id]: me, [alice.id]: alice })[id],
    },
    ChannelStore: {
      getChannel: (id) => channels[id],
      getSortedPrivateChannels: () => [channels["200000000000000002"]],
      getDMFromUserId: (id) => (id === alice.id ? "200000000000000002" : null),
    },
    GuildStore: {
      getGuild: (id) => ({ id, name: "Friends" }),
      getGuilds: () => ({
        "300000000000000001": { id: "300000000000000001", name: "Friends" },
      }),
    },
    GuildChannelStore: {
      getChannels: () => ({
        SELECTABLE: [{ channel: channels["200000000000000001"] }],
      }),
    },
    SelectedChannelStore: { getChannelId: () => "200000000000000001" },
    RelationshipStore: { getFriendIDs: () => [alice.id] },
    PresenceStore: { getStatus: () => "online" },
    GuildMemberStore: { getMembers: () => [{ userId: alice.id, nick: "Ali" }] },
    RestAPI: {
      get: rest("get"),
      post: rest("post"),
      put: rest("put"),
      patch: rest("patch"),
      del: rest("del"),
    },
    NavigationRouter: { transitionTo: (p) => calls.push(["nav", p]) },
  };
  const voice = { selectVoiceChannel: (id) => selected.push(id) };
  const ctx = {
    Vencord: {
      Webpack: {
        Common: C,
        findByProps: (...n) => (n[0] === "selectVoiceChannel" ? voice : null),
      },
      Util: {
        sendMessage: async () => ({ body: { id: "400000000000000008" } }),
      },
    },
    File: class {
      constructor(parts, name) {
        this.name = name;
        this.size = parts[0].length;
      }
    },
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
  };
  return { run: load("discord.js", ctx), calls, selected };
}

// -- Slack ---------------------------------------------------------------------
function slack() {
  const calls = [];
  const users = [
    { id: "U0000001", name: "me", profile: { display_name: "Me" } },
    {
      id: "U0000002",
      name: "bob",
      profile: { display_name: "Bob", real_name: "Bob Martin" },
    },
  ];
  const chans = [
    { id: "C0000001", name: "general" },
    { id: "D0000001", is_im: true, user: "U0000002" },
  ];
  const answers = {
    "auth.test": { user_id: "U0000001", team: "Acme" },
    "users.list": { members: users },
    "conversations.list": { channels: chans },
    "conversations.history": {
      messages: [
        { ts: "1762600000.000200", user: "U0000002", text: "hi" },
        { ts: "1762600000.000100", user: "U0000001", text: "yo" },
      ],
    },
    "conversations.replies": {
      messages: [
        {
          ts: "1762600000.000100",
          user: "U0000001",
          text: "yo",
          reply_count: 1,
        },
      ],
    },
    "conversations.open": { channel: { id: "D0000001" } },
    "chat.postMessage": { ts: "1762600001.000100", channel: "C0000001" },
    "chat.update": { ts: "1762600000.000100" },
    "search.messages": {
      messages: {
        total: 1,
        matches: [
          {
            ts: "1",
            channel: { id: "C0000001", name: "general" },
            username: "bob",
            text: "deploy",
          },
        ],
      },
    },
    "files.getUploadURLExternal": {
      upload_url: "https://files.slack.test/upload/1",
      file_id: "F0001",
    },
    "conversations.create": { channel: { id: "C0000009", name: "new-one" } },
    "bookmarks.list": { bookmarks: [] },
  };
  const storage = {
    localConfig_v2: JSON.stringify({
      lastActiveTeamId: "T1",
      teams: {
        T1: {
          id: "T1",
          name: "Acme",
          domain: "acme",
          url: "https://acme.slack.com/",
          token: "xoxc-secret",
          user_id: "U0000001",
        },
      },
    }),
  };
  class FormData {
    constructor() {
      this.m = {};
    }
    append(k, v) {
      this.m[k] = v;
    }
  }
  const ctx = {
    localStorage: { getItem: (k) => storage[k] || null },
    FormData,
    Blob: class {
      constructor(p) {
        this.size = p[0].length;
      }
    },
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
    fetch: async (url, init) => {
      if (url.startsWith("https://files.slack.test/")) {
        calls.push(["upload", init.body.size]);
        return { ok: true, status: 200 };
      }
      const method = url.replace("https://acme.slack.com/api/", "");
      calls.push([method, init.body.m, init.credentials]);
      const a = answers[method];
      return {
        status: 200,
        json: async () => (a === undefined ? { ok: true } : { ok: true, ...a }),
      };
    },
  };
  return { run: load("slack.js", ctx), calls };
}

// -- YouTube Music -------------------------------------------------------------
function ytm() {
  const calls = [];
  const item = (title, videoId, setVideoId) => ({
    musicResponsiveListItemRenderer: {
      flexColumns: [
        {
          musicResponsiveListItemFlexColumnRenderer: {
            text: { runs: [{ text: title }] },
          },
        },
        {
          musicResponsiveListItemFlexColumnRenderer: {
            text: { runs: [{ text: "Artist" }] },
          },
        },
      ],
      playlistItemData: { videoId, playlistSetVideoId: setVideoId },
    },
  });
  const pl = (title, id) => ({
    musicTwoRowItemRenderer: {
      title: { runs: [{ text: title }] },
      navigationEndpoint: { browseEndpoint: { browseId: id } },
    },
  });
  const answer = (ep, body) => {
    if (ep === "/browse" && body.browseId === "FEmusic_liked_playlists")
      return {
        contents: [
          pl("Liked Music", "VLLM"),
          pl("Road trip", "VLPLroad1234"),
          pl("Chill", "VLPLchill123"),
        ],
      };
    if (ep === "/browse" && body.browseId === "VLPLroad1234")
      return {
        header: {
          musicResponsiveHeaderRenderer: {
            title: { runs: [{ text: "Road trip" }] },
          },
        },
        contents: [
          item("Song A", "aaaaaaaaaaa", "S1"),
          item("Song B", "bbbbbbbbbbb", "S2"),
        ],
      };
    if (ep === "/playlist/create") return { playlistId: "PLnew12345" };
    return { status: "STATUS_SUCCEEDED" };
  };
  const ctx = {
    document: {
      querySelector: () => ({
        networkManager: {
          fetch: async (ep, body) => (calls.push([ep, body]), answer(ep, body)),
        },
      }),
    },
    ytcfg: { get: (k) => (k === "LOGGED_IN" ? true : undefined) },
  };
  return { run: load("youtube-music.js", ctx), calls };
}

(async () => {
  // Discord.
  let d = discord();
  let r = await d.run("edit", {
    channel: "general",
    message: "400000000000000001",
    content: "fixed",
  });
  ok(
    r.edited &&
      d.calls.some(
        (c) =>
          c[0] === "patch" &&
          c[1] === "/channels/200000000000000001/messages/400000000000000001" &&
          c[2].content === "fixed",
      ),
    "discord edit: PATCH the message",
    d.calls,
  );
  r = await d.run("delete", {
    channel: "general",
    message: "400000000000000001",
  });
  ok(
    r.deleted &&
      d.calls.some(
        (c) => c[0] === "del" && c[1].endsWith("/messages/400000000000000001"),
      ),
    "discord delete",
    r,
  );
  r = await d.run("delete", { channel: "general", message: "nope" });
  ok(/an id/.test(r.error || ""), "discord delete: a message id needed", r);
  r = await d.run("pins", { channel: "general" });
  ok(r.messages[0].content === "pinned", "discord pins", r);
  r = await d.run("pin", { channel: "general", message: "400000000000000001" });
  ok(
    r.pinned &&
      d.calls.some(
        (c) => c[0] === "put" && c[1].endsWith("/pins/400000000000000001"),
      ),
    "discord pin",
    r,
  );
  r = await d.run("search", { query: "found", channel: "general" });
  ok(
    r.total === 1 &&
      r.messages[0].content === "found" &&
      d.calls.some(
        (c) =>
          c[1] === "/guilds/300000000000000001/messages/search" &&
          c[3].channel_id === "200000000000000001",
      ),
    "discord search: in a channel's server",
    d.calls,
  );
  r = await d.run("search", { author: "alice" });
  ok(
    d.calls.some((c) => c[3] && c[3].author_id === "100000000000000002"),
    "discord search: by author name",
    r,
  );
  r = await d.run("thread_create", {
    channel: "general",
    name: "plans",
    message: "400000000000000001",
  });
  ok(
    r.created && r.created.name === "plans",
    "discord thread_create from a message",
    r,
  );
  r = await d.run("send_file", {
    channel: "alice",
    name: "a.txt",
    data: Buffer.from("hello").toString("base64"),
    content: "here",
  });
  ok(
    r.sent && d.calls.some((c) => c[0] === "post" && c[4] === 1),
    "discord send_file: multipart through the REST client",
    r,
  );
  r = await d.run("friends", {});
  ok(
    r.friends[0].name === "Alice" && r.friends[0].status === "online",
    "discord friends",
    r,
  );
  r = await d.run("members", { guild: "friends" });
  ok(r.members[0].name === "Ali", "discord members", r);
  r = await d.run("voice_join", { channel: "200000000000000003" });
  ok(
    r.joined && d.selected[0] === "200000000000000003",
    "discord voice_join",
    r,
  );
  r = await d.run("voice_join", { channel: "general" });
  ok(
    /isn't a voice channel/.test(r.error || ""),
    "discord voice_join: a text channel refused",
    r,
  );
  r = await d.run("api", {
    method: "get",
    path: "/guilds/300000000000000001/roles",
  });
  ok(
    r.path === "/guilds/300000000000000001/roles",
    "discord api: any other call",
    r,
  );
  for (const p of [
    "/auth/login",
    "/users/@me/mfa/totp/enable",
    "/users/@me/billing/payment-sources",
    "/users/@me/connections",
    "/oauth2/authorize",
  ]) {
    r = await d.run("api", { method: "post", path: p });
    ok(/refused/.test(r.error || ""), `discord api: ${p} refused`, r);
  }
  r = await d.run("api", { method: "get", path: "/channels/../auth" });
  ok(/path/.test(r.error || ""), "discord api: .. refused", r);
  r = await d.run("open", { channel: "general" });
  ok(r.opened && d.calls.some((c) => c[0] === "nav"), "discord open", r);

  // Slack.
  let s = slack();
  r = await s.run("status", {});
  ok(r.signedIn && r.user === "Me" && r.team === "Acme", "slack status", r);
  ok(
    s.calls[0][1].token === "xoxc-secret" && s.calls[0][2] === "include",
    "slack: the app's own session",
    s.calls[0],
  );
  ok(!JSON.stringify(r).includes("xoxc"), "slack: never the token back", r);
  r = await s.run("read", { channel: "#general", limit: 5 });
  ok(
    r.messages.length === 2 &&
      r.messages[0].text === "yo" &&
      r.messages[1].author === "Bob" &&
      r.messages[0].mine,
    "slack read: oldest first, names",
    r,
  );
  r = await s.run("send", { channel: "bob", content: "hello" });
  ok(
    r.sent &&
      s.calls.some(
        (c) => c[0] === "chat.postMessage" && c[1].channel === "D0000001",
      ),
    "slack send: to a person, their DM",
    s.calls.slice(-3),
  );
  r = await s.run("send", { channel: "U0000002", content: "hello" });
  ok(
    s.calls.some(
      (c) => c[0] === "conversations.open" && c[1].users === "U0000002",
    ),
    "slack send: by user id, the DM opened",
    s.calls.slice(-2),
  );
  r = await s.run("edit", {
    channel: "C0000001",
    ts: "1762600000.000100",
    content: "fixed",
  });
  ok(
    r.edited &&
      s.calls.some((c) => c[0] === "chat.update" && c[1].text === "fixed"),
    "slack edit",
    r,
  );
  r = await s.run("delete", { channel: "C0000001", ts: "bad" });
  ok(/ts/.test(r.error || ""), "slack delete: a ts needed", r);
  r = await s.run("react", {
    channel: "C0000001",
    ts: "1762600000.000100",
    emoji: ":thumbsup:",
  });
  ok(
    s.calls.some((c) => c[0] === "reactions.add" && c[1].name === "thumbsup"),
    "slack react",
    r,
  );
  r = await s.run("search", { query: "deploy" });
  ok(r.total === 1 && r.messages[0].where === "#general", "slack search", r);
  r = await s.run("upload", {
    channel: "C0000001",
    name: "a.txt",
    data: Buffer.from("hello").toString("base64"),
  });
  ok(
    r.uploaded === "a.txt" &&
      s.calls.some((c) => c[0] === "upload" && c[1] === 5) &&
      s.calls.some((c) => c[0] === "files.completeUploadExternal"),
    "slack upload: the external upload flow",
    r,
  );
  r = await s.run("profile_status", {
    text: "Lunch",
    emoji: "sandwich",
    minutes: 30,
  });
  ok(
    s.calls.some(
      (c) =>
        c[0] === "users.profile.set" &&
        JSON.parse(c[1].profile).status_emoji === ":sandwich:",
    ),
    "slack profile_status",
    r,
  );
  r = await s.run("channel_create", { name: "New One" });
  ok(r.created && r.created.name === "#new-one", "slack channel_create", r);
  r = await s.run("api", {
    method: "bookmarks.list",
    params: { channel_id: "C0000001" },
  });
  ok(r.method === "bookmarks.list", "slack api: any other method", r);
  for (const m of [
    "auth.revoke",
    "admin.users.remove",
    "apps.uninstall",
    "oauth.v2.access",
  ]) {
    r = await s.run("api", { method: m });
    ok(/refused/.test(r.error || ""), `slack api: ${m} refused`, r);
  }

  // YouTube Music.
  let y = ytm();
  r = await y.run("playlists", {});
  ok(
    r.playlists.length === 3 &&
      r.playlists[1].id === "PLroad1234" &&
      r.playlists[1].title === "Road trip",
    "ytm playlists",
    r,
  );
  r = await y.run("playlist", { playlist: "road trip" });
  ok(
    r.playlist.title === "Road trip" &&
      r.tracks[1].videoId === "bbbbbbbbbbb" &&
      r.tracks[1].setVideoId === "S2",
    "ytm playlist by title: its tracks",
    r,
  );
  r = await y.run("playlist_create", { title: "New", videos: ["aaaaaaaaaaa"] });
  ok(
    r.created.id === "PLnew12345" &&
      y.calls.some(
        (c) => c[0] === "/playlist/create" && c[1].privacyStatus === "PRIVATE",
      ),
    "ytm playlist_create, private by default",
    r,
  );
  r = await y.run("playlist_add", {
    playlist: "chill",
    videos: ["ccccccccccc"],
  });
  ok(
    y.calls.some(
      (c) =>
        c[0] === "/browse/edit_playlist" &&
        c[1].playlistId === "PLchill123" &&
        c[1].actions[0].addedVideoId === "ccccccccccc",
    ),
    "ytm playlist_add",
    r,
  );
  r = await y.run("playlist_remove", {
    playlist: "PLroad1234",
    videos: ["bbbbbbbbbbb"],
  });
  ok(
    y.calls.some(
      (c) =>
        c[0] === "/browse/edit_playlist" && c[1].actions[0].setVideoId === "S2",
    ),
    "ytm playlist_remove: by its setVideoId",
    r,
  );
  r = await y.run("playlist_add", { playlist: "chill", videos: ["short"] });
  ok(/videoIds/.test(r.error || ""), "ytm playlist_add: bad ids refused", r);
  r = await y.run("like", { video: "aaaaaaaaaaa" });
  ok(r.liked && y.calls.some((c) => c[0] === "/like/like"), "ytm like", r);
  r = await y.run("playlist_delete", { playlist: "LM" });
  ok(
    /can't be deleted/.test(r.error || ""),
    "ytm: the liked songs can't be deleted",
    r,
  );
  r = await y.run("innertube", { endpoint: "account/account_menu" });
  ok(
    /refused/.test(r.error || ""),
    "ytm innertube: the account's own refused",
    r,
  );
  r = await y.run("innertube", {
    endpoint: "next",
    body: { videoId: "aaaaaaaaaaa" },
  });
  ok(r.endpoint === "next", "ytm innertube: another call", r);

  if (failures) {
    console.log(`${failures} failure(s)`);
    process.exit(1);
  }
})();
