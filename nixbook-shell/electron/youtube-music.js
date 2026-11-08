// nixbook's YouTube Music library operations (the `youtube_music` tool of
// nixbook-desktop-mcp), run by the Electron bridge
// (scripts/electron-bridge.py) in pear-desktop's page, through YouTube
// Music's own client: the app element's network manager (the InnerTube
// API, signed by the page itself), else the page's own fetch with its
// signed-in cookies. Playback and the queue are the youtube-music MCP
// server's (the app's API Server plugin); this is the library: playlists,
// likes, subscriptions, history. No cookie or header is ever returned.
//
//   nixbookApp(op, args) → a plain object, or {error}
//
// Operations: status, playlists, playlist {playlist, limit?} (its tracks,
// each with videoId and setVideoId), liked {limit?}, history {limit?},
// library {kind: songs|albums|artists|subscriptions, limit?},
// playlist_create {title, description?, privacy?, videos?},
// playlist_add {playlist, videos}, playlist_remove {playlist, videos},
// playlist_rename {playlist, title?, description?, privacy?},
// playlist_delete {playlist}, like / dislike / unlike {video},
// subscribe / unsubscribe {channel}, innertube {endpoint, body?}: any
// other InnerTube call of the page (browse, next, search…), never the
// account's own settings.
// A playlist is its id (PL…, VL…, LM) or its title in the library.
"use strict";

