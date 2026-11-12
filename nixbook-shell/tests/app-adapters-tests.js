// The Electron bridge's adapters for Discord (electron/discord.js), Slack
// (electron/slack.js), YouTube Music (electron/youtube-music.js) and YouTube
// in ZenPlay (electron/youtube.js), each run under node against a fake of
// what its app's page exposes: Vencord's stores and Discord's REST client;
// Slack's localConfig_v2 and Web API; YouTube Music's network manager;
// YouTube's player, navigation and InnerTube API. What each operation asks
// of the app, and that the generic calls never reach the account's own
// secrets. Also YouTube's styling script (electron/youtube.style.js): which
// of the page's design tokens get which of the palette's colours. Run by
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

// -- YouTube (ZenPlay) ---------------------------------------------------------
function youtube(opts = {}) {
  const calls = [];
  const events = [];
  const video = (id, title) => ({
    videoRenderer: {
      videoId: id,
      title: { runs: [{ text: title }] },
      ownerText: {
        runs: [
          {
            text: "Blender",
            navigationEndpoint: {
              browseEndpoint: { browseId: "UCSMOQeBJ2RAnuFungnQOxLg" },
            },
          },
        ],
      },
      lengthText: { simpleText: "10:35" },
      viewCountText: { simpleText: "23M views" },
      publishedTimeText: { simpleText: "12y ago" },
    },
  });
  // The newer renderer: a row for who it is by, one for views and age.
  const lockup = (id, title, type, rows) => ({
    lockupViewModel: {
      contentId: id,
      contentType: type,
      metadata: {
        lockupMetadataViewModel: {
          title: { content: title },
          metadata: {
            contentMetadataViewModel: {
              metadataRows: rows.map((parts) => ({
                metadataParts: parts.map((t) => ({ text: { content: t } })),
              })),
            },
          },
        },
      },
      contentImage: {
        thumbnailViewModel: {
          overlays: [{ thumbnailBadgeViewModel: { text: "4:40" } }],
        },
      },
    },
  });
  const answer = (ep, body) => {
    if (ep === "search")
      return {
        contents: [
          video("aaaaaaaaaaa", "Big Buck Bunny"),
          {
            channelRenderer: {
              channelId: "UCSMOQeBJ2RAnuFungnQOxLg",
              title: { simpleText: "Blender" },
              subscriberCountText: { simpleText: "@BlenderOfficial" },
              videoCountText: { simpleText: "1.26M subscribers" },
            },
          },
          lockup(
            "PLmovies1234",
            "Open Movies",
            "LOCKUP_CONTENT_TYPE_PLAYLIST",
            [
              ["Blender", "Playlist"],
              ["Updated today"],
              ["A long description"],
            ],
          ),
          video("aaaaaaaaaaa", "Big Buck Bunny (again)"),
        ],
      };
    if (ep === "next")
      return {
        contents: {
          results: [
            {
              videoPrimaryInfoRenderer: {
                title: { runs: [{ text: "Big Buck Bunny" }] },
                viewCount: {
                  videoViewCountRenderer: {
                    viewCount: { simpleText: "23,535,338 views" },
                  },
                },
                dateText: { simpleText: "Nov 10, 2014" },
              },
            },
            {
              videoSecondaryInfoRenderer: {
                owner: {
                  videoOwnerRenderer: {
                    title: { runs: [{ text: "Blender" }] },
                    navigationEndpoint: {
                      browseEndpoint: { browseId: "UCSMOQeBJ2RAnuFungnQOxLg" },
                    },
                  },
                },
                attributedDescription: { content: "A short film." },
              },
            },
          ],
          secondaryResults: {
            results: [
              lockup("ccccccccccc", "Sintel", "LOCKUP_CONTENT_TYPE_VIDEO", [
                ["Blender"],
                ["5M", "10y ago"],
              ]),
            ],
          },
        },
      };
    if (ep === "browse" && body.browseId === "VLPLmovies1234")
      return {
        header: {
          pageHeaderViewModel: {
            title: {
              dynamicTextViewModel: { text: { content: "Open Movies" } },
            },
          },
        },
        contents: [
          {
            playlistVideoRenderer: {
              videoId: "bbbbbbbbbbb",
              title: { runs: [{ text: "Elephants Dream" }] },
              shortBylineText: { runs: [{ text: "Blender" }] },
              setVideoId: "S1",
            },
          },
        ],
      };
    if (ep === "browse" && body.browseId === "UCSMOQeBJ2RAnuFungnQOxLg")
      return {
        metadata: { channelMetadataRenderer: { title: "Blender" } },
        contents: [
          // A channel's own page: no "by" row.
          lockup("ddddddddddd", "What's new", "LOCKUP_CONTENT_TYPE_VIDEO", [
            ["241K", "2d ago"],
          ]),
        ],
      };
    if (ep === "browse" && body.browseId === "FEsubscriptions")
      return opts.signedIn
        ? { contents: [video("eeeeeeeeeee", "New one")] }
        : {};
    if (ep === "navigation/resolve_url") {
      if (/@BlenderOfficial$/.test(body.url))
        return {
          endpoint: {
            commandMetadata: {
              webCommandMetadata: {
                url: "/youtubei/v1/navigation/resolve_url",
              },
            },
            browseEndpoint: { browseId: "UCSMOQeBJ2RAnuFungnQOxLg" },
          },
        };
      if (/feed\/subscriptions$/.test(body.url))
        return {
          endpoint: {
            commandMetadata: {
              webCommandMetadata: { url: "/feed/subscriptions" },
            },
            browseEndpoint: { browseId: "FEsubscriptions" },
          },
        };
      return {};
    }
    if (ep === "playlist/create") return { playlistId: "PLnew12345" };
    return { status: "STATUS_SUCCEEDED" };
  };
  const location = {
    hostname: opts.hostname === undefined ? "www.youtube.com" : opts.hostname,
    origin: "https://www.youtube.com",
    href: "https://www.youtube.com/",
    pathname: "/",
    assign: (url) => events.push(["assign", url]),
  };
  const playerState = {
    id: opts.playing || "",
    state: opts.playing ? 1 : -1,
    time: 0,
    volume: 100,
    muted: false,
    rate: 1,
    captions: null,
  };
  const player = {
    classList: { contains: () => false },
    getPlayerState: () => playerState.state,
    getVideoData: () => ({
      video_id: playerState.id,
      title: "Video " + playerState.id,
      author: "Blender",
    }),
    getCurrentTime: () => playerState.time,
    getDuration: () => 600,
    getVolume: () => playerState.volume,
    isMuted: () => playerState.muted,
    getPlaybackRate: () => playerState.rate,
    getAvailablePlaybackRates: () => [0.5, 1, 1.5, 2],
    getPlaybackQuality: () => "hd720",
    getPlaylistId: () => null,
    getOption: (m, k) =>
      k === "tracklist"
        ? [
            { languageCode: "en", languageName: "English" },
            { languageCode: "fr", languageName: "French" },
          ]
        : { languageCode: playerState.captions },
    setOption: (m, k, v) => (playerState.captions = v.languageCode),
    loadModule: () => {},
    unloadModule: () => (playerState.captions = null),
    playVideo: () => (playerState.state = 1),
    pauseVideo: () => (playerState.state = 2),
    seekTo: (t) => (playerState.time = t),
    setVolume: (v) => (playerState.volume = v),
    mute: () => (playerState.muted = true),
    unMute: () => (playerState.muted = false),
    setPlaybackRate: (r) => (playerState.rate = r),
    nextVideo: () => (playerState.id = "nnnnnnnnnnn"),
    previousVideo: () => (playerState.id = "ppppppppppp"),
  };
  const attrs = new Set(opts.dark ? ["dark"] : []);
  const app = {
    // YouTube's own navigation: the page and its player follow the endpoint.
    dispatchEvent: (e) => {
      events.push([e.type, e.detail.endpoint]);
      if (opts.deaf) return;
      const ep = e.detail.endpoint;
      const url = ep.commandMetadata.webCommandMetadata.url;
      location.href = location.origin + url;
      location.pathname = url.split("?")[0];
      if (ep.watchEndpoint) {
        playerState.id = ep.watchEndpoint.videoId;
        playerState.state = 2; // held paused until asked to play
        playerState.time = ep.watchEndpoint.startTimeSeconds || 0;
      }
    },
    handleSignalActionToggleDarkThemeOn: () => (
      events.push(["look", "dark"]),
      attrs.add("dark")
    ),
    handleSignalActionToggleDarkThemeOff: () => (
      events.push(["look", "light"]),
      attrs.delete("dark")
    ),
    handleSignalActionToggleDarkThemeDevice: () =>
      events.push(["look", "device"]),
  };
  const ctx = {
    URL,
    setTimeout,
    CustomEvent: class {
      constructor(type, init) {
        this.type = type;
        this.detail = init.detail;
      }
    },
    location,
    document: {
      title: "YouTube",
      cookie: opts.cookie || "",
      documentElement: { hasAttribute: (a) => attrs.has(a) },
      querySelector: (sel) => (sel === "ytd-app" && !opts.loading ? app : null),
      getElementById: (id) => (id === "movie_player" ? player : null),
    },
    ytcfg: {
      get: (k) =>
        k === "LOGGED_IN"
          ? !!opts.signedIn
          : k === "INNERTUBE_CONTEXT"
            ? { client: { clientName: "WEB" } }
            : undefined,
    },
    fetch: async (url, init) => {
      const ep = url.replace("/youtubei/v1/", "").split("?")[0];
      const body = JSON.parse(init.body);
      calls.push([ep, body, init.headers]);
      if (
        !opts.signedIn &&
        /^(like|subscription|playlist|browse\/edit)/.test(ep)
      )
        return { ok: false, status: 401, json: async () => ({}) };
      return { ok: true, status: 200, json: async () => answer(ep, body) };
    },
  };
  return {
    run: load("youtube.js", ctx),
    calls,
    events,
    player: playerState,
    location,
  };
}

