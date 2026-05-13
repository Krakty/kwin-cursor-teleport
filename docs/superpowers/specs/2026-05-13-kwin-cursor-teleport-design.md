# KWin Cursor Edge Teleport — Design

| | |
|---|---|
| **Status** | Design — awaiting user approval |
| **Date** | 2026-05-13 |
| **Target** | KWin 6.6.4 (Plasma 6, Wayland), Arch Linux |
| **Dev box** | T7910 (Arch) |
| **Deploy target** | BEAST (Arch) |

## Problem

On a multi-output Wayland session with unaligned monitor edges, KWin's pointer-clamping logic corner-pins the cursor when motion would carry it through a region of one output's edge that has no adjacent output at the same y-coordinate. The cursor cannot enter the offset neighbor unless the user manually navigates around the dead zone.

Concrete failing scenario (BEAST): 2×3 monitor grid with 4K outer monitors and 2K inner monitors vertically centered between the 4Ks. When the user pushes the cursor from a 4K toward the adjacent 2K, the cursor gets pinned in the 4K's corner unless the cursor's y-coordinate happens to be within the 2K's smaller vertical range.

## Goal

Patch KWin to **teleport the cursor to the nearest reachable point on an adjacent output** when motion would otherwise produce a dead-zone corner-pin. Behavior is opt-in via a `kwinrc` flag; default-off preserves stock KWin behavior byte-for-byte.

## Requirements

**Functional**
1. When a motion event would carry the cursor to a position outside all outputs, identify the nearest reachable point on any adjacent output and place the cursor there.
2. "Nearest" is closest Euclidean distance from the candidate position to the projection onto each candidate output's rect.
3. Only teleport to outputs in the direction of motion — reject candidates "behind" the motion vector (cursor pushed into pure void with no neighbor → fall back to standard clamp).
4. Skip the source output when searching for teleport targets (otherwise the source's edge always wins by proximity and we'd never teleport).
5. Behavior is gated by `[CursorEdgeTeleport]/Enabled` in `kwinrc`. Default `false`.
6. Config changes apply without Plasma restart via `KConfigWatcher`.
7. When the flag is off, patched KWin behaves identically to stock KWin.

**Non-functional**
1. Patch surface is small: one call-site change in `pointer_input.cpp` + new isolated helper files. Goal: minimize rebase pain.
2. Algorithm is pure (no I/O, no globals, no KWin state mutation). Unit-testable in isolation.
3. Debug logging via `qCDebug(KWIN_INPUT)` so testers can verify behavior without watching cursor pixels.

## Non-goals (v1)

- No System Settings UI checkbox. `kwinrc` only.
- No directional weighting beyond the "behind us" rejection. Closest-Euclidean wins, even at diagonal corners.
- No motion gating, threshold, or anti-jitter logic. Teleport fires on the first motion event that produces a dead-zone candidate.
- No support for pointer-warp protocol clients placing cursors in dead zones (clients are responsible for valid coordinates).
- No tablet / touchscreen / pen handling. Absolute-coord input doesn't reach the patched path.
- No per-output enable/disable. Global flag.
- No upstream merge request as part of this work. The patch is fork-first; upstreaming is a separate decision after lived experience.

## Architecture

Two trees:

**Project repo** (BEAST, `/mnt/DEV/Projects/kwin-cursor-teleport`, accessed from T7910 via SSH/SSHFS):

```
.
├── patches/
│   └── 6.6.4/
│       └── 0001-cursor-edge-teleport.patch    # canonical patch, git-format-patch output
├── packaging/
│   └── PKGBUILD                                # forked from Arch's kwin, provides=kwin
├── docs/
│   └── superpowers/specs/                      # this document
├── scripts/
│   ├── apply.sh                                # clone upstream + apply patch into build dir
│   ├── nested-test.sh                          # launch nested kwin_wayland with synthetic mismatched outputs
│   ├── install-stock.sh                        # pacman -S kwin --overwrite '*' for fast rollback
│   └── checklist.md                            # manual verification checklist
├── VERSION_HISTORY.md                          # log of "verified against KWin X.Y.Z on YYYY-MM-DD"
└── README.md
```

