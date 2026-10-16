// The Spotify Web API, for what MPRIS can't do (search, queue, playlists).
// Logs in with OAuth PKCE (no client secret) through a loopback redirect, so it
// only needs the client ID of the user's own Spotify developer app.
import { createHash, randomBytes } from "node:crypto";
import { execFile } from "node:child_process";
import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const API_URL = (
  process.env.SPOTIFY_API_URL ?? "https://api.spotify.com/v1"
).replace(/\/$/, "");
const ACCOUNTS_URL = (
  process.env.SPOTIFY_ACCOUNTS_URL ?? "https://accounts.spotify.com"
).replace(/\/$/, "");
const REDIRECT_PORT = Number(process.env.SPOTIFY_REDIRECT_PORT ?? 8898);
export const REDIRECT_URI = `http://127.0.0.1:${REDIRECT_PORT}/callback`;
const CONFIG_FILE =
  process.env.SPOTIFY_MCP_CONFIG ??
  join(
    process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"),
    "spotify-mcp",
    "auth.json",
  );
const SCOPES = [
  "user-read-playback-state",
  "user-modify-playback-state",
  "user-read-currently-playing",
  "playlist-read-private",
  "playlist-read-collaborative",
  "user-library-read",
].join(" ");
const LOGIN_TIMEOUT_MS = 10 * 60_000;

export class WebApiError extends Error {}

let auth; // { clientId, accessToken, refreshToken, expiresAt }

async function loadAuth() {
  if (auth) return auth;
  try {
    auth = JSON.parse(await readFile(CONFIG_FILE, "utf8"));
  } catch {
    auth = {};
  }
  if (process.env.SPOTIFY_CLIENT_ID)
    auth.clientId ??= process.env.SPOTIFY_CLIENT_ID;
  return auth;
}

async function saveAuth() {
  await mkdir(dirname(CONFIG_FILE), { recursive: true });
  await writeFile(CONFIG_FILE, JSON.stringify(auth), { mode: 0o600 });
}

async function tokenRequest(params) {
  let res;
  try {
    res = await fetch(`${ACCOUNTS_URL}/api/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(params),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    throw new WebApiError(
      `Cannot reach Spotify: ${error.cause?.code ?? error.message}`,
    );
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok)
    throw new WebApiError(
      `Spotify login failed: ${body.error_description ?? body.error ?? res.status}`,
    );
  auth.accessToken = body.access_token;
  auth.refreshToken = body.refresh_token ?? auth.refreshToken;
  auth.expiresAt = Date.now() + (body.expires_in - 60) * 1000;
  await saveAuth();
}

export async function isLoggedIn() {
  return Boolean((await loadAuth()).refreshToken);
}

let pendingLogin;

/**
 * Start a login: returns the URL the user opens (also opened in the browser).
 * A loopback server on REDIRECT_URI receives the code and stores the tokens.
 */
export async function startLogin(clientId) {
  await loadAuth();
  if (clientId) auth.clientId = clientId;
  if (!auth.clientId) {
    throw new WebApiError(
      "A Spotify client ID is needed: create an app at https://developer.spotify.com/dashboard " +
        `(Web API, redirect URI ${REDIRECT_URI}) and pass its client ID to login.`,
    );
  }
  pendingLogin?.close();

  const verifier = randomBytes(48).toString("base64url");
  const state = randomBytes(16).toString("base64url");
  const url = new URL(`${ACCOUNTS_URL}/authorize`);
  url.search = new URLSearchParams({
    client_id: auth.clientId,
    response_type: "code",
    redirect_uri: REDIRECT_URI,
    scope: SCOPES,
    state,
    code_challenge_method: "S256",
    code_challenge: createHash("sha256").update(verifier).digest("base64url"),
  });

  const server = createServer(async (req, res) => {
    const params = new URL(req.url, REDIRECT_URI).searchParams;
    if (!req.url.startsWith("/callback") || params.get("state") !== state) {
      res.writeHead(404).end();
      return;
    }
    let message = "Logged in to Spotify. You can close this tab.";
    try {
      if (params.get("error"))
        throw new WebApiError(
          `Spotify login was refused: ${params.get("error")}`,
        );
      await tokenRequest({
        grant_type: "authorization_code",
        code: params.get("code"),
        redirect_uri: REDIRECT_URI,
        client_id: auth.clientId,
        code_verifier: verifier,
      });
    } catch (error) {
      message = error.message;
    }
    res
      .writeHead(200, { "Content-Type": "text/plain; charset=utf-8" })
      .end(message);
    server.close();
  });
  await new Promise((resolve, reject) => {
    server.once("error", (error) =>
      reject(
        new WebApiError(
          `Cannot listen on ${REDIRECT_URI}: ${error.code ?? error.message}`,
        ),
      ),
    );
    server.listen(REDIRECT_PORT, "127.0.0.1", resolve);
  });
  setTimeout(() => server.close(), LOGIN_TIMEOUT_MS).unref();
  pendingLogin = server;
  await saveAuth();

  if (!process.env.SPOTIFY_MCP_NO_BROWSER)
    execFile("xdg-open", [url.href], () => {});
  return url.href;
}

async function accessToken() {
  await loadAuth();
  if (!auth.refreshToken) {
    throw new WebApiError(
      "Not logged in to the Spotify Web API: call the login tool first.",
    );
  }
  if (!auth.accessToken || Date.now() >= auth.expiresAt) {
    await tokenRequest({
      grant_type: "refresh_token",
      refresh_token: auth.refreshToken,
      client_id: auth.clientId,
    });
  }
  return auth.accessToken;
}

/** Call the Web API. `path` is relative to /v1, query values are added as search params. */
export async function api(method, path, { query, body } = {}) {
  const url = new URL(`${API_URL}${path}`);
  for (const [key, value] of Object.entries(query ?? {}))
    if (value !== undefined) url.searchParams.set(key, value);
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await fetch(url, {
        method,
        headers: {
          Authorization: `Bearer ${await accessToken()}`,
          ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(15_000),
      });
    } catch (error) {
      if (error instanceof WebApiError) throw error;
      throw new WebApiError(
        `Cannot reach Spotify: ${error.cause?.code ?? error.message}`,
      );
    }
    if (res.status === 401 && attempt === 0) {
      auth.accessToken = undefined;
      continue;
    }
    if (res.status === 204 || res.status === 202) return null;
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) {
      const reason = data?.error?.message ?? res.statusText;
      if (res.status === 404 && path.startsWith("/me/player")) {
        throw new WebApiError(
          `No active Spotify device (${reason}): start playing something in the app first.`,
        );
      }
      if (res.status === 403 && path.startsWith("/me/player")) {
        throw new WebApiError(
          `Spotify refused (${reason}): playback control through the Web API needs Premium.`,
        );
      }
      throw new WebApiError(
        `${method} ${path} failed: ${res.status} ${reason}`,
      );
    }
    return data;
  }
}
