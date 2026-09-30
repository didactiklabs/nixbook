pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"
    // Where screenshots are saved ("" = only copied to the clipboard).
    readonly property string saveDir: FileUtils.expandHome(Config.options.screenSnip.savePath)

    // Sets $out to the file a copied screenshot goes to: in saveDir, named like
    // niri's own (Screenshot-%Y-%m-%d-%H-%M-%S.png), else a temporary one in
    // Directories.screenshotTemp (cleared on the next open).
    function outputFileCommand(saveDir) {
        const dir = StringUtils.shellSingleQuoteEscape(saveDir !== "" ? saveDir : Directories.screenshotTemp);
        const name = saveDir !== "" ? `Screenshot-$(date '+%Y-%m-%d-%H-%M-%S').png` : `snip-$(date '+%s%N').png`;
        return `mkdir -p '${dir}' && out='${dir}'/"${name}"`;
    }

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        // A zero size keeps the whole image (a window captured by niri).
        const cropBase = `magick '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
            + (rw > 0 && rh > 0 ? ` -crop ${rw}x${rh}+${rx}+${ry} +repage` : "")
        const cropToStdout = `${cropBase} -`
        const cropInPlace = `${cropBase} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const cleanup = `rm '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const uploadAndGetUrl = (filePath) => {
            return `curl -sSf --max-time 30 -F 'files[]=@${StringUtils.shellSingleQuoteEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url // empty'`
        }
        const annotationCommand = `${Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"} -f -`;
        switch (action) {
            case ScreenshotAction.Action.Copy: {
                // Written to a file first, which the notification shows.
                return ["bash", "-c", `${root.outputFileCommand(saveDir)} && ${cropBase} "$out" && wl-copy --type image/png < "$out" && ${cleanup} && ${root.notifyCommand}`]
            }
            case ScreenshotAction.Action.Edit:
                return ["bash", "-c", `${cropToStdout} | ${annotationCommand} && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Search: {
                // Uploaded for the search engine to fetch; a failed upload used
                // to open the engine with an empty (or "null") image URL, silently.
                const failed = `notify-send -a Shell '${StringUtils.shellSingleQuoteEscape(Translation.tr("Image search failed"))}' `
                    + `'${StringUtils.shellSingleQuoteEscape(Translation.tr("Couldn't upload the image"))} (${root.fileUploadApiEndpoint})'`;
                return ["bash", "-c", `${cropInPlace} && url=$(${uploadAndGetUrl(screenshotPath)}); ${cleanup}; `
                    + `case "$url" in https://*) xdg-open "${root.imageSearchEngineBaseUrl}$(jq -rn --arg u "$url" '$u | @uri')" ;; *) ${failed} ;; esac`]
            }
            case ScreenshotAction.Action.CharRecognition:
                return ["bash", "-c", `${cropInPlace} && tesseract '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`]
                break;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }

    // Starts a recording (record.sh), with the desktop audio when
    // `withSound`, of the output `output`, else of the area x, y, width x
    // height in niri's global logical coordinates (what wf-recorder's
    // --geometry, like slurp, takes).
    function getRecordCommand(output, x, y, width, height, withSound) {
        const target = output !== ""
            ? ["--output", output]
            : ["--region", `${Math.round(x)},${Math.round(y)} ${Math.round(width)}x${Math.round(height)}`];
        return [Directories.recordScriptPath, ...target, ...(withSound ? [] : ["--no-sound"])];
    }

    // The notification niri sends for its own screenshots (a window capture
    // gets that one), for the region and screen copies: the image in "$out".
    readonly property string notifyCommand: `notify-send -a '${StringUtils.shellSingleQuoteEscape(Translation.tr("Screenshot"))}' `
        + `-i image-x-generic -h "string:image-path:$out" -h boolean:transient:true `
        + `'${StringUtils.shellSingleQuoteEscape(Translation.tr("Screenshot captured"))}' `
        + `'${StringUtils.shellSingleQuoteEscape(Translation.tr("You can paste the image from the clipboard."))}'`

    // `action` on the window `windowId` as niri renders it: whole, borderless,
    // even where it is off screen or covered. niri writes it to a file (kept
    // until the next open: its notification shows it), puts it in the
    // clipboard and notifies, so a copy is done once the file is there; the
    // other actions work on a copy of the file.
    function getWindowCommand(windowId, action, saveDir = "") {
        const dir = StringUtils.shellSingleQuoteEscape(Directories.screenshotTemp);
        const id = Number(windowId);
        const workPath = `${Directories.screenshotTemp}/window-${id}-work.png`;
        const capture = `mkdir -p '${dir}' && win='${dir}/window-${id}.png' && rm -f "$win" && `
            + `niri msg action screenshot-window --id ${id} --path "$win" && `
            // niri encodes and writes it from a thread: wait until it is complete.
            + `prev=-1 && for _ in $(seq 80); do size=$(stat -c %s "$win" 2>/dev/null || echo 0); `
            + `[ "$size" -gt 0 ] && [ "$size" = "$prev" ] && break; prev=$size; sleep 0.05; done && [ -s "$win" ]`;
        if (action === ScreenshotAction.Action.Copy) {
            const save = saveDir === "" ? "" : ` && ${root.outputFileCommand(saveDir)} && cp "$win" "$out"`;
            return ["bash", "-c", capture + save];
        }
        const command = root.getCommand(0, 0, 0, 0, workPath, action, "");
        if (!command) return;
        return ["bash", "-c", `${capture} && cp "$win" '${StringUtils.shellSingleQuoteEscape(workPath)}' && ${command[2]}`];
    }
}