async function nixbookApp(op, o) {
  o = o || {};
  const app = document.querySelector("ytmusic-app");
  const cfg = globalThis.ytcfg;
  const get = (k) =>
    cfg && cfg.get ? cfg.get(k) : cfg && cfg.data_ ? cfg.data_[k] : undefined;
  if (!app && !cfg)
    return { error: "YouTube Music is still loading: try again in a moment" };

  function fail(msg) {
    return { nixbook: msg };
  }
  function fold(s) {
    return String(s || "")
      .normalize("NFKD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .trim();
  }
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
    const nm = app && (app.networkManager || app.networkManager_);
    if (nm && typeof nm.fetch === "function")
      return nm.fetch(`/${endpoint}`, body || {});
    const key = get("INNERTUBE_API_KEY");
    const context = get("INNERTUBE_CONTEXT");
    if (!context) throw fail("YouTube Music's client isn't ready");
    const auth = await sapisidHash();
    const r = await fetch(
      `/youtubei/v1/${endpoint}?prettyPrint=false${key ? "&key=" + key : ""}`,
      {
        method: "POST",
        credentials: "include",
        headers: {
          "Content-Type": "application/json",
          "X-Origin": location.origin,
          ...(auth ? { Authorization: auth } : {}),
        },
        body: JSON.stringify({ context, ...(body || {}) }),
      },
    );
    const j = await r.json().catch(() => null);
    if (!r.ok)
      throw fail(
        `YouTube Music said ${r.status}${j && j.error ? ": " + j.error.message : ""}`,
      );
    return j;
  }
  function text(t) {
    if (!t) return "";
    if (t.simpleText) return t.simpleText;
    return (t.runs || []).map((r) => r.text).join("");
  }
  // Every renderer of a kind in an answer, wherever it is.
  function collect(node, key, out = [], depth = 0) {
    if (!node || typeof node !== "object" || depth > 40) return out;
    if (Array.isArray(node)) {
      for (const x of node) collect(x, key, out, depth + 1);
      return out;
    }
    for (const [k, v] of Object.entries(node)) {
      if (k === key) out.push(v);
      else collect(v, key, out, depth + 1);
    }
    return out;
  }
  function track(r) {
    const cols = (r.flexColumns || []).map((c) =>
      text((c.musicResponsiveListItemFlexColumnRenderer || {}).text),
    );
    const data = r.playlistItemData || {};
    let videoId = data.videoId;
    if (!videoId) {
      const w = collect(r.overlay, "watchEndpoint")[0];
      videoId = w && w.videoId;
    }
    const nav = collect(r, "browseEndpoint")[0];
    return {
      title: cols[0] || "",
      by: cols[1] || "",
      album: cols[2] || undefined,
      videoId: videoId || undefined,
      setVideoId: data.playlistSetVideoId || undefined,
      browseId: !videoId && nav ? nav.browseId : undefined,
    };
  }
  function card(r) {
    const nav = collect(r.navigationEndpoint || r, "browseEndpoint")[0] || {};
    return {
      title: text(r.title),
      subtitle: text(r.subtitle),
      id: nav.browseId || undefined,
    };
  }
  async function browse(browseId, limit) {
    const j = await call("browse", { browseId });
    const tracks = collect(j, "musicResponsiveListItemRenderer").map(track);
    const cards = collect(j, "musicTwoRowItemRenderer").map(card);
    const header =
      collect(j, "musicResponsiveHeaderRenderer")[0] ||
      collect(j, "musicDetailHeaderRenderer")[0];
    return {
      title: header ? text(header.title) : undefined,
      tracks: tracks.slice(0, limit),
      items: cards.slice(0, limit),
    };
  }
  const limitOf = () => Math.max(1, Math.min(500, Number(o.limit) || 100));
  async function playlistsAll() {
    const b = await browse("FEmusic_liked_playlists", 500);
    return b.items
      .filter((x) => x.id && /^VL|^LM/.test(x.id))
      .map((x) => ({
        id: x.id.replace(/^VL/, ""),
        title: x.title,
        subtitle: x.subtitle,
      }));
  }
  async function playlistFor(want) {
    const s = String(want || "").trim();
    if (!s) throw fail("`playlist`: its id or title");
    if (/^(VL)?(PL|RD|OL|LM|SE)[\w-]*$/.test(s) && s.length >= 2)
      return { id: s.replace(/^VL/, ""), title: s };
    const all = await playlistsAll();
    const q = fold(s);
    const exact = all.filter((p) => fold(p.title) === q);
    const some = exact.length
      ? exact
      : all.filter((p) => fold(p.title).includes(q));
    if (some.length === 1) return some[0];
    throw fail(
      some.length
        ? `${JSON.stringify(s)} could be ${some
            .slice(0, 6)
            .map((p) => `${p.title} = ${p.id}`)
            .join(", ")}`
        : `no playlist ${JSON.stringify(s)} in the library: ${all
            .slice(0, 30)
            .map((p) => p.title)
            .join(", ")}`,
    );
  }
  function videos(v) {
    const list = (Array.isArray(v) ? v : [v])
      .map((x) => String(x || "").trim())
      .filter(Boolean);
    if (!list.length || list.some((x) => !/^[\w-]{11}$/.test(x)))
      throw fail(
        "`videos`: videoIds (11 characters; the youtube-music search gives them)",
      );
    return list.slice(0, 100);
  }
  const OFF_LIMITS =
    /^(account|accounts|notification|get_settings|set_setting|ypc|upload|feedback\/delete)/;

  try {
    switch (op) {
      case "status":
        return {
          ready: true,
          signedIn: get("LOGGED_IN") !== false,
          client: !!(app && app.networkManager),
        };
      case "playlists":
        return { playlists: await playlistsAll() };
      case "playlist": {
        const p = await playlistFor(o.playlist);
        const b = await browse("VL" + p.id, limitOf());
        return {
          playlist: { id: p.id, title: b.title || p.title },
          tracks: b.tracks,
        };
      }
      case "liked": {
        const b = await browse("VLLM", limitOf());
        return { tracks: b.tracks };
      }
      case "history": {
        const b = await browse("FEmusic_history", limitOf());
        return { tracks: b.tracks };
      }
      case "library": {
        const ids = {
          songs: "FEmusic_liked_videos",
          albums: "FEmusic_liked_albums",
          artists: "FEmusic_library_corpus_track_artists",
          subscriptions: "FEmusic_library_corpus_artists",
        };
        const id = ids[String(o.kind || "")];
        if (!id) throw fail("kind: songs, albums, artists or subscriptions");
        const b = await browse(id, limitOf());
        return {
          kind: o.kind,
          tracks: b.tracks.length ? b.tracks : undefined,
          items: b.items.length ? b.items : undefined,
        };
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
      case "playlist_add": {
        const p = await playlistFor(o.playlist);
        const ids = videos(o.videos);
        const j = await call("browse/edit_playlist", {
          playlistId: p.id,
          actions: ids.map((v) => ({
            action: "ACTION_ADD_VIDEO",
            addedVideoId: v,
          })),
        });
        return { playlist: p.title, added: ids.length, status: j && j.status };
      }
      case "playlist_remove": {
        const p = await playlistFor(o.playlist);
        const ids = new Set(videos(o.videos));
        const b = await browse("VL" + p.id, 5000);
        const hits = b.tracks.filter((t) => ids.has(t.videoId) && t.setVideoId);
        if (!hits.length) throw fail(`none of those videos is in ${p.title}`);
        await call("browse/edit_playlist", {
          playlistId: p.id,
          actions: hits.map((t) => ({
            action: "ACTION_REMOVE_VIDEO",
            setVideoId: t.setVideoId,
            removedVideoId: t.videoId,
          })),
        });
        return { playlist: p.title, removed: hits.map((t) => t.title) };
      }
      case "playlist_rename": {
        const p = await playlistFor(o.playlist);
        const actions = [];
        if (o.title)
          actions.push({
            action: "ACTION_SET_PLAYLIST_NAME",
            playlistName: String(o.title).slice(0, 150),
          });
        if (o.description !== undefined)
          actions.push({
            action: "ACTION_SET_PLAYLIST_DESCRIPTION",
            playlistDescription: String(o.description).slice(0, 5000),
          });
        if (o.privacy) {
          const pr = String(o.privacy).toUpperCase();
          if (!["PRIVATE", "UNLISTED", "PUBLIC"].includes(pr))
            throw fail("privacy: private, unlisted or public");
          actions.push({
            action: "ACTION_SET_PLAYLIST_PRIVACY",
            playlistPrivacy: pr,
          });
        }
        if (!actions.length)
          throw fail("nothing to change: title, description or privacy");
        await call("browse/edit_playlist", { playlistId: p.id, actions });
        return { playlist: p.id, changed: actions.map((a) => a.action) };
      }
      case "playlist_delete": {
        const p = await playlistFor(o.playlist);
        if (p.id === "LM") throw fail("the liked songs can't be deleted");
        await call("playlist/delete", { playlistId: p.id });
        return { deleted: p.title || p.id };
      }
      case "like":
      case "dislike":
      case "unlike": {
        const [v] = videos(o.video);
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
        const id = String(o.channel || "").trim();
        if (!/^UC[\w-]{20,}$/.test(id))
          throw fail("`channel`: the artist's channel id (UC…)");
        await call(`subscription/${op}`, { channelIds: [id] });
        return { [op + "d"]: id };
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
          return {
            endpoint: ep,
            truncated: true,
            tracks: collect(j, "musicResponsiveListItemRenderer")
              .map(track)
              .slice(0, 200),
            items: collect(j, "musicTwoRowItemRenderer")
              .map(card)
              .slice(0, 200),
          };
        return { endpoint: ep, result: j };
      }
      default:
        return { error: `unknown operation ${op}` };
    }
  } catch (e) {
    if (e && typeof e.nixbook === "string") return { error: e.nixbook };
    return { error: String((e && e.message) || e).slice(0, 300) };
  }
}
