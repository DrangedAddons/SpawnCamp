# Changelog

## 0.23.1

- Removed pinging and marking. Neither works from an addon on this client. The setting is gone.

## 0.23.0

- The key pings the mob instead of marking it. Raid markers can't be set by an addon on this client by any route (direct call, `/run` in the key's macro, the secure marker action, a saved macro run from a button). The first press that casts at a mob adds `/ping [@target] attack` (out of combat, once per mob).
- The setting is now **Ping the target**; the marker icon picker is gone.
- SpawnCamp no longer makes the SpawnCampMark character macro. If 0.22.5 made one, you can delete it.

## 0.22.5

- Raid marker, take four. The client blocks every way an addon can set a marker, and the secure marker action does nothing. A saved macro runs as your own, so SpawnCamp now makes a character macro named **SpawnCampMark** holding `/run SetRaidTarget("target", 8)` (your chosen icon) and the key runs it. It needs one free character macro slot; you don't need to put it on a bar.

## 0.22.4

- Took out the `/run SetRaidTarget` line from 0.22.3. The game runs `/run` lines in an addon's macro as addon code, so it was blocked (the "ForceTaint_Strong" popup).
- Back to the hidden marker button. It now carries the icon in both the `action` and `raidtarget` attributes, since client versions differ on which one the marker action reads.

## 0.22.3

- The raid marker now goes on with `/run SetRaidTarget("target", 8)` (your chosen icon) at the end of the key's attack lines, the same line that works when typed in chat. It sets the marker without toggling, so it's in every attack press, in combat too. The hidden marker button is gone.

## 0.22.2

- Fixed the raid marker never going on. The key's macro `/click`s a hidden marker button, and a macro click is an up-click, but the button only listened for down-clicks when "cast on key down" is on (the game's default). The marker and talk buttons now take either edge.
- If a mob still has no marker 1.5 s after the press that marked it, the marker line goes back in for the next press (out of combat, up to 3 tries).

## 0.22.1

- Clicking a target's portrait targets the mob in game, like clicking its name.

## 0.22.0

- Hovering a target's portrait or name shows the mob's game tooltip. When the mob is in view it's the live tooltip. When it isn't, it's a copy of the tooltip from the last time you saw it (name and reaction colour, level and type, quest lines and so on), with how long ago that was. Copies for your targets are saved, so they survive a reload.
- Before a mob has been seen at all, the tooltip shows its level, type and rank if Nearby knows them.

## 0.21.2

- Fixed the key finding nothing when your first target's nearest copy was a corpse. The name search found the corpse, skipped the searches for your other targets, then dropped it. Each search now drops a corpse before the next one runs.
- Mobs out of range of your attack spell rank below the ones in range, like out-of-sight ones. A far-off higher-priority mob no longer pulls the key off one you can hit.
- Bigger priority arrows; the place number is gone (the list order shows it).

## 0.21.1

- Line of sight no longer benches a mob. A mob that just failed with "Target not in line of sight" ranks below the targets you can see for 8 seconds, and is still used when nothing else is in view.
- Priority arrows moved to their own column on the left edge of each box: up arrow, place number, down arrow. At the top or bottom of the list the arrow is greyed out instead of hidden.

## 0.21.0

- **Priority**: the target list order is the priority. Arrows on each portrait move a mob up or down, and the number shows its place. With several in view, the nameplate lock goes for the highest one, and stays put between equal ones instead of hopping.
- The key lets go of a mob you haven't hit yet when a higher-priority one comes into view. A mob you're fighting is never dropped.
- **Line of sight**: when a press fails with "Target not in line of sight", that mob sits out for 8 seconds and the key moves to the next target in view. Fixes the key staying locked on a mob behind a wall.
- Hovering a target's name shows the mob's own game tooltip when it's in view (target, nameplate or mouseover). Clicking still targets it.

## 0.20.2

- No alerts of any kind for mobs that aren't targets in the main window. Killing a Recent mob (or one Auto Quest picked) no longer shows "You got X!". Sightings are still logged.

## 0.20.1

- Spawn alerts and respawn dings are only for your current targets. Mobs you cleared (still in Recent) no longer set them off; their sightings are still logged.

## 0.20.0

- The add row is gone from the top. **+ Add another target** now opens a blank target box holding the ways to add one: type or paste a name, **My Target**, **Nearby**, **Quest** and **Auto Quest**, with **x** to close it. Adding a target (or turning on Auto Quest) closes it. With no targets and Auto Quest off, it's always open.

## 0.19.1

- **+ Add another target** is always shown (until you have 8), also with no targets or with only Auto Quest on.

## 0.19.0

