#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import { nowPlaying, openUri, playerctl, toUri } from "./mpris.js";
import { api, isLoggedIn, REDIRECT_URI, startLogin } from "./webapi.js";

const server = new McpServer({ name: "spotify", version: "0.1.0" });

const text = (value) => ({
  content: [
    {
      type: "text",
      text: typeof value === "string" ? value : JSON.stringify(value, null, 2),
    },
  ],
});

// Every tool reports failures as tool errors so the model sees what went wrong.
function tool(name, description, inputSchema, handler) {
  server.registerTool(name, { description, inputSchema }, async (args) => {
    try {
      return await handler(args);
    } catch (error) {
      return { ...text(error.message), isError: true };
    }
  });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const artists = (item) => item?.artists?.map((a) => a.name).join(", ");

function trackSummary(t) {
  if (!t) return null;
  return {
    name: t.name,
    artists: artists(t) ?? t.show?.name,
    album: t.album?.name,
    uri: t.uri,
    durationSeconds: Math.round(t.duration_ms / 1000),
  };
}

const SUMMARIES = {
  track: trackSummary,
  album: (a) => ({
    name: a.name,
    artists: artists(a),
    released: a.release_date,
    uri: a.uri,
  }),
  artist: (a) => ({ name: a.name, uri: a.uri }),
  playlist: (p) => ({ name: p.name, owner: p.owner?.display_name, uri: p.uri }),
};

async function search(query, type, limit) {
  const data = await api("GET", "/search", {
    query: { q: query, type, limit },
  });
  return (data?.[`${type}s`]?.items ?? []).filter(Boolean).map(SUMMARIES[type]);
}

async function resolveUri(query, uri, type) {
  if (uri) return { uri: toUri(uri) };
  if (!query) throw new Error("Provide a query or a uri.");
  const [match] = await search(query, type, 1);
  if (!match) throw new Error(`Nothing found on Spotify for "${query}".`);
  return match;
}

tool(
  "login",
  "Log in to the Spotify Web API (needed for search, queue, playlists, shuffle and repeat). " +
    "Returns a URL the user opens to approve; it is also opened in their browser. Only needed once.",
  {
    client_id: z
      .string()
      .optional()
      .describe(
        `Client ID of the user's app from developer.spotify.com/dashboard (redirect URI ${REDIRECT_URI}); remembered after the first login`,
      ),
  },
  async ({ client_id }) => {
    const url = await startLogin(client_id);
    return text(
      `Open this link and approve access (it was opened in the browser too):\n${url}`,
    );
  },
);

tool(
  "now_playing",
  "The track playing in the Spotify app, with its position.",
  {},
  async () => text((await nowPlaying()) ?? "Nothing is playing."),
);

tool(
  "search",
  "Search Spotify (needs login). Returns uris to pass to play or add_to_queue. At most 10 results.",
  {
    query: z.string().describe('e.g. "Mass Destruction Lotus Juice"'),
    type: z.enum(["track", "album", "artist", "playlist"]).default("track"),
    limit: z.number().int().min(1).max(10).default(5),
  },
  async ({ query, type, limit }) => {
    const results = await search(query, type, limit);
    return text(results.length ? results : `Nothing found for "${query}".`);
  },
);

tool(
  "play",
  "Play something now in the Spotify app: a uri/link (works without login), or the first search match for a query (needs login).",
  {
    query: z
      .string()
      .optional()
      .describe("What to search for, e.g. a song and artist"),
    type: z
      .enum(["track", "album", "artist", "playlist"])
      .default("track")
      .describe("What the query is for"),
    uri: z
      .string()
      .optional()
      .describe("spotify:… uri or open.spotify.com link"),
  },
  async ({ query, type, uri }) => {
    const target = await resolveUri(query, uri, type);
    await openUri(target.uri);
    await sleep(1500);
    return text({
      requested: target,
      nowPlaying: await nowPlaying().catch(() => null),
    });
  },
);

tool(
  "add_to_queue",
  "Add a track to the Spotify queue (needs login and Premium).",
  {
    query: z
      .string()
      .optional()
      .describe("Song name, optionally with the artist"),
    uri: z.string().optional().describe("spotify:track:… uri or link"),
  },
  async ({ query, uri }) => {
    const target = await resolveUri(query, uri, "track");
    await api("POST", "/me/player/queue", { query: { uri: target.uri } });
    return text(
      `Queued ${target.name ? `${target.name} (${target.artists})` : target.uri}.`,
    );
  },
);

tool(
  "get_queue",
  "The current track and the upcoming queue (needs login).",
  {},
  async () => {
    const data = await api("GET", "/me/player/queue");
    return text({
      current: trackSummary(data?.currently_playing),
      upcoming: (data?.queue ?? []).slice(0, 20).map(trackSummary),
    });
  },
);

tool(
  "my_playlists",
  "The user's playlists (needs login). Pass a playlist's uri to play.",
  { limit: z.number().int().min(1).max(50).default(30) },
  async ({ limit }) => {
    const data = await api("GET", "/me/playlists", { query: { limit } });
    return text((data?.items ?? []).filter(Boolean).map(SUMMARIES.playlist));
  },
);

const CONTROLS = {
  play: "play",
  pause: "pause",
  toggle: "play-pause",
  next: "next",
  previous: "previous",
};

tool(
  "playback",
  "Control the Spotify app: play, pause, toggle, next, previous.",
  { action: z.enum(Object.keys(CONTROLS)) },
  async ({ action }) => {
    await playerctl(CONTROLS[action]);
    return text(`Done: ${action}.`);
  },
);

tool(
  "seek",
  "Seek within the current track: to a position, or forward/back by some seconds.",
  {
    seconds: z.number().min(0),
    mode: z.enum(["to", "forward", "back"]).default("to"),
  },
  async ({ seconds, mode }) => {
    await playerctl(
      "position",
      `${seconds}${{ to: "", forward: "+", back: "-" }[mode]}`,
    );
    return text(`Seeked ${mode} ${seconds}s.`);
  },
);

tool(
  "volume",
  "Get Spotify's volume, or set it (0-100).",
  { volume: z.number().int().min(0).max(100).optional() },
  async ({ volume }) => {
    // The Web API is more reliable for volume; MPRIS without a login.
    if (await isLoggedIn()) {
      if (volume !== undefined)
        await api("PUT", "/me/player/volume", {
          query: { volume_percent: volume },
        });
      const player = await api("GET", "/me/player");
      return text({ volume: player?.device?.volume_percent ?? volume });
    }
    if (volume !== undefined) await playerctl("volume", String(volume / 100));
    return text({
      volume: Math.round(Number(await playerctl("volume")) * 100),
    });
  },
);

tool(
  "shuffle_repeat",
  "Get or set shuffle and repeat (needs login and Premium).",
  {
    shuffle: z.boolean().optional(),
    repeat: z
      .enum(["off", "context", "track"])
      .optional()
      .describe("context = repeat the album/playlist"),
  },
  async ({ shuffle, repeat }) => {
    if (shuffle !== undefined)
      await api("PUT", "/me/player/shuffle", { query: { state: shuffle } });
    if (repeat !== undefined)
      await api("PUT", "/me/player/repeat", { query: { state: repeat } });
    const player = await api("GET", "/me/player");
    return text({
      shuffle: player?.shuffle_state,
      repeat: player?.repeat_state,
    });
  },
);

await server.connect(new StdioServerTransport());
console.error("Spotify MCP server running on stdio");
