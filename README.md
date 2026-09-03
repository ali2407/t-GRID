# t-GRID

**Three ways to arrange your native macOS terminals. No multiplexer.**

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
tgrid --reflow --theme   # ...and give every cell its own colour and a clean title
tgrid --deck             # one window centred, the rest peeking in at the edges
tgrid --next             # swipe the deck along
tgrid --queue            # the sessions waiting for an answer, in line
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
| `-t, --theme` | colour each cell, strip the title bar, fit the font to the cell |
| `--plain` | undo that — put the windows back on your default profile |
| `--font PT` | font size for `--theme` (default: fitted to the cell) |
| `--deck` | one window centred, the others peeking in from the edges |
| `--next` / `--prev` | move the deck one window along |
| `--main PCT` | width of the centred window, % of the screen (default 58) |
| `--peek PX` | how much of the nearest side window stays visible (default 150) |
| `--glass` | translucent windows with a blurred backdrop (softens the text) |
| `--reprofile` | rebuild t-GRID's profiles after changing the look |
| `--queue` | line the waiting sessions up, oldest wait in front of you |
| `--queue-list` | print that line-up without moving anything |
| `--queue-next` / `--queue-prev` | walk the line |
| `--queue-watch` | background monitor: log what you answer and what you skip |
| `--queue-learn` | read that log back and suggest ranking changes |

The queue has its own tool, `tgrid-queue`, installed next to `tgrid`. The flags
above are a front door to it; run it directly for `pin`, `json` and `md`.

A few combinations worth knowing:

```sh
tgrid --reflow -D next            # throw the whole grid onto the other monitor
tgrid --reflow --here -D 1        # tidy monitor 2 without disturbing monitor 1
tgrid --dirs ~/api,~/web,~/infra  # three projects, three windows, one command
tgrid 8 -r 2 -k 4 -g 0            # dense 2×4, no gaps
tgrid --reflow --theme            # tidy up and style what's already open
```

Set `TGRID_THEME=1` in your shell profile if you want `--theme` to be the default.

---

## Three views

**The grid** shows you everything at once. Good when you're supervising — six
agents running, and you want to catch the one that stopped.

**The deck** is the other half of the day: one session has your attention, the
rest should be one keystroke away and otherwise out of the way. The focused
window sits centred and large; the others wait at the edges with a strip
showing, stacked so the one behind peeks out a little less than the one in
front.

```sh
tgrid --deck            # centre whatever is frontmost, park the rest
tgrid --next            # bring the next window to the middle
tgrid --prev            # and back
tgrid --deck --main 70  # give the centred window more of the screen
tgrid --deck --peek 220 # let more of the side windows show
```

The order is a **ring** kept between runs, so `--next` walks the same sequence
every time instead of jumping to whatever happens to be frontmost. Windows that
you close drop out of it; new ones join the end. `--undo` still puts everything
back.

**The queue** answers the question the other two don't. You come back to six
terminals and one of them finished twenty minutes ago — but which, and what was
it asking? Before you can type a word you re-read scrollback to remember what
that session was even about. The queue is the list of sessions that are waiting
for an answer, oldest wait first, each with one sentence saying what it wants.

```sh
tgrid --queue-list      # print the line-up, move nothing
tgrid --queue           # ...and put the front one in front of you
tgrid --queue-next      # send it to the back, raise the next
tgrid --queue-learn     # what the log says about your own ordering
```

```
5 waiting for you
1. scalplab                    4h41m  albertos-brain
   Logg dich im offenen Chrome-Tab bei claude.ai ein, dann mache ich den Rest.
2. CraderMind media coverage   3h25m  cradermind-brain
   Next: say go and I'll draft the press kit into cradermind-brain/plan/pr.md.
3. LANDING                        2m  CraderMind@neue-landingpage
   Sag Bescheid, dann setze ich das als Nummer 21 rein, bevor es fest wird.
4. 100k integration plan file  5h15m  ~
   interrupted 292 min ago — the prompt is open, nothing is running
   thinking: t-GRID
```

All three views are the same windows and the same sessions. Only the arithmetic
changes — switch between them as often as you like.

---

## The queue, in detail

### Which sessions are waiting

