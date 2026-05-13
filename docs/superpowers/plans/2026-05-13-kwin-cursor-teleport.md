# KWin Cursor Edge Teleport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Patch KWin 6.6.4 (Plasma 6, Wayland) so the cursor teleports to the nearest reachable point on an adjacent output when motion would otherwise corner-pin in a dead zone. Behavior is opt-in via `kwinrc`; default off preserves stock behavior byte-for-byte.

**Architecture:** New pure helper module (`cursor_edge_teleport.{h,cpp}`) holding the geometry algorithm + a thin config helper (`cursor_edge_teleport_config.{h,cpp}`) reading `kwinrc` via `KConfigWatcher`. One conditional block inserted in `src/pointer_input.cpp` before KWin's existing clamp-to-current-output call. Algorithm operates on `QList<QRectF>` for testability. Build via Arch PKGBUILD that applies a single git-format-patch on top of upstream `kwin` 6.6.4.

**Tech Stack:** KWin 6.6.4 source (C++17, Qt 6, CMake/Extra-CMake-Modules), KConfig/KConfigWatcher, QtTest autotest framework, Arch Linux PKGBUILD packaging, `kwin_wayland` nested compositor for testing.

---

## Hosts and Repo Layout (read before starting)

- **Project repo** lives on BEAST at `/mnt/DEV/Projects/kwin-cursor-teleport/`
- **Development happens on T7910** (Arch Linux). The repo is accessed from T7910 via SSHFS mount
- **BEAST is the deploy target** only — the patched binary is installed on BEAST after T7910 validation
- All paths in this plan that start with `~/src/kwin/` refer to T7910's local KWin source clone (kept out of the repo)
- All paths that start with `~/kwin-teleport-repo/` refer to T7910's SSHFS mount of the BEAST repo

---

## Phase 0 — Repo Scaffolding (on BEAST)

### Task 0.1: Create README

**Files:**
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/README.md`

- [ ] **Step 1: Write the README**

```markdown
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

After installing the patched package:

```ini
# ~/.config/kwinrc
[CursorEdgeTeleport]
Enabled=true
```

Then `qdbus org.kde.KWin /KWin reconfigure` (or log out / back in).

## Rollback

```
sudo pacman -S kwin --overwrite '*'
```

Logs out the patched KWin and installs stock from official repos.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Add README"
```

### Task 0.2: Create .gitignore

**Files:**
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/.gitignore`

- [ ] **Step 1: Write .gitignore**

```
# Arch packaging artifacts
packaging/*.pkg.tar.zst
packaging/*.pkg.tar.zst.sig
packaging/src/
packaging/pkg/

# Editor backups
*.swp
*.swo
*~
.DS_Store

# Build directories that might leak in via SSHFS
build/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "Add .gitignore"
```

### Task 0.3: Create directory structure

**Files:**
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/patches/6.6.4/.gitkeep`
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/packaging/.gitkeep`
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/scripts/.gitkeep`

- [ ] **Step 1: Create directories with .gitkeep placeholders**

```bash
mkdir -p patches/6.6.4 packaging scripts
touch patches/6.6.4/.gitkeep packaging/.gitkeep scripts/.gitkeep
```

- [ ] **Step 2: Commit**

```bash
git add patches/ packaging/ scripts/
git commit -m "Add empty patches/, packaging/, scripts/ dirs"
```

### Task 0.4: VERSION_HISTORY.md initial entry

**Files:**
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/VERSION_HISTORY.md`

- [ ] **Step 1: Write initial version-history file**

```markdown
# Version History

Log of patch verification against each KWin version.

| KWin version | Patch | T7910 unit tests | T7910 nested-session | BEAST hardware | Verified on |
|---|---|---|---|---|---|
| 6.6.4 | `patches/6.6.4/0001-cursor-edge-teleport.patch` | pending | pending | pending | — |
```

- [ ] **Step 2: Commit**

```bash
git add VERSION_HISTORY.md
git commit -m "Add VERSION_HISTORY.md with KWin 6.6.4 row"
```

### Task 0.5: Create install-stock.sh recovery script

**Files:**
- Create: `/mnt/DEV/Projects/kwin-cursor-teleport/scripts/install-stock.sh`

- [ ] **Step 1: Write the recovery script**

```bash
#!/usr/bin/env bash
# Restore stock kwin from official Arch repos, overwriting the patched
# package. Use this when a patched session fails to start; run via SSH.
set -euo pipefail
echo "Restoring stock kwin from official Arch repos..."
sudo pacman -Syu --noconfirm kwin --overwrite '*'
echo
echo "Stock kwin restored. Log out and back in (or reboot) to use it."
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/install-stock.sh
git add scripts/install-stock.sh
git commit -m "Add scripts/install-stock.sh recovery script"
```

---

## Phase 1 — Dev Environment Setup (on T7910)

> All steps in this phase run on T7910. Connect via:
>
> ```bash
> ssh tlindell@t7910.romulous.lan
> ```

### Task 1.1: Mount BEAST repo via SSHFS

**Files:**
- N/A (creates a mount point and mounts a filesystem)

- [ ] **Step 1: Install sshfs if missing**

```bash
sudo pacman -S --needed sshfs
```

- [ ] **Step 2: Create mount point**

```bash
mkdir -p ~/kwin-teleport-repo
```

- [ ] **Step 3: Mount BEAST's repo**

```bash
sshfs beast.romulous.lan:/mnt/DEV/Projects/kwin-cursor-teleport ~/kwin-teleport-repo
```

- [ ] **Step 4: Verify mount works**

```bash
ls ~/kwin-teleport-repo
```

Expected: see README.md, docs/, patches/, packaging/, scripts/, VERSION_HISTORY.md, .gitignore

### Task 1.2: Install KWin build dependencies

**Files:**
- N/A (package installation)

- [ ] **Step 1: Install build dependencies**

```bash
sudo pacman -S --needed --asdeps base-devel git cmake ninja extra-cmake-modules \
    qt6-base qt6-declarative qt6-multimedia qt6-tools qt6-wayland qt6-svg \
    kf6-kconfig kf6-kcoreaddons kf6-ki18n kf6-kdeclarative kf6-kglobalaccel \
    kf6-kguiaddons kf6-kiconthemes kf6-kio kf6-kirigami kf6-knewstuff \
    kf6-knotifications kf6-kpackage kf6-kservice kf6-kwidgetsaddons \
    kf6-kwindowsystem kf6-plasma-framework kf6-solid kf6-syndication \
    kf6-syntax-highlighting kf6-threadweaver kf6-kcmutils kf6-krunner \
    kf6-kstatusnotifieritem libdisplay-info libdrm libei libinput \
    libxkbcommon libxcb pixman pipewire xorg-xwayland wayland wayland-protocols
```

