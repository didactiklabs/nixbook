pragma Singleton
import Quickshell

Singleton {
    id: root

    function intersectionOverUnion(regionA, regionB) {
        // region: { at: [x, y], size: [w, h] }
        const ax1 = regionA.at[0], ay1 = regionA.at[1];
        const ax2 = ax1 + regionA.size[0], ay2 = ay1 + regionA.size[1];
        const bx1 = regionB.at[0], by1 = regionB.at[1];
        const bx2 = bx1 + regionB.size[0], by2 = by1 + regionB.size[1];

        const interX1 = Math.max(ax1, bx1);
        const interY1 = Math.max(ay1, by1);
        const interX2 = Math.min(ax2, bx2);
        const interY2 = Math.min(ay2, by2);

        const interArea = Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
        const areaA = (ax2 - ax1) * (ay2 - ay1);
        const areaB = (bx2 - bx1) * (by2 - by1);
        const unionArea = areaA + areaB - interArea;

        return unionArea > 0 ? interArea / unionArea : 0;
    }

    function filterOverlappingImageRegions(regions) {
        let keep = [];
        let removed = new Set();
        for (let i = 0; i < regions.length; ++i) {
            if (removed.has(i)) continue;
            let regionA = regions[i];
            for (let j = i + 1; j < regions.length; ++j) {
                if (removed.has(j)) continue;
                let regionB = regions[j];
                if (intersectionOverUnion(regionA, regionB) > 0) {
                    // Compare areas
                    let areaA = regionA.size[0] * regionA.size[1];
                    let areaB = regionB.size[0] * regionB.size[1];
                    if (areaA <= areaB) {
                        removed.add(j);
                    } else {
                        removed.add(i);
                    }
                }
            }
        }
        for (let i = 0; i < regions.length; ++i) {
            if (!removed.has(i)) keep.push(regions[i]);
        }
        return keep;
    }

    // niri's layout settings the window estimate needs, from its config file
    // (gaps and struts are not in its IPC). niri's defaults when unset.
    function parseNiriLayout(text) {
        const layout = { gap: 16, struts: { left: 0, right: 0, top: 0, bottom: 0 } };
        const gaps = /^\s*gaps\s+([\d.]+)/m.exec(text ?? "");
        if (gaps) layout.gap = Number(gaps[1]);
        const struts = /^\s*struts\s*\{([^}]*)\}/m.exec(text ?? "");
        if (struts) {
            for (const side of ["left", "right", "top", "bottom"]) {
                const m = new RegExp(`\\b${side}\\s+(-?[\\d.]+)`).exec(struts[1]);
                if (m) layout.struts[side] = Number(m[1]);
            }
        }
        return layout;
    }

    // The windows shown on a workspace, as rects in screen-logical coordinates
    // ({ id, title, appId, floating, x, y, width, height }), floating first.
    // niri gives a position to floating windows only; tiled ones are laid out
    // from their columns. Their y is exact (tiles fill the column, with gaps
    // around), their x assumes the view starts at the first column and, when
    // the columns overflow, scrolls just far enough to show the active one
    // (center-focused-column "never"): exact on a workspace that fits, an
    // estimate on a scrolled one. `reserved` is the side space the shell's own
    // bars take ({ left, right }); the vertical space follows from the columns
    // and is put above them, below with `reserved.bottom`.
    function windowTargets(windows, workspace, screenWidth, screenHeight, layout, reserved) {
        if (!workspace) return [];
        const gap = layout.gap;
        const struts = layout.struts;
        const onWorkspace = windows.filter(w => w.workspaceId === workspace.id);
        const rect = (w, tileX, tileY) => ({
            id: w.id, title: w.title, appId: w.appId, floating: w.floating,
            x: tileX + w.windowOffsetX, y: tileY + w.windowOffsetY,
            width: w.width, height: w.height
        });

        const floating = onWorkspace
            .filter(w => w.floating && w.tileX !== null)
            .sort((a, b) => (b.focused ? 1 : 0) - (a.focused ? 1 : 0))
            .map(w => rect(w, w.tileX, w.tileY));

        const byColumn = {};
        for (const w of onWorkspace) {
            if (w.floating || w.column === null) continue;
            (byColumn[w.column] = byColumn[w.column] ?? []).push(w);
        }
        const columns = Object.keys(byColumn).map(Number).sort((a, b) => a - b)
            .map(c => byColumn[c].sort((a, b) => a.tileIndex - b.tileIndex));
        if (columns.length === 0) return floating;

        const isFullscreen = col => col.length === 1
            && Math.abs(col[0].tileWidth - screenWidth) < 1 && Math.abs(col[0].tileHeight - screenHeight) < 1;
        const activeIndex = Math.max(0, columns.findIndex(col => col.some(w => w.id === String(workspace.active_window_id))));
        if (isFullscreen(columns[activeIndex])) return floating.concat([rect(columns[activeIndex][0], 0, 0)]);

        // Working area: tiles fill its height, so it follows from any column.
        let workHeight = 0;
        for (const col of columns) {
            if (isFullscreen(col)) continue;
            workHeight = Math.max(workHeight, col.reduce((sum, w) => sum + w.tileHeight, 0) + (col.length + 1) * gap);
        }
        const verticalSpace = Math.max(0, screenHeight - struts.top - struts.bottom - workHeight);
        const workY = struts.top + (reserved.bottom ? 0 : verticalSpace);
        const workX = struts.left + (reserved.left ?? 0);
        const workWidth = screenWidth - workX - struts.right - (reserved.right ?? 0);

        // Column positions along the scrolling strip, then the view over it.
        const columnX = [];
        const columnWidth = columns.map(col => Math.max(...col.map(w => w.tileWidth)));
        let stripX = 0;
        for (let i = 0; i < columns.length; ++i) {
            columnX.push(stripX);
            stripX += columnWidth[i] + gap;
        }
        let viewStart = -gap;
        const activeEnd = columnX[activeIndex] + columnWidth[activeIndex] + gap;
        if (activeEnd > viewStart + workWidth) viewStart = activeEnd - workWidth;

        const tiled = [];
        for (let i = 0; i < columns.length; ++i) {
            const x = workX + columnX[i] - viewStart;
            if (x >= screenWidth || x + columnWidth[i] <= 0) continue;
            let y = workY + gap;
            for (const w of columns[i]) {
                tiled.push(rect(w, x, y));
                y += w.tileHeight + gap;
            }
        }
        return floating.concat(tiled);
    }

    function targetAt(targets, x, y) {
        return targets.find(t => t.x <= x && x < t.x + t.width && t.y <= y && y < t.y + t.height) ?? null;
    }
}