Claude Code writes a glyph into the window title, and **the glyph is the state**:
`✳` while it sits at the prompt, `◐ ◑ ◒ ◓` while a turn is running. Driving a
throwaway session through one turn and sampling the title twice a second shows
the transition both ways, immediately. One AppleScript call reads it for every
window at once and no file has to be parsed.

**`tab.busy()` is not that signal**, and it is the obvious trap. It reports
whether anything other than the shell is in the foreground, so it is `true` for
every window running `claude` — thinking or not. Six sessions all sitting there
waiting for an answer reported `busy=true`; it went false only when claude
exited. It answers "is a program running", which is not the question.

The transcript at `~/.claude/projects/<encoded-cwd>/<session>.jsonl` supplies the
rest: **when** the turn ended, and **what** was asked. The end of a turn is
marked explicitly, by a `{"type":"system","subtype":"turn_duration"}` record — do
not try to infer it from "the last message is from the assistant", because
assistant text blocks land mid-turn, before tool calls, all the time.

That gives four states, not two:

| state | what it means |
|---|---|
| `waiting` | the turn ended and nobody has answered — in the queue |
| `thinking` | a turn is running — not your problem yet |
| `stalled` | a turn was started and produced nothing: interrupted, crashed, or an API error. In the queue, at the back, saying so |
| `idle` | a Terminal window with no session we can name |

### Which window is which session

Not by working directory. Nearly everything here is launched from `$HOME`, so
cwd puts five unrelated sessions in one bucket. Neither the `claude` process nor
its environment carries the session id either — it keeps no open handle on its
own `.jsonl`, and `ps -E` has nothing in it.

What lines up exactly is the **title**. A transcript carries a `custom-title`
(what `/title` or an agent name set) falling back to an `ai-title` (the summary
Claude Code writes after the first turn), and that string is character-for-
character what appears in the window title after the glyph. Checked against six
live sessions: six matches, no misses. A transcript is claimed by at most one
window, and ties go to whichever file was written to last.

### The one sentence

No model call — the sentence Claude Code already wrote is better than one you
would pay for, and it is already on disk. In order:

1. **The recap.** When you have been away a while, Claude Code writes a
   `system/away_summary` record: *"Goal: … Next: say go and I'll draft the press
   kit into `cradermind-brain/plan/pr.md`."* Written for exactly this moment.
2. **The last question** in the final assistant message — a turn that ends
   *"Soll ich mit der Willkommensstrecke anfangen?"* has told you the whole thing
   you need to decide.
3. **The last hand-back sentence** — *"Sag mir die Nummer"*, *"Say the word and
   I'll …"*. Failing all of that, the last sentence, which is the closing line
   and still specific.

Prefixed with where you are, the whole line reads:

> `LANDING (CraderMind@neue-landingpage): Sag Bescheid, dann setze ich das als
> Nummer 21 rein.`

### The order

One pure function over one struct of features and one dict of weights, in
`bin/tgrid-queue`:

```python
score = w_pin         * pin          # an explicit pin beats everything
      + w_wait_min    * waited_min   # v1: oldest wait first
      + w_question    * is_question  # off in v1
      + w_stalled     * is_stalled   # interrupted goes to the back
      + w_answer_rate * answer_rate  # from the behaviour log, reserved
      + w_skip_rate   * skip_rate
```

v1 is exactly what it says: time of finishing, plus a priority you pin yourself
(`tgrid-queue pin LANDING +1`). Everything a learned ranking would want is
already computed and passed in; replacing `score()` touches nothing else.
Weights live in `~/.cache/tgrid/ranking.json` and override the defaults.

### The staging

**Nothing is ever resized.** Resizing a Terminal window running a TUI makes
Claude Code reflow its whole transcript, and these are live sessions — so the
queue only ever writes a window's `x`/`y`, re-sending the width and height the
window already reports. Position and z-order are free; size is not.

The front session goes to the stage anchor and gets focus. Everyone behind it is
shifted up and left by one title bar each, so their title bars — and the
nameplates t-GRID parks on them — stack above the front window like a row of
raised hands. When the sessions are close to full height there is nowhere for
that offset to go and it collapses to zero: the order then survives in z-order
and in the queue board, and still nothing gets resized to make it fit.

