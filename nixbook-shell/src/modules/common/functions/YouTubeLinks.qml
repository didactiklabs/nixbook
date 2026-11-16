pragma Singleton
import Quickshell
import "youtube_links.js" as Links

/**
 * YouTube links the shell opens itself (youtube_links.js): a video, a
 * YouTube Music song or playlist, or null (services/YouTubeMusic.qml's
 * openLink).
 */
Singleton {
    function linkTarget(url) {
        return Links.linkTarget(url)
    }
    // `played`: play was pressed on the video's page (media.youtubeLinks.onPlay).
    function wanted(target, choice, played) {
        return Links.wanted(target, choice, played === true)
    }
    // A film, an episode or a series of the Jellyfin server `server`, or null.
    function jellyfinTarget(url, server) {
        return Links.jellyfinTarget(url, server)
    }
    // A YouTube link, else one of the Jellyfin server in `choice`, else null.
    function target(url, choice) {
        return Links.target(url, choice)
    }
}
