# Karabiner-Elements

One complex-modification rule, `assets/complex_modifications/pc-alt-tab.json`,
which puts application switching back under the physical Alt key on a PC
keyboard.

Only the asset file is kept here. Karabiner rewrites
`~/.config/karabiner/karabiner.json` itself on every UI change, so that file is
deliberately left out of the repo — `confinst` creates
`~/.config/karabiner/assets/complex_modifications/` as a real directory and
symlinks only the rule into it, which Karabiner reads but never rewrites.

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

Tab is the one exception. macOS switches applications with `Cmd+Tab`, which
Linux does with `Alt+Tab`, so the rotation lands app switching on the physical
Ctrl key and leaves `Ctrl+Tab` (next tab) on the physical Alt key — the two
swap round. This rule swaps them back.

Both directions are mapped, which matters: remapping only Alt+Tab would move
app switching onto the physical Alt key while leaving it on the physical Ctrl
key too, and next-tab would then have no physical keys at all. So the rule is
a genuine swap.

| Physical keys | Without this rule | With it |
| --- | --- | --- |
| Alt+Tab | next tab | **switch applications** |
| Ctrl+Tab | switch applications | **next tab** |

Shift variants are mapped alongside each, so `Shift+Alt+Tab` cycles the
switcher backwards and `Shift+Ctrl+Tab` goes to the previous tab.

## Why the rule outputs left_control

The rule maps `left_option`+Tab to **`left_control`**+Tab, which looks wrong
until you account for the layering: Karabiner grabs the keyboard and sees the
*physical* key, and its virtual keyboard's output then passes through the
`hidutil` rotation. So the output has to name the key that the rotation turns
into Command, and that's left Control.

Chain: physical Alt → Karabiner sees `left_option` → emits `left_control` →
`hidutil` maps Control to Command → `Cmd+Tab`.

The reciprocal runs the same way: physical Ctrl → Karabiner sees
`left_control` → emits `left_option` → `hidutil` maps Alt to Control →
`Ctrl+Tab`. Karabiner doesn't feed its own output back through its
manipulators, so the two mappings don't chase each other.

### If the layering is the other way round

On a macOS version where Karabiner sees the *rotated* key rather than the
physical one, this rule is wrong in a way that shows up immediately: physical
Alt arrives as `left_control`, which matches the reciprocal manipulator and is
rewritten to `left_option` — so Alt+Tab produces Option+Tab, which does nothing,
rather than switching applications. Physical Ctrl+Tab arrives as
`left_command`, matches nothing, and keeps switching applications.

**Alt+Tab doing nothing at all is the symptom.** It is not a silent no-op: the
rule is remapping, just from the wrong starting point.

To correct it, shift every modifier name one step along the rotation —
`left_option` becomes `left_control`, and `left_control` becomes `left_command`.
Do it as one substitution rather than in sequence, or the first rename feeds
the second. The four manipulators become:

| # | `from` | `to` |
| --- | --- | --- |
| 1 | `left_control` + `shift` | `left_command` + `shift` |
| 2 | `left_control` | `left_command` |
| 3 | `left_command` + `shift` | `left_control` + `shift` |
| 4 | `left_command` | `left_control` |

If you would rather back the whole thing out, disabling the rule in Karabiner
restores the rotation's own behavior — application switching on physical
Ctrl+Tab, next tab on physical Alt+Tab.

## Enabling it

Karabiner does not enable assets automatically. In Karabiner-Elements
Settings > Complex Modifications > Add rule, enable "Alt+Tab switches
applications". `setup-macos` installs Karabiner and says this, but the enabling
step is a GUI action that can't be scripted.

Karabiner also needs its driver extension approved and Input Monitoring
permission granted, both prompted for on first launch.

## Scope

Only left Alt is mapped. Right Alt is left alone so it stays available as a
plain modifier, and the rotation still sends it to right Control.

## Modifier names

Karabiner's canonical name for the Alt modifier is `left_option`, not
`left_alt`, and that is what the rule uses throughout — `left_alt` is at best
an alias, and an unrecognized modifier name in a `mandatory` block is not an
error Karabiner reports. It simply never matches, which looks identical to the
rule not being enabled. The test asserts `left_option` in both the trigger and
output positions for that reason.
