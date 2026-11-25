# Screenshots & recording

## Screenshots — Print

**Print** opens the region selector over every screen (it appears instantly, and a selection made before the capture is ready is queued):

| Key / click | Action                                                                         |
| ----------- | ------------------------------------------------------------------------------ |
| Drag        | Select a rectangle (or a circle — toolbar tabs)                                |
| Left click  | Copy the selection to the clipboard                                            |
| Right click | Annotate the selection (swappy / satty)                                        |
| `W`         | Window mode: hover highlights a window, click captures it whole and borderless |
| `S`         | Screen mode: hover highlights a monitor, click captures it                     |
| `Esc`       | Cancel                                                                         |

Every capture is copied to the clipboard, shown in a notification with the image, and saved as `Screenshot-YYYY-MM-DD-HH-MM-SS.png` in `screenSnip.savePath` (default `~/Pictures/Screenshots`; empty = clipboard only; Settings → Services → Screenshot path).

**QR codes**: when a copied capture holds a QR code, a second notification shows what it says, with **Open link** (web links only, in your browser) and **Copy text** (e.g. a Wi-Fi code). Nothing is opened or copied until you click; the buttons stay on the notification in the side panel. It reads the first QR code in the capture (with `zbarimg`, on this computer).

The selector also offers **OCR** / screen translation of a selection.

## Recording — Shift+Print

**Shift+Print** (or the bar's record button, or `nixbook-shell ipc call region recordWithSound`) opens the same selector in record mode: a rectangle, a window (`W`, the area it is shown in) or a whole screen (`S`). Recording uses wf-recorder **with the desktop audio** (the default output's monitor). While recording, only a thin border outside the area stays on screen and the keyboard is yours.

**Shift+Print** or the record button again **stops** it; the video is copied to the clipboard as a file.

AI agents can take silent screenshots and, on request, save screenshots or record the screen for you through the [desktop control tools](./desktop-agents#what-agents-can-do).
