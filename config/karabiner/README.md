# Karabiner-Elements

Complex-modification rules for a PC keyboard, in five files:

- `assets/complex_modifications/pc-alt-tab.json` puts the next tab back on
  physical Ctrl+Tab; physical Alt+Tab is tide for macOS's.
- `assets/complex_modifications/pc-arrows.json` makes physical Ctrl+Left/Right,
  left or right Ctrl, move by word, Win+Left/Right switch Spaces and
  Win+Shift+Left/Right move the window a Space; see
  [Arrow keys](#arrow-keys).
- `assets/complex_modifications/pc-terminal.json` gives kitty and Ghostty
  their Ctrl and Alt back, as Control and Meta, and puts the interrupt on
  Ctrl+Shift+C in Terminal and iTerm2; see [Terminals](#terminals).
- `assets/complex_modifications/pc-lock.json` makes Ctrl+U clear the
  password at the lock screen, as on Linux; see [Lock screen](#lock-screen).
- `assets/complex_modifications/tide.json` gives
  [tide for macOS](https://github.com/mikelward/tidemo) its Super key; see
  [tide for macOS](#tide-for-macos).

Only the asset file is kept here. Karabiner rewrites
`~/.config/karabiner/karabiner.json` itself on every UI change, so that file is
deliberately left out of the repo — `confinst` creates
`~/.config/karabiner/assets/complex_modifications/` as a real directory and
symlinks only the rules into it, which Karabiner reads but never rewrites.

## Why the rule exists

`setup-macos` rotates the modifiers with `hidutil` so Linux muscle memory
survives:

| Physical key | Sends |
| --- | --- |
| Ctrl (pinky) | Command |
| Win / Super | Option |
| Alt (by space) | Control |

That works because macOS uses Command wherever Linux uses Control —
`Ctrl+C`, `Ctrl+V`, `Ctrl+T`, `Ctrl+W` all stay under the same physical key.

Tab is the one exception. macOS switches applications with `Cmd+Tab`, so the
rotation lands app switching on physical Ctrl+Tab, where Linux has the next
tab. This rule puts the next tab back there.

| Physical keys | Without this rule | With it |
| --- | --- | --- |
| Ctrl+Tab | switch applications | **next tab** |
| Shift+Ctrl+Tab | switch applications, backwards | **previous tab** |

**Physical Alt+Tab is tide for macOS's**, swap with the master, in tide for macOS's rule
below (tidemo SPEC.md §7.2). This rule used to swap the two both ways, making
Alt+Tab switch applications; it gave that up when tide for macOS took the key.
**Without tide for macOS's rule**, physical Alt+Tab is left to the rotation, as
Ctrl+Tab, the next tab too.

What still switches applications:

- **Physical right Ctrl+Tab,** on a keyboard that has a right Ctrl. The
  rotation makes it Cmd+Tab, and this rule only takes left Ctrl (see
  [Scope](#scope)).
- **tide for macOS's switcher,** with tide for macOS: its Windows tab stands in for the
  application switcher.
- **Not a Mac keyboard's Cmd+Tab.** `setup-macos` applies the rotation to
  every keyboard, the built-in one included, so its Command key sends Option.

## Why the rule outputs left_option

The rule maps `left_control`+Tab to **`left_option`**+Tab, which looks wrong
until you account for the layering: Karabiner grabs the keyboard and sees the
*physical* key, and its virtual keyboard's output then passes through the
`hidutil` rotation. So the output has to name the key that the rotation turns
into Control, and that's left Option.

Chain: physical Ctrl → Karabiner sees `left_control` → emits `left_option` →
`hidutil` maps Alt to Control → `Ctrl+Tab`.

### If the layering is the other way round

On a macOS version where Karabiner sees the *rotated* key rather than the
physical one, physical Ctrl arrives as `left_command`, matches nothing, and
keeps switching applications. **Ctrl+Tab still switching applications is the
symptom.**

To correct it, shift every modifier name one step along the rotation —
`left_option` becomes `left_control`, and `left_control` becomes `left_command`.
Do it as one substitution rather than in sequence, or the first rename feeds
the second. The two manipulators become:

| # | `from` | `to` |
| --- | --- | --- |
| 1 | `left_command` + `shift` | `left_control` + `shift` |
| 2 | `left_command` | `left_control` |

If you would rather back the whole thing out, disabling the rule in Karabiner
restores the rotation's own behavior: application switching on physical
Ctrl+Tab.

## Arrow keys

The rotation puts Command under the physical Ctrl key, and `Cmd+Left`/`Right`
jump to the start or end of the line. macOS moves by word with
`Option+Left`/`Right`, which lands on the physical Win key — where Linux
switches desktops instead. This rule puts both back where KDE has them:

| Physical keys | Emits | macOS sees | Does |
| --- | --- | --- | --- |
| Ctrl+Left/Right | `left_command`+arrow | `Option+arrow` | move by word |
| Ctrl+Shift+Left/Right | `left_command`+`shift`+arrow | `Option+Shift+arrow` | select by word |
| Alt+Left/Right | `left_command`+arrow | `Option+arrow` | move by word |
| Alt+Shift+Left/Right | `left_command`+`shift`+arrow | `Option+Shift+arrow` | select by word |
| Win+Left/Right | `left_option`+`left_command`+arrow | `Control+Option+arrow` | switch Spaces |
| Win+Shift+Left/Right | `left_option`+`left_command`+`shift`+arrow | `Control+Option+Shift+arrow` | move the window a Space |

The outputs name the keys the rotation turns into what macOS should see, by
the same layering as above: `left_command` becomes Option and `left_option`
becomes Control.

**Alt+arrow moves by word too,** where a Mac keyboard's Option sits. Left to
the rotation, Alt is Control, and Control+Left/Right jump to the line ends.

**Space switching can't live on `Option+arrow`.** Symbolic hotkeys see the
event after Karabiner and can't tell a synthesized `Option+Left` from a
physical one, so if Spaces were bound there, Ctrl+Left would switch Spaces
rather than move by word. `setup-macos` binds "Move left/right a space" to
`Control+Option+arrow` instead, and only Win+arrow produces that.

**Moving a window a Space is Amethyst's**, as `throw-space-left`/`right` on
`mod3` in `amethyst.yml` — macOS has no shortcut of its own for it. It gets its
own chord for the same reason: left to the rotation, Win+Shift+arrow would be
`Option+Shift+arrow`, which is select-by-word. Without this
rule, Win+arrow is plain `Option+arrow` again — the stock word movement — and
Ctrl+arrow jumps to the line ends.

If Karabiner sees the rotated key rather than the physical one, the fix is the
same one-step shift as above, applied as one substitution: `left_control` →
`left_command`, `left_command` → `left_option`, `left_option` →
`left_control`.

**Either Ctrl moves by word,** as on Linux: right Ctrl+arrow has its own
manipulators, the same as left Ctrl's. Left to the rotation, right Ctrl is
Command too, and Cmd+arrow jumps to the line ends. In kitty and Ghostty,
where the terminal rule below takes only left Ctrl, right Ctrl+arrow reaches
the shell as Alt+arrow, which conf's `zshrc` and `inputrc` bind to the same
word moves. Only left Win and left Alt are mapped.

### Home and End

On a Mac, Home and End scroll to the top and bottom of the document and leave
the cursor where it is. A second rule in the same file makes them go to the
line's start and end, as on a PC, everywhere but the terminals, which take
Home and End themselves (kitty, Ghostty, Terminal and iTerm2):

| Physical keys | Emits | macOS sees | Does |
| --- | --- | --- | --- |
| Home, End | `left_control`+Left, Right | Command+Left, Right | the line's start, end |
| Shift+Home, End | the same, plus `shift` | Command+Shift+Left, Right | select to there |
| Ctrl+Home, End, either Ctrl | `left_control`+Up, Down | Command+Up, Down | the document's start, end |

It's its own rule, "Home and End go to the line's start and end", enabled on
its own.

## Terminals

The rotation's trade, Ctrl for Command, is wrong in a terminal: Ctrl+U,
Ctrl+K, Ctrl+R and the rest arrive as Cmd+U and so on, which the terminal
takes as its own shortcuts, and never reach the shell. Alt arrives as
Control, so Alt+B and Alt+F don't move by word either. In kitty and Ghostty,
this rule gives both keys back, as on Linux:

| Physical keys | Emits | The terminal sees | Does |
| --- | --- | --- | --- |
| Ctrl+key, Ctrl+Shift+key | `left_option`+key | Control+key | the shell's Ctrl+U, Ctrl+K, …; kitty's Ctrl+Shift shortcuts |
| Ctrl+C, Ctrl+V | `left_option`+C, V | Control+C, V | the terminal's config: copy (or interrupt, with nothing selected) and paste |
| Alt+key, Alt+Shift+key | `left_command`+key | Option+key | Meta, through kitty's `macos_option_as_alt left` or Ghostty's `macos-option-as-alt = left` |

The outputs name the keys the rotation turns into Control and Option, by the
same layering as above. Copy and paste are the terminal's, from conf's
`config/kitty/kitty.conf` or `config/ghostty/config`, the same files Linux
uses, so Ctrl+C there copies a selection and otherwise sends the interrupt
(in Ghostty, a `performable:` binding, from Ghostty 1.1).

- **Left to the rotation:** Tab, which the Ctrl+Tab rule and tide for macOS's take; Space, since
  Control+Space is macOS's input source switch; and Ctrl+Up and Down, which
  are Mission Control. Right Ctrl and right Alt are left alone, so right Ctrl
  still reaches the terminal's Command shortcuts (Cmd+Q, Cmd+,), but for
  right Ctrl+arrow, which the arrow rule makes a word move.
- **Enable it after the arrow rule,** so it sits above it: both match
  Ctrl+Left/Right, and in kitty this one should win, as Control+arrow, which
  the shell takes as a word move and Ctrl+Shift+Left/Right as kitty's previous
  and next tab. Otherwise Ctrl+Left/Right still moves by word, as Option+arrow,
  but Ctrl+Shift+Left/Right reaches the shell as Alt+Shift+arrow instead of
  switching tabs.
- **kitty and Ghostty only.** Each manipulator names both bundle IDs
  (`net.kovidgoyal.kitty`, `com.mitchellh.ghostty`). Another terminal needs
  its own copy and paste on Ctrl+C and Ctrl+V, and Option as Alt, before it
  can join.

### Terminal and iTerm2

Terminal and iTerm2 copy on Command+C, which the rotation already puts on
physical Ctrl+C, as Linux's copy key; they're not in the rule above. What they
lack is the interrupt, Control+C, which the rotation puts on physical Alt+C.
A second rule in the same file puts it on physical Ctrl+Shift+C, where a Linux
terminal's copy and interrupt keys sit together:

| Physical keys | Emits | The terminal sees | Does |
| --- | --- | --- | --- |
| Ctrl+C | (left to the rotation) | Command+C | copy |
| Ctrl+Shift+C | `left_option`+C | Control+C | interrupt (`^C`) |

It's its own rule, "Ctrl+Shift+C interrupts in Terminal and iTerm2", enabled
on its own (`com.apple.Terminal`, `com.googlecode.iterm2`). kitty and Ghostty
keep Ctrl+Shift+C as copy, through the rule above.

## Lock screen

On Linux, Ctrl+U clears a password field, tide's lock among them. The
rotation makes physical Ctrl+U Cmd+U, which does nothing in the lock
screen's password field. This rule makes it select the password and delete
it:

| Physical keys | Emits | macOS sees | Does |
| --- | --- | --- | --- |
| Ctrl+U, either Ctrl | `left_control`+A, then Backspace | Command+A, Backspace | clears the password |
| Command+U, a Mac keyboard's | the same | the same | the same |

- **Only at the lock screen.** Each manipulator's condition is the
  frontmost application being `com.apple.loginwindow`, which draws the lock
  screen; Karabiner's own Escape-at-the-login-window workaround keys on the
  same name. Everywhere else Ctrl+U is left to the other rules.
- **A Mac keyboard's Command+U,** for the habit of a Mac's own Command key:
  to Karabiner it's `left_command`, the PC's Win key, so Win+U clears the
  password too. tide for macOS's rule takes Win+U elsewhere, as Super+U; there's
  nothing of tide for macOS's at the lock screen.
- **Not the login window after a restart.** Before you log in, Karabiner
  runs only what's copied to its system default configuration (Settings,
  Misc), and the rotation isn't set yet, so Command+A would arrive as
  Control+A. The rule is for unlocking.
- **It's a new file:** run `confinst` once after pulling conf, to link it
  into Karabiner's folder. tide for macOS then turns it on by itself, at the top;
  without tide for macOS, enable it as in [Enabling it](#enabling-it).

## tide for macOS

tide for macOS, the macOS tiling desktop, puts tide's keys on Super, the physical Win
key. The rotation makes Win into Option, and Option already means things on
a Mac: Option+Backspace deletes a word, the arrow rule above makes
Option+arrow from Ctrl+arrow, and Option+E and friends are accent dead keys.
So this rule turns physical Win+key into a combination nothing else uses,
Ctrl+Option+Command+key, and tide for macOS binds that (tidemo SPEC.md §7.1).

| Physical keys | Emits | macOS sees |
| --- | --- | --- |
| Win+key, for each key tide for macOS binds | `left_option`+`left_command`+`left_control`+key | Ctrl+Option+Command+key |
| Win+Shift+key | the same, plus `shift` | Ctrl+Option+Command+Shift+key |
| Win+click, Win+right-click, Win+middle-click | the same modifiers, on the button | Super+drag and Super+middle-click in tide for macOS |
| Win, tapped alone | `f20` with the same modifiers | tide for macOS's launcher, as Super+Space |
| Win+Backspace | `f19` with the same modifiers | tide for macOS's close, as Super+Backspace: some Macs take Ctrl+Option+Command+Backspace before tide for macOS sees it |
| Alt+Tab | `left_option`+`left_command`+`shift`+`tab` | Ctrl+Option+Shift+Tab: tide for macOS's swap with the master |

The outputs name the keys the rotation turns into Control, Option and
Command, by the same layering as the rules above.

- **Every key of the typing block is mapped, by physical position:** the
  letters, digits and all the punctuation keys, whether tide for macOS binds what's
  on them in U.S. layout or not. tide for macOS binds its keys by character in the
  current layout (`hs.hotkey`), so on Dvorak, Super+/ is the physical `[`
  key and Super+S the physical `;`; a key missing here would type its
  character instead. Keys off that block that tide for macOS doesn't bind, such as
  the function keys, are left alone and stay Option.

- **The lone tap is Super+F20,** a key no PC keyboard here has, so tide for macOS
  tells it from Super+Space. Both open its launcher now, as tide's tap and
  chromeOS's Search tap do (tidemo SPEC.md §7.2, §9). The rule's
  description still says the workspace list: Tide Settings' Keyboard page
  knows an enabled rule by its whole description, so changing it would
  show the rule as off until it's added again.
- **Alt+Tab is Ctrl+Option+Shift+Tab,** without Command, so no Win
  combination makes it. Physical Alt+Shift+Tab is left to the rotation, as
  Shift+Ctrl+Tab, the previous tab.

- **Enable it above the arrow rule.** Both match Win+Left/Right, and
  Karabiner uses the first rule that matches, with newly added rules at the
  top. tide for macOS's window keys (Win+Left/Right to select a window, Win+Shift+Left/Right
  to move it, across displays) take Win+arrow over the Spaces shortcut.
- **tide for macOS finds it by its description,** which starts `tide:`. Without it,
  tide for macOS puts its keys on plain Option and says so once.
- **A rule enabled before the rename still works.** tide for macOS was called
  tilemo, and timo before that, and its rule's description started `tilemo:`
  or `timo:`; tide for macOS accepts all three prefixes while the rename
  settles. Removing the rule and adding it again, as in
  [Enabling it](#enabling-it), gives it the new `tide:` name. `confinst`
  doesn't prune, so the old `tilemo.json` and `timo.json` links in
  `~/.config/karabiner/assets/complex_modifications/` are left dangling;
  delete them.
- **The mouse needs enabling too.** Karabiner leaves mouse devices alone by
  default, so Win+click, Win+drag and Win+middle-click only carry Super once
  Modify events is turned on beside the mouse or trackpad under Devices
  ([Karabiner's mouse button docs](https://karabiner-elements.pqrs.org/docs/help/how-to/mouse-button/)).
  Until then, tide for macOS's mouse gestures see plain Option.
- Whether a click while Win is held cancels the lone tap, as a key does, is
  *(unverified)*.

## Enabling it

Karabiner does not enable assets automatically. In Karabiner-Elements, click
Complex Modifications in the sidebar, then **Add predefined rule** (not "Add
your own rule", which opens an editor). Each file here is listed under its
`title`, with an Enable button beside each rule; the box at the top filters
the list. Enable, in this order:

1. under "PC keyboard Ctrl+Tab", "Ctrl+Tab goes to the next tab";
2. under "PC keyboard arrows", "Ctrl+Left/Right moves by word, …";
3. under "PC keyboard terminals", "Ctrl is Control and Alt is Meta in kitty
   and Ghostty", so it sits above the arrow rule;
4. with tide for macOS, under "tide", the "tide:" rule, so it sits above them;
5. under "PC keyboard lock screen", "Ctrl+U clears the password at the lock
   screen", last, above tide for macOS's, which would otherwise take a Mac
   keyboard's Command+U there as Super+U.

Karabiner puts each rule you enable at the top of the Complex Modifications
list, and uses the first that matches a key. `setup-macos` installs Karabiner
and lists these steps at the end of its run, but enabling is a GUI action that
can't be scripted.

Enabling a rule copies it into `karabiner.json`, and Karabiner runs that copy,
so a change to an asset doesn't reach a rule that's already enabled. After
pulling one, click the trash icon beside the rule under Complex Modifications,
then enable it again as above.

Karabiner also needs its driver extension, background services and input
capture allowed: its Setup page, in the sidebar, lists each with a button to
the System Settings page for it.

## Scope

Only left Ctrl, and in tide for macOS's rule left Alt, are mapped, but for the
arrow rule's Ctrl+arrow and Ctrl+Home/End and the lock screen's Ctrl+U,
which take right Ctrl too. Right Alt is left alone so it stays available as
a plain modifier, and the rotation still sends it to right Control.

## Modifier names

Karabiner's canonical name for the Alt modifier is `left_option`, not
`left_alt`, and that is what the rule uses throughout — `left_alt` is at best
an alias, and an unrecognized modifier name in a `mandatory` block is not an
error Karabiner reports. It simply never matches, which looks identical to the
rule not being enabled. The test asserts `left_option` in both the trigger
(tide for macOS's Alt+Tab) and output positions for that reason.
