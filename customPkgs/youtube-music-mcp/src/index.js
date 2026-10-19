#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import { api } from "./client.js";
import { parseSearchResults, SEARCH_FILTERS } from "./search.js";

const server = new McpServer({ name: "youtube-music", version: "0.1.0" });

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

async function currentSong() {
  const song = await api("GET", "/song");
  if (!song) return null;
  const {
    title,
    artist,
    album,
    videoId,
    isPaused,
    elapsedSeconds,
    songDuration,
    url,
  } = song;
  return {
    title,
    artist,
    album,
    videoId,
    isPaused,
    elapsedSeconds,
    songDuration,
    url,
  };
}

function queueItems(queue) {
  return (queue?.items ?? []).map((item, index) => {
    const video =
      item.playlistPanelVideoRenderer ??
      item.playlistPanelVideoWrapperRenderer?.primaryRenderer
        ?.playlistPanelVideoRenderer ??
      {};
    const runs = (t) =>
      t?.runs?.map((r) => r.text).join("") ?? t?.simpleText ?? "";
    return {
      index,
      title: runs(video.title),
      artist: runs(video.shortBylineText),
      duration: runs(video.lengthText),
      videoId: video.videoId,
      current: Boolean(video.selected),
    };
  });
}

async function search(query, filter, limit) {
  const params = filter === "all" ? undefined : SEARCH_FILTERS[filter];
  const response = await api("POST", "/search", {
    query,
    ...(params ? { params } : {}),
  });
  return parseSearchResults(response).slice(0, limit);
}

/**
 * Wait until the app really plays (`videoId`, if given): a play sent while it
 * is still switching tracks is lost, leaving it paused, so press play again,
 * and `retry` (switch again) when another track stays loaded. Throws with
 * what is loaded when it never starts, so a caller can't report it playing.
 */
async function ensurePlaying(videoId, retry) {
  let song;
  for (let i = 0; i < 12; i++) {
    song = await currentSong();
    const right = song && (!videoId || song.videoId === videoId);
    if (right && !song.isPaused) return song;
    if (right) await api("POST", "/play");
    else if (retry && i % 4 === 3) await retry();
    await sleep(500);
  }
  throw new Error(
    song
      ? `YouTube Music didn't start playing: it has "${song.title}" by ${song.artist} loaded, ` +
          `${song.isPaused ? "paused" : "playing"}${videoId && song.videoId !== videoId ? ", not the requested track" : ""}.`
      : "YouTube Music didn't start playing: nothing is loaded.",
  );
}

/** Put a track right after the current one and switch to it. */
async function playVideo(videoId) {
  await api("POST", "/queue", {
    videoId,
    insertPosition: "INSERT_AFTER_CURRENT_VIDEO",
  });
  // The app fetches the track's queue data asynchronously, so wait for it to show up.
  for (let i = 0; i < 20; i++) {
    await sleep(250);
    const items = queueItems(await api("GET", "/queue"));
    const currentIndex = items.findIndex((it) => it.current);
    const target =
      items.find(
        (it) => it.videoId === videoId && it.index === currentIndex + 1,
      ) ?? items.find((it) => it.videoId === videoId);
    if (target) {
      const jump = () => api("PATCH", "/queue", { index: target.index });
      if (!target.current) await jump();
      await api("POST", "/play");
      return ensurePlaying(videoId, jump);
    }
  }
  throw new Error(
    "The track was not added to the queue. YouTube Music needs something loaded in the player first: " +
      "start any song in the app, then try again.",
  );
}

tool(
  "search",
  "Search YouTube Music. Returns results with videoId (playable, pass to play or add_to_queue).",
  {
    query: z
      .string()
      .describe('Search text, e.g. "Mass Destruction Persona 3"'),
    filter: z
      .enum(["songs", "videos", "albums", "artists", "all"])
      .default("songs"),
    limit: z.number().int().min(1).max(50).default(10),
  },
  async ({ query, filter, limit }) => {
    const results = await search(query, filter, limit);
    return text(results.length ? results : `No results for "${query}".`);
  },
);

tool(
  "play",
  "Play a song now in the YouTube Music app. Give either a search query (song and artist) or a videoId from search. " +
    "Returns once it really plays; an error says what is loaded instead.",
  {
    query: z
      .string()
      .optional()
      .describe("Song name, optionally with the artist"),
    videoId: z
      .string()
      .optional()
      .describe("Exact video id to play (from search)"),
  },
  async ({ query, videoId }) => {
    if (!videoId) {
      if (!query) throw new Error("Provide a query or a videoId.");
      const match = (await search(query, "songs", 5)).find((r) => r.videoId);
      if (!match) return text(`No playable song found for "${query}".`);
      videoId = match.videoId;
    }
    return text({ nowPlaying: await playVideo(videoId) });
  },
);

