# Version History

Log of patch verification against each KWin version.

| KWin version | Patch | T7910 unit tests | T7910 nested-session | BEAST hardware | Verified on |
|---|---|---|---|---|---|
| 6.6.4 | `patches/6.6.4/0001-cursor-edge-teleport.patch` | pass | skipped — rolled forward to 6.6.5 | skipped | 2026-05-13 (algorithm tests only) |
| 6.6.5 | `patches/6.6.5/0001-cursor-edge-teleport.patch` | pass | pending | pending | 2026-05-13 |
| 6.6.5 (pkgrel 2.3) | same patch, bottom-edge fix | pass | n/a | n/a | 2026-05-20 |

## Real-hardware results

| Host | Layout | Patched ver | Outcome | Date |
|---|---|---|---|---|
| T7910 | Aligned multi-monitor (no dead zones) | 6.6.5-1.1 | Non-regression confirmed; flag toggles cleanly; nothing breaks | 2026-05-13 |
| wks-lt7760 (CachyOS) | 4K eDP-1 + 1080p HDMI-A-1 offset y=453 (centered) | 6.6.5-2.3 | Top dead zone (y=0..453) and bottom dead zone (y=1533..2160) both teleport correctly into the 1080p | 2026-05-20 |
| BEAST | 2x3 grid with center 2K column between 4Ks | 6.6.5-2.3 | Installed + configured; pending user logout/login to load patched binary | 2026-05-20 (install) |

## Notes

- **6.6.4 → 6.6.5 carryover**: patch applied to v6.6.5 via `git am` with zero conflicts. Generated artifact differs from 6.6.4 only in commit SHA / blob hashes; the source-level diff is identical. Suggests our change targets stable code paths in `pointer_input.cpp`.
- **2.2 → 2.3 bottom-edge fix**: KWin's `Rect::contains()` uses half-open intervals `[left, right)` and `[top, bottom)`. Our `projectOntoRect` originally clamped warp targets to the inclusive `right()` / `bottom()`, which `screenContainsPos()` in `updatePosition` then rejected. Manifested asymmetrically: top edge worked, bottom edge did not. Fix is one line — clamp to `right() - 1.0` / `bottom() - 1.0`, matching KWin's `confineToBoundingBox` convention. Confirmed working on wks-lt7760 2026-05-20.