**KWin source tree** (cloned, modified files only):

```
kwin/
├── src/
│   ├── pointer_input.cpp                       # ~5-line call-site change
│   ├── cursor_edge_teleport.h                  # NEW (~30 lines)
│   ├── cursor_edge_teleport.cpp                # NEW (~60 lines, pure algorithm)
│   ├── cursor_edge_teleport_config.h           # NEW (~15 lines)
│   ├── cursor_edge_teleport_config.cpp         # NEW (~30 lines, kwinrc read + KConfigWatcher)
│   └── CMakeLists.txt                          # add new sources
└── autotests/
    └── cursor_edge_teleport_test.cpp           # NEW, QtTest, ~150 lines
```

**Packaging strategy**: PKGBUILD provides `kwin` and replaces the stock package. SSH-based recovery is the fallback if a patched session breaks (`scripts/install-stock.sh`).

## Algorithm

The core is a single pure function:

```cpp
// src/cursor_edge_teleport.h
namespace KWin {

class CursorEdgeTeleport {
public:
    // Returns the warp target on the nearest reachable output, or
    // nullopt if no teleport is needed / possible (caller should
    // fall back to standard clamping).
    //
    // currentPos: cursor position before this motion event
    // candidate:  cursor position the motion event would produce
    // allOutputRects: geometries of all enabled outputs; the source
    //                 output is identified internally as the one
    //                 containing currentPos.
    static std::optional<QPointF> resolve(
        const QPointF& currentPos,
        const QPointF& candidate,
        const QList<QRectF>& allOutputRects);
};

}
```

**Steps:**

1. If any rect in `allOutputRects` contains `candidate`, return `nullopt`. (Normal motion stays valid; no teleport needed.)
2. Compute `motion = candidate - currentPos`. If zero, return `nullopt`.
3. Identify the source rect: the one containing `currentPos`. (If none — defensive — treat all rects as non-source.)
4. For each non-source rect:
   - Compute `projected` = `candidate` clamped to the rect's bounds (nearest point on the rect).
   - Compute `fromCurrent = projected - currentPos`.
   - If `dot(motion, fromCurrent) <= 0`, skip — this output is behind the motion direction.
   - Compute `distSq = (candidate - projected) · (candidate - projected)`.
   - Track the projected point with the smallest `distSq`.
5. Return the tracked point if any was found; otherwise `nullopt`.

**Worked examples** (using single-row geometry: 4K-left at x∈[0,3840] y∈[0,2160], 2K-center at x∈[3840,6400] y∈[360,1800]):

| currentPos | delta | candidate | Step 1 hit? | Result |
|---|---|---|---|---|
| (3839, 1000) | (+10, 0) | (3849, 1000) | yes — inside 2K | `nullopt` (clean cross) |
| (3839, 100) | (+10, 0) | (3849, 100) | no | teleport to **(3849, 360)** — top edge of 2K |
| (0, 0) | (-10, -10) | (-10, -10) | no | all projections "behind"; `nullopt` (clamp) |
| (3839, 2050) | (+10, +10) | (3849, 2060) | no | 4K-SW projection ≈ (3840, 2060) closer than 2K's (3849, 1800); teleport to **(3840, 2060)** |

**Files**: `src/cursor_edge_teleport.{h,cpp}`. ~90 lines total. Pure, stateless, no KWin dependencies beyond `QPointF`/`QRectF`.

## Call-site integration

KWin's relative-motion path produces a candidate position after applying the motion delta, then clamps the candidate to the current output if it lies outside all outputs. The patch splices our helper in immediately before the clamp commits.

Conceptual diff (exact function name and line numbers verified during patch generation):