The **queue board** is the part that always works: a floating list, one row per
session — rank, name, how long it has been standing there, and the sentence.
Switch it on in the menu bar app ("Show the queue as a floating list"); clicking
a row raises that window. With nameplates on, each queued window's plate also
turns into a queue row: rank badge, wait, and the sentence along the title bar.

### The behaviour log

Every scan diffs against the last one and appends what changed to
`~/.cache/tgrid/events.jsonl`, one JSON object per line:

```json
{"ts": 1788470574.194, "event": "front", "session": "cccccccc-…", "title": "QTEST charlie",
 "rank": 1, "waited_s": 3630.8, "ask": "Soll ich die Migration jetzt schreiben?"}
{"ts": 1788470609.764, "event": "skipped", "session": "cccccccc-…", "waited_s": 3666.4}
```

`entered` · `front` · `answered` · `skipped` · `left`. Raw events with
timestamps, nothing aggregated, nothing rewritten — aggregates can always be
recomputed from a raw log, and a raw log cannot be recovered from aggregates.
That is the whole point of it: the log is what makes a learned ranking possible
later.

It fills up on its own. Every command that looks at the queue writes to it, and
the menu bar app re-scans every 20 seconds while the plates or the board are on.
`tgrid --queue-watch` is the same thing without the app — it moves no windows at
all, it only looks.

`tgrid --queue-learn` reads it back and says, in words, what the ordering is
getting wrong:

```
41 events since 03 Sep
12 brought to the front · 7 answered · 4 walked past
· You walk past "scalplab" 3 of the 4 times it reaches the front.
  Pin it down: tgrid-queue pin "scalplab" -1
· You take the session the order put first 58% of the time.
```

It suggests and never edits `ranking.json` itself. An ordering that quietly
rewrites itself is one you stop trusting the moment it surprises you.

### Wiring it into a brain

Every scan also writes two files, and both are stable paths meant to be read by
something else:

- `~/.cache/tgrid/queue.json` — the whole queue, machine-readable: window id,
  session id, title, cwd, branch, state, `waited_s`, rank, the features that
  produced the rank, and the sentence.
- `~/.cache/tgrid/queue.md` — the same thing rendered as a markdown list.

t-GRID does not write to your notes. If you keep a brain repo, the wiring is
yours to choose, and there are three obvious shapes:

1. **Point at it, don't copy it.** One line in your daily note:
   `Open agent asks: see ~/.cache/tgrid/queue.md (live).` Nothing to sync,
   nothing to go stale, and any Claude session can read the file.
2. **Snapshot it on a schedule.** `tgrid-queue md >> inbox/queue-TODAY.md` from
   cron, and let whatever curates the inbox sort it. Good if you want history.
3. **Let a session ask for it.** `tgrid-queue json` on stdout is small enough to
   paste into any prompt: "here is what is waiting for me, what first?"

The deliberate choice is that t-GRID *proposes* and never *performs*. It writes
its own two files under `~/.cache` and stops there. Which of your notes this
belongs in is a decision about your notes, not about window management.

---

## The terminal design

Six tiled terminals have a problem tiling alone doesn't fix: they are six
identical dark rectangles, and the only glanceable text on them is a title bar
that reads

```
albert — ◑ 100k integration plan files — caffeinate ◂ claude — 116×43
```

The part you actually want is in the middle. `--theme` deals with both.

**Solid, and deliberately so.** t-GRID can make the windows translucent with a
blurred backdrop — `--glass` — and it looks good in a screenshot. It is off by
default because macOS switches off subpixel antialiasing for any window that is
not opaque: it cannot blend subpixels against a backdrop it cannot see. Terminal
text goes visibly soft, and it is all-or-nothing — 99% opacity looks exactly as
soft as 70%. Glass is lovely on a card you glance at. This is a wall of text you
read all day.

**Every cell gets its own ground.** A near-black tinted with one of eight
accents, and a cursor in that accent. Text stays the same neutral grey in every
window, so reading never changes; the colour is spent on the background — which
you only notice when a neighbour is beside it — and on the cursor, which is the
thing you hunt for. Bold stays neutral on purpose: tinting it would make a red
cell's headings look like errors. The palette alternates warm and cool rather
than running round the colour wheel, so no two neighbouring cells look alike.

