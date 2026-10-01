#!/usr/bin/env python3
"""Find the least (or most) busy region of a wallpaper, as JSON: where a
background widget goes, and the colour under it.

Every background widget runs this on each screen when the shell starts and
when the wallpaper changes, so it is cached ($XDG_CACHE_HOME/nixbook-shell/
least-busy-region, private to the user):
  - results/: the JSON answer, keyed by the wallpaper file (path, inode, size,
    mtime) and every argument; a hit never loads OpenCV;
  - images/: the wallpaper decoded and scaled to the screen, shared by the
    widgets that start together (a lock makes one of them decode it).
"""

import argparse
import fcntl
import hashlib
import json
import os
import sys
import tempfile

# Bumped when the output for the same input changes: old entries are ignored.
CACHE_VERSION = 1
MAX_RESULTS = 256
MAX_IMAGES = 4

cv2 = None
np = None


def load_cv():
    global cv2, np
    if cv2 is None:
        os.environ["OPENCV_LOG_LEVEL"] = "SILENT"
        # One thread: the work is small, and the widgets run this all at
        # once; a thread pool per process (one thread per core, spinning)
        # costs several times the CPU it saves.
        for var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "OPENCV_FOR_THREADS_NUM"):
            os.environ.setdefault(var, "1")
        import cv2 as _cv2
        import numpy as _np
        _cv2.setNumThreads(1)
        cv2, np = _cv2, _np


def cache_root():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "nixbook-shell", "least-busy-region")


def cache_dir(name):
    root = cache_root()
    os.makedirs(root, mode=0o700, exist_ok=True)
    path = os.path.join(root, name)
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def cache_key(image_path, **params):
    """A hash of the wallpaper file's identity and the parameters, or None
    when the file cannot be read (then nothing is cached)."""
    try:
        real = os.path.realpath(image_path)
        st = os.stat(real)
    except OSError:
        return None
    ident = {"v": CACHE_VERSION, "path": real, "ino": st.st_ino, "size": st.st_size,
             "mtime": st.st_mtime_ns, **params}
    return hashlib.sha256(json.dumps(ident, sort_keys=True).encode()).hexdigest()


def write_atomic(directory, name, write):
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
    try:
        with os.fdopen(fd, "wb") as f:
            write(f)
        os.replace(tmp, os.path.join(directory, name))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def prune(directory, suffix, keep):
    """Keep the `keep` most recently used `suffix` files."""
    try:
        entries = [e for e in os.scandir(directory) if e.name.endswith(suffix)]
        entries.sort(key=lambda e: e.stat().st_mtime, reverse=True)
        for e in entries[keep:]:
            os.unlink(e.path)
    except OSError:
        pass


