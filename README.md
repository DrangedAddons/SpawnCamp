# SpawnCamp

WoW Forever addon for camping a mob: one key to tag it or talk to it (chat, quest hand-ins and accepts), and a respawn timer built from the kills it has seen.

## The window

```
              SpawnCamp             Recent  [> Log] [gear] [x]
 Log drawer   [ Shift-Wheel Down ] [Unassign]   Attacks Mechanized Sentry.
 (left, or    +----------------------------------------------------------------+
  right)      | (portrait) Mechanized Sentry   ETA 2:55  [SWORD] [BUBBLE] [Clear] |
              |            dead 2:05, earliest in 1:10  Avg respawn 5:00           |
              +----------------------------------------------------------------+
              [+ Add another target]  -> opens a blank box:
              +----------------------------------------------------------------+
              | New target [ type or paste a mob name ] [Add]               [x] |
              | [My Target] [Nearby] [Quest] [Auto Quest]                        |
              +----------------------------------------------------------------+
```

- **Key button**: shows the bound key (e.g. "Shift-Wheel Down"), or **Click to Bind Key**. Click it and press a key, roll the mouse wheel, or press mouse button 3-5 (Shift/Ctrl/Alt combos work). **Unassign** removes it. The key only does something while you have a **target**.
- **Target**: the mob your key works on. Set it by typing or pasting a name (**Add** or Enter), with **My Target** (your in-game target), from **Nearby**, or from **Recent**. **Hover the target's name** for the mob's own game tooltip (when it's in view), and **click it** to target it in game. **Clear** unsets it: the key then does nothing and goes back to its normal binding. Getting the kill clears it too, unless **Keep** (under Clear) is ticked for that mob.
- **More targets** (up to 8): every add joins the list, and **+ Add another target** under the last box opens a blank target box with the ways to add one: type a name, **My Target**, **Nearby**, **Quest** or **Auto Quest**. With nothing on your key that box is always open. Each gets the same controls. The list order is the **priority**: the little arrows on the box's left edge move it up or down, with its place number between them. The key goes for the highest one in view that's alive and untagged. Click the log's title to step through them.
- **ETA / Avg respawn**: *Avg respawn* is how long this mob usually takes to come back after it dies (from the log). *ETA* counts down to that from its last death. It shows **DUE** once the average has passed without a sighting, and **UP** once the mob is seen.
- **Sword / bubble**: big square buttons, one always pressed. The sword means your key targets the mob and casts your attack spell. The bubble means it targets the NPC and talks to it: chat, quest hand-ins, new and follow-up quests. Clicking the pressed one does nothing; clicking the other swaps them. **Right-click the sword** for the spell or your own macro lines, **right-click the bubble** for the chat and quest options. Clicking anywhere outside an options box closes it.
- **Log** (header button): a drawer on the left of the window (or the right, in the settings). It shows the target's respawn times (fastest, average, slowest), a known respawn time you can enter, the manual "it died / it's up" buttons, and every sighting with its time.
- **Recent** (small link in the header): a pop-out listing every mob you've targeted, with **Use** to pick one again and **x** to remove it.
- **Nearby**: a pop-out of mobs around you, with **Use**.
- **Quest**: a pop-out of mobs your current quests want: kill objectives from your quest log, and mobs seen nearby that your quests need (item drops too), with **Use**.
- **Auto Quest**: your key goes for any mob your quests still need, after your own targets, without adding each one. It gets its own box like a target's: the mob it's on (or the only one left), the quest and your progress (3/10), or "Any quest mob" with the count. **Clear** on that box turns Auto Quest off.
- **Portrait**: the mob's real portrait once it has been seen (targeted, on a nameplate, moused over). Before that, an icon for its creature type, or a sword or scroll if that isn't known yet.
- **Gear**:
  - Sharing with **Party**, **Raid** and **Guild**.
  - **Alert when a mob spawns** (loud).
  - **Respawn dings** (soft), with how early the first one comes.
  - **Put a marker on the target**: a raid marker (skull by default; click the icon to change it) goes over the mob as soon as your key has it. In a raid this needs lead or assist.
  - Show mobs you've already killed, sound, lock window, log on the right.

Hostile mobs start on the sword and friendly ones on the bubble.

The game requires a real keypress for every target, cast and interact. SpawnCamp doesn't press anything for you and never will.
### What the key runs

The key picks the best of three, and the line next to it says which one it's in:

1. **On target: won't swap.** Your target is the alive mob and nobody else has tagged it, so the key only casts at it (and re-finds it by name only if your target is gone). Spamming can't move you off it, including during combat.
   It does let go of a mob you haven't hit yet when a higher-priority one comes into view, or when a press failed with "not in line of sight" and another target in view is in sight. A mob you're fighting is never dropped.
2. **Locked on its nameplate.** The mob's alive nameplate is showing and it isn't tagged by someone else, so the key targets that unit and casts at exactly it. With several in view it picks the highest priority (Auto Quest mobs come after your own targets). A mob that just failed with "not in line of sight" ranks below the ones in sight for 8 seconds; it's still used when nothing else is around.
3. **Searching.** `/cleartarget`, `/targetexact <name>`, drop a corpse (`/cleartarget [dead]`). No cast, since a name search can't tell a tagged mob from a free one. Once the target checks out the key switches to 1 and the next press casts. In combat, when the key can't switch, it casts at what it finds.

The game requires a real keypress for every target and cast. Keep enemy nameplates on (V) so the lock can work.
### Bubble options (right-click the bubble)

- **Hand in and accept quests** and **Click through chat**: both on by default. With several chat options it picks one matching your **Prefer** list, otherwise the first.
- **Quest reward**: which reward to take when a quest offers a choice. 1 (the default) = first. Empty = you pick.
- Hold **Shift** while talking to do a window yourself.
## Respawn timer

The timer starts when the mob dies and stops when it's seen alive again. That time is the respawn. The status line shows `dead 2:05` while it's down (with `earliest in` once there's history), then `UP, respawned after 4:51`. The log shows the fastest, average and slowest respawn.

**Where deaths and spawns come from.** You don't need to be in combat with the mob. (Forever doesn't let addons read the combat log, so there's no zone-wide death feed.)

- **Nameplates, your target, your mouseover**, read a few times a second. A watched mob seen dead is a death and seen alive is a spawn. Nameplates only cover mobs near you, so camp within nameplate range and turn enemy nameplates on (V).
- **Your key**: a target right after pressing it is your mob, and SpawnCamp follows it until it dies or leaves range.
- **Other SpawnCamp users** in your party, raid or guild (if sharing is on).
- **Manual**: **It died now** / **It's up now** in the log.

A mob first found already dead is logged with a **+** ("died at least this long ago"), since the real time of death isn't known.

Alerts:

- **Spawn alert** (loud, raid-warning sound): the mob is seen alive.
- **Soft ding** (whisper sound, small yellow text): a set time before the earliest respawn, when the respawn window opens, and when the **average** respawn time is reached, whether or not the mob has shown.
- **Known respawn** (minutes): overrides the history.
- **Your own kill**: the mob is marked "got" and cleared as your target.
### Hidden names (dungeons)

In dungeons Forever hides NPC names from addons. SpawnCamp then knows a mob by your key: a target right after a press is your selected target. A chat or quest window within 8 seconds of a press that targeted a friendly NPC gets handled.

## Commands

- `/spawncamp` (or `/spc`): show or hide the window
- `/spawncamp settings`: open the settings
- `/spawncamp add [name]`: watch your target, or a mob by name
- `/spawncamp died [name]` / `up [name]`: log a sighting now
- `/spawncamp probe`: print and save what the addon can read (for bug reports)
- `/spawncamp key`: the key's mode, its macro, and what the last presses targeted
