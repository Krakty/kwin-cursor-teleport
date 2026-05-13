# Manual verification checklist

Each row gives an action and the expected outcome. Run with
`QT_LOGGING_RULES="kwin_core.debug=true"` so teleport events are logged
visibly.

Watch for log lines matching:

```
kwin_core: CursorEdgeTeleport: warped from QPointF(...) to QPointF(...)
```

## Setup
- [ ] `[CursorEdgeTeleport]/Enabled=true` in `~/.config/kwinrc`
- [ ] Edge Barrier disabled: System Settings → Window Management → Screen Edges → Corner Barrier and Edge Barrier both set to 0
- [ ] Reload via `qdbus org.kde.KWin /KWin reconfigure`

## Tests with Enabled=true

- [ ] Move cursor across an aligned edge (mid-height of stand-in 4K → 2K):
      expected: clean crossing, NO `warped from ...` log line
- [ ] Move cursor from 4K-stand-in top-right corner pushing right:
      expected: log line `warped from QPointF(1919,X) to QPointF(192Y,180)`;
      cursor visibly jumps down to top edge of 2K-stand-in
- [ ] Move cursor from 4K-stand-in bottom-right corner pushing right:
      expected: log line `warped from QPointF(1919,X) to QPointF(192Y,900)`;
      cursor jumps up to bottom edge of 2K-stand-in
- [ ] Move cursor at (0,0) pushing up-left:
      expected: clamped, NO log line
- [ ] Move cursor at 2K-stand-in pushing right into 4K-right's y range:
      expected: clean crossing, NO log line

## Tests with Enabled=false (regression check)

- [ ] Set `Enabled=false`, run `qdbus org.kde.KWin /KWin reconfigure`
- [ ] Move cursor from 4K-stand-in top-right corner pushing right:
      expected: corner-pins, NO log line (stock KWin behavior)
- [ ] Move cursor across aligned edge:
      expected: clean crossing, NO log line

## Runtime toggle test
- [ ] With Enabled=false (corner-pinned), set `Enabled=true` and reconfigure:
      expected: subsequent edge motion produces teleport without restart
- [ ] Set `Enabled=false`, reconfigure:
      expected: corner-pin returns immediately

## Result
After all rows pass on T7910 nested session, update `VERSION_HISTORY.md` with the date.
After all rows pass on BEAST real hardware, update again.