def center_crop(img, target_w, target_h):
    h, w = img.shape[:2]
    if w == target_w and h == target_h:
        return img
    x1 = max(0, (w - target_w) // 2)
    y1 = max(0, (h - target_h) // 2)
    x2 = x1 + target_w
    y2 = y1 + target_h
    return img[y1:y2, x1:x2]


def decode_screen_image(image_path, screen_width, screen_height, screen_mode="fill", verbose=False):
    """The wallpaper (BGR) as it is shown on a screen of that size."""
    load_cv()
    img = cv2.imread(image_path, cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(f"Image not found: {image_path}")
    orig_h, orig_w = img.shape[:2]
    scale_w = screen_width / orig_w
    scale_h = screen_height / orig_h
    scale = max(scale_w, scale_h) if screen_mode == "fill" else min(scale_w, scale_h)
    new_w = int(orig_w * scale)
    new_h = int(orig_h * scale)
    if verbose:
        print(f"Scaling image from {orig_w}x{orig_h} to {new_w}x{new_h} (scale: {scale:.3f}, mode: {screen_mode})")
    img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
    return np.ascontiguousarray(center_crop(img, screen_width, screen_height))


def screen_image(image_path, screen_width, screen_height, screen_mode="fill", verbose=False):
    """decode_screen_image, through the shared image cache (skipped when the
    cache cannot be written)."""
    load_cv()
    key = cache_key(image_path, screen=[screen_width, screen_height, screen_mode])
    try:
        if key is None:
            raise OSError("no cache key")
        directory = cache_dir("images")
        lock = open(os.path.join(directory, "lock"), "a")
    except OSError:
        return decode_screen_image(image_path, screen_width, screen_height, screen_mode, verbose)
    cached = os.path.join(directory, f"{key}.npy")
    with lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            img = np.load(cached, allow_pickle=False)
            if img.dtype == np.uint8 and img.ndim == 3 and img.shape[2] == 3:
                os.utime(cached)
                return img
        except (OSError, ValueError, EOFError):
            pass
        img = decode_screen_image(image_path, screen_width, screen_height, screen_mode, verbose)
        try:
            write_atomic(directory, f"{key}.npy", lambda f: np.save(f, img, allow_pickle=False))
            prune(directory, ".npy", MAX_IMAGES)
        except OSError:
            pass
        return img


def integrals(gray):
    """Summed-area tables of the values and of their squares, with a leading
    row and column of zeros."""
    arr = gray.astype(np.float64)
    return cv2.integral(arr, sdepth=cv2.CV_64F), cv2.integral(arr ** 2, sdepth=cv2.CV_64F)


def window_variances(sums, sums_sq, xs, ys, region_w, region_h):
    """The variance of every region_w x region_h window whose top-left corner
    is at (x, y) for y in ys and x in xs: a len(ys) x len(xs) array."""
    x1, y1 = xs[np.newaxis, :], ys[:, np.newaxis]
    x2, y2 = x1 + region_w, y1 + region_h
    area = region_w * region_h
    s = sums[y2, x2] - sums[y1, x2] - sums[y2, x1] + sums[y1, x1]
    s2 = sums_sq[y2, x2] - sums_sq[y1, x2] - sums_sq[y2, x1] + sums_sq[y1, x1]
    mean = s / area
    return (s2 / area) - (mean ** 2)


def window_starts(start, end, stride, region, limit):
    """Window corners from start to end (inclusive) every stride, the window
    inside the image."""
    starts = np.arange(start, end + 1, stride)
    return starts[starts + region - 1 < limit]


def find_least_busy_region(gray, region_width=300, region_height=200, verbose=False, stride=2, horizontal_padding=50, vertical_padding=50, busiest=False):
    h, w = gray.shape
    stride = max(1, int(stride) if stride else 1)
    # Adjust region size if it does not fit given padding
    if horizontal_padding * 2 >= w or vertical_padding * 2 >= h:
        # Reduce padding to fit at least a 1x1 region
        horizontal_padding = max(0, min(horizontal_padding, (w - 1) // 2))
        vertical_padding = max(0, min(vertical_padding, (h - 1) // 2))
    max_region_w = w - 2 * horizontal_padding
    max_region_h = h - 2 * vertical_padding
    if max_region_w <= 0 or max_region_h <= 0:
        raise ValueError("Image too small for the specified padding.")
    if region_width > max_region_w:
        if verbose:
            print(f"Requested region_width {region_width} too large; clamping to {max_region_w}")
        region_width = max_region_w
    if region_height > max_region_h:
        if verbose:
            print(f"Requested region_height {region_height} too large; clamping to {max_region_h}")
        region_height = max_region_h
    x_start = horizontal_padding
    y_start = vertical_padding
    x_end = max(x_start, w - region_width - horizontal_padding + 1)
    y_end = max(y_start, h - region_height - vertical_padding + 1)
    xs = window_starts(x_start, x_end, stride, region_width, w)
    ys = window_starts(y_start, y_end, stride, region_height, h)
    if xs.size == 0 or ys.size == 0:
        return (horizontal_padding, vertical_padding), None
    var = window_variances(*integrals(gray), xs, ys, region_width, region_height)
    # First extreme in row order, as a scan keeping only strictly better ones.
    i = int(np.argmax(var) if busiest else np.argmin(var))
    row, col = divmod(i, xs.size)
    return (int(xs[col]), int(ys[row])), float(var[row, col])


def find_largest_region(gray, verbose=False, stride=2, threshold=100.0, aspect_ratio=1.0, horizontal_padding=50, vertical_padding=50):
    h, w = gray.shape
    stride = max(1, int(stride) if stride else 1)
    threshold = max(0.0, float(threshold))
    # Adjust padding if image too small
    if horizontal_padding * 2 >= w or vertical_padding * 2 >= h:
        horizontal_padding = max(0, min(horizontal_padding, (w - 1) // 2))
        vertical_padding = max(0, min(vertical_padding, (h - 1) // 2))
    sums, sums_sq = integrals(gray)
    min_size = 10
    # Determine maximum feasible size respecting padding
    effective_w = w - 2 * horizontal_padding
    effective_h = h - 2 * vertical_padding
    if effective_w <= 0 or effective_h <= 0:
        return None, (0, 0), None
    # Largest square-ish dimension given aspect ratio and effective space
    if aspect_ratio >= 1.0:
        max_size = min(effective_h, int(effective_w / aspect_ratio))
    else:
        max_size = min(int(effective_h * aspect_ratio), effective_w)
    if max_size < min_size:
        min_size = 1
        max_size = max(1, max_size)
    best = None
    while min_size <= max_size:
        mid = (min_size + max_size) // 2
        if aspect_ratio >= 1.0:
            region_h = mid
            region_w = int(round(mid * aspect_ratio))
        else:
            region_w = mid
            region_h = int(round(mid / aspect_ratio if aspect_ratio != 0 else mid))
        if region_w <= 0 or region_h <= 0:
            break
        if region_w > effective_w or region_h > effective_h:
            max_size = mid - 1
            continue
        xs = window_starts(horizontal_padding, w - region_w - horizontal_padding, stride, region_w, w)
        ys = window_starts(vertical_padding, h - region_h - vertical_padding, stride, region_h, h)
        found = False
        if xs.size > 0 and ys.size > 0:
            var = window_variances(sums, sums_sq, xs, ys, region_w, region_h)
            under = (var <= threshold).ravel()
            if under.any():
                # The first one in row order.
                row, col = divmod(int(np.argmax(under)), xs.size)
                best = (int(xs[col]), int(ys[row]), region_w, region_h, float(var[row, col]))
                found = True
        if found:
            min_size = mid + 1
        else:
            max_size = mid - 1
    if best:
        x, y, region_w, region_h, var = best
        center_x = x + region_w // 2
        center_y = y + region_h // 2
        return (center_x, center_y), (region_w, region_h), var
    else:
        return None, (0, 0), None


def draw_region(img, coords, region_width=300, region_height=200, output_path='output.png'):
    img = img.copy()
    x, y = coords
    cv2.rectangle(img, (x, y), (x+region_width-1, y+region_height-1), (0,0,255), 3)
    cv2.imwrite(output_path, img)


def draw_largest_region(img, center, size, output_path='output.png'):
    img = img.copy()
    cx, cy = center
    region_w, region_h = size
    x1 = cx - region_w // 2
    y1 = cy - region_h // 2
    x2 = cx + region_w // 2 - 1
    y2 = cy + region_h // 2 - 1
    cv2.rectangle(img, (x1, y1), (x2, y2), (255,0,0), 3)
    cv2.imwrite(output_path, img)


def get_dominant_color(img, x, y, w, h):
    # Ensure region is within bounds
    x = max(0, x)
    y = max(0, y)
    w = max(1, min(w, img.shape[1] - x))
    h = max(1, min(h, img.shape[0] - y))
    region = img[y:y+h, x:x+w]
    if region.size == 0 or region.shape[0] == 0 or region.shape[1] == 0:
        return [0, 0, 0]
    region = region.reshape((-1, 3))
    # Filter out black pixels (optional, improves accuracy for some images)
    non_black = region[np.any(region > 10, axis=1)]
    if non_black.shape[0] == 0:
        non_black = region
    region = np.float32(non_black)
    if region.shape[0] < 3:
        return [int(x) for x in np.mean(region, axis=0)]
    # K-means to find dominant color
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0)
    K = min(3, region.shape[0])
    _, labels, centers = cv2.kmeans(region, K, None, criteria, 10, cv2.KMEANS_RANDOM_CENTERS)
    counts = np.bincount(labels.flatten())
    dominant = centers[np.argmax(counts)]
    # Reverse from BGR to RGB
    return [int(x) for x in reversed(dominant)]


def hex_color(rgb):
    return '#{:02x}{:02x}{:02x}'.format(*rgb)


def compute(args, use_cache=True):
    """The answer, as a dict (the visual output written on the way)."""
    load = screen_image if use_cache else decode_screen_image
    img = load(args.image_path, args.screen_width, args.screen_height, args.screen_mode, args.verbose)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    if args.largest_region:
        center, size, var = find_largest_region(
            gray,
            verbose=args.verbose,
            stride=args.stride,
            threshold=args.variance_threshold,
            aspect_ratio=args.aspect_ratio,
            horizontal_padding=args.horizontal_padding,
            vertical_padding=args.vertical_padding
        )
        if not center:
            return {"error": "No region found under the threshold."}
        if args.visual_output:
            draw_largest_region(img, center, size)
        region_w, region_h = size
        dominant_color = get_dominant_color(img, center[0] - region_w // 2, center[1] - region_h // 2, region_w, region_h)
        return {
            "center_x": center[0],
            "center_y": center[1],
            "width": size[0],
            "height": size[1],
            "variance": var,
            "dominant_color": hex_color(dominant_color)
        }

    coords, variance = find_least_busy_region(
        gray,
        region_width=args.width,
        region_height=args.height,
        verbose=args.verbose,
        stride=args.stride,
        horizontal_padding=args.horizontal_padding,
        vertical_padding=args.vertical_padding,
        busiest=args.busiest
    )
    if args.visual_output:
        draw_region(img, coords, region_width=args.width, region_height=args.height)
    dominant_color = get_dominant_color(img, coords[0], coords[1], args.width, args.height)
    return {
        "center_x": coords[0] + args.width // 2,
        "center_y": coords[1] + args.height // 2,
        "width": args.width,
        "height": args.height,
        "variance": variance,
        "dominant_color": hex_color(dominant_color)
    }


def main():
    parser = argparse.ArgumentParser(description="Find least busy region in an image and output a JSON. Made for determining a suitable position for a wallpaper widget.")
    parser.add_argument("image_path", help="Path to the input image")
    parser.add_argument("--width", type=int, default=300, help="Region width")
    parser.add_argument("--height", type=int, default=200, help="Region height")
    parser.add_argument("-v", "--visual-output", action="store_true", help="Output image with rectangle")
    parser.add_argument("--screen-width", type=int, default=1920, help="Screen width for wallpaper scaling")
    parser.add_argument("--screen-height", type=int, default=1080, help="Screen height for wallpaper scaling")
    parser.add_argument("--stride", type=int, default=10, help="Step size for sliding window (higher is faster, less precise)")
    parser.add_argument("--screen-mode", choices=["fill", "fit"], default="fill", help="Wallpaper scaling mode: 'fill' (default) or 'fit'")
    parser.add_argument("--verbose", action="store_true", help="Print verbose output")
    parser.add_argument("-l", "--largest-region", action="store_true", help="Find the largest region under the variance threshold and output its center")
    parser.add_argument("-t", "--variance-threshold", type=float, default=1000.0, help="Variance threshold for largest region mode")
    parser.add_argument("--aspect-ratio", type=float, default=1.78, help="Aspect ratio (width/height) for largest region mode")
    parser.add_argument("--horizontal-padding", "-hp", type=int, default=50, help="Minimum horizontal distance from region to image edge")
    parser.add_argument("--vertical-padding", "-vp", type=int, default=50, help="Minimum vertical distance from region to image edge")
    parser.add_argument("--busiest", action="store_true", help="Find the busiest region instead of the least busy")
    parser.add_argument("--no-cache", action="store_true", help="Neither read nor write the cache")
    args = parser.parse_args()

    # Only the answer is cached: not a run that draws or explains itself.
    cacheable = not (args.no_cache or args.visual_output or args.verbose)
    params = {k: v for k, v in vars(args).items()
              if k not in ("image_path", "visual_output", "verbose", "no_cache")}
    key = cache_key(args.image_path, args=params) if cacheable else None
    try:
        directory = cache_dir("results") if key is not None else None
    except OSError:
        directory = None
    if directory is not None:
        cached = os.path.join(directory, f"{key}.json")
        try:
            with open(cached) as f:
                result = json.load(f)
        except (OSError, ValueError):
            result = None
        if isinstance(result, dict):
            try:
                os.utime(cached)
            except OSError:
                pass
            print(json.dumps(result))
            return

    load_cv()
    result = compute(args, use_cache=not args.no_cache)
    output = json.dumps(result)
    if directory is not None:
        try:
            write_atomic(directory, f"{key}.json", lambda f: f.write(output.encode()))
            prune(directory, ".json", MAX_RESULTS)
        except OSError:
            pass
    print(output)


if __name__ == "__main__":
    try:
        main()
    except (FileNotFoundError, ValueError) as e:
        print(f"least_busy_region: {e}", file=sys.stderr)
        sys.exit(1)