- **Auto Quest button** on the front, replacing the tick box in the Quest pop-out. It lights green when on.
- Auto Quest gets its own box that looks like a target's: portrait, name, Attack button (right-click for the spell) and Clear (turns it off). It shows the only quest mob left, or the one your key last went for, with its quest and progress (3/10). With several and none picked yet it shows "Any quest mob" and how many are needed. A gold "!" on the portrait marks it as the key's pick. Clicking the name targets that mob.
- **Recent** is now a small link in the header.

## 0.18.0

- **Target any quest mob** (tick box in the Quest pop-out). Your key then goes for any mob your quests still need, alive and not tagged by someone else, after your own targets. You don't need to add them; finished objectives drop off by themselves. A quest mob's nameplate locks the key the same way a target's does, and the key won't hop to another quest mob while you're on one. You can still Use a quest mob to make it a target of its own.

## 0.17.0

- **Quest** pop-out next to Recent: mobs your current quests want, with **Use**. It lists kill objectives from your quest log (with progress, e.g. 3/10), plus mobs you've seen nearby whose tooltip names one of your quests, which covers mobs that drop quest items. Unfinished ones first, then ones nearby; finished ones are greyed.

## 0.16.0

- **Any number of targets, up to 8.** Every add (typed name, My Target, Use in Nearby or Recent) joins the list, and **+ Add another target** sits under the last box. Clear on a box removes just that target. The key goes for whichever is alive, untagged and found first, and doesn't swap off one it's on.
- Clicking the log's title steps through the targets.
- Your one or two targets from 0.15 carry over.

## 0.15.0

- **Second target.** **+ Add a second target** under the first, then add a mob the usual way (typed name, My Target, or Use in Nearby / Recent). Each target has its own box with Attack/Talk, ETA, Keep and Clear, and clicking either name targets it.
- The key covers both: it goes for whichever is alive, untagged and found first, and once you're on either one it won't swap off. Clearing the first target moves the second up.
- With two targets, click the log's title to switch which one it shows.

## 0.14.2

- The marker goes on through a hidden secure "raidtarget" button the key's macro clicks, instead of `/tm`, which didn't mark in testing.
- The press log (`/spc key`) records the macro that actually ran and the marker the target has after the press.

## 0.14.1

- Fixed the "blocked from an action only available to the Blizzard UI" popups. The marker was placed by calling SetRaidTarget from the addon, which this client forbids, and it retried on every press. It now goes on with a `/tm` line in the key's macro. The line is there only for the press that casts, is taken out straight after (before combat freezes the macro, so the marker can't be toggled off), and is skipped if the mob already has that marker.
- "The game blocked ..." chat lines are shown at most every 30 seconds.

## 0.14.0

- **Marker on the target:** as soon as a key press puts you on the free, alive mob, it gets a raid marker (skull by default). It's only set when the mob doesn't already have that marker, so spamming doesn't toggle it off. Works solo and in a party; in a raid it needs lead or assist.
- Settings: **Put a marker on the target** (on by default) and a marker picker (click to cycle).
- If the game refuses addon markers, marking switches itself off and says so in chat.

## 0.13.0

The key only goes for a mob nobody else has tagged.

- **Locked** only arms on a live nameplate that isn't tagged by someone else, and the cast goes at exactly that mob.
- **On target** only counts when your target isn't tagged by someone else (yours or nobody's).
- The **name search** only targets and doesn't cast, because it can't tell a tagged mob from a free one, and casting at a tagged one would put you on the global cooldown as the real spawn appears. Once the target checks out, the key switches to On target and the next press casts. In combat, when the key can't switch, the search casts as before.

## 0.12.2

- The Attack and Talk options stay open when you click in the spellbook or on the action bars, or while holding a spell on the cursor, so a spell can be dragged onto the Spell box.

## 0.12.1

- Fixed: in "Locked on its nameplate" mode the key didn't target at all. It relied only on `/target nameplateN`, which this client apparently doesn't honour. That mode now falls back to the name search, drops a corpse, and casts at the target.
- `/spawncamp key` shows the key's mode, its macro, and the last 20 presses with what each one ended up targeting (saved in SpawnCampDB.keyLog).

## 0.12.0

The key never swaps off the mob once it has it, and only ever goes for the alive mob.

- **On the mob:** when your target is the alive mob, the key only casts. It doesn't clear or retarget, so spamming can't move you off it. This holds through combat.
- **Locked:** when the mob's alive nameplate is known, the key targets exactly that unit and casts at it. No clearing and no name search, so no other mob or corpse can be picked.
- **Searching:** otherwise it clears, searches by name, drops a corpse, then casts.
- The line next to the key shows which of these it's in ("On target: won't swap", "Locked on its nameplate", "Waiting: no live nameplate yet", "In combat: searching by name").

