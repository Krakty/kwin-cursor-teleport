# Version History

Log of patch verification against each KWin version.

| KWin version | Patch | T7910 unit tests | T7910 nested-session | BEAST hardware | Verified on |
|---|---|---|---|---|---|
| 6.6.4 | `patches/6.6.4/0001-cursor-edge-teleport.patch` | pass | skipped — rolled forward to 6.6.5 | skipped | 2026-05-13 (algorithm tests only) |
| 6.6.5 | `patches/6.6.5/0001-cursor-edge-teleport.patch` | pass | pending | pending | 2026-05-13 |

## Notes

- **6.6.4 → 6.6.5 carryover**: patch applied to v6.6.5 via `git am` with zero conflicts. Generated artifact differs from 6.6.4 only in commit SHA / blob hashes; the source-level diff is identical. Suggests our change targets stable code paths in `pointer_input.cpp`.
