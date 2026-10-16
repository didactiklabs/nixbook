// The Spotify desktop app's MPRIS interface, through playerctl. Works without
// any Spotify account setup, as long as the app is running.
import { execFile } from "node:child_process";

const PLAYERCTL = process.env.PLAYERCTL ?? "playerctl";
const PLAYER = process.env.SPOTIFY_MPRIS_PLAYER ?? "spotify";
const SEP = "\u001f";
const FIELDS = [
  "status",
  "xesam:title",
  "xesam:artist",
  "xesam:album",
  "xesam:url",
  "mpris:length",
  "position",
];

export class MprisError extends Error {}

export function playerctl(...args) {
  return new Promise((resolve, reject) => {
    execFile(
      PLAYERCTL,
      ["--player", PLAYER, ...args],
      { timeout: 10_000 },
      (error, stdout, stderr) => {
        if (!error) return resolve(stdout.trim());
        if (error.code === "ENOENT")
          return reject(new MprisError(`${PLAYERCTL} is not installed.`));
        const message = (stderr || error.message).trim();
        reject(
          new MprisError(
            /no players? found/i.test(message)
              ? "The Spotify app is not running. Start it, then try again."
              : `playerctl ${args.join(" ")} failed: ${message}`,
          ),
        );
      },
    );
  });
}

/** The current track, or null when nothing is loaded. Times in seconds. */
export async function nowPlaying() {
  const out = await playerctl(
    "metadata",
    "--format",
    FIELDS.map((f) => `{{${f}}}`).join(SEP),
  );
  if (!out) return null;
  const [status, title, artist, album, url, length, position] = out.split(SEP);
  if (!title) return null;
  return {
    status,
    title,
    artist,
    album,
    url,
    durationSeconds: Math.round(Number(length) / 1e6) || undefined,
    positionSeconds: Math.round(Number(position) / 1e6) || 0,
  };
}

/** Open a Spotify URI (spotify:track:…, spotify:playlist:…, or an open.spotify.com link) and play it. */
export async function openUri(uri) {
  await playerctl("open", toUri(uri));
}

export function toUri(value) {
  const match =
    /^https?:\/\/open\.spotify\.com\/(?:intl-[a-z-]+\/)?(\w+)\/(\w+)/i.exec(
      value,
    );
  if (match) return `spotify:${match[1]}:${match[2]}`;
  if (/^spotify:\w+:\w+/.test(value)) return value;
  throw new MprisError(`Not a Spotify URI or link: ${value}`);
}
