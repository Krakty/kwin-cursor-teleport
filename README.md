# kwin-cursor-teleport

Personal community fork of [KWin](https://invent.kde.org/plasma/kwin) (Plasma 6, Wayland) that
**teleports the cursor to the nearest reachable point on an adjacent output** when motion would
otherwise corner-pin the cursor in a dead zone caused by unaligned monitor edges.

Not affiliated with KDE. This is an unofficial patch maintained for personal use; it is published
publicly so others affected by the same long-standing issue can find and adopt it.

## The problem this fixes

If you have monitors of different vertical resolutions arranged side-by-side (e.g., a 4K next to a
1080p, or a 4K next to a vertically-centered 2K), regions of the larger monitor's edge have no
adjacent output to cross into. Stock KWin clamps the cursor in the corner of the larger monitor
in those regions — you have to drag the cursor up or down to find the "live band" before it will
cross.

Prior community discussion of this issue with no upstream resolution as of 2026:
- [discuss.kde.org #10434](https://discuss.kde.org/t/10434)
- [discuss.kde.org #39058](https://discuss.kde.org/t/39058)
- [discuss.kde.org #44427](https://discuss.kde.org/t/44427)

## What this patch does

When a pointer motion event would carry the cursor outside all enabled outputs, the patch picks
the nearest reachable point on an adjacent output **in the direction of motion** and warps the
cursor there. When motion stays inside an output (or crosses cleanly across aligned edges),
behavior is unchanged from stock KWin.

The behavior is **opt-in** via a `kwinrc` flag, so installing the patched package does not change
default behavior. Algorithm details, requirements, and worked examples are in
[docs/superpowers/specs/](docs/superpowers/specs/).

## Targets

- KWin 6.6.5 (current Arch / CachyOS at time of writing)
- Older artifact preserved for KWin 6.6.4 in `patches/6.6.4/`
- Patch reapplied cleanly across the 6.6.4 → 6.6.5 version bump with zero conflicts; expected to
  carry forward similarly for future point releases

## Install (Arch / CachyOS / derivatives)

```bash
git clone https://github.com/Krakty/kwin-cursor-teleport.git
cd kwin-cursor-teleport/packaging
makepkg -s --skippgpcheck
sudo pacman -U kwin-*.pkg.tar.zst
```

Then enable the feature in your kwinrc:

```bash
kwriteconfig6 --file kwinrc --group CursorEdgeTeleport --key Enabled true
qdbus6 org.kde.KWin /KWin reconfigure
```

Also recommended: disable Edge Barrier (System Settings → Window Management → Screen Edges →
Corner Barrier off, Edge Barrier 0) so its friction doesn't compound with the teleport.

You'll need to log out and back in (or reboot) for the patched binary to start running. Log out is
sufficient; full reboot is not required.

## Pinning against pacman upgrades

By default, the next `pacman -Syu` that brings a newer `kwin` will silently replace this patched
build with stock. To prevent that, add `kwin` to `IgnorePkg` in `/etc/pacman.conf`:

```ini
IgnorePkg = kwin
```

Pacman will then skip kwin during system upgrades and print a clear warning when a new version is
available. When you're ready to take a new KWin version, rebase this patch on top of the new tag
(see `patches/` for the per-version artifacts), rebuild, and reinstall.

## Rollback to stock

```bash
sudo pacman -S kwin --overwrite '*'
```

Restores stock KWin from official Arch repos. SSH access to the affected machine is sufficient —
no need for a working KWin session to recover.

## Repo layout

- `patches/<kwin-version>/` — canonical git-format-patch files, one per KWin version
- `packaging/PKGBUILD` — Arch package that applies the patch and provides `kwin`
- `packaging/0001-cursor-edge-teleport.patch` — symlink to the current target version's patch
- `scripts/install-stock.sh` — recovery script (pacman -S kwin --overwrite '*')
- `scripts/nested-test.sh` — launch nested `kwin_wayland` with mismatched virtual outputs for testing
- `scripts/checklist.md` — manual verification checklist
- `docs/superpowers/specs/` — design specs
- `docs/superpowers/plans/` — implementation plans
- `VERSION_HISTORY.md` — verification log per KWin version + per host

## License

GPL-2.0-or-later, matching KWin upstream. See [LICENSE](LICENSE).

## Contributing

This is a personal fork. If you hit the same problem and the patch works for you, the most useful
thing you can do is mention it in the discuss.kde.org threads linked above — community evidence
that the fix has real users is more compelling to upstream maintainers than yet another feature
request thread.
