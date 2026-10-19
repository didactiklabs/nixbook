import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const BASE_URL = (process.env.YTM_API_URL ?? "http://127.0.0.1:26538").replace(
  /\/$/,
  "",
);
const CLIENT_ID = process.env.YTM_CLIENT_ID ?? "claude-mcp";
const TOKEN_FILE =
  process.env.YTM_TOKEN_FILE ??
  join(
    process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"),
    "youtube-music-mcp",
    "token.json",
  );
// Approving the request means clicking "Allow" in a dialog inside the app, so give it time.
const AUTH_TIMEOUT_MS = 120_000;
const REQUEST_TIMEOUT_MS = 15_000;

export class ApiError extends Error {}

let token;
let authenticating; // one "Allow" dialog for concurrent calls

async function loadToken() {
  if (process.env.YTM_TOKEN) return process.env.YTM_TOKEN;
  try {
    const saved = JSON.parse(await readFile(TOKEN_FILE, "utf8"));
    if (saved.baseUrl === BASE_URL && saved.clientId === CLIENT_ID)
      return saved.accessToken;
  } catch {
    // no saved token yet
  }
  return undefined;
}

async function fetchWithTimeout(url, init, timeoutMs) {
  try {
    return await fetch(url, {
      ...init,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    const reason =
      error.name === "TimeoutError"
        ? "timed out"
        : (error.cause?.code ?? error.message);
    throw new ApiError(
      `Cannot reach YouTube Music at ${BASE_URL} (${reason}). Is the app running with the ` +
        `"API Server" plugin enabled (Plugins menu → API Server)?`,
    );
  }
}

async function authenticate() {
  const res = await fetchWithTimeout(
    `${BASE_URL}/auth/${encodeURIComponent(CLIENT_ID)}`,
    { method: "POST" },
    AUTH_TIMEOUT_MS,
  );
  if (res.status === 403) {
    throw new ApiError(
      'Access was denied in the YouTube Music app. Call the tool again and click "Allow".',
    );
  }
  if (!res.ok) throw new ApiError(`Authorization failed: HTTP ${res.status}`);
  const { accessToken } = await res.json();
  // Private to the user, also when the file was there already (writeFile's
  // mode only applies to a new file).
  await mkdir(dirname(TOKEN_FILE), { recursive: true, mode: 0o700 });
  await writeFile(
    TOKEN_FILE,
    JSON.stringify({ baseUrl: BASE_URL, clientId: CLIENT_ID, accessToken }),
    { mode: 0o600 },
  );
  await chmod(TOKEN_FILE, 0o600);
  return accessToken;
}

/**
 * Call the app's REST API (/api/v1/...). Requests a token on first use, which makes the app
 * show an "Allow / Deny" dialog, and again whenever the saved token is rejected.
 */
export async function api(method, path, body) {
  token ??= await loadToken();
  for (let attempt = 0; ; attempt++) {
    const res = await fetchWithTimeout(
      `${BASE_URL}/api/v1${path}`,
      {
        method,
        headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
      },
      REQUEST_TIMEOUT_MS,
    );
    if (res.status === 401 && attempt === 0 && !process.env.YTM_TOKEN) {
      authenticating ??= authenticate().finally(() => {
        authenticating = undefined;
      });
      token = await authenticating;
      continue;
    }
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new ApiError(
        `${method} ${path} failed: HTTP ${res.status}${text ? ` ${text.slice(0, 300)}` : ""}`,
      );
    }
    if (res.status === 204) return null;
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }
}