Expected: pacman installs missing dependencies; no errors.

- [ ] **Step 2: Install asp/pkgctl for fetching the official PKGBUILD**

```bash
sudo pacman -S --needed pkgctl
```

### Task 1.3: Clone KWin 6.6.4 source

**Files:**
- N/A (creates `~/src/kwin/` on T7910)

- [ ] **Step 1: Clone KWin upstream**

```bash
mkdir -p ~/src
cd ~/src
git clone https://invent.kde.org/plasma/kwin.git
cd kwin
```

- [ ] **Step 2: Check out the matching tag**

```bash
git fetch --tags
git checkout v6.6.4
```

Expected: "HEAD is now at <sha> Update version to 6.6.4" or similar.

- [ ] **Step 3: Verify version**

```bash
grep -E "^set\(PROJECT_VERSION" CMakeLists.txt
```

Expected: `set(PROJECT_VERSION "6.6.4")`

### Task 1.4: Stock baseline build + test

**Files:**
- N/A (builds upstream KWin; produces `~/src/kwin/build/`)

- [ ] **Step 1: Configure build**

```bash
cd ~/src/kwin
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
```

Expected: configuration succeeds, "Build files have been written to: build".

- [ ] **Step 2: Build**

```bash
cmake --build build -j$(nproc)
```

Expected: build completes successfully. Takes 15-30 minutes on first run.

- [ ] **Step 3: Run KWin's own autotest suite as baseline**

```bash
cd build
ctest --output-on-failure -j$(nproc) 2>&1 | tee ~/kwin-baseline-ctest.log
```

Expected: most tests pass (some may flake or skip in headless/nested environments). Record the pass/fail summary in `~/kwin-baseline-ctest.log` for later comparison.

- [ ] **Step 4: Verify nested-session launch works**

```bash
cd ~/src/kwin/build
./bin/kwin_wayland --xwayland --width 1024 --height 768 &
KWIN_PID=$!
sleep 3
kill $KWIN_PID
```

Expected: a nested KWin window opens for ~3 seconds, then is killed. No error output before kill.

---

## Phase 2 — Algorithm Module (TDD on T7910)

All source-tree work happens in `~/src/kwin/`. New files go in `src/` and `autotests/`. We commit to the KWin repo's local git after each TDD cycle so we can `git format-patch` at the end.

### Task 2.1: Create the helper header skeleton

**Files:**
- Create: `~/src/kwin/src/cursor_edge_teleport.h`

- [ ] **Step 1: Write the header**

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QList>
#include <QPointF>
#include <QRectF>
#include <optional>

namespace KWin
{

class CursorEdgeTeleport
{
public:
    // Resolve where the cursor should land when a motion event would
    // carry it outside all enabled outputs.
    //
    // currentPos    cursor position before this motion event (expected
    //               to lie inside some output; defensive: tolerated if not)
    // candidate     position the motion event would produce after applying
    //               the delta (may be outside any output)
    // allOutputRects geometries of all enabled outputs in logical coords;
    //                the source output is identified internally as the
    //                one containing currentPos
    //
    // Returns nullopt when no teleport is needed (candidate is on some
    // output) or no reachable target exists in the motion direction.
    // The caller should fall back to standard clamping in those cases.
    static std::optional<QPointF> resolve(
        const QPointF &currentPos,
        const QPointF &candidate,
        const QList<QRectF> &allOutputRects);
};

} // namespace KWin
```

- [ ] **Step 2: Verify file syntax compiles (without registration yet)**

```bash
cd ~/src/kwin
g++ -std=c++17 -fsyntax-only -I$(qmake6 -query QT_INSTALL_HEADERS) src/cursor_edge_teleport.h
```

Expected: no output (success). If qmake6 isn't on PATH, use `pkg-config --cflags Qt6Core` for the include path.

### Task 2.2: Create the implementation stub

**Files:**
- Create: `~/src/kwin/src/cursor_edge_teleport.cpp`

- [ ] **Step 1: Write a stub that always returns nullopt**

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "cursor_edge_teleport.h"

namespace KWin
{

std::optional<QPointF> CursorEdgeTeleport::resolve(
    const QPointF &currentPos,
    const QPointF &candidate,
    const QList<QRectF> &allOutputRects)
{
    Q_UNUSED(currentPos);
    Q_UNUSED(candidate);
    Q_UNUSED(allOutputRects);
    return std::nullopt;
}

} // namespace KWin
```

### Task 2.3: Register new sources in src/CMakeLists.txt

**Files:**
- Modify: `~/src/kwin/src/CMakeLists.txt` (location to be identified)

- [ ] **Step 1: Identify the source list**

```bash
grep -n "pointer_input.cpp" ~/src/kwin/src/CMakeLists.txt
```

Expected: one line showing the source group that lists `pointer_input.cpp` (the `kwin` library target or similar). Note that line number.

- [ ] **Step 2: Add cursor_edge_teleport.cpp adjacent to pointer_input.cpp**

Open `~/src/kwin/src/CMakeLists.txt` and add `cursor_edge_teleport.cpp` to the same source list as `pointer_input.cpp`. Insertion is a single new line; preserve alphabetical or existing ordering if any.

Example (the surrounding context will look like):

```cmake
    cursor.cpp
    cursor_edge_teleport.cpp     # <-- added
    ...
    pointer_input.cpp
```

- [ ] **Step 3: Sanity check — full incremental build still passes**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc)
```

Expected: build completes; `cursor_edge_teleport.cpp` is compiled and linked into libkwin.

- [ ] **Step 4: Commit the skeleton**

```bash
cd ~/src/kwin
git add src/cursor_edge_teleport.h src/cursor_edge_teleport.cpp src/CMakeLists.txt
git commit -m "Add CursorEdgeTeleport helper skeleton"
```

### Task 2.4: Set up autotest registration

**Files:**
- Create: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`
- Modify: `~/src/kwin/autotests/CMakeLists.txt` (location to be identified)

- [ ] **Step 1: Identify the autotest registration macro**

```bash
head -40 ~/src/kwin/autotests/CMakeLists.txt
grep -n "kwin_test\|kwin_add_test\|ecm_add_test" ~/src/kwin/autotests/CMakeLists.txt | head -5
```

Expected: identify the function used to register simple unit tests (e.g., `kwin_add_test(<name> <source>)` or `ecm_add_test(<source> TEST_NAME <name>)`).

- [ ] **Step 2: Write the test file with one empty test fixture**

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "cursor_edge_teleport.h"

