// The app's /search endpoint returns YouTube Music's raw (innertube) search response.
// These helpers flatten it into a list of results.

// Search filter params, as used by music.youtube.com's filter chips.
export const SEARCH_FILTERS = {
  songs: "EgWKAQIIAWoMEA4QChADEAQQCRAF",
  videos: "EgWKAQIQAWoMEA4QChADEAQQCRAF",
  albums: "EgWKAQIYAWoMEA4QChADEAQQCRAF",
  artists: "EgWKAQIgAWoMEA4QChADEAQQCRAF",
};

const runsText = (text) =>
  text?.runs?.map((r) => r.text).join("") ?? text?.simpleText ?? "";

function findFirst(node, key) {
  if (!node || typeof node !== "object") return undefined;
  if (key in node) return node[key];
  for (const value of Object.values(node)) {
    const found = findFirst(value, key);
    if (found !== undefined) return found;
  }
  return undefined;
}

function walk(node, visit) {
  if (!node || typeof node !== "object") return;
  visit(node);
  for (const value of Object.values(node)) walk(value, visit);
}

function fromListItem(item) {
  const columns = (item.flexColumns ?? []).map((c) =>
    runsText(c.musicResponsiveListItemFlexColumnRenderer?.text),
  );
  const videoId =
    item.playlistItemData?.videoId ??
    findFirst(item.overlay, "watchEndpoint")?.videoId;
  const browseId = item.navigationEndpoint?.browseEndpoint?.browseId;
  return {
    title: columns[0] ?? "",
    subtitle: columns.slice(1).filter(Boolean).join(" • "),
    videoId,
    browseId,
  };
}

function fromCard(card) {
  const watch =
    findFirst(card.title, "watchEndpoint") ??
    findFirst(card.thumbnailOverlay, "watchEndpoint");
  return {
    title: runsText(card.title),
    subtitle: runsText(card.subtitle),
    videoId: watch?.videoId,
    browseId: findFirst(card.title, "browseEndpoint")?.browseId,
    topResult: true,
  };
}

/** Flatten a raw search response into [{ title, subtitle, videoId?, browseId?, topResult? }]. */
export function parseSearchResults(response) {
  const results = [];
  const seen = new Set();
  walk(response, (node) => {
    let result;
    if (node.musicCardShelfRenderer)
      result = fromCard(node.musicCardShelfRenderer);
    else if (node.musicResponsiveListItemRenderer)
      result = fromListItem(node.musicResponsiveListItemRenderer);
    if (!result?.title) return;
    const key = result.videoId ?? result.browseId ?? result.title;
    if (seen.has(key)) return;
    seen.add(key);
    results.push(result);
  });
  return results;
}
