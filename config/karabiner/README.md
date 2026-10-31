# Karabiner-Elements

Four complex-modification rules for a PC keyboard:

- `assets/complex_modifications/pc-alt-tab.json` puts the next tab back on
  physical Ctrl+Tab; physical Alt+Tab is tilemo's.
- `assets/complex_modifications/pc-arrows.json` makes physical Ctrl+Left/Right
  move by word, Win+Left/Right switch Spaces and Win+Shift+Left/Right move the
  window a Space; see
  [Arrow keys](#arrow-keys).
- `assets/complex_modifications/pc-terminal.json` gives kitty its Ctrl and
  Alt back, as Control and Meta; see [Terminals](#terminals).
- `assets/complex_modifications/tilemo.json` gives
  [tilemo](https://github.com/mikelward/tilemo) its Super key; see
  [tilemo](#tilemo).

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

**Physical Alt+Tab is tilemo's**, swap with the master, in tilemo's rule
below (tilemo SPEC.md §7.2). This rule used to swap the two both ways, making
Alt+Tab switch applications; it gave that up when tilemo took the key. The
switcher's Windows tab stands in for the application switcher, and a Mac
keyboard's own Cmd+Tab still works. **Without tilemo's rule**, physical
Alt+Tab is left to the rotation, as Ctrl+Tab, the next tab too, so a PC
keyboard has no application switcher key.

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

Only left Ctrl and left Win are mapped, matching the Ctrl+Tab rule. Home and End
still reach the line ends.

## Terminals

The rotation's trade, Ctrl for Command, is wrong in a terminal: Ctrl+U,
Ctrl+K, Ctrl+R and the rest arrive as Cmd+U and so on, which the terminal
takes as its own shortcuts, and never reach the shell. Alt arrives as
Control, so Alt+B and Alt+F don't move by word either. In kitty, this rule
gives both keys back, as on Linux:

| Physical keys | Emits | kitty sees | Does |
| --- | --- | --- | --- |
| Ctrl+key, Ctrl+Shift+key | `left_option`+key | Control+key | the shell's Ctrl+U, Ctrl+K, …; kitty's Ctrl+Shift shortcuts |
| Ctrl+C, Ctrl+V | `left_option`+C, V | Control+C, V | kitty's `kitty.conf` maps: copy (or interrupt, with nothing selected) and paste |
| Alt+key, Alt+Shift+key | `left_command`+key | Option+key | Meta, through kitty's `macos_option_as_alt left` |

The outputs name the keys the rotation turns into Control and Option, by the
same layering as above. Copy and paste are kitty's, from conf's `kitty.conf`,
the same file Linux uses, so Ctrl+C there copies a selection and otherwise
sends the interrupt.

- **Left to the rotation:** Tab, which the Ctrl+Tab rule and tilemo's take; Space, since
  Control+Space is macOS's input source switch; and Ctrl+Up and Down, which
  are Mission Control. Right Ctrl and right Alt are left alone, so right Ctrl
  still reaches kitty's Command shortcuts (Cmd+Q, Cmd+,).
- **Enable it after the arrow rule,** so it sits above it: both match
  Ctrl+Left/Right, and in kitty this one should win, as Control+arrow, which
  the shell takes as a word move and Ctrl+Shift+Left/Right as kitty's previous
  and next tab. Otherwise Ctrl+Left/Right still moves by word, as Option+arrow,
  but Ctrl+Shift+Left/Right reaches the shell as Alt+Shift+arrow instead of
  switching tabs.
- **kitty only, for now.** Each manipulator names kitty's bundle ID, and
  another terminal needs its own copy and paste on Ctrl+C and Ctrl+V before
  it can join; Ghostty is the next (`TODO.md`).

## tilemo

tilemo, the macOS tiling desktop, puts tide's keys on Super, the physical Win
key. The rotation makes Win into Option, and Option already means things on
a Mac: Option+Backspace deletes a word, the arrow rule above makes
Option+arrow from Ctrl+arrow, and Option+E and friends are accent dead keys.
So this rule turns physical Win+key into a combination nothing else uses,
Ctrl+Option+Command+key, and tilemo binds that (tilemo SPEC.md §7.1).

| Physical keys | Emits | macOS sees |
| --- | --- | --- |
| Win+key, for each key tilemo binds | `left_option`+`left_command`+`left_control`+key | Ctrl+Option+Command+key |
| Win+Shift+key | the same, plus `shift` | Ctrl+Option+Command+Shift+key |
| Win+click, Win+right-click, Win+middle-click | the same modifiers, on the button | Super+drag and Super+middle-click in tilemo |
| Win, tapped alone | `f20` with the same modifiers | tilemo's switcher, on its workspace list |
| Alt+Tab | `left_option`+`left_command`+`shift`+`tab` | Ctrl+Option+Shift+Tab: tilemo's swap with the master |

The outputs name the keys the rotation turns into Control, Option and
Command, by the same layering as the rules above. A key tilemo doesn't bind,
such as Win+Q, is left alone and stays Option.

- **The lone tap is Super+F20,** a key no PC keyboard here has, so tilemo
  tells it from Super+Space: the tap opens its workspace list, Super+Space
  its launcher (tilemo SPEC.md §7.2, §9).
- **Alt+Tab is Ctrl+Option+Shift+Tab,** without Command, so no Win
  combination makes it. Physical Alt+Shift+Tab is left to the rotation, as
  Shift+Ctrl+Tab, the previous tab.

- **Enable it above the arrow rule.** Both match Win+Left/Right, and
  Karabiner uses the first rule that matches, with newly added rules at the
  top. tilemo's workspace keys take Win+arrow over the Spaces shortcut.
- **tilemo finds it by its description,** which starts `tilemo:`. Without it,
  tilemo puts its keys on plain Option and says so once.
- **A rule enabled before the rename still works.** tilemo was called timo,
  and its rule's description started `timo:`; tilemo accepts both prefixes
  while the rename settles. Removing the rule and adding it again, as in
  [Enabling it](#enabling-it), gives it the new `tilemo:` name. `confinst`
  doesn't prune, so the old
  `~/.config/karabiner/assets/complex_modifications/timo.json` link is left
  dangling; delete it.
- **The mouse needs enabling too.** Karabiner leaves mouse devices alone by
  default, so Win+click, Win+drag and Win+middle-click only carry Super once
  the mouse or trackpad is turned on under Settings > Devices
  ([Karabiner's mouse button docs](https://karabiner-elements.pqrs.org/docs/help/how-to/mouse-button/)).
  Until then, tilemo's mouse gestures see plain Option.
- Whether a click while Win is held cancels the lone tap, as a key does, is
  *(unverified)*.

## Enabling it

Karabiner does not enable assets automatically. In Karabiner-Elements
Settings > Complex Modifications > Add rule, enable "Ctrl+Tab goes to the
next tab", "Ctrl+Left/Right moves by word, Win+Left/Right switches
Spaces, Win+Shift+Left/Right moves the window a Space" and then "Ctrl is
Control and Alt is Meta in kitty", so it sits above the arrow rule, and, with
tilemo, the "tilemo:" rule last, so it sits above them all. `setup-macos` installs
Karabiner and says this, but the enabling step is a GUI action that can't be
scripted.

Enabling a rule copies it into `karabiner.json`, and Karabiner runs that copy,
so a change to an asset doesn't reach a rule that's already enabled. After
pulling one, remove the rule under Complex Modifications and add it again.

Karabiner also needs its driver extension approved and Input Monitoring
permission granted, both prompted for on first launch.

## Scope

Only left Ctrl, and in tilemo's rule left Alt, are mapped. Right Alt is left
alone so it stays available as a plain modifier, and the rotation still sends
it to right Control.

## Modifier names

Karabiner's canonical name for the Alt modifier is `left_option`, not
`left_alt`, and that is what the rule uses throughout — `left_alt` is at best
an alias, and an unrecognized modifier name in a `mandatory` block is not an
error Karabiner reports. It simply never matches, which looks identical to the
rule not being enabled. The test asserts `left_option` in both the trigger
(tilemo's Alt+Tab) and output positions for that reason.
