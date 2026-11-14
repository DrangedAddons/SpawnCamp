# SpawnCamp

WoW Forever addon for camping a mob: one key to tag it or talk to it (chat, quest hand-ins and accepts), and a respawn timer built from the kills it has seen.

## The window

```
 Log drawer  [icon] SpawnCamp                          [Recent] [Log] [gear] [x]
 (left, or   [   R   ]  * On target                                  [Unassign]
  right)                Attack - Vicious Owlbeast - won't swap
             [ Add a mob or search...       ] [My Target] [Nearby] [Quest] [Auto v]
             TARGETS  2 / 8   (top = highest priority)
             | (portrait) Vicious Owlbeast [KEY]   DUE       [SWORD] [BUBBLE] [Clear]
             |            dead 4:59                3:03 over avg
             | (portrait) Primitive Owlbeast       UP        [SWORD] [BUBBLE] [Clear]
```

- **Key bar**: the big box shows your key (e.g. "R", "Shift-Wheel Down"), or **Set key**. Click it and press a key, roll the mouse wheel, or press mouse button 3-5 (Shift/Ctrl/Alt combos work). **Unassign** removes it. Next to it, a coloured light and a line say what the next press does: green **On target** or **Locked on its nameplate**, gold **Searching**, grey **Idle** when nothing's on your key, with the mode and the mob underneath.
- **Add bar**: always open under the key bar. Type a name or part of one and press Enter, or use **My Target**, **Nearby**, **Quest** or the **Auto** menu.
- **Target**: the mob your key works on. Set it by typing or pasting a name and pressing Enter, with **My Target** (your in-game target), from **Nearby**, or from **Recent**. **Hover the target's name or portrait** for the mob's game tooltip: the live one when it's in view, else a copy from the last time you saw it. **Click the name or portrait** to target it in game. **Clear** unsets it: the key then does nothing and goes back to its normal binding. Cards stay until you press **Clear**: getting the kill only alerts you.
- **More targets** (up to 8): every add joins the list under TARGETS, each as its own card with the same controls. A coloured strip on a card's left edge shows its mode (red attack, blue talk, gold Auto Quest), and the card your key is on has a green edge and a **KEY** tag on its portrait. The list order is the **priority**: drag a card by the dotted grab bar on its left edge to move it. In combat too, but the game locks the key until combat ends, so it switches to the new order then (and until then, clicking a moved card's name targets the mob that used to be in that spot). The key goes for the highest one in view that's alive, untagged, in range of your attack spell and in sight; mobs out of range or out of sight come after those. Click the log's title to step through them.
- **Typed names are searches**: type "owl" and press Enter. It's always a wildcard **search**: any mob with that text in its name, capitals don't matter, even when you type a full name. The key looks for it straight away (`/target owl`, after your exact targets), and every mob seen nearby whose name matches is added as its own target, right under the search, and found by its exact name from then on. Clear a wrong one and the search skips that name. When you've found the one, click **Lock in** on its box: that keeps it and removes the search and its other finds.
- **ETA / Avg**: *Avg* (the average respawn) is how long this mob usually takes to come back after it dies (from the log). *ETA* counts down to that from its last death. It shows **DUE** once the average has passed without a sighting, and **UP** once the mob is seen.
- **Sword / bubble**: big square buttons, one always pressed. The sword means your key targets the mob and casts your attack spell. The bubble means it targets the NPC and talks to it: chat, quest hand-ins, new and follow-up quests. Clicking the pressed one does nothing; clicking the other swaps them. **Right-click the sword** to pick the spell (Choose spell lists your spellbook with a filter and a Show all ranks box, or drag one onto the icon) or one of your saved macros from /m (edits in /m apply on their own), **right-click the bubble** for the chat and quest options. Clicking anywhere outside an options box closes it.
- **Log** (book icon in the header, shown while you have a target): a drawer on the left of the window (or the right, in the settings). It shows the target's respawn times (fastest, average, slowest), a known respawn time you can enter, the manual "it died / it's up" buttons, and every sighting with its time.
- **Recent** (watch icon in the header): a pop-out listing every mob you've targeted, with **Use** to pick one again and **x** to remove it.
- **Nearby**: a pop-out of mobs around you, with **Use**.
- **Quest**: a pop-out of mobs your current quests want: kill objectives from your quest log, and mobs seen nearby that your quests need (item drops too), with **Use**.
- **Rares**: when a rare's minimap vignette (the rare star) appears, a rare or rare elite nameplate comes into view, or someone in your party or raid targets a rare, it's added at the top of your targets in a box with a silver frame and the game's silver dragon around its portrait, the window opens and a loud alert goes off. Clear its box and it won't pop up again until you next log in. No list is involved: the game marks rares on their nameplates. The vignette reaches furthest, and its alert gives a rough distance and direction; your key targets the rare once it's in reach. Without a vignette, range is nameplate range (up to 60 yards), or any rare you target or mouse over. `/spc vignettes` shows whether the game is giving vignettes where you are. **Ignore** on a rare's box takes it off your key and stops it ever popping up again; **Ignored rares** in the gear settings lists them, with **Remove** and a box to add a name by hand. **Pop up rares** in the gear settings turns the whole thing off. While SilverDragon is loaded the box still pops up but SilverDragon does the alerting.
- **Map button** (with Questie installed): the small map icon at the top right of a target's name pins that mob's spawns on your map and minimap through Questie, the same as Questie's Advanced Search > Show on Map. On a search it pins every NPC with that text in its name. Click again, or clear the target, to remove them.
- **Dungeon mobs** (with Questie installed): in a dungeon or raid, the key also goes for that instance's mobs, after your own targets. Names can't be read in instances and `/target <part of a name>` finds nothing there, so the key targets every mob by its full name with `/targetexact`, from Questie's database: every NPC it places in the instance, plus event and summoned mobs of the same family that Questie has no spawn point for (Zul'Farrak's stair event: Sandfury Slave, Drudge, Zealot, Acolyte). The searches run through hidden macro buttons so the 255-character macro limit doesn't cut them, and end with "any enemy", which catches pets, totems and wards. NPCs that start friendly and turn hostile later (the Witch Doctor, Sergeant Bly) are skipped while friendly. **Typed searches** work in instances too: "slave" adds a card for every mob on the list containing "slave", the same as outdoors; text that matches none of them ("totem") matches nothing. What a dungeon's mobs summon (totems, wards, adds) is on a hand-written list per dungeon, since Questie doesn't record it; Zul'Farrak's has the Witch Doctor's Lava Spout Totem and Greater Healing Ward and Zum'rah's ward and adds. `/spc dungeon` lists the names in order; untick **Dungeon mobs on the key** in the settings to keep only your own targets and searches.
- **Dungeon profiles**: Questie's list for the instance, plus `DungeonData.lua` for what Questie lacks: mobs the cMaNGOS classic database spawns there that Questie doesn't place, and what the instance's mobs summon (totems, wards, adds) and who summons them. Generated for every classic dungeon and raid by `tools/build_dungeon_data.py`; run it with `--refresh` to pull the newest cMaNGOS dump. Summons the server makes in its own code, and Forever-only NPCs, go in the small hand-written list in `Dungeon.lua`.
- **Auto > Totem / Ward**: your key goes for an enemy totem or ward first, before your own targets, then back to them once it's gone. It gets its own box at the top of the list, like Auto Quest's: the totem your key is on, or the names it knows here; **Clear** turns it off. It learns each zone's totems from their nameplates (the game's Totem creature type, which covers wards); one first seen mid-fight is on the key from the next fight, since the game locks the key during combat. In a dungeon it uses the dungeon's summons list instead (Zul'Farrak: Lava Spout Totem, Greater Healing Ward, Ward of Zum'rah). A friendly totem of the same name (a party shaman's) is skipped.
- **Auto > Quest**: your key goes for any mob your quests still need, after your own targets, without adding each one. It gets its own box like a target's: the mob it's on (or the only one left), the quest and your progress (3/10), or "Any quest mob" with the count. **Clear** on that box turns Auto Quest off.
- **Portrait**: the mob's real portrait once it has been seen (targeted, on a nameplate, moused over). Before that, an icon for its creature type, or a sword or scroll if that isn't known yet.
- **Gear**: the settings open beside the window.
  - Sharing with **Party**, **Raid** and **Guild**.
  - **Alert when a mob spawns** (loud).
  - **Pop up rares**: a rare's nameplate adds it as a silver target box. **Ignored rares** next to it reviews, adds and removes ignored rares. **Test rare** shows a pretend one so you can see the look.
  - **Respawn dings** (soft), with how early the first one comes.
  - Show mobs you've already killed, sound, lock window, log on the right.
  - **Look**: Match EllesmereUI (default), SpawnCamp default, EllesmereUI Style, WoW Forever, Blizzard Style or Classic WoW UI. Changes straight away.
  - **Show minimap button**. Click the minimap button to open the window, right-click for these settings. They're also under Options > AddOns > SpawnCamp.