tool(
  "add_to_queue",
  "Add a song to the queue, either next or at the end.",
  {
    query: z
      .string()
      .optional()
      .describe("Song name, optionally with the artist"),
    videoId: z.string().optional(),
    position: z.enum(["next", "end"]).default("end"),
  },
  async ({ query, videoId, position }) => {
    let label = videoId;
    if (!videoId) {
      if (!query) throw new Error("Provide a query or a videoId.");
      const match = (await search(query, "songs", 5)).find((r) => r.videoId);
      if (!match) return text(`No playable song found for "${query}".`);
      ({ videoId } = match);
      label = `${match.title} (${match.subtitle})`;
    }
    await api("POST", "/queue", {
      videoId,
      insertPosition:
        position === "next" ? "INSERT_AFTER_CURRENT_VIDEO" : "INSERT_AT_END",
    });
    return text(
      `Queued ${label} ${position === "next" ? "to play next" : "at the end"}.`,
    );
  },
);

tool(
  "now_playing",
  "Get the song currently loaded in YouTube Music and the playback position.",
  {},
  async () => text((await currentSong()) ?? "Nothing is playing."),
);

const CONTROLS = {
  play: ["POST", "/play"],
  pause: ["POST", "/pause"],
  toggle: ["POST", "/toggle-play"],
  next: ["POST", "/next"],
  previous: ["POST", "/previous"],
  like: ["POST", "/like"],
  dislike: ["POST", "/dislike"],
  shuffle: ["POST", "/shuffle"],
  toggle_mute: ["POST", "/toggle-mute"],
};

tool(
  "playback",
  "Control playback: play, pause, toggle, next, previous, like, dislike, shuffle (shuffles the queue), toggle_mute.",
  { action: z.enum(Object.keys(CONTROLS)) },
  async ({ action }) => {
    await api(...CONTROLS[action]);
    if (action === "play") return text({ nowPlaying: await ensurePlaying() });
    return text(`Done: ${action}.`);
  },
);

tool(
  "seek",
  "Seek within the current song: to an absolute position, or forward/back by a number of seconds.",
  {
    seconds: z.number().describe("Position, or offset for forward/back"),
    mode: z.enum(["to", "forward", "back"]).default("to"),
  },
  async ({ seconds, mode }) => {
    if (mode === "to") await api("POST", "/seek-to", { seconds });
    else
      await api("POST", mode === "forward" ? "/go-forward" : "/go-back", {
        seconds,
      });
    return text(`Seeked ${mode} ${seconds}s.`);
  },
);

tool(
  "volume",
  "Get the volume, or set it (0-100).",
  { volume: z.number().min(0).max(100).optional() },
  async ({ volume }) => {
    if (volume !== undefined) await api("POST", "/volume", { volume });
    return text(await api("GET", "/volume"));
  },
);

tool(
  "repeat",
  "Get the repeat mode (NONE, ALL, ONE), or cycle it a number of steps.",
  {
    steps: z
      .number()
      .int()
      .min(1)
      .max(2)
      .optional()
      .describe("How many times to cycle NONE → ALL → ONE"),
  },
  async ({ steps }) => {
    if (steps) await api("POST", "/switch-repeat", { iteration: steps });
    return text(await api("GET", "/repeat-mode"));
  },
);

tool("get_queue", "List the songs in the play queue.", {}, async () => {
  const items = queueItems(await api("GET", "/queue"));
  return text(items.length ? items : "The queue is empty.");
});

tool(
  "edit_queue",
  "Change the queue: jump to an index, move or remove an item, or clear it. Indexes come from get_queue.",
  {
    action: z.enum(["jump", "move", "remove", "clear"]),
    index: z.number().int().min(0).optional(),
    toIndex: z
      .number()
      .int()
      .min(0)
      .optional()
      .describe("Target index for move"),
  },
  async ({ action, index, toIndex }) => {
    if (action === "clear") {
      await api("DELETE", "/queue");
      return text("Queue cleared.");
    }
    if (index === undefined) throw new Error(`"${action}" needs an index.`);
    if (action === "jump") await api("PATCH", "/queue", { index });
    if (action === "remove") await api("DELETE", `/queue/${index}`);
    if (action === "move") {
      if (toIndex === undefined) throw new Error('"move" needs toIndex.');
      await api("PATCH", `/queue/${index}`, { toIndex });
    }
    return text(`Done: ${action}.`);
  },
);

await server.connect(new StdioServerTransport());
console.error("YouTube Music MCP server running on stdio");
