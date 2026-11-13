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
    function wanted(target, choice) {
        return Links.wanted(target, choice)
    }
}
