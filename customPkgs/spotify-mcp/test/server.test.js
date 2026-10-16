import assert from "node:assert/strict";
import { createServer } from "node:http";
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

import { toUri } from "../src/mpris.js";

let dir;
let mock;
let client;
const calls = [];
const redirectPort = 20000 + Math.floor(Math.random() * 20000);

// playerctl stand-in: logs its arguments, answers metadata and volume.
const PLAYERCTL = `#!/bin/sh
echo "$*" >> "$PLAYERCTL_LOG"
case "$3" in
  metadata) printf 'Playing\\037Mass Destruction\\037Lotus Juice\\037Persona 3 OST\\037https://open.spotify.com/track/abc\\037240000000\\03712000000' ;;
  volume) echo 0.5 ;;
esac
`;

before(async () => {
  dir = await mkdtemp(join(tmpdir(), "spotify-mcp-"));
  await writeFile(join(dir, "playerctl"), PLAYERCTL);
  await chmod(join(dir, "playerctl"), 0o755);

  // Spotify's accounts and Web API, on one port.
  mock = createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    const url = new URL(req.url, "http://x");
    const send = (status, data) => {
      res.writeHead(status, { "Content-Type": "application/json" });
      res.end(data === undefined ? undefined : JSON.stringify(data));
    };
    if (url.pathname === "/accounts/api/token") {
      const form = new URLSearchParams(body);
      calls.push(`token ${form.get("grant_type")}`);
      return send(200, {
        access_token: "access",
        refresh_token: "refresh",
        expires_in: 3600,
      });
    }
    if (req.headers.authorization !== "Bearer access")
      return send(401, { error: { message: "bad token" } });
    calls.push(`${req.method} ${url.pathname}${url.search}`);
    if (url.pathname === "/v1/search") {
      return send(200, {
        tracks: {
          items: [
            {
              name: "Mass Destruction",
              artists: [{ name: "Lotus Juice" }],
              album: { name: "Persona 3 OST" },
              uri: "spotify:track:abc",
              duration_ms: 240000,
            },
          ],
        },
      });
    }
    if (url.pathname === "/v1/me/player/queue" && req.method === "POST")
      return send(204);
    return send(404, { error: { message: "not mocked" } });
  });
  await new Promise((resolve) => mock.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${mock.address().port}`;

  client = new Client({ name: "test", version: "0" });
  await client.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: ["src/index.js"],
      env: {
        PATH: process.env.PATH,
        PLAYERCTL: join(dir, "playerctl"),
        PLAYERCTL_LOG: join(dir, "playerctl.log"),
        SPOTIFY_API_URL: `${base}/v1`,
        SPOTIFY_ACCOUNTS_URL: `${base}/accounts`,
        SPOTIFY_REDIRECT_PORT: String(redirectPort),
        SPOTIFY_MCP_CONFIG: join(dir, "auth.json"),
        SPOTIFY_MCP_NO_BROWSER: "1",
      },
    }),
  );
});

after(async () => {
  await client?.close();
  mock?.close();
});

const call = async (name, args = {}) => {
  const result = await client.callTool({ name, arguments: args });
  return { ...result, body: result.content[0].text };
};
const playerctlLog = async () =>
  (await readFile(join(dir, "playerctl.log"), "utf8").catch(() => ""))
    .trim()
    .split("\n");

test("toUri accepts uris and open.spotify.com links", () => {
  assert.equal(toUri("spotify:track:abc"), "spotify:track:abc");
  assert.equal(
    toUri("https://open.spotify.com/intl-fr/playlist/37i9dQ?si=x"),
    "spotify:playlist:37i9dQ",
  );
  assert.throws(() => toUri("mass destruction"));
});

test("MPRIS tools work without login", async () => {
  const now = await call("now_playing");
  assert.deepEqual(JSON.parse(now.body), {
    status: "Playing",
    title: "Mass Destruction",
    artist: "Lotus Juice",
    album: "Persona 3 OST",
    url: "https://open.spotify.com/track/abc",
    durationSeconds: 240,
    positionSeconds: 12,
  });
  assert.ok(!(await call("playback", { action: "toggle" })).isError);
  assert.ok(!(await call("seek", { seconds: 10, mode: "back" })).isError);
  assert.equal(JSON.parse((await call("volume")).body).volume, 50);
  const log = await playerctlLog();
  assert.ok(log.includes("--player spotify play-pause"));
  assert.ok(log.includes("--player spotify position 10-"));
});

test("search before login asks to log in", async () => {
  const result = await call("search", { query: "x" });
  assert.equal(result.isError, true);
  assert.match(result.body, /login/);
});

test("login, then search, play and queue", async () => {
  const login = await call("login", { client_id: "my-client" });
  assert.ok(!login.isError, login.body);
  const authorize = new URL(login.body.match(/https?:\/\/\S+/)[0]);
  assert.equal(authorize.searchParams.get("client_id"), "my-client");
  assert.equal(authorize.searchParams.get("code_challenge_method"), "S256");

  // The browser follows Spotify's redirect back to the loopback server.
  const state = authorize.searchParams.get("state");
  const callback = await fetch(
    `http://127.0.0.1:${redirectPort}/callback?code=c0de&state=${state}`,
  );
  assert.match(await callback.text(), /Logged in/);
  assert.ok(calls.includes("token authorization_code"));
  assert.equal(
    JSON.parse(await readFile(join(dir, "auth.json"), "utf8")).refreshToken,
    "refresh",
  );

  const search = await call("search", { query: "mass destruction" });
  assert.equal(JSON.parse(search.body)[0].uri, "spotify:track:abc");

  const play = await call("play", { query: "mass destruction" });
  assert.ok(!play.isError, play.body);
  assert.ok(
    (await playerctlLog()).includes("--player spotify open spotify:track:abc"),
  );

  const queue = await call("add_to_queue", {
    uri: "https://open.spotify.com/track/def",
  });
  assert.ok(!queue.isError, queue.body);
  assert.ok(
    calls.includes("POST /v1/me/player/queue?uri=spotify%3Atrack%3Adef"),
  );
});
