pragma Singleton
pragma ComponentBehavior: Bound

// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.modules.common
import qs.services

/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
	id: root;
	property list<MprisPlayer> players: Mpris.players.values.filter(player => isRealPlayer(player));
	property MprisPlayer trackedPlayer: null;

	readonly property string preferredPlayerName: Config.options.bar.media.preferredPlayer.trim().toLowerCase();
	readonly property MprisPlayer preferredPlayer: {
		if (preferredPlayerName.length === 0) return null;
		const _ = root.players.length;
		for (const p of root.players) {
			if ((p.identity ?? "").toLowerCase().includes(preferredPlayerName) ||
				(p.desktopEntry ?? "").toLowerCase().includes(preferredPlayerName))
				return p;
		}
		return null;
	}

	// Media source selection (the chips in the media popup / sidebars).
	// "" = Auto: the configured preferred player, else the one that last
	// started playing. A picked player is remembered by D-Bus name in
	// Persistent.states.media.selectedPlayer; while it's gone (app closed,
	// phone disconnected) Auto takes over, and it is picked again when it
	// comes back.
	readonly property string selectedKey: Persistent.states?.media?.selectedPlayer ?? ""
	readonly property bool autoSelect: root.selectedKey === ""
	readonly property MprisPlayer selectedPlayer: {
		if (root.selectedKey === "") return null;
		const _ = root.players.length;
		return root.players.find(p => p.dbusName === root.selectedKey) ?? null;
	}
	// The tracked player may be a filtered-out duplicate (playerctld, the
	// native browser bus when plasma-integration is active): only use it if real.
	readonly property MprisPlayer trackedRealPlayer: (root.trackedPlayer && root.players.includes(root.trackedPlayer)) ? root.trackedPlayer : null

	property MprisPlayer activePlayer: selectedPlayer ?? preferredPlayer ?? trackedRealPlayer ?? root.players[0] ?? null;

	function selectPlayer(player) {
		if (player && root.activePlayer) {
			root.__reverse = root.players.indexOf(player) < root.players.indexOf(root.activePlayer);
		}
		if (Persistent.states?.media)
			Persistent.states.media.selectedPlayer = player?.dbusName ?? "";
		if (player)
			root.trackedPlayer = player;
	}

	function cyclePlayer(delta) {
		if (root.players.length < 2) return;
		const i = root.players.indexOf(root.activePlayer);
		const n = root.players.length;
		root.selectPlayer(root.players[((i < 0 ? 0 : i) + delta + n) % n]);
	}

	// "phone" (KDE Connect republishes phone players as
	// org.mpris.MediaPlayer2.kdeconnect.mpris_*), "browser" or "app".
	readonly property var browserIds: ["firefox", "zen", "chromium", "chrome", "brave", "vivaldi", "librewolf", "floorp", "opera", "edge", "epiphany", "falkon", "qutebrowser", "plasma-browser-integration"]
	function playerSource(player) {
		const bus = (player?.dbusName ?? "").toLowerCase();
		if (bus.includes("kdeconnect")) return "phone";
		// Judge by the app (desktop entry / identity); the bus name only as a
		// last resort — Electron apps like YouTube Music register as
		// "chromium" without being a browser.
		const app = `${(player?.desktopEntry ?? "").toLowerCase()} ${(player?.identity ?? "").toLowerCase()}`.trim();
		const id = app.length > 0 ? app : bus;
		if (root.browserIds.some(b => id.includes(b))) return "browser";
		return "app";
	}

	function playerName(player) {
		if (!player) return "";
		const identity = player.identity || player.desktopEntry || player.dbusName.replace("org.mpris.MediaPlayer2.", "");
		// Some players (YouTube Music / pear-desktop) report a reverse-DNS id
		// as Identity: use the desktop entry's name instead.
		if (/^[\w-]+(\.[\w-]+)+$/.test(identity)) {
			const entry = DesktopEntries.heuristicLookup(player.desktopEntry || identity) ?? DesktopEntries.byId(identity);
			if (entry?.name) return entry.name;
			const last = identity.split(".").pop().replace(/[_-]+/g, " ");
			return last.replace(/\b\w/g, c => c.toUpperCase());
		}
		return identity.charAt(0).toUpperCase() + identity.slice(1);
	}

	// System icon name (for IconImage) or "" when a Material symbol fits better.
	function playerIcon(player) {
		if (!player || root.playerSource(player) === "phone") return "";
		return AppSearch.guessIcon(player.desktopEntry || player.identity || "");
	}
	function playerSymbol(player) {
		switch (root.playerSource(player)) {
		case "phone": return "smartphone";
		case "browser": return "public";
		default: return "music_note";
		}
	}
	signal trackChanged(reverse: bool);

	property bool __reverse: false;

	property var activeTrack;

	readonly property bool hasActivePlasmaIntegration: Mpris.players.values.some(
		p => p.dbusName?.startsWith('org.mpris.MediaPlayer2.plasma-browser-integration')
	)
	function isRealPlayer(player) {
        if (!Config.options.media.filterDuplicatePlayers) {
            return true;
        }
        return (
            // Remove native browser buses only if plasma-browser-integration is actually active on D-Bus
            !(hasActivePlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.firefox')) && !(hasActivePlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.chromium')) &&
            // playerctld just copies other buses and we don't need duplicates
            !player.dbusName?.startsWith('org.mpris.MediaPlayer2.playerctld') &&
            // Non-instance mpd bus
            !(player.dbusName?.endsWith('.mpd') && !player.dbusName.endsWith('MediaPlayer2.mpd')));
    }

	// Original stuff from fox below
	Instantiator {
		model: Mpris.players;

		Connections {
			required property MprisPlayer modelData;
			target: modelData;

			Component.onCompleted: {
				if (root.trackedPlayer == null || modelData.isPlaying) {
					root.trackedPlayer = modelData;
				}
			}

			Component.onDestruction: {
				if (root.trackedPlayer == null || !root.trackedPlayer.isPlaying) {
					for (const player of Mpris.players.values) {
						if (player.playbackState.isPlaying) {
							root.trackedPlayer = player;
							break;
						}
					}

					if (trackedPlayer == null && Mpris.players.values.length != 0) {
						trackedPlayer = Mpris.players.values[0];
					}
				}
			}

			function onPlaybackStateChanged() {
				if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData;
			}
		}
	}

	Connections {
		target: activePlayer

		function onPostTrackChanged() {
			root.updateTrack();
		}

		function onTrackArtUrlChanged() {
			// console.log("arturl:", activePlayer.trackArtUrl)
			// root.updateTrack();
			if (root.activePlayer.uniqueId == root.activeTrack.uniqueId && root.activePlayer.trackArtUrl != root.activeTrack.artUrl) {
				// cantata likes to send cover updates *BEFORE* updating the track info.
				// as such, art url changes shouldn't be able to break the reverse animation
				const r = root.__reverse;
				root.updateTrack();
				root.__reverse = r;

			}
		}
	}

	onActivePlayerChanged: this.updateTrack();

	function updateTrack() {
		//console.log(`update: ${this.activePlayer?.trackTitle ?? ""} : ${this.activePlayer?.trackArtists}`)
		this.activeTrack = {
			uniqueId: this.activePlayer?.uniqueId ?? 0,
			artUrl: this.activePlayer?.trackArtUrl ?? "",
			title: this.activePlayer?.trackTitle || Translation.tr("Unknown Title"),
			artist: this.activePlayer?.trackArtist || Translation.tr("Unknown Artist"),
			album: this.activePlayer?.trackAlbum || Translation.tr("Unknown Album"),
		};

		this.trackChanged(__reverse);
		this.__reverse = false;
	}

	property bool isPlaying: this.activePlayer && this.activePlayer.isPlaying;
	property bool canTogglePlaying: this.activePlayer?.canTogglePlaying ?? false;
	function togglePlaying() {
		if (this.canTogglePlaying) this.activePlayer.togglePlaying();
	}

	property bool canGoPrevious: this.activePlayer?.canGoPrevious ?? false;
	function previous() {
		if (this.canGoPrevious) {
			this.__reverse = true;
			this.activePlayer.previous();
		}
	}

	property bool canGoNext: this.activePlayer?.canGoNext ?? false;
	function next() {
		if (this.canGoNext) {
			this.__reverse = false;
			this.activePlayer.next();
		}
	}

	property bool canChangeVolume: this.activePlayer && this.activePlayer.volumeSupported && this.activePlayer.canControl;

	// ---------------------------------------------- extra transport actions
	// Shared by the dock card and the popup/sidebar player controls.
	function seekBy(player, seconds) {
		if (!player?.canSeek) return;
		const len = player.length > 0 ? player.length : Number.MAX_SAFE_INTEGER;
		player.position = Math.max(0, Math.min(len - 1, player.position + seconds));
	}
	function toggleShuffle(player) {
		if (player?.shuffleSupported && player?.canControl)
			player.shuffle = !player.shuffle;
	}
	// None -> Playlist -> Track -> None
	function cycleLoop(player) {
		if (!player?.loopSupported || !player?.canControl) return;
		player.loopState = player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
			: player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
			: MprisLoopState.None;
	}
	function loopIcon(player) {
		return player?.loopState === MprisLoopState.Track ? "repeat_one_on"
			: player?.loopState === MprisLoopState.Playlist ? "repeat_on" : "repeat";
	}
	function raisePlayer(player) {
		if (player?.canRaise) player.raise();
	}

	// Shareable link for the current track: xesam:url when it is a web link;
	// Spotify's /com/spotify/track/<id> track id otherwise.
	function trackUrl(player) {
		const md = player?.metadata ?? {};
		const url = String(md["xesam:url"] ?? "");
		if (/^https?:\/\//.test(url)) return url;
		const id = String(md["mpris:trackid"] ?? "");
		const m = id.match(/^\/com\/spotify\/(track|episode)\/(\w+)$/);
		if (m) return `https://open.spotify.com/${m[1]}/${m[2]}`;
		return "";
	}

	// A link/URI from the clipboard the player can open (OpenUri), normalised
	// to a scheme it supports: open.spotify.com links become spotify: URIs for
	// Spotify; plain http(s) links go to players that accept them (mpv, VLC…).
	function clipboardUriFor(player) {
		return root.uriForText(player, String(Quickshell.clipboardText ?? ""));
	}
	function uriForText(player, rawText) {
		const schemes = (player?.supportedUriSchemes ?? []).map(s => String(s).toLowerCase());
		if (schemes.length === 0) return "";
		const text = String(rawText ?? "").trim();
		if (text.length === 0 || text.length > 2048 || /\s/.test(text)) return "";
		const sp = text.match(/^https?:\/\/open\.spotify\.com\/(?:intl-\w+\/)?(track|album|playlist|artist|episode|show)\/(\w+)/);
		if (sp && schemes.includes("spotify")) return `spotify:${sp[1]}:${sp[2]}`;
		const scheme = (text.match(/^([a-z][a-z0-9+.-]*):/i)?.[1] ?? "").toLowerCase();
		return scheme !== "" && schemes.includes(scheme) ? text : "";
	}

	// ------------------------------------------------------ per-player volume
	// Chromium/Electron players (YouTube Music, browser tabs, Discord…) report
	// an MPRIS Volume but silently ignore writes, so volume buttons "did
	// nothing". Prefer the player's own PipeWire output stream (matched by
	// process binary / app name / desktop id, like the volume mixer rows);
	// fall back to MPRIS volume (e.g. KDE Connect phone players), then to the
	// default output.
	function appKey(s) {
		return (s ?? "").toLowerCase().replace(/^\./, "").replace(/-wrapped$/, "").replace(/[^a-z0-9]/g, "");
	}
	function playerKeys(player) {
		if (!player) return [];
		const entry = player.desktopEntry ?? "";
		const bus = (player.dbusName ?? "").replace("org.mpris.MediaPlayer2.", "").replace(/\.instance.*$/, "");
		return [player.identity, entry, entry.split(".").pop(), bus].map(root.appKey).filter(k => k.length > 1);
	}
	function streamFor(player) {
		if (!player || root.playerSource(player) === "phone") return null;
		const keys = root.playerKeys(player);
		if (keys.length === 0) return null;
		const streams = Audio.outputAppNodes;
		const props = n => n.properties ?? {};
		// Binary first (unique per app), then app name / id.
		const byBinary = streams.find(n => keys.includes(root.appKey(props(n)["application.process.binary"])));
		if (byBinary) return byBinary;
		return streams.find(n => {
			const ks = [props(n)["application.name"], props(n)["application.id"], n.name].map(root.appKey).filter(k => k.length > 1);
			return ks.some(sk => keys.some(pk => sk === pk || sk.includes(pk) || pk.includes(sk)));
		}) ?? null;
	}
	PwObjectTracker {
		objects: Audio.outputAppNodes
	}

	// Which control the volume helpers act on for this player.
	function volumeTarget(player) {
		// No player: never fall through to the system output.
		if (!player) return { kind: "none" };
		const stream = root.streamFor(player);
		if (stream?.audio) return { kind: "stream", node: stream };
		if (player?.volumeSupported && player?.canControl) return { kind: "mpris" };
		return { kind: "system", node: Audio.sink };
	}
	function playerVolume(player) {
		const t = root.volumeTarget(player);
		if (t.kind === "mpris") return player.volume ?? 0;
		return t.node?.audio?.volume ?? 0;
	}
	function playerMuted(player) {
		const t = root.volumeTarget(player);
		if (t.kind === "mpris") return (player.volume ?? 1) <= 0;
		return (t.node?.audio?.muted ?? false) || (t.node?.audio?.volume ?? 1) <= 0;
	}
	function setPlayerVolume(player, value) {
		if (!player) return;
		const v = Math.max(0, Math.min(1, value));
		const t = root.volumeTarget(player);
		if (t.kind === "mpris") {
			player.volume = v;
		} else if (t.node?.audio) {
			t.node.audio.muted = false;
			t.node.audio.volume = v;
		}
	}
	function adjustPlayerVolume(player, delta) {
		root.setPlayerVolume(player, root.playerVolume(player) + delta);
	}
	property var unmuteVolume: ({}) // mpris players: volume to restore on unmute
	function togglePlayerMute(player) {
		if (!player) return;
		const t = root.volumeTarget(player);
		if (t.kind === "mpris") {
			const key = player.dbusName;
			if ((player.volume ?? 1) > 0) {
				root.unmuteVolume[key] = player.volume;
				player.volume = 0;
			} else {
				player.volume = root.unmuteVolume[key] ?? 1;
			}
		} else if (t.node?.audio) {
			t.node.audio.muted = !t.node.audio.muted;
		}
	}

	property bool loopSupported: this.activePlayer && this.activePlayer.loopSupported && this.activePlayer.canControl;
	property var loopState: this.activePlayer?.loopState ?? MprisLoopState.None;
	function setLoopState(loopState: var) {
		if (this.loopSupported) {
			this.activePlayer.loopState = loopState;
		}
	}

	property bool shuffleSupported: this.activePlayer && this.activePlayer.shuffleSupported && this.activePlayer.canControl;
	property bool hasShuffle: this.activePlayer?.shuffle ?? false;
	function setShuffle(shuffle: bool) {
		if (this.shuffleSupported) {
			this.activePlayer.shuffle = shuffle;
		}
	}

	// Explicit user choice from a player card: same as picking it in a
	// source selector.
	function setActivePlayer(player: MprisPlayer) {
		if (player) {
			root.selectPlayer(player);
			return;
		}
		const targetPlayer = player ?? Mpris.players[0];
		console.log(`[Mpris] Active player ${targetPlayer} << ${activePlayer}`)

		if (targetPlayer && this.activePlayer) {
			this.__reverse = Mpris.players.indexOf(targetPlayer) < Mpris.players.indexOf(this.activePlayer);
		} else {
			// always animate forward if going to null
			this.__reverse = false;
		}

		this.trackedPlayer = targetPlayer;
	}

	IpcHandler {
		target: "mpris"

		function pauseAll(): void {
			for (const player of Mpris.players.values) {
				if (player.canPause) player.pause();
			}
		}

		function playPause(): void { root.togglePlaying(); }
		function previous(): void { root.previous(); }
		function next(): void { root.next(); }
	}
}