**The title bar loses everything but the title.** `albert —` is the folder
proxy, `— -zsh` the running process, `— 116×43` the window size. What's left is
whatever the session put there — which for an agent is the task it's working on.
New windows are named `3 · myproject` on the way in, so a plain shell has
something to say too; anything that runs afterwards is free to overwrite it.

**The font fits the cell.** A 2×2 gets 16pt, a 3×2 gets 12, a 4×2 gets 9 — each
picked so the cell still holds about 100 columns. A dense grid gives you smaller
type instead of an agent UI clipped down the right-hand side. `--font 11` if you
disagree.

In the deck the accent follows the window's place in the **ring**, not where it
is standing right now — otherwise every swipe would repaint everything, which
destroys the one thing a colour is for.

t-GRID does this with Terminal profiles of its own, named `t-GRID 1` … `t-GRID
8`. Your own profiles are never touched, and `--plain` puts every window back on
your default. The look is baked into the profile when it is built, so after
changing `--glass` you need `--reprofile` to rebuild them.

---

## Nameplates

Terminal.app has no API for custom chrome, so nothing can draw a header *inside*
its window. What nothing stops you doing is putting a panel of your own *on top*
of one.

Turn on **Nameplates** in the menu bar app and every Terminal window gets a
small bar parked exactly over its title bar, between the traffic lights and
Terminal's own split button: an icon in the window's accent, the session name,
what's running in it, and a green dot while it's busy.

```
 ● ● ●   [✦] LANDING · claude                                          ●
```

The plate is **click-through**. That matters more than it sounds: the title bar
underneath keeps working, so the window still drags, double-click still zooms,
and nothing about Terminal behaves differently because there is a picture
floating over it.

It needs no extra permission. Window rectangles come from the public window list
— no screen recording, no accessibility — and the names come over the same
Apple Events the panel already uses. Geometry is followed 5×/second so a dragged
window doesn't leave its plate behind; names refresh once a second and a half,
because those cost an Apple Event and the name rarely changes.

Agents write a spinner glyph into their title (`✳ LANDING`). That glyph becomes
the plate's icon rather than being printed twice.

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
- **Colour each cell, strip the title bar** — the checkbox next to the monitor.
  The same thing `--theme` does on the CLI.
- **Nameplates over the title bars** — the overlay described above.
- **Deck** with `‹ ›` — the deck view, and swiping it along.
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
- **Half of the title bar has no AppleScript switch.** Colours, font and four
  title flags are settable on a Terminal profile. The folder proxy and the
  process name are not — they exist only in the profile's plist, so setting
  every switch AppleScript exposes changes nothing you can see. A profile that
  hides them has to be *born* from a `.terminal` file. The useful part is that
  importing one registers a real profile, which can then be handed to windows
  that are already open.
- **`close()` on a window whose shell is still running does nothing.** Terminal
  puts up a confirmation sheet instead of failing, so the call reports success
  and the window stays. Exit the shell first, then close.

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
- **Nameplates and the queue board need the app running.** They are drawn by
  TGrid.app, so they live and die with it. The CLI alone cannot draw anything on
  screen — `tgrid --queue-list` prints the same line-up into your terminal.
- **The queue only understands Claude Code.** The state glyph and the transcript
  format are Claude Code's; a plain shell, vim or another agent is a window with
  nothing to say. Nothing breaks, they just never join the line.
- **A session that has never finished a turn has no title yet**, so there is
  nothing to match it to its transcript, and it reads as idle until its first
  answer lands. One turn of blindness, once per session.
- **The queue needs `python3`** — the Xcode Command Line Tools install it, and so
  does anything else that gives you `swiftc`.
- **"Interrupted" is a guess.** It means a turn was started and the transcript
  then went quiet; an agent that genuinely spent twenty minutes inside one tool
  call looks the same from outside. The window title is checked first for exactly
  this reason, and it is right whenever the window is there.
- No global hotkey yet, so `--next` needs the menu bar app or a shell alias.
- `--theme` styles the window, not the session. Colours follow the cell, so a
  window that moves cells changes colour — they name a position in the grid,
  not a project.
- The first themed run builds one Terminal profile per accent, and importing a
  profile costs a window that opens and closes again. It takes a few seconds,
  once.

---

## License

MIT. Do what you like with it.
