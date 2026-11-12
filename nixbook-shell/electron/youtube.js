// nixbook's YouTube operations (the `youtube` tool of nixbook-desktop-mcp),
// run by the Electron bridge (scripts/electron-bridge.py) in the YouTube page
// ZenPlay shows, through YouTube's own client: the page's player
// (#movie_player: what plays, pause, seek, volume, speed, captions), its
// navigation (the app goes to a video or a page without loading anew) and
// the InnerTube API the page itself calls, with its signed-in cookies. No
// cookie or header is ever returned.
//
//   nixbookApp(op, args) → a plain object, or {error}
//
// Operations:
//   status: the page shown and what plays.
//   search {query, kind?: video|channel|playlist, limit?}, video {video}
//   (its details and what YouTube suggests next), home, subscriptions,
//   history, watch_later, liked, playlists, playlist {playlist, limit?},
//   channel {channel, limit?} (its latest videos).
//   play {video | query, at?, playlist?}, open {page | url}, pause, resume,
//   toggle, seek {to | by}, volume {level}, mute, unmute, speed {rate},
//   next, previous, captions {on, language?}.
//   like / dislike / unlike {video}, subscribe / unsubscribe {channel},
//   watch_later_add / watch_later_remove {video}, playlist_create {title,
//   description?, privacy?, videos?}, playlist_add / playlist_remove
//   {playlist, videos}, playlist_delete {playlist}, innertube {endpoint,
//   body?}: any other InnerTube call of the page (browse, next, search…),
//   never the account's own settings.
//   look {mode: light|dark|device}: YouTube's own Appearance setting (the
//   bridge's, after it styles the page: the palette's look).
// A video is its id (11 characters) or a youtube.com / youtu.be link; a
// channel its id (UC…), @handle or link; a playlist its id (PL…, WL, LL).
"use strict";