Hostile mobs start on the sword and friendly ones on the bubble.

The game requires a real keypress for every target, cast and interact. SpawnCamp doesn't press anything for you and never will.
### What the key runs

The key picks the best of three, and the line next to it says which one it's in:

1. **On target: won't swap.** Your target is the alive mob and nobody else has tagged it, so the key only casts at it (and re-finds it by name only if your target is gone). Spamming can't move you off it, including during combat.
   It does let go of a mob you haven't hit yet when a higher-priority one comes into view, or when a press failed with "not in line of sight" and another target in view is in sight. A mob you're fighting is never dropped.
2. **Locked on its nameplate.** The mob's alive nameplate is showing and it isn't tagged by someone else, so the key targets that unit and casts at exactly it. With several in view it picks the highest priority (Auto Quest mobs come after your own targets). A mob that just failed with "not in line of sight" ranks below the ones in sight for 8 seconds; it's still used when nothing else is around.
3. **Searching.** `/cleartarget`, then `/targetexact <name>` for each target in order, dropping a corpse (`/cleartarget [dead]`) after each so a dead mob doesn't stop the search. No cast, since a name search can't tell a tagged mob from a free one. Once the target checks out the key switches to 1 and the next press casts. In combat, when the key can't switch, it casts at what it finds.

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
- **Your own kill**: logged with a "You got it!" alert. The mob stays your target until you clear it.
### Hidden names (dungeons)

In dungeons Forever hides NPC names from addons. SpawnCamp then knows a mob by your key: a target right after a press is your selected target. A chat or quest window within 8 seconds of a press that targeted a friendly NPC gets handled.

## Commands

- `/spawncamp` (or `/spc`): show or hide the window
- `/spawncamp settings`: open the settings
- `/spawncamp add [name]`: watch your target, or a mob by name
- `/spawncamp died [name]` / `up [name]`: log a sighting now
- `/spawncamp probe`: print and save what the addon can read (for bug reports)
- `/spawncamp key`: the key's mode, its macro, and what the last presses targeted
