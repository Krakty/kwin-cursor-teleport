# kwin-cursor-teleport

Patch for KWin (Plasma 6, Wayland) that teleports the cursor to the nearest
reachable point on an adjacent output when motion would otherwise corner-pin
the cursor in a dead zone caused by unaligned monitor edges.

## Status

Opt-in via `kwinrc`. Default off. Targets KWin 6.6.4 on Arch Linux.

## Layout

- `patches/<kwin-version>/` — canonical git-format-patch files, one per KWin version
- `packaging/PKGBUILD` — Arch package that applies the patch
- `scripts/apply.sh` — clone upstream KWin and apply the patch into a build tree
- `scripts/nested-test.sh` — launch nested `kwin_wayland` with mismatched outputs
- `scripts/install-stock.sh` — restore stock KWin via pacman (recovery)
- `scripts/checklist.md` — manual verification checklist
- `docs/superpowers/specs/` — design specs
- `docs/superpowers/plans/` — implementation plans
- `VERSION_HISTORY.md` — log of "verified against KWin X.Y.Z on YYYY-MM-DD"

## Enable

After installing the patched package, add to `~/.config/kwinrc`:

```ini
[CursorEdgeTeleport]
Enabled=true
```

Then reload KWin's config without restarting Plasma:

```
qdbus org.kde.KWin /KWin reconfigure
```

## Rollback

```
sudo pacman -S kwin --overwrite '*'
```

Restores stock KWin from official Arch repos.