```cpp
// Existing:
//     QPointF newPos = m_pos + delta;
//     if (!isOnAnyOutput(newPos)) {
//         newPos = clampToCurrentOutput(newPos);
//     }
//     setPosition(newPos);

// Patched:
QPointF newPos = m_pos + delta;
if (!isOnAnyOutput(newPos)) {
    if (CursorEdgeTeleportConfig::enabled()) {
        QList<QRectF> rects;
        rects.reserve(workspace()->outputs().size());
        for (auto* o : workspace()->outputs()) rects.append(o->geometry());
        if (auto warp = CursorEdgeTeleport::resolve(m_pos, newPos, rects)) {
            qCDebug(KWIN_INPUT) << "CursorEdgeTeleport: warped from"
                                << m_pos << "to" << *warp;
            newPos = *warp;
        } else {
            newPos = clampToCurrentOutput(newPos);
        }
    } else {
        newPos = clampToCurrentOutput(newPos);
    }
}
setPosition(newPos);
```

Net new lines in `pointer_input.cpp`: ~12. Original clamp call remains as fallthrough — behavior is byte-identical to stock when the flag is off.

**Config helper** (`src/cursor_edge_teleport_config.{h,cpp}`):

```cpp
namespace KWin::CursorEdgeTeleportConfig {
    void load();      // called from PointerInputRedirection::init()
    bool enabled();   // branchless cached lookup; std::atomic<bool>
}
```

`load()` reads `[CursorEdgeTeleport]/Enabled` from `kwinrc`, caches in atomic bool, and registers a `KConfigWatcher` listener so runtime changes apply without restart.

**User-facing config surface:**

```ini
[CursorEdgeTeleport]
Enabled=true
```

Applied via `kwriteconfig6 --file kwinrc --group CursorEdgeTeleport --key Enabled true`. No System Settings UI in v1.

## Error handling & edge cases

Most degenerate inputs handle themselves correctly through algorithm structure:

| Case | Behavior |
|---|---|
| Empty outputs list | Loop iterates zero times → `nullopt` → caller clamps |
| `currentPos` outside all outputs (defensive) | No source rect to skip; algorithm proceeds normally |
| Zero-delta candidate | Early `nullopt`; caller clamps (no-op) |
| Overlapping/mirrored outputs (candidate inside multiple) | First containment match returns `nullopt` |
| Mixed-scale outputs | `Output::geometry()` returns logical coords already; rect math works in unified space |
| Negative-coordinate outputs | Signed arithmetic; no issue |
| Very large motion delta (fling) | Closest reachable point selected; cursor lands on far edge of nearest output |
| Output hotplug mid-motion | KWin serializes layout changes upstream; we see current snapshot |
| Equidistant tie-break | First match by list iteration order; deterministic |

**Explicit concerns:**

1. **Runtime config toggle race.** `KConfigWatcher` triggers `load()`; cached `std::atomic<bool>` is updated. Motion events mid-update see either old or new value — both correct.
2. **Edge Barrier interaction.** Plasma 6.1+ Edge Barrier intercepts motion *before* the candidate reaches our path. If enabled, the cursor will feel sticky at the corner first, then teleport — functional but odd. Documentation note: **users enabling `CursorEdgeTeleport` should also set Edge Barrier to 0** in System Settings → Screen Edges.
3. **Debug logging.** Single `qCDebug(KWIN_INPUT)` line per teleport. Enable with `QT_LOGGING_RULES="kwin.input.debug=true"`. Zero cost when off.

**Failure mode worth a one-time warning at config load:**
- An output with empty (zero-area) geometry. Algorithm silently skips it; we log a `qCWarning` to surface a misconfigured display.

## Testing strategy