## 0.11.1

- With the fast path, the spell and auto attack go straight at the mob's nameplate unit (`/cast [@nameplate5,harm,nodead][@target,harm,nodead]`) in the same press, not waiting on the target swap.
- If a key press doesn't cast, the game's reason (facing, range, line of sight...) is echoed in chat, so a slow first cast can be traced.

## 0.11.0

- **Faster targeting.** Out of combat, the moment the target mob's alive nameplate appears, the key is rewritten to target that exact unit (`/target nameplateN`). That's instant and can't land on the last kill's corpse, which `/targetexact` (nearest by name, dead or alive) could. The name search stays as a fallback, and in combat it's the only path, because the key can't be changed then.
- `/cleartarget [dead]` after the targeting lines, so a corpse is never cast at.
- Target box laid out in columns: name and status, ETA and Avg respawn, sword and bubble, then Clear with Keep under it. The window is a little wider so the name and status line fit.

## 0.10.1

- **Keep** tick box under Clear on the target, saved per mob, off by default. Ticked, getting the kill leaves the mob as your target and on the key until you press Clear.

## 0.10.0

- **Click the target's name** to target the mob in game (a secure click area over the name; it repositions out of combat).
- The **log** is a drawer on the left of the window, opened and closed with the **Log** button in the header. A setting puts it on the right.
- **Recent** is a pop-out next to Nearby listing every previous target, with **Use** and remove.
- **Alert when a mob spawns** and **Respawn dings** (with the early-ding time) moved to the settings and apply to every mob.
- The small text under the ETA says **Avg respawn 5:00**. The log spells it out as respawn time (death until seen again): fastest, average, slowest.
- The key button shows just the key in a short form ("Shift-Wheel Down", "Mouse 4") so it fits.
- The main window is shorter: it ends at the target.

## 0.9.1

- Sword and bubble states are much clearer. Pressed: bright red, thick gold border, gold glow, shaded top and a gold icon nudged down. Not pressed: dark grey with a grey border and a clean grey icon, no red tint.

## 0.9.0

- **ETA** next to the target's name: a countdown to the average respawn, with the average under it; **DUE** once it has passed, **UP** once the mob is seen.
- A soft **ding** (whisper sound plus small yellow text) when the average respawn time is reached, whether or not the mob has shown. The early warning and window-open alarms use the ding too; the spawn alert keeps the raid-warning sound.
- The key button reads **Click to Bind Key** / **Bound: F**, with no separate label. The mouse wheel can be bound.
- The Attack and Talk options are wider so the text fits, and close when you click anywhere outside them (clicking the other button just closes them).
- The log sits under the target instead of in a side panel.
- Recent targets are collapsed until you click the header.

## 0.8.1

- Removed the combat log. Forever forbids addons from reading it, and registering for it brought up the "blocked from an action only available to the Blizzard UI" popup.
- If the game blocks a SpawnCamp call again, chat names the function and `/spc probe` shows the last one (kept in SpawnCampDB.blocked).

## 0.8.0

- **One selected target.** The key works on that mob only; with no target it does nothing and goes back to its normal binding. **Clear** unsets it.
- **Recent**: mobs you've targeted before, newest first, with timers. Click to make one the target again.
- The key is on the front: assign, change or **Unassign** it there.
- Sword and bubble are big square red buttons with gold icons, no text. **Right-click** the sword for the spell/macro, the bubble for chat and quest options. Both open beside the window.
- The respawn log opens beside the window (target name, or right-click a Recent mob) instead of expanding under it.
- Portraits fall back to a creature-type icon (saved the first time the mob is seen), then to a sword or scroll, instead of a question mark.
- Deaths are also read from the combat log when Forever allows it: any unit within about 50 yards, in or out of combat. `/spc probe` reports whether it works.
- Getting the kill clears the mob as your target.

## 0.7.0

- Sharing has separate **Party**, **Raid** and **Guild** boxes. Messages are only sent to and accepted from ticked ones.
- "Keep mobs I already got" is now **Show mobs I've already killed**, with a tooltip. It also works again: since every mob always has Attack or Talk, killed mobs could never be hidden.
- Click through chat picks the first option when several are offered and none match the Prefer list (it used to stop and ask).
- Quest reward defaults to **1** (first reward); empty means you pick. Existing settings left at "ask" move to 1 once.

## 0.6.0

- **Attack** and **Talk** are a pressed/raised pair on each mob, in the game's red button style with gold icons and text. One is always pressed. Clicking it again does nothing; clicking the other swaps them.
- New add row under the title: a box to type or paste a mob name, **Add**, **Current Target** and **Nearby**. The tiny + is gone.
- Nearby has an **Add** button next to each mob (hostile starts on Attack, friendly on Talk).
- Mobs you already got stay on their button but come off the key; **Still hunting** in the details puts them back.

