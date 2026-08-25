# t-GRID

**A grid for your native macOS terminals. No multiplexer.**

You open four Terminal windows, each running its own thing — an agent here, a
build there, a server, a shell. Then you spend a minute dragging them into
place. Every time.

t-GRID does the dragging. One command, or one click from the menu bar, and every
open Terminal window snaps into a clean grid on the monitor you choose.

![six native Terminal windows tiled 3x2 by t-GRID](docs/grid.png)

*Six real Terminal.app windows, six separate shells, one command: `tgrid 6`.*

That's the whole idea. No tmux, no screen, no Ghostty, no session server, no
config language, no daemon. Your terminals stay exactly what they were: real,
separate, native macOS windows.

---

## Why this exists

Terminal.app has a **Split Pane** feature (⌘D). It does not do what almost
everyone assumes it does.

Splitting a Terminal pane gives you *a second view of the same session*. Type in
the bottom half and the top half types too — because it is the same shell. It's
a split of the scrollback, not a split of the process. Terminal.app has no real
split sessions and never has.

So on macOS, **one session means one window**. Which is fine — until you have six
of them scattered across two monitors like playing cards.

The usual answers are to give up the native terminal (tmux, a different terminal
emulator) or to install a system-wide tiling window manager that rearranges
*every* app you own. Both are large moves for a small problem.

t-GRID is the small move.

---

## Install

Requires macOS 13+ and the Xcode Command Line Tools (for the optional menu bar
app only — the CLI needs nothing but bash).

```sh
git clone https://github.com/ali2407/t-GRID.git
cd t-GRID
./install.sh
```

`install.sh` puts `tgrid` on your `PATH` and offers to build the menu bar app.
Nothing else is touched — no login items, no launch agents, no `sudo`.

To remove it: delete the symlink it made, delete `~/Applications/TGrid.app`, and
delete the folder. There is no uninstaller because there is nothing to uninstall.

---

## The CLI

```sh
tgrid --reflow           # tile the Terminal windows that are already open
tgrid                    # open 4 new windows in a 2×2, each running `claude`
tgrid 6                  # 6 windows, 3×2
tgrid 2 -c zsh           # 2 plain shells instead
tgrid --undo             # put everything back where it was
```

Everything else:

| Flag | Meaning |
|---|---|
| `-c, --cmd CMD` | command to run in each new window (default `claude`; `""` = plain shell) |
| `-d, --dir DIR` | working directory for every new window |
| `--dirs a,b,c` | one directory per window — a window per project |
| `-r, --rows N` | force the row count |
| `-k, --cols N` | force the column count |
| `-g, --gap PX` | gap between windows (default 6) |
| `-p, --pad PX` | outer margin around the whole grid |
| `-D, --display N` | which monitor — `0` is main, `next` is the other one |
| `--reflow` | tile what's already open instead of opening anything |
| `--here` | with `--reflow`: only windows already on the target monitor |
| `--undo` | restore the positions from before the last tile |

A few combinations worth knowing:

```sh
tgrid --reflow -D next            # throw the whole grid onto the other monitor
tgrid --reflow --here -D 1        # tidy monitor 2 without disturbing monitor 1
tgrid --dirs ~/api,~/web,~/infra  # three projects, three windows, one command
tgrid 8 -r 2 -k 4 -g 0            # dense 2×4, no gaps
```

---

## The menu bar app

Optional, and the same thing with a face on it. `install.sh` builds it, or:

```sh
./app/build.sh          # → ~/Applications/TGrid.app
```

It lives in the menu bar and nowhere else — no Dock icon, no app switcher entry.
Click the grid symbol and you get:

- **Monitor** — your displays drawn to their real shape. Click one.
- **Layout** — hover a cell to sweep out a `3 × 2`, click to lock it, click the
  same cell again to go back to *Auto*.
- **Sort open terminals** — the button. Everything open, snapped into place.
- **New grid of N** — spawns that many fresh sessions, already tiled, in a
  folder you pick.
- **Sessions** — what's running, which monitor it's on, a green dot when it's
  busy. Click a row to bring that window to the front.
- **Undo** — for when you sort something you didn't mean to.

Your monitor, gap, layout and folder are remembered between launches.

On first use macOS will ask whether TGrid may control Terminal. It has to —
moving another app's windows *is* automation. Say yes, or the panel will show
you a link straight to the right settings pane.

---

## How it actually works

There is no magic here, and that's deliberate.

Terminal.app is scriptable. Every window has an `id` and a `bounds` rectangle
that can be **written**, not just read. t-GRID asks macOS for the usable area of
a display, divides it into cells, and tells Terminal:

> window `3440`, your rectangle is now `x=0 y=30 957×522`.

That is the entire mechanism. It's the same thing as dragging the window corner,
done by arithmetic instead of by hand. Nothing runs afterwards — no daemon
watching your windows, no compositor, no state. The windows are simply somewhere
else now, and they are still ordinary Terminal windows that know nothing about
t-GRID.

Which means: if t-GRID vanished from your disk right now, nothing about your
setup would break.

Two details that took real debugging, in case you're reading the source:

- **Windows are addressed by `id`, never by index.** AppleScript window
  references resolve lazily by position in the window list, and that list
  reshuffles as you move things — so index-based code cheerfully puts two
  windows in the same cell.
- **Every display reserves menu bar height**, not just the primary one. With
  "Displays have separate Spaces" enabled each screen has its own menu bar, but
  only the primary reports that inset in `visibleFrame`. Miss it and the bottom
  row of your grid hangs off the bottom of the second monitor.

Picking a layout in the menu bar app is a request for that many slots: **Sort
opens the windows the grid is short of** and then tiles the full set. Four
windows and a 2x3 gives you six, not four spread across six cells with the last
row stretched. On Auto the grid follows the window count instead, and nothing
is opened.

Windows are tiled in **reading order of where they already are** — top-left to
bottom-right, the way you would tidy a desk. Each window moves to the nearest
cell rather than to a slot decided somewhere else, so tiling straightens your
layout instead of reshuffling it, and sorting twice gives you the same result
twice.

Ordering by window id was tried first. It is just as stable, but ids follow
creation order, which has nothing to do with what you see — so tidying up flung
sessions across the screen and looked random.

---

## Limits, honestly

- **macOS and Terminal.app only.** iTerm2, Ghostty, WezTerm and friends are not
  supported. They mostly have their own splits that work properly.
- Terminal snaps window sizes to whole character cells, so a window can land a
  pixel or two off its computed rectangle.
- Minimized windows are skipped.
- The layout is a one-shot arrangement, not a managed tiling mode. New windows
  you open afterwards land wherever Terminal puts them until you sort again.
- No global hotkey yet.

---

## License

MIT. Do what you like with it.