// YouTube's styling script: its functions, and a page's stylesheets as it
// reads them.
function youtubeStyle() {
  const ctx = { console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(
    fs.readFileSync(path.join(dir, "youtube.style.js"), "utf8"),
    ctx,
  );
  return ctx;
}
function sheetRule(selectorText, props) {
  const names = Object.keys(props);
  const style = { length: names.length, getPropertyValue: (n) => props[n] };
  names.forEach((n, i) => (style[i] = n));
  return { selectorText, style };
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

  // YouTube (ZenPlay).
  let t = youtube();
  r = await t.run("status", {});
  ok(
    r.ready && r.signedIn === false && r.playing === null,
    "youtube status: nothing playing",
    r,
  );
  r = await t.run("search", { query: "big buck bunny" });
  ok(
    r.results.length === 3 &&
      r.results[0].kind === "video" &&
      r.results[0].id === "aaaaaaaaaaa" &&
      r.results[0].channelId === "UCSMOQeBJ2RAnuFungnQOxLg" &&
      r.results[0].info === "23M views · 12y ago" &&
      r.results[1].kind === "channel" &&
      r.results[1].handle === "@BlenderOfficial" &&
      r.results[1].subscribers === "1.26M subscribers" &&
      r.results[2].kind === "playlist" &&
      r.results[2].id === "PLmovies1234" &&
      r.results[2].info === "Updated today",
    "youtube search: videos, channels and playlists, each once, whatever their renderer",
    r,
  );
  r = await t.run("search", { query: "blender", kind: "channel" });
  ok(
    r.results.length === 1 && t.calls.at(-1)[1].params === "EgIQAg==",
    "youtube search: a kind asked is YouTube's own filter",
    r,
  );
  r = await t.run("video", { video: "https://youtu.be/aaaaaaaaaaa?t=3" });
  ok(
    r.video.id === "aaaaaaaaaaa" &&
      r.video.views === "23,535,338 views" &&
      r.video.channel === "Blender" &&
      r.video.description === "A short film." &&
      r.next[0].id === "ccccccccccc" &&
      r.next[0].channel === "Blender" &&
      r.next[0].info === "5M · 10y ago" &&
      r.next[0].length === "4:40",
    "youtube video: by its link, its details and what comes next",
    r,
  );
  r = await t.run("playlist", {
    playlist: "https://www.youtube.com/playlist?list=PLmovies1234",
  });
  ok(
    r.playlist.title === "Open Movies" &&
      r.videos[0].id === "bbbbbbbbbbb" &&
      r.videos[0].setVideoId === "S1",
    "youtube playlist: by its link",
    r,
  );
  r = await t.run("channel", { channel: "@BlenderOfficial" });
  ok(
    r.channel.id === "UCSMOQeBJ2RAnuFungnQOxLg" &&
      r.videos[0].id === "ddddddddddd" &&
      r.videos[0].channel === undefined &&
      r.videos[0].info === "241K · 2d ago" &&
      t.calls.at(-1)[1].params === "EgZ2aWRlb3PyBgQKAjoA",
    "youtube channel: its @handle resolved, its latest videos",
    r,
  );
  r = await t.run("subscriptions", {});
  ok(
    /not signed in/.test(r.error || ""),
    "youtube subscriptions: signed out, said so",
    r,
  );
  r = await t.run("like", { video: "aaaaaaaaaaa" });
  ok(
    /not signed in/.test(r.error || ""),
    "youtube like: signed out (401), said so",
    r,
  );

  r = await t.run("play", { video: "aaaaaaaaaaa", at: 90 });
  ok(
    r.playing.video === "aaaaaaaaaaa" &&
      r.playing.state === "playing" &&
      r.playing.position === 90 &&
      t.events[0][0] === "yt-navigate" &&
      t.events[0][1].watchEndpoint.startTimeSeconds === 90 &&
      !t.events.some((e) => e[0] === "assign"),
    "youtube play: through YouTube's own navigation, no page load, started",
    r,
  );
  r = await t.run("play", { query: "big buck bunny" });
  ok(
    r.found.id === "aaaaaaaaaaa" && t.calls.at(-1)[1].params === "EgIQAQ==",
    "youtube play: a query plays the first video found",
    r,
  );
  r = await t.run("play", { playlist: "PLmovies1234" });
  ok(
    r.playing.video === "bbbbbbbbbbb" &&
      t.events.at(-1)[1].watchEndpoint.playlistId === "PLmovies1234",
    "youtube play: a playlist from its first video",
    r,
  );
  r = await t.run("play", {});
  ok(
    /video|query|playlist/.test(r.error || ""),
    "youtube play: nothing to play refused",
    r,
  );
  r = await t.run("play", { video: "not a video" });
  ok(/its id/.test(r.error || ""), "youtube play: a bad id refused", r);
  r = await t.run("pause", {});
  ok(r.playing.state === "paused", "youtube pause", r);
  r = await t.run("toggle", {});
  ok(r.playing.state === "playing", "youtube toggle", r);
  r = await t.run("seek", { to: 120 });
  const at = r.playing.position;
  r = await t.run("seek", { by: -30 });
  ok(at === 120 && r.playing.position === 90, "youtube seek: to, and by", r);
  r = await t.run("seek", {});
  ok(/`to`/.test(r.error || ""), "youtube seek: nowhere refused", r);
  r = await t.run("mute", {});
  r = await t.run("volume", { level: 35 });
  ok(
    r.playing.volume === 35 && r.playing.muted === false,
    "youtube volume: sets it and unmutes",
    r,
  );
  r = await t.run("volume", { level: 150 });
  ok(/0 to 100/.test(r.error || ""), "youtube volume: out of range refused", r);
  r = await t.run("speed", { rate: 1.5 });
  ok(r.playing.speed === 1.5, "youtube speed", r);
  r = await t.run("speed", { rate: 3 });
  ok(
    /one of 0.5, 1, 1.5, 2/.test(r.error || ""),
    "youtube speed: only the player's rates",
    r,
  );
  r = await t.run("captions", { language: "french" });
  ok(r.captions === "fr", "youtube captions: a language by its name", r);
  r = await t.run("captions", { language: "klingon" });
  ok(
    /en \(English\), fr \(French\)/.test(r.error || ""),
    "youtube captions: none in that language, the ones there said",
    r,
  );
  r = await t.run("captions", { on: false });
  ok(r.captions === false, "youtube captions off", r);
  r = await t.run("next", {});
  ok(r.playing.video === "nnnnnnnnnnn", "youtube next", r);

  r = await t.run("open", { page: "subscriptions" });
  ok(
    r.opened === "https://www.youtube.com/feed/subscriptions" &&
      t.events.at(-1)[1].browseEndpoint.browseId === "FEsubscriptions",
    "youtube open: a named page, where YouTube says it leads",
    r,
  );
  r = await t.run("open", { url: "https://www.youtube.com/@BlenderOfficial" });
  ok(
    t.location.pathname === "/@BlenderOfficial" &&
      t.events.at(-1)[1].commandMetadata.webCommandMetadata.url ===
        "/@BlenderOfficial",
    "youtube open: a channel's link keeps its own address",
    r,
  );
  for (const url of [
    "https://evil.example/watch?v=aaaaaaaaaaa",
    "javascript:alert(1)",
    "settings",
  ]) {
    r = await t.run("open", { url });
    ok(/a YouTube link/.test(r.error || ""), `youtube open: ${url} refused`, r);
  }
  r = await t.run("open", { url: "https://www.youtube.com/nowhere" });
  ok(
    /doesn't know/.test(r.error || ""),
    "youtube open: a link YouTube doesn't know refused",
    r,
  );

  // Without YouTube's navigation (it changed): a plain load.
  t = youtube({ deaf: true });
  r = await t.run("play", { video: "aaaaaaaaaaa" });
  ok(
    r.loading &&
      t.events.at(-1)[0] === "assign" &&
      t.events.at(-1)[1] === "/watch?v=aaaaaaaaaaa",
    "youtube play: a plain load when the page no longer navigates by itself",
    r,
  );

  t = youtube({
    signedIn: true,
    playing: "aaaaaaaaaaa",
    cookie: "PREF=tz=Europe.Paris&f6=400",
  });
  r = await t.run("subscriptions", {});
  ok(r.subscriptions[0].id === "eeeeeeeeeee", "youtube subscriptions", r);
  r = await t.run("like", { video: "aaaaaaaaaaa" });
  ok(
    r.liked === "aaaaaaaaaaa" && t.calls.at(-1)[0] === "like/like",
    "youtube like",
    r,
  );
  r = await t.run("subscribe", { channel: "UCSMOQeBJ2RAnuFungnQOxLg" });
  ok(
    r.subscribed &&
      t.calls.at(-1)[1].channelIds[0] === "UCSMOQeBJ2RAnuFungnQOxLg",
    "youtube subscribe",
    r,
  );
  r = await t.run("subscribe", { channel: "Blender" });
  ok(
    /its id/.test(r.error || ""),
    "youtube subscribe: a name isn't a channel",
    r,
  );
  r = await t.run("watch_later_add", { video: "aaaaaaaaaaa" });
  ok(
    t.calls.at(-1)[0] === "browse/edit_playlist" &&
      t.calls.at(-1)[1].playlistId === "WL" &&
      t.calls.at(-1)[1].actions[0].addedVideoId === "aaaaaaaaaaa",
    "youtube watch_later_add",
    r,
  );
  r = await t.run("playlist_remove", {
    playlist: "PLmovies1234",
    videos: ["bbbbbbbbbbb"],
  });
  ok(
    t.calls.at(-1)[1].actions[0].action === "ACTION_REMOVE_VIDEO_BY_VIDEO_ID",
    "youtube playlist_remove",
    r,
  );
  r = await t.run("playlist_create", { title: "New", videos: ["aaaaaaaaaaa"] });
  ok(
    r.created.id === "PLnew12345" &&
      t.calls.at(-1)[1].privacyStatus === "PRIVATE",
    "youtube playlist_create, private by default",
    r,
  );
  r = await t.run("playlist_delete", { playlist: "WL" });
  ok(
    /can't be deleted/.test(r.error || ""),
    "youtube: Watch later can't be deleted",
    r,
  );
  for (const ep of [
    "account/account_menu",
    "player",
    "att/get",
    "get_settings",
  ]) {
    r = await t.run("innertube", { endpoint: ep });
    ok(/refused/.test(r.error || ""), `youtube innertube: ${ep} refused`, r);
  }
  r = await t.run("innertube", { endpoint: "guide" });
  ok(r.endpoint === "guide", "youtube innertube: another call", r);
  ok(
    !t.calls.some((c) => JSON.stringify(c[2]).includes("Authorization")),
    "youtube: no Authorization header without the login's cookie",
  );
  // Its own look: YouTube's Appearance setting, only when it differs.
  r = await t.run("look", { mode: "dark" });
  ok(
    r.changed === true && t.events.at(-1)[1] === "dark",
    "youtube look: dark asked of a light page",
    r,
  );
  r = await t.run("look", { mode: "dark" });
  ok(
    r.changed === false,
    "youtube look: nothing to do when it is already so",
    r,
  );
  r = await t.run("look", { mode: "light" });
  ok(
    r.changed === true && t.events.at(-1)[1] === "light",
    "youtube look: light",
    r,
  );
  r = await t.run("look", { mode: "device" });
  ok(
    r.changed === true && t.events.at(-1)[1] === "device",
    "youtube look: back to the device's, a look having been chosen (PREF f6)",
    r,
  );
  t = youtube();
  r = await t.run("look", { mode: "device" });
  ok(
    r.changed === false,
    "youtube look: device, nothing chosen: left alone",
    r,
  );
  r = await t.run("look", { mode: "pink" });
  ok(
    /light, dark or device/.test(r.error || ""),
    "youtube look: another word refused",
    r,
  );
  t = youtube({ hostname: "accounts.google.com" });
  r = await t.run("status", {});
  ok(
    /accounts\.google\.com, not YouTube/.test(r.error || ""),
    "youtube: another site's page (sign-in) isn't touched",
    r,
  );
  t = youtube({ loading: true });
  r = await t.run("status", {});
  ok(/still loading/.test(r.error || ""), "youtube: still loading, said so", r);

  // YouTube's styling script.
  const st = youtubeStyle();
  const c = st.nixbookParseColor;
  ok(
    JSON.stringify([
      c("#fff"),
      c("#0f0f0f80").a.toFixed(2),
      c("rgba(0, 0, 0, 0.1)").a,
      c("rgb(255 255 255 / 20%)").a,
      c("white").r,
      c("var(--x)"),
      c("initial"),
    ]) ===
      JSON.stringify([
        { r: 255, g: 255, b: 255, a: 1 },
        "0.50",
        0.1,
        0.2,
        255,
        null,
        null,
      ]),
    "style: colours parsed (hex, rgb, alpha), the rest left",
  );
  ok(
    JSON.stringify(
      [
        ":root",
        "[light], html",
        "[dark], html[dark]",
        '[color-version="v2_0"] [dark]',
        "ytd-masthead[dark]",
        "[dark] .x",
        "html, [dark]",
      ].map(st.nixbookTokenScope),
    ) === JSON.stringify(["light", "light", "dark", "dark", null, null, null]),
    "style: only the rules that set the page's own tokens, light or dark",
  );
  const role = (l, d, dark) => st.nixbookTokenColor(c(l), c(d), dark);
  const roles = [
    ["#fff", "#0f0f0f", "var(--nixbook-surface)"],
    ["#fff", "#212121", "var(--nixbook-surface-container-high)"],
    ["#f2f2f2", "#3f3f3f", "var(--nixbook-surface-container-highest)"],
    ["#e5e5e5", "#3f3f3f", "var(--nixbook-outline-variant)"],
    ["#0f0f0f", "#f1f1f1", "var(--nixbook-on-surface)"],
    ["#606060", "#aaa", "var(--nixbook-on-surface-variant)"],
    ["#909090", "#717171", "var(--nixbook-outline)"],
    ["#065fd4", "#3ea6ff", "var(--nixbook-primary)"],
    ["#def1ff", "#263850", "var(--nixbook-primary-container)"],
    ["#c30027", "#f57", null],
    ["#107516", "#2ba640", null],
  ];
  ok(
    roles.every(([l, d, want]) => role(l, d, true) === want),
    "style: what a token is for from its light and dark values; the reds and greens left",
    roles.map(([l, d]) => role(l, d, true)),
  );
  ok(
    role("rgba(0,0,0,0.05)", "rgba(255,255,255,0.1)", true) ===
      "color-mix(in srgb, var(--nixbook-on-surface) 10%, transparent)" &&
      role("rgba(0,0,0,0.05)", "rgba(255,255,255,0.1)", false) ===
        "color-mix(in srgb, var(--nixbook-on-surface) 5%, transparent)",
    "style: a wash is the text colour at the strength of the palette's look",
  );
  const tokens = st.nixbookTokens([
    {
      cssRules: [
        sheetRule(":root", { "--t1": "initial", "--tstatic": "#fff" }),
        sheetRule(":root", { "--t1": "#0f0f0f", "--t2": "#fff" }),
        sheetRule("[dark]", {
          "--t1": "#f1f1f1",
          "--t2": "#0f0f0f",
          "--tstatic": "#fff",
        }),
        sheetRule("[light]", { "--t1": "#0f0f0f", "--t2": "#fff" }),
        // An experiment on the root: the look named outright is believed.
        sheetRule(":root:root", { "--t2": "#f1f1f1" }),
        sheetRule("[light], html", {
          "--yt-sys-color-baseline--text-secondary": "#606060",
          "--nixbook-surface": "#000",
        }),
        sheetRule("[dark], html[dark]", {
          "--yt-sys-color-baseline--text-secondary": "#aaa",
          "--nixbook-surface": "#fff",
        }),
        sheetRule("ytd-masthead[dark]", { "--t1": "#123456" }),
        sheetRule(".x", { color: "red" }),
      ],
    },
    {
      get cssRules() {
        throw new Error("SecurityError");
      },
    },
  ]);
  const built = st.nixbookTokenCss(tokens, true);
  ok(
    built.count === 3 &&
      built.css ===
        ":root, [dark], [light] {\n  --t1: var(--nixbook-on-surface) !important;\n  --t2: var(--nixbook-surface) !important;\n  --yt-sys-color-baseline--text-secondary: var(--nixbook-on-surface-variant) !important;\n}\n",
    "style: the page's tokens (hashed or named) given the palette's variables; one-look tokens, another site's sheet and its own variables left",
    built,
  );

  if (failures) {
    console.log(`${failures} failure(s)`);
    process.exit(1);
  }
})();