## 0.5.0

- **One key** for every mob, set once in the settings. The sword or bubble on each mob decides what it does: hostile targets get the attack lines, friendly ones get talked to. The separate Attack and Talk keys are gone, and so is the Talk "Reach" option (talking is always by name).
- Sword and bubble are big red buttons with gold icons. Clicking one only toggles it, it never opens a menu.
- Mob lines are taller: big name, the mob's portrait (grabbed whenever it's targeted or on a nameplate), and the timer under the name.
- The timer counts up from the death (`dead 2:05, due in 2:55`) and shows the measured respawn once the mob is seen again (`UP, respawned after 4:51`).
- With hidden names (dungeons), hostile/friendly narrows which mob a key press targeted.
- Existing keys move into the one key setting.

## 0.4.0

Simpler window.

- Each mob line has a **sword** and a **chat bubble**. Sword = the Attack key goes for it; bubble = the Talk key talks to it (chat, quest hand-ins, accepts, follow-ups). That's the only choice per mob.
- One **Attack** key and one **Talk** key for the whole list, set once in the gear settings with the attack spell, an optional custom macro, and how talking works. The keys show under the title.
- The Attack key covers every sword mob: `/targetexact` for the first, `/targetexact [noexists]` for the rest.
- Clicking a mob's name opens its details: status, respawn times, history, alarms.
- **+** asks for a typed name only when the game hides it (dungeons).
- Removed the per-mob key, spell, mode and quest options, and the Custom macro mode (now a setting). Existing mobs keep their sword/bubble, and the first key and spell found move into the settings.

## 0.3.0

Forever hides NPC names and GUIDs from addons (confirmed with `/spc probe`), so the addon now tells mobs apart by your key presses.

- A target right after pressing a mob's key is that mob: it's logged as up, then followed as your target and on its nameplate. Its death is logged when it dies, as your kill when it wasn't someone else's tag.
- Quest and chat automation applies to windows that open within 8 seconds of pressing an Interact key. Each step extends it, and closing the window ends it.
- **+** opens the name box when it can't read your target's name, with Attack or Interact picked from whether the target is hostile.
- Nearby explains that names are hidden when that's why it's empty.
- Fixed: your own kills never counted as yours (a not-tapped-by-someone-else reading was lost).

## 0.2.2

- Unit names come from the first source that gives a readable name: UnitName, GetUnitName, UnitNameUnmodified, the unit's tooltip data, then the game tooltip (mouseover). Forever can hide UnitName.
- A unit whose existence the game hides is still checked by name.
- **+** (watch my target) now says why it failed: no target, a player, or a name it can't read.
- `/spawncamp probe` prints every read for target, mouseover and the first nameplate, and saves it to SpawnCampDB.probe.
- Button errors are printed in chat.

## 0.2.1

- Nearby: a **Scan now** button reads all nameplates, your target and your mouseover immediately. A line at the bottom says how many NPCs it read and how many it skipped or couldn't read (players, pets, names the game hides, errors). Opening the list scans too.
- Nameplates 1-40 are read directly every tick, so the list and the spawn tracker no longer depend on nameplate events.
- Unit checks accept the 1/nil style of return as well as true/false. Before, a client returning 1 made every unit look like it didn't exist.
- `/spawncamp debug` also prints the first nameplate's reads and a nearby scan report.

## 0.2.0

- One compact window replaces the big window and the timer list. It stays on screen with a line per mob (status, countdown bar, key). **More** opens Setup, History and Options tabs under it.
- Setup is laid out in steps: 1. Action, 2. What it does, 3. Key, 4. Alarms.
- New action: **Custom macro**. Your own macro text runs on the key, with `{mob}` replaced by the name. It can start from the attack macro.
- **Nearby** list: NPCs seen on nameplates, as target or as mouseover in the last 3 minutes, rares first. Click one to watch it.
- **+** in the header watches your target and opens its setup.

## 0.1.0

- First version.
- Attack mode: one key targets the watched mob by exact name and casts your chosen instant spell, then starts auto attack. A miss leaves you with no target.
- Interact mode: target by name, mouseover, or the game's Interact key (with a button to turn on soft-target interact for objects).
- Watched NPCs: finished quests are handed in, available and follow-up quests accepted, and chat options picked from your list. Hold Shift to skip.
- Respawn tracking from nameplates, target and mouseover: death and spawn history per realm, earliest/average/latest respawn, timer list, alarm before the earliest respawn, spawn alert.
- Sightings are shared with party/raid and guild members running SpawnCamp.
- Your own kill stops hunting that mob and frees its key.