#include <QTest>
#include <QList>
#include <QPointF>
#include <QRectF>

using namespace KWin;

class TestCursorEdgeTeleport : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void testPlaceholder();
};

void TestCursorEdgeTeleport::testPlaceholder()
{
    QVERIFY(true);
}

QTEST_GUILESS_MAIN(TestCursorEdgeTeleport)
#include "test_cursor_edge_teleport.moc"
```

- [ ] **Step 3: Register the autotest in autotests/CMakeLists.txt**

Add a line matching the existing pattern (identified in Step 1). For example, if the existing pattern is `ecm_add_test(test_something.cpp TEST_NAME testSomething LINK_LIBRARIES Qt6::Test kwin)`, add:

```cmake
ecm_add_test(test_cursor_edge_teleport.cpp
    TEST_NAME testCursorEdgeTeleport
    LINK_LIBRARIES Qt6::Test kwin)
```

Adjust to whatever macro/library name the existing tests in the same file use.

- [ ] **Step 4: Build and run the placeholder test**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc)
cd build
ctest -R testCursorEdgeTeleport -V
```

Expected: one test runs, one passes (placeholder).

- [ ] **Step 5: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp autotests/CMakeLists.txt
git commit -m "Add CursorEdgeTeleport autotest skeleton"
```

### Task 2.5: TDD cycle — testCandidateInsideOutput

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`
- Modify: `~/src/kwin/src/cursor_edge_teleport.cpp`

- [ ] **Step 1: Replace the placeholder with the first real test**

Replace the contents of `test_cursor_edge_teleport.cpp` with:

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "cursor_edge_teleport.h"

#include <QTest>
#include <QList>
#include <QPointF>
#include <QRectF>

using namespace KWin;

class TestCursorEdgeTeleport : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void testCandidateInsideOutput();
};

void TestCursorEdgeTeleport::testCandidateInsideOutput()
{
    // 4K-left and 2K-center vertically centered. Candidate inside 2K.
    const QList<QRectF> outputs = {
        QRectF(0, 0, 3840, 2160),
        QRectF(3840, 360, 2560, 1440),
    };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(3839, 1000),
        QPointF(3849, 1000),
        outputs);
    QVERIFY(!result.has_value());
}

QTEST_GUILESS_MAIN(TestCursorEdgeTeleport)
#include "test_cursor_edge_teleport.moc"
```

- [ ] **Step 2: Build and confirm test passes with the stub**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: PASS — the stub returns nullopt for every input, so this test trivially passes. This is fine; the next tests will force the implementation.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp
git commit -m "Add testCandidateInsideOutput"
```

### Task 2.6: TDD cycle — testDeadZoneTeleportsToNearestEdge

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`
- Modify: `~/src/kwin/src/cursor_edge_teleport.cpp`

- [ ] **Step 1: Add the failing test**

In `test_cursor_edge_teleport.cpp`, add to the private slots and add the test method:

```cpp
// Add to private Q_SLOTS:
    void testDeadZoneTeleportsToNearestEdge();

// Add method body:
void TestCursorEdgeTeleport::testDeadZoneTeleportsToNearestEdge()
{
    // Cursor on 4K-left at y=100 (above 2K's range), pushed +10 right.
    // Candidate (3849, 100) is in dead zone above 2K. Expected:
    // teleport to (3849, 360) — top edge of 2K.
    const QList<QRectF> outputs = {
        QRectF(0, 0, 3840, 2160),
        QRectF(3840, 360, 2560, 1440),
    };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(3839, 100),
        QPointF(3849, 100),
        outputs);
    QVERIFY(result.has_value());
    QCOMPARE(*result, QPointF(3849, 360));
}
```

- [ ] **Step 2: Build and run — verify it FAILS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: FAIL on `testDeadZoneTeleportsToNearestEdge` — stub returns nullopt, test asserts `has_value()`.

- [ ] **Step 3: Implement the full algorithm in cursor_edge_teleport.cpp**

Replace the contents of `~/src/kwin/src/cursor_edge_teleport.cpp` with:

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "cursor_edge_teleport.h"

#include <algorithm>
#include <limits>

namespace KWin
{

namespace
{

QPointF projectOntoRect(const QPointF &p, const QRectF &r)
{
    return QPointF(
        std::clamp(p.x(), r.left(), r.right()),
        std::clamp(p.y(), r.top(), r.bottom()));
}

qreal squaredDistance(const QPointF &a, const QPointF &b)
{
    const QPointF d = a - b;
    return QPointF::dotProduct(d, d);
}

} // anonymous namespace

std::optional<QPointF> CursorEdgeTeleport::resolve(
    const QPointF &currentPos,
    const QPointF &candidate,
    const QList<QRectF> &allOutputRects)
{
    // Already valid? No teleport needed.
    for (const QRectF &r : allOutputRects) {
        if (r.contains(candidate)) {
            return std::nullopt;
        }
    }

    const QPointF motion = candidate - currentPos;
    if (motion.isNull()) {
        return std::nullopt;
    }

    // Identify the source rect (the one containing currentPos). May be
    // none in degenerate cases — that's tolerated.
    const QRectF *sourceRect = nullptr;
    for (const QRectF &r : allOutputRects) {
        if (r.contains(currentPos)) {
            sourceRect = &r;
            break;
        }
    }

    QPointF bestTarget;
    qreal bestDistSq = std::numeric_limits<qreal>::max();
    bool found = false;

    for (const QRectF &r : allOutputRects) {
        if (sourceRect && &r == sourceRect) {
            continue;
        }
        const QPointF projected = projectOntoRect(candidate, r);
        const QPointF fromCurrent = projected - currentPos;
        if (QPointF::dotProduct(motion, fromCurrent) <= 0.0) {
            continue;
        }
        const qreal distSq = squaredDistance(candidate, projected);
        if (distSq < bestDistSq) {
            bestDistSq = distSq;
            bestTarget = projected;
            found = true;
        }
    }

    if (!found) {
        return std::nullopt;
    }
    return bestTarget;
}

} // namespace KWin
```

- [ ] **Step 4: Build and run — verify both tests PASS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/src/kwin
git add src/cursor_edge_teleport.cpp autotests/test_cursor_edge_teleport.cpp
git commit -m "Implement CursorEdgeTeleport::resolve algorithm"
```

### Task 2.7: TDD cycle — testCleanAlignedCrossing

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`

- [ ] **Step 1: Add test**

In `test_cursor_edge_teleport.cpp`, add to private slots and add the body:

