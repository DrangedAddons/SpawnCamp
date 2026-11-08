# Changelog

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
