// nixbook's Discord operations (the `discord` tool of nixbook-desktop-mcp),
// run by the Electron bridge (scripts/electron-bridge.py) in Vesktop's page,
// through Discord's own client code as Vencord exposes it
// (Vencord.Webpack.Common): the stores the app already has, and its own
// REST client for what isn't loaded (it adds the credentials itself: no
// token, cookie or header is read here, nor ever returned).
//
//   nixbookApp(op, args) → a plain object, or {error}
//
// Operations: status, current, guilds, channels {guild}, dms, find {query},
// read {channel, limit}, send {channel, content, reply_to?}, react
// {channel, message, emoji}. A channel is its id, `user:<id>` (the direct
// messages with someone), or a name find resolves to one channel.
"use strict";

async function nixbookApp(op, o) {
  const V = globalThis.Vencord;
  const C = V && V.Webpack && V.Webpack.Common;
  if (!C || !C.UserStore || !C.ChannelStore)
    return {
      error:
        "Discord is still loading (Vencord isn't ready): try again in a moment",
    };
  const me = C.UserStore.getCurrentUser && C.UserStore.getCurrentUser();
  if (op === "status")
    return {
      loggedIn: !!me,
      user: me ? userName(me) : null,
      vencord: true,
      current: me ? describe(currentChannel()) : null,
    };
  if (!me)
    return {
      error:
        "Discord isn't logged in (or still loading): ask the user to log in to Vesktop",
    };

  function fold(s) {
    return String(s || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/^[#@]/, "")
      .trim();
  }
  function userName(u) {
    return u ? u.globalName || u.global_name || u.username || "" : "";
  }
  function guildName(id) {
    const g = id && C.GuildStore && C.GuildStore.getGuild(id);
    return g ? g.name : "";
  }
  function recipients(ch) {
    const ids = ch.recipients || (ch.rawRecipients || []).map((r) => r.id);
    return ids.map((id) => C.UserStore.getUser(id)).filter(Boolean);
  }
  function channelName(ch) {
    if (!ch) return "";
    if (ch.type === 1) return "@" + userName(recipients(ch)[0]);
    if (ch.type === 3)
      return ch.name || recipients(ch).map(userName).join(", ");
    return "#" + (ch.name || ch.id);
  }
  function describe(ch) {
    if (!ch) return null;
    const out = {
      id: ch.id,
      kind: ch.type === 1 ? "dm" : ch.type === 3 ? "group" : "channel",
      name: channelName(ch),
    };
    if (ch.guild_id) {
      out.guild = guildName(ch.guild_id);
      out.guildId = ch.guild_id;
    }
    return out;
  }
  function currentChannel() {
    const id = C.SelectedChannelStore && C.SelectedChannelStore.getChannelId();
    return id ? C.ChannelStore.getChannel(id) : null;
  }
  function guilds() {
    const all = C.GuildStore.getGuilds ? C.GuildStore.getGuilds() : {};
    return Object.values(all || {});
  }
  function textChannels(guildId) {
    const g = C.GuildChannelStore && C.GuildChannelStore.getChannels(guildId);
    const list = ((g && g.SELECTABLE) || []).map((x) => x.channel || x);
    // Text and announcement channels, and the threads the store knows.
    return list.filter((ch) => ch && [0, 5, 10, 11, 12].includes(ch.type));
  }
  function privateChannels() {
    const s = C.ChannelStore;
    if (s.getSortedPrivateChannels) return s.getSortedPrivateChannels();
    const ids = s.getPrivateChannelIds ? s.getPrivateChannelIds() : [];
    return ids.map((id) => s.getChannel(id)).filter(Boolean);
  }
  function findAll(query) {
    const q = fold(query);
    if (!q) return [];
    const hits = [];
    const score = (name) => {
      const n = fold(name);
      return n === q ? 3 : n.startsWith(q) ? 2 : n.includes(q) ? 1 : 0;
    };
    for (const ch of privateChannels()) {
      const s = Math.max(
        score(channelName(ch)),
        ...recipients(ch).map((u) =>
          Math.max(score(userName(u)), score(u.username)),
        ),
      );
      if (s) hits.push([s + 0.5, describe(ch)]);
    }
    for (const g of guilds())
      for (const ch of textChannels(g.id)) {
        const s = score(ch.name);
        if (s) hits.push([s, describe(ch)]);
      }
    // Friends without a conversation open yet: `user:<id>`.
    const R = C.RelationshipStore;
    const friends = R && R.getFriendIDs ? R.getFriendIDs() : [];
    for (const id of friends) {
      if (hits.some(([, h]) => h.kind === "dm" && h.userId === id)) continue;
      const u = C.UserStore.getUser(id);
      const s = u ? Math.max(score(userName(u)), score(u.username)) : 0;
      const dm =
        C.ChannelStore.getDMFromUserId && C.ChannelStore.getDMFromUserId(id);
      if (s && !dm)
        hits.push([
          s,
          { id: "user:" + id, kind: "user", name: "@" + userName(u) },
        ]);
    }
    hits.sort((a, b) => b[0] - a[0]);
    return hits.map(([s, h]) => ({ ...h, exact: s >= 3 }));
  }
  async function channelFor(to) {
    const s = String(to || "").trim();
    if (!s) {
      const ch = currentChannel();
      if (!ch) throw new Error("no channel given, and none is open in Discord");
      return ch;
    }
    if (/^\d{15,22}$/.test(s)) {
      const ch = C.ChannelStore.getChannel(s);
      if (!ch) throw new Error(`no channel ${s} here (discord find gives ids)`);
      return ch;
    }
    let userId = (/^user:(\d{15,22})$/.exec(s) || [])[1];
    if (!userId) {
      const hits = findAll(s);
      const exact = hits.filter((h) => h.exact);
      const pick =
        exact.length === 1 ? exact[0] : hits.length === 1 ? hits[0] : null;
      if (!pick)
        throw new Error(
          hits.length
            ? `${JSON.stringify(s)} is ambiguous: ${hits
                .slice(0, 6)
                .map(
                  (h) =>
                    `${h.name}${h.guild ? " (" + h.guild + ")" : ""} = ${h.id}`,
                )
                .join(", ")}; give the id`
            : `nothing in Discord is called ${JSON.stringify(s)}`,
        );
      if (pick.kind !== "user") return C.ChannelStore.getChannel(pick.id);
      userId = pick.id.slice(5);
    }
    const dm =
      C.ChannelStore.getDMFromUserId && C.ChannelStore.getDMFromUserId(userId);
    if (dm) return C.ChannelStore.getChannel(dm);
    const A = C.ChannelActionCreators || {};
    const ensure = A.getOrEnsurePrivateChannel || A.ensurePrivateChannel;
    if (!ensure)
      throw new Error(
        "no conversation with them yet: ask the user to open one",
      );
    const id = await ensure.call(A, userId);
    const ch = C.ChannelStore.getChannel(
      typeof id === "string" ? id : (id && id.id) || "",
    );
    if (!ch) throw new Error("couldn't open a conversation with them");
    return ch;
  }
  function time(m) {
    const t = m.timestamp;
    try {
      return new Date(t && t.toISOString ? t.toISOString() : t).toISOString();
    } catch (e) {
      return "";
    }
  }
  function message(m) {
    const author = m.author || {};
    const mentions = (m.mentions || []).map((x) =>
      typeof x === "string" ? x : x.id,
    );
    const out = {
      id: m.id,
      author: userName(author) || author.username || "",
      mine: author.id === me.id,
      time: time(m),
      content: String(m.content || "").slice(0, 1500),
    };
    if (mentions.includes(me.id) || m.mentionEveryone || m.mention_everyone)
      out.mentionsMe = true;
    const ref = m.messageReference || m.message_reference;
    if (ref && ref.message_id) out.replyTo = ref.message_id;
    const files = (m.attachments || []).length;
    if (files) out.attachments = files;
    if ((m.embeds || []).length && !out.content) out.content = "[embed]";
    const reactions = (m.reactions || []).map((r) => ({
      emoji: (r.emoji && r.emoji.name) || "",
      count: r.count,
      me: !!r.me,
    }));
    if (reactions.length) out.reactions = reactions;
    return out;
  }

  try {
    switch (op) {
      case "current":
        return { channel: describe(currentChannel()) };
      case "guilds":
        return {
          guilds: guilds()
            .slice(0, 200)
            .map((g) => ({ id: g.id, name: g.name })),
        };
      case "channels": {
        const want = fold(o.guild);
        const g =
          guilds().find((x) => x.id === String(o.guild)) ||
          guilds().find((x) => fold(x.name) === want) ||
          guilds().find((x) => want && fold(x.name).includes(want));
        if (!g)
          return {
            error: `no server ${JSON.stringify(o.guild || "")} (discord guilds lists them)`,
          };
        return {
          guild: g.name,
          channels: textChannels(g.id).slice(0, 200).map(describe),
        };
      }
      case "dms":
        return {
          dms: privateChannels().slice(0, 50).map(describe),
        };
      case "find":
        return { results: findAll(o.query).slice(0, 20) };
      case "read": {
        const ch = await channelFor(o.channel);
        const limit = Math.max(1, Math.min(50, Number(o.limit) || 20));
        const stored = C.MessageStore && C.MessageStore.getMessages(ch.id);
        let list = stored
          ? stored._array || (stored.toArray ? stored.toArray() : [])
          : [];
        if (list.length < limit && C.RestAPI) {
          // Not loaded in the app: through Discord's own client (it doesn't
          // mark the channel read).
          const r = await C.RestAPI.get({
            url: `/channels/${ch.id}/messages`,
            query: { limit },
          });
          list = ((r && r.body) || []).slice().reverse();
        }
        return {
          channel: describe(ch),
          messages: list.slice(-limit).map(message),
        };
      }
      case "send": {
        const ch = await channelFor(o.channel);
        const content = String(o.content || "");
        const options = {};
        if (o.reply_to)
          options.messageReference = {
            channel_id: ch.id,
            message_id: String(o.reply_to),
            guild_id: ch.guild_id || undefined,
          };
        const data = {
          content,
          tts: false,
          invalidEmojis: [],
          validNonShortcutEmojis: [],
        };
        const started = Date.now();
        const send = V.Util && V.Util.sendMessage;
        const r = await (send
          ? send(ch.id, data, false, options)
          : C.MessageActions.sendMessage(ch.id, data, false, options));
        let id = r && ((r.body && r.body.id) || r.id);
        if (!id && C.MessageStore) {
          // Its id from the store: my last message there with this text.
          const s = C.MessageStore.getMessages(ch.id);
          const mine = (s ? s._array || [] : []).filter(
            (m) =>
              m.author &&
              m.author.id === me.id &&
              m.content === content &&
              new Date(time(m)).getTime() >= started - 5000,
          );
          if (mine.length) id = mine[mine.length - 1].id;
        }
        return { sent: true, id: id || null, channel: describe(ch) };
      }
      case "react": {
        const ch = await channelFor(o.channel);
        const emoji = String(o.emoji || "").trim();
        if (!emoji || emoji.length > 80)
          return { error: "an emoji: 👍, or name:id for a server's own" };
        if (!/^\d{15,22}$/.test(String(o.message || "")))
          return { error: "`message`: a message id (discord read gives them)" };
        await C.RestAPI.put({
          url: `/channels/${ch.id}/messages/${o.message}/reactions/${encodeURIComponent(emoji)}/@me`,
        });
        return { reacted: true, id: String(o.message), channel: describe(ch) };
      }
      default:
        return { error: `unknown operation ${op}` };
    }
  } catch (e) {
    const status = e && (e.status || (e.body && e.body.code));
    const msg =
      (e && e.body && e.body.message) || (e && e.message) || String(e);
    return {
      error: String(status ? `Discord said ${status}: ${msg}` : msg).slice(
        0,
        300,
      ),
    };
  }
}
