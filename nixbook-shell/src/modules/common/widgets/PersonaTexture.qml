import QtQuick
import Quickshell
import qs.modules.common

/**
 * Persona-style background art for a panel (original SVG textures in each
 * game's visual language: P5 red burst + halftone + slashes, P3R blue light
 * beams + bubbles + waves, P4 Revival gold TV stripes + scanlines +
 * amber glow — assets/persona/generate.py). Drawn under the panel's
 * content.
 *
 * Every panel uses one of three shared textures (Persona.textureShapes: tall
 * for sidebars, panel for popups, wide for the OSD / search bar; PNGs
 * rasterised at build time), and the Persona singleton keeps the current
 * variant's three decoded, so a panel's art is already in the pixmap cache
 * when it opens instead of rasterising the SVG at that panel's size.
 */
Image {
    id: root
    visible: Persona.halftone
    readonly property string shape: Persona.textureShapeFor(root.width, root.height)
    // Wait for a real size: a 0-height item mid-layout would pick "wide".
    source: visible && root.width > 0 && root.height > 0 ? Persona.textureUrl(root.shape) : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    opacity: Persona.textureOpacity
}