async function nixbookApp(op, o) {
  o = o || {};
  const app = document.querySelector("ytd-app");
  const cfg = globalThis.ytcfg;
  const get = (k) =>
    cfg && cfg.get ? cfg.get(k) : cfg && cfg.data_ ? cfg.data_[k] : undefined;
  if (!location.hostname)
    return { error: "ZenPlay's page is still loading: try again in a moment" };
  if (!/(^|\.)youtube\.com$/.test(location.hostname))
    return {
      error: `ZenPlay shows ${location.hostname}, not YouTube (a sign-in page?): the page tools read it`,
    };
  if (!app || !cfg)
    return { error: "YouTube is still loading: try again in a moment" };

  function fail(msg) {
    return { nixbook: msg };
  }
  const SIGN_IN =
    "not signed in to YouTube in ZenPlay: the user signs in there (its Sign in button)";
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  async function sapisidHash() {
    const m = /(?:^|;\s*)(?:__Secure-3PAPISID|SAPISID)=([^;]+)/.exec(
      document.cookie,
    );
    if (!m) return null;
    const t = Math.floor(Date.now() / 1000);
    const data = new TextEncoder().encode(`${t} ${m[1]} ${location.origin}`);
    const h = await crypto.subtle.digest("SHA-1", data);
    const hex = [...new Uint8Array(h)]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return `SAPISIDHASH ${t}_${hex}`;
  }
  async function call(endpoint, body) {
    const key = get("INNERTUBE_API_KEY");
    const context = get("INNERTUBE_CONTEXT");
    if (!context) throw fail("YouTube's client isn't ready");
    const auth = await sapisidHash();
    const session = get("SESSION_INDEX");
    const page = get("DELEGATED_SESSION_ID");
    const r = await fetch(
      `/youtubei/v1/${endpoint}?prettyPrint=false${key ? "&key=" + key : ""}`,
      {
        method: "POST",
        credentials: "include",
        headers: {
          "Content-Type": "application/json",
          "X-Origin": location.origin,
          ...(auth
            ? {
                Authorization: auth,
                "X-Goog-AuthUser": String(session || 0),
                ...(page ? { "X-Goog-PageId": String(page) } : {}),
              }
            : {}),
        },
        body: JSON.stringify({ context, ...(body || {}) }),
      },
    );
    const j = await r.json().catch(() => null);
    if (r.status === 401) throw fail(SIGN_IN);
    if (!r.ok)
      throw fail(
        `YouTube said ${r.status}${j && j.error ? ": " + j.error.message : ""}`,
      );
    return j;
  }
  function text(t) {
    if (!t) return "";
    if (typeof t === "string") return t;
    if (t.simpleText) return t.simpleText;
    if (t.content) return t.content;
    return (t.runs || []).map((r) => r.text).join("");
  }
  // Every renderer of the kinds asked in an answer, in its order.
  function collect(node, keys, out = [], depth = 0) {
    if (!node || typeof node !== "object" || depth > 60) return out;
    if (Array.isArray(node)) {
      for (const x of node) collect(x, keys, out, depth + 1);
      return out;
    }
    for (const [k, v] of Object.entries(node)) {
      if (keys.includes(k) && v && typeof v === "object") out.push([k, v]);
      else collect(v, keys, out, depth + 1);
    }
    return out;
  }
  const first = (node, key) => (collect(node, [key])[0] || [])[1];
  const KINDS = [
    "videoRenderer",
    "compactVideoRenderer",
    "gridVideoRenderer",
    "playlistVideoRenderer",
    "playlistPanelVideoRenderer",
    "channelRenderer",
    "playlistRenderer",
    "gridPlaylistRenderer",
    "lockupViewModel",
  ];
  // One line of a list, whatever renderer YouTube used for it.
  function item([kind, r]) {
    if (kind === "channelRenderer")
      return {
        kind: "channel",
        id: r.channelId,
        title: text(r.title),
        // The @handle sits where the subscriber count used to be.
        handle: /^@/.test(text(r.subscriberCountText))
          ? text(r.subscriberCountText)
          : undefined,
        subscribers: /^@/.test(text(r.subscriberCountText))
          ? text(r.videoCountText) || undefined
          : text(r.subscriberCountText) || undefined,
      };
    if (kind === "playlistRenderer" || kind === "gridPlaylistRenderer")
      return {
        kind: "playlist",
        id: r.playlistId,
        title: text(r.title),
        channel: text(r.shortBylineText || r.longBylineText) || undefined,
        videos: text(r.videoCountText) || r.videoCount || undefined,
      };
    if (kind === "lockupViewModel") {
      const type = String(r.contentType || "");
      const meta = (r.metadata || {}).lockupMetadataViewModel || {};
      const rows = (
        ((meta.metadata || {}).contentMetadataViewModel || {}).metadataRows ||
        []
      ).map((row) =>
        (row.metadataParts || [])
          .map((p) => text(p.text))
          .filter(Boolean)
          .join(" · "),
      );
      const badges = collect(r.contentImage, ["thumbnailBadgeViewModel"]).map(
        ([, b]) => text(b.text),
      );
      const playlist = /PLAYLIST|PODCAST|ALBUM/.test(type);
      if (!r.contentId || (!playlist && !/VIDEO/.test(type))) return null;
      return {
        kind: playlist ? "playlist" : "video",
        id: r.contentId,
        title: text(meta.title),
        // Who it is by, then its views and age; on a channel's own page
        // only the latter. A playlist's other rows are its first videos
        // and its description.
        channel: (rows.length > 1 && rows[0]) || undefined,
        info:
          (rows.length > 1 ? rows.slice(1, playlist ? 2 : 4) : rows)
            .filter(Boolean)
            .join(" · ")
            .slice(0, 160) || undefined,
        length: playlist ? undefined : badges[0] || undefined,
        videos: playlist ? badges[0] || undefined : undefined,
      };
    }
    if (!r.videoId) return null;
    const by = r.ownerText || r.longBylineText || r.shortBylineText;
    const channelId = (first(by, "browseEndpoint") || {}).browseId;
    const live = collect(r.badges, ["metadataBadgeRenderer"]).some(([, b]) =>
      /LIVE/.test(String(b.style || "")),
    );
    return {
      kind: "video",
      id: r.videoId,
      title: text(r.title),
      channel: text(by) || undefined,
      channelId: channelId || undefined,
      length: text(r.lengthText) || undefined,
      info:
        [
          text(r.viewCountText || r.shortViewCountText),
          text(r.publishedTimeText),
        ]
          .filter(Boolean)
          .join(" · ") || undefined,
      live: live || undefined,
      setVideoId: r.setVideoId || undefined,
    };
  }
  function items(j, limit, kind) {
    const seen = new Set();
    const out = [];
    for (const found of collect(j, KINDS)) {
      const it = item(found);
      if (!it || !it.id || (kind && it.kind !== kind)) continue;
      const key = it.kind + it.id + (it.setVideoId || "");
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(it);
      if (out.length >= limit) break;
    }
    return out;
  }
  const limitOf = (most = 100, usual = 20) =>
    Math.max(1, Math.min(most, Number(o.limit) || usual));
  function videoId(v) {
    const s = String(v || "").trim();
    if (/^[\w-]{11}$/.test(s)) return s;
    let u;
    try {
      u = new URL(s);
    } catch (e) {
      throw fail("`video`: its id (11 characters) or its YouTube link");
    }
    const host = u.hostname.replace(/^(www|m|music)\./, "");
    let id = null;
    if (host === "youtu.be") id = u.pathname.slice(1).split("/")[0];
    else if (host === "youtube.com")
      id =
        u.searchParams.get("v") ||
        (/^\/(shorts|embed|live)\/([\w-]{11})/.exec(u.pathname) || [])[2];
    if (!id || !/^[\w-]{11}$/.test(id))
      throw fail("`video`: its id (11 characters) or its YouTube link");
    return id;
  }
  function videos(v) {
    const list = (Array.isArray(v) ? v : [v]).filter(Boolean).map(videoId);
    if (!list.length) throw fail("`videos`: video ids or links");
    return list.slice(0, 100);
  }
  function playlistId(p) {
    const s = String(p || "").trim();
    const m = /[?&]list=([\w-]+)/.exec(s);
    const id = (m ? m[1] : s).replace(/^VL/, "");
    if (!/^(PL|UU|FL|RD|OL|LL|WL|LM|SE)[\w-]*$/.test(id))
      throw fail(
        "`playlist`: its id (PL…, WL for Watch later, LL for liked videos) or its link; `playlists` lists yours",
      );
    return id;
  }
  // A channel's id from its id, @handle or link.
  async function channelId(c) {
    const s = String(c || "").trim();
    if (/^UC[\w-]{20,}$/.test(s)) return s;
    const m = /youtube\.com\/channel\/(UC[\w-]{20,})/.exec(s);
    if (m) return m[1];
    const handle =
      (/youtube\.com\/(@[\w.-]+)/.exec(s) || [])[1] ||
      (/^@[\w.-]+$/.test(s) ? s : null);
    if (!handle)
      throw fail(
        "`channel`: its id (UC…), its @handle or its link (search gives them)",
      );
    const j = await call("navigation/resolve_url", {
      url: `https://www.youtube.com/${handle}`,
    });
    const id = (first(j, "browseEndpoint") || {}).browseId;
    if (!id || !/^UC/.test(id)) throw fail(`no channel ${handle}`);
    return id;
  }
  const OFF_LIMITS =
    /^(account|accounts|notification|get_settings|set_setting|ypc|upload|feedback\/delete|att\/|player$|log_event|flag)/;

  // ── the player ──
  const player = () => {
    const p = document.getElementById("movie_player");
    return p && typeof p.getPlayerState === "function" ? p : null;
  };
  const STATES = {
    "-1": "not started",
    0: "ended",
    1: "playing",
    2: "paused",
    3: "loading",
    5: "ready",
  };
  function playing() {
    const p = player();
    const data = p && p.getVideoData ? p.getVideoData() || {} : {};
    if (!p || !data.video_id) return null;
    const state = p.getPlayerState();
    const captions =
      typeof p.getOption === "function"
        ? (p.getOption("captions", "track") || {}).languageCode
        : undefined;
    return {
      video: data.video_id,
      title: data.title || undefined,
      channel: data.author || undefined,
      state: STATES[state] || String(state),
      position: Math.round(p.getCurrentTime() || 0),
      duration: Math.round(p.getDuration() || 0) || undefined,
      live: data.isLive || undefined,
      volume: p.getVolume(),
      muted: p.isMuted(),
      speed: p.getPlaybackRate(),
      quality: p.getPlaybackQuality ? p.getPlaybackQuality() : undefined,
      captions: captions || undefined,
      playlist: (p.getPlaylistId && p.getPlaylistId()) || undefined,
      ad: p.classList && p.classList.contains("ad-showing") ? true : undefined,
    };
  }
  function needPlayer() {
    const p = player();
    if (!p || !(p.getVideoData() || {}).video_id)
      throw fail("nothing is playing in ZenPlay: `play` a video first");
    return p;
  }
  // The app goes somewhere as when a link of its own is clicked (no new
  // page load); a plain load when YouTube no longer listens to that.
  async function navigate(endpoint, url, arrived) {
    app.dispatchEvent(
      new CustomEvent("yt-navigate", {
        bubbles: true,
        composed: true,
        detail: { endpoint },
      }),
    );
    for (let i = 0; i < 20; i++) {
      await sleep(250);
      if (arrived()) return true;
    }
    location.assign(url);
    return false;
  }
  async function watch(id, at, list) {
    const url =
      `/watch?v=${id}` +
      (list ? `&list=${list}` : "") +
      (at ? `&t=${Math.floor(at)}s` : "");
    const inPage = await navigate(
      {
        commandMetadata: {
          webCommandMetadata: {
            url,
            webPageType: "WEB_PAGE_TYPE_WATCH",
            rootVe: 3832,
          },
        },
        watchEndpoint: {
          videoId: id,
          ...(list ? { playlistId: list } : {}),
          ...(at ? { startTimeSeconds: Math.floor(at) } : {}),
        },
      },
      url,
      () => {
        const p = player();
        return (
          location.pathname === "/watch" &&
          p &&
          (p.getVideoData() || {}).video_id === id
        );
      },
    );
    if (!inPage) return { opened: id, loading: true };
    const p = player();
    // Started by code, not a click: the page may hold it paused.
    for (let i = 0; i < 12 && p.getPlayerState() !== 1; i++) {
      if ([-1, 2, 5].includes(p.getPlayerState())) p.playVideo();
      await sleep(250);
    }
    return { playing: playing() };
  }
  // The pages with a name: [what InnerTube calls it, its address].
  const PAGES = {
    home: ["FEwhat_to_watch", "/"],
    subscriptions: ["FEsubscriptions", "/feed/subscriptions"],
    history: ["FEhistory", "/feed/history"],
    library: ["FElibrary", "/feed/you"],
    playlists: ["FEplaylist_aggregation", "/feed/playlists"],
    watch_later: ["VLWL", "/playlist?list=WL"],
    liked: ["VLLL", "/playlist?list=LL"],
  };

  try {
    switch (op) {
      case "status":
        return {
          ready: true,
          signedIn: get("LOGGED_IN") === true,
          page: { url: location.href, title: document.title },
          playing: playing(),
        };
      case "search": {
        const query = String(o.query || "").trim();
        if (!query) throw fail("`query`: what to look for");
        const kind = String(o.kind || "");
        // YouTube's own filters (its "Type" menu).
        const params = {
          video: "EgIQAQ==",
          channel: "EgIQAg==",
          playlist: "EgIQAw==",
        }[kind];
        if (kind && !params) throw fail("kind: video, channel or playlist");
        const j = await call("search", {
          query,
          ...(params ? { params } : {}),
        });
        return { query, results: items(j, limitOf(50, 12), kind || undefined) };
      }
      case "video": {
        const id = videoId(o.video);
        const j = await call("next", { videoId: id });
        const primary = first(j, "videoPrimaryInfoRenderer") || {};
        const secondary = first(j, "videoSecondaryInfoRenderer") || {};
        const owner = first(secondary, "videoOwnerRenderer") || {};
        const description = text(
          secondary.attributedDescription || secondary.description,
        );
        return {
          video: {
            id,
            title: text(primary.title) || undefined,
            channel: text(owner.title) || undefined,
            channelId: (first(owner, "browseEndpoint") || {}).browseId,
            subscribers: text(owner.subscriberCountText) || undefined,
            views:
              text(
                (first(primary, "videoViewCountRenderer") || {}).viewCount,
              ) || undefined,
            date: text(primary.dateText) || undefined,
            description: description ? description.slice(0, 1500) : undefined,
          },
          next: items(
            first(j, "secondaryResults") || {},
            limitOf(40, 10),
            undefined,
          ),
        };
      }
      case "home":
      case "subscriptions":
      case "history":
      case "watch_later":
      case "liked":
      case "playlists": {
        const j = await call("browse", { browseId: PAGES[op][0] });
        const list = items(
          j,
          limitOf(200, 30),
          op === "playlists" ? "playlist" : undefined,
        );
        if (!list.length && get("LOGGED_IN") !== true && op !== "home")
          throw fail(SIGN_IN);
        return { [op]: list };
      }
      case "playlist": {
        const id = playlistId(o.playlist);
        const j = await call("browse", { browseId: "VL" + id });
        const header =
          first(j, "pageHeaderViewModel") ||
          first(j, "playlistHeaderRenderer") ||
          {};
        return {
          playlist: {
            id,
            title:
              text((first(header, "dynamicTextViewModel") || {}).text) ||
              text(header.title) ||
              undefined,
          },
          videos: items(j, limitOf(500, 100), "video"),
        };
      }
      case "channel": {
        const id = await channelId(o.channel);
        // Its Videos tab, latest first.
        const j = await call("browse", {
          browseId: id,
          params: "EgZ2aWRlb3PyBgQKAjoA",
        });
        const meta = first(j, "channelMetadataRenderer") || {};
        return {
          channel: {
            id,
            title: meta.title || undefined,
            description: meta.description
              ? String(meta.description).slice(0, 500)
              : undefined,
          },
          videos: items(j, limitOf(100, 20), "video"),
        };
      }

      case "play": {
        let id, picked;
        if (o.video) id = videoId(o.video);
        else if (o.query) {
          const query = String(o.query).trim();
          const j = await call("search", { query, params: "EgIQAQ==" });
          picked = items(j, 1, "video")[0];
          if (!picked)
            throw fail(`no video found for ${JSON.stringify(query)}`);
          id = picked.id;
        } else if (!o.playlist)
          throw fail(
            "`video` (its id or link), `query` (the first video found) or `playlist`",
          );
        const list = o.playlist ? playlistId(o.playlist) : null;
        if (!id) {
          // A playlist alone: from its first video.
          const j = await call("browse", { browseId: "VL" + list });
          const head = items(j, 1, "video")[0];
          if (!head) throw fail("that playlist has no video to play");
          id = head.id;
        }
        const at = Number(o.at) > 0 ? Number(o.at) : 0;
        return { ...(await watch(id, at, list)), found: picked };
      }
      case "open": {
        const want = String(o.page || o.url || "").trim();
        let u = null;
        try {
          u = new URL(PAGES[want] ? PAGES[want][1] : want, location.origin);
        } catch (e) {
          u = null;
        }
        if (
          !u ||
          (!PAGES[want] && !/^https?:\/\//.test(want)) ||
          !/(^|\.)youtube\.com$|^youtu\.be$/.test(u.hostname)
        )
          throw fail(
            `\`page\`: ${Object.keys(PAGES).join(", ")}, or \`url\`: a YouTube link`,
          );
        // Where YouTube itself says that address leads.
        const j = await call("navigation/resolve_url", { url: u.href });
        const endpoint = j && j.endpoint;
        if (!endpoint || endpoint.urlEndpoint)
          throw fail("YouTube doesn't know that link");
        // The address to show (a channel's @handle resolves with the
        // resolver's own).
        const meta = (endpoint.commandMetadata || {}).webCommandMetadata;
        if (meta) meta.url = u.pathname + u.search;
        if (u.href === location.href)
          return { opened: location.href, title: document.title };
        const from = location.href;
        const inPage = await navigate(
          endpoint,
          u.href,
          () => location.href !== from,
        );
        await sleep(inPage ? 600 : 0);
        return {
          opened: inPage ? location.href : u.href,
          title: document.title,
        };
      }
      case "pause":
        needPlayer().pauseVideo();
        await sleep(150);
        return { playing: playing() };
      case "resume":
        needPlayer().playVideo();
        await sleep(300);
        return { playing: playing() };
      case "toggle": {
        const p = needPlayer();
        if ([1, 3].includes(p.getPlayerState())) p.pauseVideo();
        else p.playVideo();
        await sleep(300);
        return { playing: playing() };
      }
      case "seek": {
        const p = needPlayer();
        const to =
          o.to !== undefined && o.to !== null
            ? Number(o.to)
            : p.getCurrentTime() + Number(o.by);
        if (!Number.isFinite(to))
          throw fail(
            "`to` (seconds from the start) or `by` (seconds, back when negative)",
          );
        p.seekTo(Math.max(0, Math.min(to, p.getDuration() || to)), true);
        await sleep(250);
        return { playing: playing() };
      }
      case "volume": {
        const p = needPlayer();
        const level = Number(o.level);
        if (!Number.isFinite(level) || level < 0 || level > 100)
          throw fail("`level`: 0 to 100");
        p.setVolume(Math.round(level));
        if (level > 0 && p.isMuted()) p.unMute();
        await sleep(100);
        return { playing: playing() };
      }
      case "mute":
      case "unmute": {
        const p = needPlayer();
        if (op === "mute") p.mute();
        else p.unMute();
        await sleep(100);
        return { playing: playing() };
      }
      case "speed": {
        const p = needPlayer();
        const rate = Number(o.rate);
        const rates = p.getAvailablePlaybackRates
          ? p.getAvailablePlaybackRates()
          : [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
        if (!rates.includes(rate))
          throw fail(`\`rate\`: one of ${rates.join(", ")}`);
        p.setPlaybackRate(rate);
        await sleep(100);
        return { playing: playing() };
      }
      case "next":
      case "previous": {
        const p = needPlayer();
        const before = p.getVideoData().video_id;
        if (op === "next") p.nextVideo();
        else p.previousVideo();
        for (let i = 0; i < 16; i++) {
          await sleep(250);
          if ((p.getVideoData() || {}).video_id !== before) break;
        }
        return { playing: playing() };
      }
      case "captions": {
        const p = needPlayer();
        const on = o.on !== false && o.on !== "off";
        if (!on) {
          if (p.unloadModule) p.unloadModule("captions");
          await sleep(150);
          return { captions: false, playing: playing() };
        }
        if (p.loadModule) p.loadModule("captions");
        let tracks = [];
        for (let i = 0; i < 8 && !tracks.length; i++) {
          await sleep(250);
          tracks = (p.getOption && p.getOption("captions", "tracklist")) || [];
        }
        if (!tracks.length) throw fail("this video has no captions");
        const want = String(o.language || "").toLowerCase();
        const track = want
          ? tracks.find(
              (t) =>
                String(t.languageCode).toLowerCase() === want ||
                String(t.languageName || t.displayName || "")
                  .toLowerCase()
                  .includes(want),
            )
          : tracks[0];
        if (!track)
          throw fail(
            `no captions in ${JSON.stringify(o.language)}: ${tracks
              .map(
                (t) => `${t.languageCode} (${t.languageName || t.displayName})`,
              )
              .join(", ")}`,
          );
        p.setOption("captions", "track", { languageCode: track.languageCode });
        await sleep(150);
        return { captions: track.languageCode, playing: playing() };
      }

      case "like":
      case "dislike":
      case "unlike": {
        const v = videoId(o.video);
        const ep =
          op === "like"
            ? "like/like"
            : op === "dislike"
              ? "like/dislike"
              : "like/removelike";
        await call(ep, { target: { videoId: v } });
        return { [op === "unlike" ? "unliked" : op + "d"]: v };
      }
      case "subscribe":
      case "unsubscribe": {
        const id = await channelId(o.channel);
        await call(`subscription/${op}`, { channelIds: [id] });
        return { [op + "d"]: id };
      }
      case "watch_later_add":
      case "watch_later_remove": {
        const ids = videos(o.video || o.videos);
        await call("browse/edit_playlist", {
          playlistId: "WL",
          actions: ids.map((v) =>
            op === "watch_later_add"
              ? { action: "ACTION_ADD_VIDEO", addedVideoId: v }
              : {
                  action: "ACTION_REMOVE_VIDEO_BY_VIDEO_ID",
                  removedVideoId: v,
                },
          ),
        });
        return { [op === "watch_later_add" ? "added" : "removed"]: ids };
      }
      case "playlist_create": {
        const title = String(o.title || "")
          .trim()
          .slice(0, 150);
        if (!title) throw fail("`title`: the new playlist's");
        const privacy = String(o.privacy || "PRIVATE").toUpperCase();
        if (!["PRIVATE", "UNLISTED", "PUBLIC"].includes(privacy))
          throw fail("privacy: private, unlisted or public");
        const j = await call("playlist/create", {
          title,
          description: String(o.description || "").slice(0, 5000),
          privacyStatus: privacy,
          ...(o.videos ? { videoIds: videos(o.videos) } : {}),
        });
        return { created: { id: j && j.playlistId, title, privacy } };
      }
      case "playlist_add":
      case "playlist_remove": {
        const id = playlistId(o.playlist);
        const ids = videos(o.videos || o.video);
        const j = await call("browse/edit_playlist", {
          playlistId: id,
          actions: ids.map((v) =>
            op === "playlist_add"
              ? { action: "ACTION_ADD_VIDEO", addedVideoId: v }
              : {
                  action: "ACTION_REMOVE_VIDEO_BY_VIDEO_ID",
                  removedVideoId: v,
                },
          ),
        });
        return {
          playlist: id,
          [op === "playlist_add" ? "added" : "removed"]: ids,
          status: j && j.status,
        };
      }
      case "playlist_delete": {
        const id = playlistId(o.playlist);
        if (id === "WL" || id === "LL")
          throw fail("Watch later and the liked videos can't be deleted");
        await call("playlist/delete", { playlistId: id });
        return { deleted: id };
      }
      case "innertube": {
        const ep = String(o.endpoint || "").replace(/^\/+/, "");
        if (!/^[a-z_]+(\/[a-z_]+)?$/.test(ep))
          throw fail("endpoint: an InnerTube path, e.g. browse or next");
        if (OFF_LIMITS.test(ep))
          throw fail(`refused: ${ep} is the account's own`);
        const j = await call(
          ep,
          o.body && typeof o.body === "object" ? o.body : {},
        );
        // A whole page is too big to hand over: what it lists, then.
        if (JSON.stringify(j || null).length > 200000)
          return { endpoint: ep, truncated: true, items: items(j, 200) };
        return { endpoint: ep, result: j };
      }

      case "look": {
        // YouTube's own Appearance setting, as its menu sets it.
        const mode = String(o.mode || "");
        const dark = document.documentElement.hasAttribute("dark");
        // A look chosen in its menu is two bits of the PREF cookie's f6
        // (0x400 dark, 0x80000 light); neither: the device's.
        const pref = (/(?:^|;\s*)PREF=([^;]*)/.exec(document.cookie) || [])[1];
        const f6 = parseInt(
          (/(?:^|&)f6=([0-9a-f]+)/.exec(pref || "") || [])[1],
          16,
        );
        const chosen = !!(f6 & 0x80400);
        const fn =
          mode === "dark"
            ? !dark && "handleSignalActionToggleDarkThemeOn"
            : mode === "light"
              ? dark && "handleSignalActionToggleDarkThemeOff"
              : mode === "device"
                ? chosen && "handleSignalActionToggleDarkThemeDevice"
                : null;
        if (fn === null) throw fail("mode: light, dark or device");
        if (fn && typeof app[fn] !== "function")
          throw fail("YouTube's page no longer has that setting's switch");
        if (fn) app[fn]();
        return { look: mode, changed: !!fn };
      }
      default:
        return { error: `unknown operation ${op}` };
    }
  } catch (e) {
    if (e && typeof e.nixbook === "string") return { error: e.nixbook };
    return { error: String((e && e.message) || e).slice(0, 300) };
  }
}
