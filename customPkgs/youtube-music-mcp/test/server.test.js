import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

import { parseSearchResults } from "../src/search.js";

const runs = (text) => ({ runs: [{ text }] });
const listItem = (videoId, title, subtitle) => ({
  musicResponsiveListItemRenderer: {
    playlistItemData: { videoId },
    flexColumns: [
      { musicResponsiveListItemFlexColumnRenderer: { text: runs(title) } },
      { musicResponsiveListItemFlexColumnRenderer: { text: runs(subtitle) } },
    ],
  },
});
const SEARCH_RESPONSE = {
  contents: {
    tabbedSearchResultsRenderer: {
      tabs: [
        {
          tabRenderer: {
            content: {
              sectionListRenderer: {
                contents: [
                  {
                    musicShelfRenderer: {
                      contents: [
                        listItem(
                          "abc123",
                          "Mass Destruction",
                          "Song • Lotus Juice",
                        ),
                      ],
                    },
                  },
                  {
                    musicShelfRenderer: {
                      contents: [
                        listItem(
                          "def456",
                          "Burn My Dread",
                          "Song • Yumi Kawamura",
                        ),
                        listItem("abc123", "dup", "dup"),
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

test("parseSearchResults flattens and dedupes list items", () => {
  assert.deepEqual(parseSearchResults(SEARCH_RESPONSE), [
    {
      title: "Mass Destruction",
      subtitle: "Song • Lotus Juice",
      videoId: "abc123",
      browseId: undefined,
    },
    {
      title: "Burn My Dread",
      subtitle: "Song • Yumi Kawamura",
      videoId: "def456",
      browseId: undefined,
    },
  ]);
});

// A mock of the app's API Server plugin, with AUTH_AT_FIRST auth.
const state = {
  queue: [{ videoId: "cur", title: "Current" }],
  index: 0,
  paused: false,
  // Plays the app drops (sent while it switches tracks).
  lostPlays: 0,
  // At the end of the queue: jumps in the queue are ignored, next works.
  ended: false,
  calls: [],
};
const queueResponse = () => ({
  items: state.queue.map((q, i) => ({
    playlistPanelVideoRenderer: {
      videoId: q.videoId,
      title: runs(q.title),
      selected: i === state.index,
    },
  })),
});
let mock;
let client;

before(async () => {
  mock = createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    const json = body ? JSON.parse(body) : undefined;
    const send = (status, data) => {
      res.writeHead(status, { "Content-Type": "application/json" });
      res.end(data === undefined ? undefined : JSON.stringify(data));
    };
    if (req.method === "POST" && req.url === "/auth/claude-mcp")
      return send(200, { accessToken: "tok" });
    if (req.headers.authorization !== "Bearer tok") return send(401);
    const route = `${req.method} ${req.url.replace("/api/v1", "")}`;
    state.calls.push(route);
    switch (route) {
      case "POST /search":
        return send(200, SEARCH_RESPONSE);
      case "POST /queue":
        // The real app adds asynchronously.
        setTimeout(
          () =>
            state.queue.splice(state.index + 1, 0, {
              videoId: json.videoId,
              title: "Added",
            }),
          300,
        );
        return send(204);
      case "GET /queue":
        return send(200, queueResponse());
      case "PATCH /queue":
        if (!state.ended) state.index = json.index;
        return send(204);
      case "POST /next":
        state.ended = false;
        state.index = Math.min(state.index + 1, state.queue.length - 1);
        state.paused = false;
        return send(204);
      case "GET /song": {
        const q = state.queue[state.index];
        return send(200, {
          title: q.title,
          artist: "X",
          videoId: q.videoId,
          isPaused: state.paused,
          songDuration: 100,
        });
      }
      case "POST /play":
        if (state.lostPlays > 0) state.lostPlays--;
        else state.paused = false;
        return send(204);
      case "POST /pause":
        state.paused = true;
        return send(204);
      default:
        return send(404);
    }
  });
  await new Promise((resolve) => mock.listen(0, "127.0.0.1", resolve));

  const configDir = await mkdtemp(join(tmpdir(), "ytm-mcp-"));
  client = new Client({ name: "test", version: "0" });
  await client.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: ["src/index.js"],
      env: {
        YTM_API_URL: `http://127.0.0.1:${mock.address().port}`,
        XDG_CONFIG_HOME: configDir,
      },
    }),
  );
});

after(async () => {
  await client?.close();
  mock?.close();
});

test("lists tools", async () => {
  const { tools } = await client.listTools();
  assert.ok(
    [
      "search",
      "play",
      "add_to_queue",
      "now_playing",
      "playback",
      "get_queue",
    ].every((n) => tools.some((t) => t.name === n)),
  );
});

test("play searches, queues after current, and jumps to it", async () => {
  const result = await client.callTool({
    name: "play",
    arguments: { query: "mass destruction" },
  });
  assert.ok(!result.isError, result.content[0].text);
  assert.equal(JSON.parse(result.content[0].text).nowPlaying.videoId, "abc123");
  assert.equal(state.index, 1);
  assert.ok(state.calls.includes("PATCH /queue"));
});

test("play presses play again when the first one is lost", async () => {
  state.paused = true;
  state.lostPlays = 1;
  const result = await client.callTool({
    name: "play",
    arguments: { videoId: "def456" },
  });
  assert.ok(!result.isError, result.content[0].text);
  const { nowPlaying } = JSON.parse(result.content[0].text);
  assert.equal(nowPlaying.videoId, "def456");
  assert.equal(nowPlaying.isPaused, false);
});

test("play moves on with next when the ended queue ignores the jump", async () => {
  state.paused = true;
  state.ended = true;
  const result = await client.callTool({
    name: "play",
    arguments: { videoId: "ghi789" },
  });
  state.ended = false;
  assert.ok(!result.isError, result.content[0].text);
  const { nowPlaying } = JSON.parse(result.content[0].text);
  assert.equal(nowPlaying.videoId, "ghi789");
  assert.equal(nowPlaying.isPaused, false);
});

test("play errors when the app stays paused", async () => {
  state.paused = true;
  state.lostPlays = 100;
  const result = await client.callTool({
    name: "playback",
    arguments: { action: "play" },
  });
  state.lostPlays = 0;
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /didn't start playing: .* paused/);
});

test("unreachable app gives a helpful error", async () => {
  const c = new Client({ name: "test", version: "0" });
  await c.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: ["src/index.js"],
      env: { YTM_API_URL: "http://127.0.0.1:1" },
    }),
  );
  const result = await c.callTool({ name: "now_playing", arguments: {} });
  await c.close();
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /API Server/);
});