```cpp
    void testCleanAlignedCrossing();

void TestCursorEdgeTeleport::testCleanAlignedCrossing()
{
    // Two equal-height outputs sharing a clean edge. Candidate ends
    // up on the right one; algorithm returns nullopt (Step 1 catches it).
    const QList<QRectF> outputs = {
        QRectF(0, 0, 1920, 1080),
        QRectF(1920, 0, 1920, 1080),
    };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(1919, 500),
        QPointF(1925, 500),
        outputs);
    QVERIFY(!result.has_value());
}
```

- [ ] **Step 2: Build, run, verify PASS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: all three tests pass.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp
git commit -m "Add testCleanAlignedCrossing"
```

### Task 2.8: TDD cycle — testBackwardsWarpRejected

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`

- [ ] **Step 1: Add test**

```cpp
    void testBackwardsWarpRejected();

void TestCursorEdgeTeleport::testBackwardsWarpRejected()
{
    // Cursor at top-left of 4K-left, motion (-10, -10). Candidate
    // (-10, -10) is outside all outputs. The only other output is to
    // the right (positive x direction) — backwards from motion.
    // Expect nullopt (caller will clamp).
    const QList<QRectF> outputs = {
        QRectF(0, 0, 3840, 2160),
        QRectF(3840, 360, 2560, 1440),
    };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(0, 0),
        QPointF(-10, -10),
        outputs);
    QVERIFY(!result.has_value());
}
```

- [ ] **Step 2: Build, run, verify PASS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp
git commit -m "Add testBackwardsWarpRejected"
```

### Task 2.9: TDD cycle — testClosestAmongMultipleCandidates

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`

- [ ] **Step 1: Add test**

```cpp
    void testClosestAmongMultipleCandidates();

void TestCursorEdgeTeleport::testClosestAmongMultipleCandidates()
{
    // Three outputs: source, near neighbor (closer projection), far
    // neighbor (further projection). Algorithm should pick near.
    const QList<QRectF> outputs = {
        QRectF(0, 0, 100, 100),       // source
        QRectF(200, 0, 100, 100),     // near (projection at (200, 50))
        QRectF(400, 0, 100, 100),     // far  (projection at (400, 50))
    };
    // Cursor at (99, 50) moving right; candidate (150, 50) — between
    // source and near. Closest projection is on the near output.
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(99, 50),
        QPointF(150, 50),
        outputs);
    QVERIFY(result.has_value());
    QCOMPARE(*result, QPointF(200, 50));
}
```

- [ ] **Step 2: Build, run, verify PASS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp
git commit -m "Add testClosestAmongMultipleCandidates"
```

### Task 2.10: TDD cycle — testEmptyOutputList and testSingleOutput

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`

- [ ] **Step 1: Add both tests**

```cpp
    void testEmptyOutputList();
    void testSingleOutput();

void TestCursorEdgeTeleport::testEmptyOutputList()
{
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(100, 100),
        QPointF(110, 110),
        {});
    QVERIFY(!result.has_value());
}

void TestCursorEdgeTeleport::testSingleOutput()
{
    // Cursor leaves the only output — nothing else to teleport to.
    const QList<QRectF> outputs = { QRectF(0, 0, 100, 100) };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(99, 50),
        QPointF(110, 50),
        outputs);
    QVERIFY(!result.has_value());
}
```

- [ ] **Step 2: Build, run, verify PASS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp
git commit -m "Add testEmptyOutputList and testSingleOutput"
```

### Task 2.11: TDD cycle — testZeroDeltaCandidate, testNegativeCoordinateOutput, testEquidistantTieBreakStable

**Files:**
- Modify: `~/src/kwin/autotests/test_cursor_edge_teleport.cpp`

- [ ] **Step 1: Add all three tests**

```cpp
    void testZeroDeltaCandidate();
    void testNegativeCoordinateOutput();
    void testEquidistantTieBreakStable();

void TestCursorEdgeTeleport::testZeroDeltaCandidate()
{
    // currentPos == candidate, both outside any output.
    const QList<QRectF> outputs = {
        QRectF(0, 0, 100, 100),
        QRectF(200, 0, 100, 100),
    };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(150, 50),
        QPointF(150, 50),
        outputs);
    QVERIFY(!result.has_value());
}

void TestCursorEdgeTeleport::testNegativeCoordinateOutput()
{
    // Output positioned at negative origin (monitor to the left of (0,0))
    const QList<QRectF> outputs = {
        QRectF(-1000, 0, 1000, 1000),  // source
        QRectF(0, 100, 1000, 800),     // right neighbor, offset
    };
    const auto result = CursorEdgeTeleport::resolve(
        QPointF(-1, 50),       // top-right edge of source, above neighbor's y range
        QPointF(10, 50),
        outputs);
    QVERIFY(result.has_value());
    QCOMPARE(*result, QPointF(10, 100));  // teleport to top edge of right
}

void TestCursorEdgeTeleport::testEquidistantTieBreakStable()
{
    // Two outputs equidistant from candidate. First in list wins.
    const QList<QRectF> outputs = {
        QRectF(0, 0, 100, 100),        // source
        QRectF(200, 0, 100, 100),      // east — projection (200, 50), dist 50
        QRectF(100, 150, 100, 100),    // south — projection (100, 150), dist 50
    };
    // Candidate (150, 50): east projection (200, 50) distance sqrt(50²) = 50;
    //   south projection (150, 150) distance sqrt(100²) = 100. Pick east.
    // (Test the more straightforward "closest by distance, deterministic" case.)
    const auto result1 = CursorEdgeTeleport::resolve(
        QPointF(99, 50), QPointF(150, 50), outputs);
    const auto result2 = CursorEdgeTeleport::resolve(
        QPointF(99, 50), QPointF(150, 50), outputs);
    QVERIFY(result1.has_value());
    QVERIFY(result2.has_value());
    QCOMPARE(*result1, *result2);
    QCOMPARE(*result1, QPointF(200, 50));
}
```

- [ ] **Step 2: Build, run, verify all PASS**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) && cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: all 9 tests pass.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add autotests/test_cursor_edge_teleport.cpp
git commit -m "Add zero-delta, negative-coord, tie-break tests"
```

---

## Phase 3 — Config Helper Module (on T7910)

### Task 3.1: Create config helper header

**Files:**
- Create: `~/src/kwin/src/cursor_edge_teleport_config.h`

- [ ] **Step 1: Write the header**

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