**Layer 1 — unit tests (T7910, KWin's autotest framework):**

`autotests/cursor_edge_teleport_test.cpp` exercises `resolve()` with synthesized `QRectF` lists. Test cases:

- `testCandidateInsideOutput` — returns `nullopt` for normal motion
- `testCleanAlignedCrossing` — candidate in aligned neighbor → `nullopt`
- `testDeadZoneTeleportsToNearestEdge` — the core BEAST scenario
- `testBackwardsWarpRejected` — push into pure void → `nullopt`
- `testClosestAmongMultipleCandidates` — three reachable outputs, picks closest
- `testEmptyOutputList` — no crash, returns `nullopt`
- `testSingleOutput` — no other rect → `nullopt`
- `testEquidistantTieBreakStable` — deterministic across runs
- `testNegativeCoordinateOutput` — output at negative origin
- `testZeroDeltaCandidate` — `candidate == currentPos` → `nullopt`

Run via `cd build && ctest -R cursor_edge_teleport`. Target runtime: <50 ms.

**Layer 2 — nested-session functional test (T7910):**

`scripts/nested-test.sh` launches the patched `kwin_wayland` as a nested compositor with three synthetic mismatched outputs (1920×1080 + 1280×720 vertically centered + 1920×1080) reproducing BEAST's dead-zone topology at desk scale.

Manual verification checklist (`scripts/checklist.md`):

- [ ] 4K-stand-in center → 2K-stand-in center: clean crossing (no debug log)
- [ ] 4K-stand-in top-right corner pushing right: teleport, log shows landing at top-left of 2K
- [ ] 4K-stand-in bottom-right corner pushing right: teleport, log shows landing at bottom-left of 2K
- [ ] 2K-stand-in pushing right with y in 4K-right range: clean cross
- [ ] (0, 0) pushing up-left: clamp, no teleport
- [ ] Toggle `Enabled=false` via `kwriteconfig6`, observe via KConfigWatcher: corner-pin returns
- [ ] Toggle `Enabled=true`: teleport resumes

Each teleport expectation is verified via the `qCDebug` log line, not by eyeballing cursor coordinates.

**Layer 3 — BEAST hardware validation:**

1. `makepkg -s` on T7910 produces `kwin-*.pkg.tar.zst`
2. `scp` to BEAST, `sudo pacman -U`
3. Log out and back into Plasma Wayland session
4. Re-run checklist against real 2x3 grid
5. ~24 hours of daily use; log anomalies in `VERSION_HISTORY.md`

**Non-regression guarantee** (critical):

With `Enabled=false` (default), the patched binary behaves identically to stock KWin. Verified by:

- KWin's own `ctest` suite passes against the patched tree
- Manual: with flag off, cursor corner-pins on 2x3 grid exactly as stock did
- `kwin_wayland --version` output unchanged

## Deployment & rollback

**Deploy**:
1. T7910: `cd packaging && makepkg -s` → produces signed `kwin-*.pkg.tar.zst`
2. `scp kwin-*.pkg.tar.zst beast:/tmp/`
3. BEAST: `sudo pacman -U /tmp/kwin-*.pkg.tar.zst`
4. Log out and back in

**Rollback** (if patched session fails to start):
1. SSH to affected host from any other machine
2. Run `scripts/install-stock.sh` (`sudo pacman -S kwin --overwrite '*'`)
3. Log out and back into Plasma — stock KWin is restored

## Open questions / future work

- **kwin_wayland CLI output positioning**: if `--output-count`/`--width`/`--height` don't allow positioning the middle output offset, `scripts/nested-test.sh` will need to invoke `kscreen-doctor` inside the nested session after startup. Verified during script implementation.
- **Exact pointer_input.cpp function/line numbers**: confirmed during patch generation on T7910 against KWin 6.6.4 source.
- **Diagonal corner ambiguity**: v1 picks closest output by Euclidean distance. If BEAST usage reveals a layout where this feels wrong (e.g., user expects bottom-right corner of NW 4K to go to 2K-S rather than 4K-SW), revisit with directional weighting in v2.
- **Upstream MR**: not part of this work. Decide after the patch has been in daily use long enough to surface issues.
