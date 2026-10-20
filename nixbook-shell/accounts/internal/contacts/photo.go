package contacts

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image"
	"image/color"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/didactiklabs/nixbook/nixbook-shell/accounts/internal/core"
)

// A photo a change sets (set_photo): a PNG, JPEG or GIF file, checked to be
// an image (whatever a path names, only an image leaves the computer) and
// made a JPEG of at most PhotoEdge pixels a side, small enough to go inline
// in a vCard.
const (
	PhotoEdge     = 720
	photoMaxBytes = 20 << 20
	photoMaxArea  = 50_000_000
)

// LoadPhoto is the image file at path as the JPEG providers get.
func LoadPhoto(path string) ([]byte, error) {
	if !filepath.IsAbs(path) {
		return nil, core.Errorf("`photo` must be the absolute path of an image file")
	}
	data, err := readCapped(path)
	if err != nil {
		return nil, err
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, core.Errorf("%s isn't a PNG, JPEG or GIF image", filepath.Base(path))
	}
	if cfg.Width*cfg.Height > photoMaxArea {
		return nil, core.Errorf("%s is too large (%dx%d)", filepath.Base(path), cfg.Width, cfg.Height)
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, core.Errorf("%s isn't a readable image: %v", filepath.Base(path), err)
	}
	var out bytes.Buffer
	if err := jpeg.Encode(&out, shrink(img, PhotoEdge), &jpeg.Options{Quality: 90}); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}

func readCapped(path string) ([]byte, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, core.Errorf("no file %s", path)
	}
	if err != nil {
		return nil, core.Errorf("can't read %s: %v", path, err)
	}
	defer f.Close()
	if st, err := f.Stat(); err != nil || !st.Mode().IsRegular() {
		return nil, core.Errorf("%s isn't a file", path)
	}
	data, err := io.ReadAll(io.LimitReader(f, photoMaxBytes+1))
	if err != nil {
		return nil, core.Errorf("can't read %s: %v", path, err)
	}
	if len(data) > photoMaxBytes {
		return nil, core.Errorf("%s is over %d MB", filepath.Base(path), photoMaxBytes>>20)
	}
	return data, nil
}

// shrink fits the image in edge×edge (each pixel the average of those it
// covers), on white where it was transparent.
func shrink(src image.Image, edge int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	nw, nh := w, h
	if w > edge || h > edge {
		if w >= h {
			nw, nh = edge, max(1, h*edge/w)
		} else {
			nw, nh = max(1, w*edge/h), edge
		}
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	for y := range nh {
		y0, y1 := b.Min.Y+y*h/nh, b.Min.Y+max((y+1)*h/nh, y*h/nh+1)
		for x := range nw {
			x0, x1 := b.Min.X+x*w/nw, b.Min.X+max((x+1)*w/nw, x*w/nw+1)
			var r, g, bl, a, n uint64
			for sy := y0; sy < y1; sy++ {
				for sx := x0; sx < x1; sx++ {
					cr, cg, cb, ca := src.At(sx, sy).RGBA()
					r, g, bl, a, n = r+uint64(cr), g+uint64(cg), bl+uint64(cb), a+uint64(ca), n+1
				}
			}
			// Premultiplied: over white is c + (1 - alpha).
			white := 0xffff - a/n
			dst.Set(x, y, color.RGBA64{
				R: uint16(r/n + white), G: uint16(g/n + white), B: uint16(bl/n + white), A: 0xffff,
			})
		}
	}
	return dst
}

func photoDir() (string, error) {
	dir, err := core.StateDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "photos"), nil
}

// PhotoFile keeps an image (a vCard's inline photo) as a file in the state
// directory, named by its content, and gives its file:// URL: the copy
// holds the link, not the image.
func PhotoFile(data []byte, ext string) (string, error) {
	dir, err := photoDir()
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	path := filepath.Join(dir, hex.EncodeToString(sum[:16])+ext)
	// Written whole or not at all: a file cut short (a crash) would stay,
	// never written again.
	if _, err := os.Stat(path); err != nil {
		if err := core.ReplaceFile(path, data); err != nil {
			return "", err
		}
	}
	return "file://" + path, nil
}

// prunePhotos removes the kept photos no contact in the copy links to any
// more (its contact deleted, its photo changed, its account removed): they
// don't stay on the computer.
func prunePhotos(c *Cache) {
	dir, err := photoDir()
	if err != nil {
		return
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	used := map[string]bool{}
	for _, x := range c.Contacts {
		if p, ok := strings.CutPrefix(x.Photo, "file://"); ok {
			used[p] = true
		}
	}
	for _, e := range entries {
		if p := filepath.Join(dir, e.Name()); !used[p] {
			_ = os.Remove(p)
		}
	}
}