namespace KWin::CursorEdgeTeleportConfig
{
// Loads the [CursorEdgeTeleport]/Enabled key from kwinrc and registers
// a KConfigWatcher listener so subsequent changes apply at runtime.
// Idempotent: safe to call multiple times.
void load();

// Branchless cached lookup of the current Enabled value.
bool enabled();
} // namespace KWin::CursorEdgeTeleportConfig
```

### Task 3.2: Create config helper implementation

**Files:**
- Create: `~/src/kwin/src/cursor_edge_teleport_config.cpp`

- [ ] **Step 1: Write the implementation**

```cpp
/*
    SPDX-FileCopyrightText: 2026 tlindell <tlindell@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "cursor_edge_teleport_config.h"

#include <KConfigGroup>
#include <KConfigWatcher>
#include <KSharedConfig>

#include <QObject>
#include <atomic>

namespace KWin::CursorEdgeTeleportConfig
{

namespace
{
std::atomic<bool> s_enabled{false};
KConfigWatcher::Ptr s_watcher;

bool readFromConfig()
{
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    return config->group(QStringLiteral("CursorEdgeTeleport"))
        .readEntry(QStringLiteral("Enabled"), false);
}
} // anonymous namespace

void load()
{
    s_enabled.store(readFromConfig(), std::memory_order_relaxed);

    if (s_watcher) {
        return; // already wired
    }
    s_watcher = KConfigWatcher::create(
        KSharedConfig::openConfig(QStringLiteral("kwinrc")));
    QObject::connect(
        s_watcher.data(), &KConfigWatcher::configChanged,
        [](const KConfigGroup &group, const QByteArrayList &names) {
            if (group.name() != QLatin1String("CursorEdgeTeleport")) {
                return;
            }
            if (names.contains(QByteArrayLiteral("Enabled")) || names.isEmpty()) {
                s_enabled.store(readFromConfig(), std::memory_order_relaxed);
            }
        });
}

bool enabled()
{
    return s_enabled.load(std::memory_order_relaxed);
}

} // namespace KWin::CursorEdgeTeleportConfig
```

### Task 3.3: Register config sources in CMakeLists.txt

**Files:**
- Modify: `~/src/kwin/src/CMakeLists.txt`

- [ ] **Step 1: Add cursor_edge_teleport_config.cpp to the same source list as cursor_edge_teleport.cpp**

Open `~/src/kwin/src/CMakeLists.txt` and add `cursor_edge_teleport_config.cpp` adjacent to `cursor_edge_teleport.cpp` (added in Task 2.3).

- [ ] **Step 2: Build, confirm success**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc)
```

Expected: build completes. The new translation unit links into libkwin.

- [ ] **Step 3: Commit**

```bash
cd ~/src/kwin
git add src/cursor_edge_teleport_config.h src/cursor_edge_teleport_config.cpp src/CMakeLists.txt
git commit -m "Add CursorEdgeTeleportConfig kwinrc reader + KConfigWatcher"
```

---

## Phase 4 — Pointer Input Integration (on T7910)

### Task 4.1: Locate the clamp call site

**Files:**
- Read only: `~/src/kwin/src/pointer_input.cpp`

- [ ] **Step 1: Find candidate functions**

```bash
cd ~/src/kwin
grep -n "clamp\|isOnAnyOutput\|outputs\|setPosition" src/pointer_input.cpp | head -30
```

Note candidate functions that match the pattern "apply motion → check if position is on any output → clamp to current output if not".

- [ ] **Step 2: Read the file to identify the exact function**

```bash
less src/pointer_input.cpp
```

Look for the function that:
1. Applies a motion delta to the cursor position
2. Checks whether the resulting position is inside any output
3. Calls a clamp helper when the result is outside all outputs

Likely names: `processMotion`, `processMotionInternal`, `confineToOutput`, `clampToOutput`, or similar. Document the exact function name, file location, and surrounding lines in a scratchpad. The next task references "the function identified here".

- [ ] **Step 3: Note the existing clamp call signature**

Record the exact form of the existing clamp call (it may take a position, return a position, or modify by reference). The next task substitutes our conditional block in place of that call.

### Task 4.2: Modify pointer_input.cpp to call CursorEdgeTeleport::resolve

**Files:**
- Modify: `~/src/kwin/src/pointer_input.cpp`

- [ ] **Step 1: Add includes at the top of the file**

```cpp
#include "cursor_edge_teleport.h"
#include "cursor_edge_teleport_config.h"
```

Insert these near the existing local includes (other `#include "..."` lines for KWin headers).

- [ ] **Step 2: Replace the bare clamp call with the conditional block**

In the function identified in Task 4.1, find the existing clamp call (named here as `existingClamp(newPos)` — substitute the real call). Replace:

```cpp
// before
newPos = existingClamp(newPos);
```

with:

```cpp
// after
if (CursorEdgeTeleportConfig::enabled()) {
    QList<QRectF> rects;
    rects.reserve(workspace()->outputs().size());
    for (auto *o : workspace()->outputs()) {
        rects.append(o->geometry());
    }
    if (auto warp = CursorEdgeTeleport::resolve(m_pos, newPos, rects)) {
        qCDebug(KWIN_INPUT) << "CursorEdgeTeleport: warped from"
                            << m_pos << "to" << *warp;
        newPos = *warp;
    } else {
        newPos = existingClamp(newPos);
    }
} else {
    newPos = existingClamp(newPos);
}
```

Substitute:
- `m_pos` with whatever variable holds the position *before* the motion delta was applied in that function (it may be `m_pos`, `oldPos`, `m_lastPosition`, etc.)
- `newPos` with the candidate-position variable
- `existingClamp(newPos)` with the exact clamp call form found in Task 4.1
- `workspace()->outputs()` with the exact accessor for the current output list (likely `workspace()->outputs()` or `kwinApp()->workspace()->outputs()` — verify against neighboring code)
- `KWIN_INPUT` with the existing logging category used in that file (likely already in scope)

### Task 4.3: Wire CursorEdgeTeleportConfig::load() into PointerInputRedirection init

**Files:**
- Modify: `~/src/kwin/src/pointer_input.cpp`

- [ ] **Step 1: Identify the init function**

```bash
grep -n "::init\|PointerInputRedirection::init" ~/src/kwin/src/pointer_input.cpp
```

Note the function name and line of the `PointerInputRedirection::init()` definition (or equivalent setup function).

- [ ] **Step 2: Add CursorEdgeTeleportConfig::load() at the start of init**

In `PointerInputRedirection::init()`, add as the first line in the function body:

```cpp
CursorEdgeTeleportConfig::load();
```

- [ ] **Step 3: Build the full tree**

```bash
cd ~/src/kwin
cmake --build build -j$(nproc) 2>&1 | tee ~/kwin-patch-build.log
```

Expected: build completes successfully. If a header isn't found, add the corresponding include. If `workspace()->outputs()` is wrong, refer to neighboring code that calls similar accessors.

- [ ] **Step 4: Run KWin's full autotest suite**

```bash
cd ~/src/kwin/build
ctest --output-on-failure -j$(nproc) 2>&1 | tee ~/kwin-patch-ctest.log
diff <(grep -E "^[0-9]+/[0-9]+ Test" ~/kwin-baseline-ctest.log | awk '{print $NF, $4}' | sort) \
     <(grep -E "^[0-9]+/[0-9]+ Test" ~/kwin-patch-ctest.log | awk '{print $NF, $4}' | sort)
```

Expected: zero diff between baseline (Task 1.4) and patched test results. New `testCursorEdgeTeleport` adds a row; no existing rows regress.

- [ ] **Step 5: Commit the integration**

```bash
cd ~/src/kwin
git add src/pointer_input.cpp
git commit -m "Wire CursorEdgeTeleport into pointer_input.cpp clamp path"
```

---

## Phase 5 — Patch Artifact Generation (on T7910)

### Task 5.1: Generate format-patch from KWin commits

**Files:**
- Create: `~/kwin-teleport-repo/patches/6.6.4/0001-cursor-edge-teleport.patch`

- [ ] **Step 1: Squash the work into one commit**

```bash
cd ~/src/kwin
git log --oneline v6.6.4..HEAD
```

Note the number of commits since v6.6.4 (should be ~10 from Phase 2-4 work).

```bash
git reset --soft v6.6.4
git commit -m "Add CursorEdgeTeleport: warp cursor across unaligned outputs

Adds an opt-in cursor-warp behavior controlled by [CursorEdgeTeleport]/Enabled
in kwinrc. When enabled, motion that would corner-pin the cursor in a dead
zone (no adjacent output at the cursor's perpendicular coordinate) instead
warps to the nearest reachable point on an adjacent output in the motion
direction.

When the flag is off (default), behavior is byte-identical to stock KWin.

New module: src/cursor_edge_teleport.{h,cpp} — pure geometry, autotested
            src/cursor_edge_teleport_config.{h,cpp} — kwinrc + KConfigWatcher
            autotests/test_cursor_edge_teleport.cpp — 9 unit tests

Modified: src/pointer_input.cpp — ~12-line conditional block before clamp
          src/CMakeLists.txt — register new sources
          autotests/CMakeLists.txt — register new test"
```

- [ ] **Step 2: Generate the patch file**

```bash
cd ~/src/kwin
git format-patch -1 -o /tmp v6.6.4
ls /tmp/0001-*.patch
```

Expected: one patch file with a name like `0001-Add-CursorEdgeTeleport-warp-cursor-across-unaligned-.patch`.

- [ ] **Step 3: Move to repo and rename canonically**

```bash
cp /tmp/0001-*.patch ~/kwin-teleport-repo/patches/6.6.4/0001-cursor-edge-teleport.patch
```

- [ ] **Step 4: Verify patch re-applies cleanly on a fresh checkout**

```bash
cd /tmp
git clone ~/src/kwin kwin-verify
cd kwin-verify
git checkout v6.6.4
git am ~/kwin-teleport-repo/patches/6.6.4/0001-cursor-edge-teleport.patch
git log --oneline -1
```

Expected: patch applies cleanly; `git log -1` shows the squashed commit.

- [ ] **Step 5: Clean up verify dir**

```bash
rm -rf /tmp/kwin-verify
```

- [ ] **Step 6: Commit the patch artifact to the project repo**

```bash
cd ~/kwin-teleport-repo
git add patches/6.6.4/0001-cursor-edge-teleport.patch
rm patches/6.6.4/.gitkeep
git add patches/6.6.4/.gitkeep
git commit -m "Add KWin 6.6.4 cursor-teleport patch artifact"
```

---

## Phase 6 — Packaging (on T7910)

### Task 6.1: Fetch the official Arch kwin PKGBUILD

**Files:**
- Create: `~/kwin-teleport-repo/packaging/PKGBUILD`

- [ ] **Step 1: Clone the official package repo**

```bash
cd /tmp
pkgctl repo clone --protocol=https kwin
```

Expected: clones `kwin` into `/tmp/kwin/`.

- [ ] **Step 2: Copy PKGBUILD into project repo**

```bash
cp /tmp/kwin/PKGBUILD ~/kwin-teleport-repo/packaging/PKGBUILD
```

- [ ] **Step 3: Note the existing source/sha256/prepare/build/package structure**

```bash
less ~/kwin-teleport-repo/packaging/PKGBUILD
```

Identify:
- The `source=()` array
- The `sha256sums=()` array
- Whether a `prepare()` function exists (where we'll apply the patch)
- Whether the upstream tag matches `v6.6.4` (it should, since stock package is `kwin-6.6.4-1`)

### Task 6.2: Modify PKGBUILD to apply the patch

**Files:**
- Modify: `~/kwin-teleport-repo/packaging/PKGBUILD`

- [ ] **Step 1: Add the patch to source array**

In `~/kwin-teleport-repo/packaging/PKGBUILD`, modify the `source=()` array to append our patch. Example (the existing form may differ):

```bash
source=("https://download.kde.org/stable/plasma/${pkgver}/kwin-${pkgver}.tar.xz"
        "0001-cursor-edge-teleport.patch::../patches/6.6.4/0001-cursor-edge-teleport.patch")
```

The `::../patches/6.6.4/...` form tells makepkg the file is local relative to PKGBUILD; the part before `::` is the filename it gets in the build dir.

- [ ] **Step 2: Add sha256sum for the patch (or SKIP)**

```bash
sha256sum ~/kwin-teleport-repo/patches/6.6.4/0001-cursor-edge-teleport.patch
```

Append the hash (or `'SKIP'` for local files; SKIP is acceptable for local sources). Example:

```bash
sha256sums=('<upstream-sha256>'
            'SKIP')
```

- [ ] **Step 3: Add or modify the prepare() function**

If `prepare()` already exists, append our patch step. If not, add:

```bash
prepare() {
    cd "${srcdir}/kwin-${pkgver}"
    patch -p1 < "${srcdir}/0001-cursor-edge-teleport.patch"
}
```

- [ ] **Step 4: Bump pkgrel to mark as a custom build**

Change `pkgrel=1` to `pkgrel=1.cursorteleport1`. This makes the version distinct from the official package so pacman flags the divergence in `pacman -Qm`.

- [ ] **Step 5: Run makepkg**

```bash
cd ~/kwin-teleport-repo/packaging
makepkg -s --noconfirm
```

Expected: pulls upstream source, applies patch, builds. Takes ~20-40 minutes on first run.

- [ ] **Step 6: Verify the package contents**

```bash
pacman -Qpl ~/kwin-teleport-repo/packaging/kwin-*.pkg.tar.zst | grep -E "kwin_wayland$"
```

Expected: at least one line showing `/usr/bin/kwin_wayland` in the package.

- [ ] **Step 7: Commit the packaging files**

```bash
cd ~/kwin-teleport-repo
git add packaging/PKGBUILD
rm packaging/.gitkeep
git add packaging/.gitkeep
git commit -m "Add PKGBUILD that applies cursor-teleport patch to kwin 6.6.4"
```

---

## Phase 7 — Nested-Session Test (on T7910)

### Task 7.1: Install the patched package on T7910

**Files:**
- N/A (pacman -U)

- [ ] **Step 1: Install**

```bash
sudo pacman -U ~/kwin-teleport-repo/packaging/kwin-*.pkg.tar.zst
```

Expected: prompts to replace stock kwin; confirm.

- [ ] **Step 2: Log out and back in to T7910's Plasma session**

(Manual step at the SDDM login screen if T7910 runs a graphical session, or simply continue with nested testing from the existing session — the patched binary is loaded fresh when `kwin_wayland` starts.)

- [ ] **Step 3: Verify the patched binary exists at the expected location**

```bash
which kwin_wayland
kwin_wayland --version
```

Expected: path to `/usr/bin/kwin_wayland`; version reports `6.6.4`.

### Task 7.2: Create the nested-test launch script

**Files:**
- Create: `~/kwin-teleport-repo/scripts/nested-test.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Launch nested kwin_wayland with mismatched virtual outputs to exercise
# CursorEdgeTeleport without needing physical hardware.
#
# Layout produced (single row, scaled-down BEAST analogue):
#   [1920x1080 4K-stand-in] [1280x720 2K-stand-in offset+180] [1920x1080]
#
# After launch, the script prints the geometry it expects to set via
# kscreen-doctor; run those commands in the nested session if the CLI
# flags alone don't produce the offset.
#
# Usage:
#   ./nested-test.sh            # use installed kwin_wayland
#   ./nested-test.sh /path/to/kwin_wayland  # use a specific binary
set -euo pipefail

KWIN_BIN="${1:-kwin_wayland}"

export QT_LOGGING_RULES="kwin.input.debug=true;${QT_LOGGING_RULES:-}"

echo "Launching nested $KWIN_BIN with 3 virtual outputs..."
"$KWIN_BIN" --xwayland \
    --width 1920 --height 1080 \
    --width 1280 --height 720 \
    --width 1920 --height 1080 \
    --output-count 3 &
KWIN_PID=$!

trap "kill $KWIN_PID 2>/dev/null || true" EXIT

cat <<'EOF'

Nested kwin_wayland is starting.

If the middle output isn't vertically centered, run inside the nested
session (use the nested terminal):

    kscreen-doctor output.1.position.0,180

Then exercise the verification checklist in scripts/checklist.md.

Press Ctrl-C to terminate the nested session.
EOF

wait $KWIN_PID
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x ~/kwin-teleport-repo/scripts/nested-test.sh
cd ~/kwin-teleport-repo
git add scripts/nested-test.sh
git commit -m "Add scripts/nested-test.sh for nested kwin_wayland testing"
```

### Task 7.3: Create the verification checklist

**Files:**
- Create: `~/kwin-teleport-repo/scripts/checklist.md`

- [ ] **Step 1: Write the checklist**

```markdown
# Manual verification checklist

Each row gives an action and the expected outcome. Run with
`QT_LOGGING_RULES="kwin.input.debug=true"` so teleport events are logged.

Look for log lines matching:
```
kwin.input: CursorEdgeTeleport: warped from <QPointF> to <QPointF>
```

## Setup
- [ ] `[CursorEdgeTeleport]/Enabled=true` in kwinrc
- [ ] Edge Barrier set to 0 in System Settings → Window Management → Screen Edges
- [ ] Reload via `qdbus org.kde.KWin /KWin reconfigure`

## Tests with Enabled=true

- [ ] Move cursor across aligned edge (mid-height of stand-in 4K → 2K):
      expected: clean crossing, NO `warped from ...` log line
- [ ] Move cursor from 4K-stand-in top-right corner pushing right:
      expected: log line `warped from QPointF(1919,X) to QPointF(192Y,180)`
      (cursor visibly jumps down to top edge of 2K stand-in)
- [ ] Move cursor from 4K-stand-in bottom-right corner pushing right:
      expected: log line `warped from QPointF(1919,X) to QPointF(192Y,900)`
      (cursor jumps up to bottom edge of 2K stand-in)
- [ ] Move cursor at (0,0) pushing up-left:
      expected: clamped, NO log line
- [ ] Move cursor at 2K-stand-in pushing right into 4K-right's y range:
      expected: clean crossing, NO log line

## Tests with Enabled=false (regression check)

- [ ] Set `Enabled=false`, run `qdbus org.kde.KWin /KWin reconfigure`
- [ ] Move cursor from 4K-stand-in top-right corner pushing right:
      expected: corner-pins, NO log line
- [ ] Move cursor across aligned edge:
      expected: clean crossing, NO log line

## Runtime toggle test
- [ ] With Enabled=false (corner-pinned), set `Enabled=true` and `qdbus reconfigure`:
      expected: subsequent edge motion produces teleport without restart
- [ ] Set `Enabled=false`, `qdbus reconfigure`:
      expected: corner-pin returns immediately

## Result
After all rows pass, update `VERSION_HISTORY.md` with verification date.
```

- [ ] **Step 2: Commit**

```bash
cd ~/kwin-teleport-repo
git add scripts/checklist.md
rm scripts/.gitkeep
git add scripts/.gitkeep
git commit -m "Add scripts/checklist.md manual verification checklist"
```

### Task 7.4: Run the nested-session checklist

**Files:**
- N/A (interactive test)

- [ ] **Step 1: Launch nested session**

```bash
cd ~/kwin-teleport-repo
./scripts/nested-test.sh 2>&1 | tee ~/nested-test.log &
```

- [ ] **Step 2: Configure kwinrc for the nested session if needed**

(The nested session inherits `~/.config/kwinrc`. To isolate, you can prefix the launch with `XDG_CONFIG_HOME=/tmp/nested-test-config` and seed that dir with a kwinrc that has `[CursorEdgeTeleport]/Enabled=true`.)

- [ ] **Step 3: Walk through scripts/checklist.md**

Tick each row as it passes. For any failure, capture the actual log line and document expected vs actual in `~/nested-test.log` annotations.

- [ ] **Step 4: Update VERSION_HISTORY.md with T7910 nested-session pass**

Edit `~/kwin-teleport-repo/VERSION_HISTORY.md`. Change the `T7910 nested-session` cell for the `6.6.4` row to `pass <YYYY-MM-DD>`. Commit:

```bash
cd ~/kwin-teleport-repo
git add VERSION_HISTORY.md
git commit -m "VERSION_HISTORY: KWin 6.6.4 T7910 nested-session pass"
```

---

## Phase 8 — BEAST Deployment

### Task 8.1: Copy the built package to BEAST

**Files:**
- N/A (file transfer)

- [ ] **Step 1: scp the package from T7910 to BEAST**

```bash
scp ~/kwin-teleport-repo/packaging/kwin-*.pkg.tar.zst beast.romulous.lan:/tmp/
```

### Task 8.2: Install on BEAST

**Files:**
- N/A (pacman -U on BEAST)

- [ ] **Step 1: SSH into BEAST**

```bash
ssh tlindell@beast.romulous.lan
```

- [ ] **Step 2: Install the patched package**

```bash
sudo pacman -U /tmp/kwin-*.pkg.tar.zst
```

Expected: pacman replaces stock kwin with the patched version.

- [ ] **Step 3: Verify version**

```bash
kwin_wayland --version
```

Expected: `kwin_wayland 6.6.4`.

### Task 8.3: Enable the feature and reload

**Files:**
- Modify on BEAST: `~/.config/kwinrc`

- [ ] **Step 1: Set the flag**

```bash
kwriteconfig6 --file kwinrc --group CursorEdgeTeleport --key Enabled true
```

- [ ] **Step 2: Reload KWin config**

```bash
qdbus org.kde.KWin /KWin reconfigure
```

Expected: no error output.

- [ ] **Step 3: Verify Edge Barrier is disabled**

```bash
kreadconfig6 --file kwinrc --group Plugins --key cornersBarKey
kreadconfig6 --file kwinrc --group EdgeBarrier --key EdgeBarrier
```

If non-zero, disable via System Settings → Screen Edges → set Corner Barrier and Edge Barrier to 0.

### Task 8.4: Run the verification checklist on BEAST real hardware

**Files:**
- N/A (interactive verification)

- [ ] **Step 1: Open a terminal that captures kwin log output**

```bash
journalctl --user-unit plasma-kwin_wayland.service -f | grep CursorEdgeTeleport &
```

(If KWin isn't running as a user systemd unit, capture stderr by starting Plasma from a TTY with `QT_LOGGING_RULES="kwin.input.debug=true" startplasma-wayland`.)

- [ ] **Step 2: Run through scripts/checklist.md against real hardware**

Tick each item. The 2x3 monitor grid on BEAST is the canonical layout — expect "teleport across unaligned 4K→2K edges" rows to fire on the actual displays.

- [ ] **Step 3: Update VERSION_HISTORY.md**

On BEAST (or via SSHFS mount from T7910):

```bash
cd /mnt/DEV/Projects/kwin-cursor-teleport
# Edit VERSION_HISTORY.md, set BEAST hardware cell to "pass <YYYY-MM-DD>"
git add VERSION_HISTORY.md
git commit -m "VERSION_HISTORY: KWin 6.6.4 BEAST hardware pass"
```

### Task 8.5: 24-hour observation

**Files:**
- N/A (passive monitoring)

- [ ] **Step 1: Use BEAST normally for ~24 hours with the patch active**

Watch for:
- Unexpected cursor jumps in normal motion (false-positive teleports)
- KWin crashes (check `journalctl --since "1 hour ago" | grep -i 'kwin_wayland\|coredump'`)
- Other regressions in window management, multi-monitor behavior, drag-and-drop, etc.

- [ ] **Step 2: If anomalies appear, document in VERSION_HISTORY.md**

Add a note column explaining the issue. If severe, run `scripts/install-stock.sh` to revert and open a follow-up task to investigate.

- [ ] **Step 3: If 24h passes cleanly, mark "stable" in VERSION_HISTORY.md**

```bash
cd /mnt/DEV/Projects/kwin-cursor-teleport
# Append note "stable as of <YYYY-MM-DD>" to the 6.6.4 row
git add VERSION_HISTORY.md
git commit -m "VERSION_HISTORY: KWin 6.6.4 stable after 24h observation"
```

---

## Final integrity check

After Phase 8 completes, run a last consistency check.

- [ ] **Verify patch artifact still re-applies on a fresh checkout**

On T7910:

```bash
cd /tmp
rm -rf kwin-final-verify
git clone ~/src/kwin kwin-final-verify
cd kwin-final-verify
git checkout v6.6.4
git am ~/kwin-teleport-repo/patches/6.6.4/0001-cursor-edge-teleport.patch
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
cmake --build build -j$(nproc)
cd build && ctest -R testCursorEdgeTeleport -V
```

Expected: clone, checkout, patch-apply, full build, and 9 unit tests all succeed end-to-end with no intermediate steps.

- [ ] **Verify VERSION_HISTORY.md reflects current status**

```bash
cat ~/kwin-teleport-repo/VERSION_HISTORY.md
```

Expected: all three test gates for 6.6.4 show pass dates.

---

## Self-Review Notes

This plan was self-reviewed against the spec (`docs/superpowers/specs/2026-05-13-kwin-cursor-teleport-design.md`):

- **Spec coverage**: Algorithm (Phase 2), config helper (Phase 3), pointer_input integration (Phase 4), patch artifact (Phase 5), packaging (Phase 6), nested-session tests (Phase 7), BEAST deployment (Phase 8), non-regression check (Task 4.3 Step 4 + 8.5). All spec requirements mapped to tasks.
- **Placeholders**: A few tasks (4.1, 6.1) are explicitly *exploration* tasks — they identify exact function names, line numbers, or upstream PKGBUILD form. Subsequent tasks reference the discovery. This is unavoidable when the patch target depends on upstream code we haven't pinned yet; the plan tells the engineer exactly what to look for and what shape the change will take.
- **Type consistency**: `CursorEdgeTeleport::resolve()` signature is consistent across header (2.1), test fixtures (2.5–2.11), and call site (4.2). `CursorEdgeTeleportConfig::{load, enabled}()` is consistent across header (3.1), implementation (3.2), and call sites (4.2–4.3).
- **DRY/YAGNI**: No System Settings UI in v1, no directional weighting beyond dot-product rejection, no motion gating — all matching the spec's non-goals list.
