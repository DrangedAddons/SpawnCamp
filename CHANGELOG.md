# Changelog

## 0.46.0

- **Dungeon profiles for every dungeon and raid.** Questie stays the main source for an instance's mobs. A new generated file, `DungeonData.lua`, fills what Questie doesn't have, from the cMaNGOS classic database (the 1.12 data Questie itself is built from): mobs cMaNGOS spawns there that Questie doesn't place, and what each instance's mobs summon (totems, wards, adds), with who summons them. Questie has no summon data at all.
- Zul'Farrak from the generated data: Lava Spout Totem and Greater Healing Ward (Sandfury Witch Doctor), Earthgrab Totem and Servant of Antu'sul (Antu'sul), Sandfury Slave (Chief Ukorz Sandscalp), Ward of Zum'rah. The hand-written list keeps only what the database can't have: summons the server makes in its code (Skeleton and Zombie Troll of Zum'rah) and Forever-only NPCs.
- Auto > Totem / Ward in dungeons uses the generated totems and wards, so it works in every dungeon with them, not just Zul'Farrak.
- `/spc dungeon` shows who summons each summon.
- To refresh the data from the source: `python tools/build_dungeon_data.py --refresh` (downloads the newest cMaNGOS dump into `tools/.cache`, which isn't committed).

## 0.45.0

- **Auto** menu: the Auto Quest button is now **Auto**, a menu with two switches, **Quest** (as before) and **Totem / Ward**. The button shows which are on.
- **Auto > Totem / Ward**: your key goes for an enemy totem or ward first, before your own targets, and back to them once it's gone. Works when you're already on a mob. It learns each zone's totems from their nameplates (the game's Totem creature type, which covers wards). The game locks the key in combat, so a totem first seen mid-fight is on the key from the next fight; chat says when one is learned. In a dungeon it uses the dungeon's summons list from the start (Zul'Farrak: Lava Spout Totem, Greater Healing Ward, Ward of Zum'rah). A friendly totem of the same name, like a party shaman's, is skipped.
- **Lock in** moved under **Clear**, where Keep used to be.

## 0.44.0

- "totem" in a dungeon now means only what that dungeon's mobs summon, not every totem in the game. Questie doesn't record who summons what, so each dungeon has a hand-written summons list. Zul'Farrak's: Lava Spout Totem and Greater Healing Ward (Sandfury Witch Doctor), Ward of Zum'rah, Skeleton of Zum'rah, Zombie Troll of Zum'rah. Summons are part of the dungeon list, so "totem" adds a **Lava Spout Totem** card. Other dungeons have no summons listed yet.
- Fixed Zul'Farrak's stair-event mobs (Sandfury Slave, Drudge, Zealot, Acolyte, Zombie) missing from the dungeon list in game. Questie reads a missing zone as 0, not "none", so SpawnCamp never recognised them as zoneless event mobs.
- A typed search in a dungeon only matches the dungeon's own names. The fallback to every name in Questie is gone.

## 0.43.1

- Fixed the dungeon list not loading. SpawnCamp gave up after 30 seconds if Questie's database wasn't ready yet (after a login or `/reload` inside the instance), and then never tried again, so the key had no dungeon mobs and typed searches like "drinker" added nothing. It now keeps trying every 3 seconds while you're in an instance, and also finds the instance by its zone name or map if the instance ID lookup misses.
- `/spc dungeon` retries the lookup on the spot. If there's still no list, it says why: Questie not ready, or which instance ID Questie has no zone for, with what it could read.

## 0.43.0

- Targets stay until you press **Clear**. Getting the kill no longer takes a card off the key; you still get the "You got it!" alert. The **Keep** checkbox is gone.
- "totem" in a dungeon now targets the Sandfury Witch Doctor's **Lava Spout Totem**. 0.41.3 only kept summons within the dungeon's level, but Questie stores a totem's own level (Lava Spout is 37 in a 41-49 dungeon), so it was left out. Now every summon matching the search goes on the key (all 100 totems), nearest the dungeon's level first.
- The hidden search chain grew to 4 hubs of 15 buttons (about 200 names), so a big search doesn't push the dungeon's own mobs off the end.

## 0.42.0

- Drag to reorder works in combat. The cards move and the new order is saved straight away, but the game locks the key's macro in combat, so the key keeps its old priority until combat ends and then switches. Until then, clicking a moved card's name or portrait targets the mob that used to be in that spot. Chat says so the first time per fight.

## 0.41.3

- "totem" in a dungeon now targets totems at the dungeon's level. A search no dungeon mob matches falls back to Questie's summons (NPCs with no zone or spawn point), and only the ones within the dungeon's level band: in Zul'Farrak, Searing Totem IV, Healing Stream Totem III, Windfury Totem II and 10 more, instead of Ice Totem and Battle Totem. Up to 16 names per search.
- Boss summons are on the dungeon list: NPCs named "X of <boss>" (Ward of Zum'rah, Skeleton of Zum'rah, Zombie Troll of Zum'rah).
- The hidden search chain holds 16 buttons (was 15).

## 0.41.2

- In a dungeon your typed searches now add their matches as target cards, like outdoors when a matching nameplate shows. "slave" adds a **Sandfury Slave** card under the search, with its own portrait slot, KEY tag and priority. Clear a card and that search won't add it again.
- Only the dungeon's own mobs become cards. Guesses from the rest of Questie (the 8 totem names for "totem") stay as hidden searches on the key, so they don't fill your 8 slots.

## 0.41.1

- Fixed the key not targeting anything in dungeons. Searching by part of a name (`/target Sand`, `/target slave`) finds nothing in an instance, so the dungeon list and your typed searches now target every mob by its **full name** with `/targetexact`, from Questie's names.
- Typed searches in a dungeon: "slave" and "drudge" become Sandfury Slave and Sandfury Drudge. Text no mob on the list contains ("totem") becomes up to 8 matching names from all of Questie, summoned ones first.
- Zul'Farrak's stair event mobs (Sandfury Slave, Drudge, Zealot, Acolyte, Zombie) are on the list now. Questie has no zone or spawn point for event and summoned mobs, so the list adds spawnless NPCs that share a first word with two or more of the instance's mobs. Invisible script helpers are skipped.
- A hub button clicks the search buttons one after another, so up to 15 buttons of names (about 60) fit. `/spc key` prints the hub and every button.

## 0.41.0

- **Dungeon mobs on the key.** In a dungeon or raid the key now goes for that instance's mobs, after your own targets. Nameplates can't read names in instances, so the list comes from Questie's database: every NPC it places there, including summoned and scripted ones (Zul'Farrak has 35, the Witch Doctor's Greater Healing Ward among them). Quest givers, vendors and trainers are left out.
- Macros have no wildcards, but `/target` matches the start of a name, so names are grouped by what they start with: "Sand" covers all nine Sandfury mobs, Sandarr and Sandscalp. The searches live in a chain of hidden buttons the key clicks, so the 255-character macro limit doesn't cut them and your cast line always stays.
- The chain ends with "any enemy", for pets, totems and wards Questie has no entry for. Mobs that start friendly and turn hostile mid-run are passed over while they're still friendly.
- `/spc dungeon` lists the searches. `/spc key` also prints the chain. Turn it off with **Dungeon mobs on the key** in the settings (per character, on by default).

## 0.40.0

- Drag to reorder targets. The up/down arrows are replaced by a dotted grab bar on each card's left edge. Pick a card up and it lifts with a shadow and follows your cursor, while the other cards slide out of the way to show where it will land. Let go and it settles into the gap and the new priority is saved. Out of combat only; if combat starts mid-drag, the card goes back where it was.

## 0.39.0

- Auto Quest goes for the **closest** quest mob. Mobs of equal priority (all Auto Quest mobs, or several of one target) are now told apart by distance, read from item range checks out of combat. Your own list order still comes first.
- The key keeps your target unless a quest mob is strictly closer and you're not fighting the one you have. Equal distances never swap.
- Fixed the key clearing and re-taking targets while you spam it. When it went for a locked nameplate, its backup name search ran in list order and could land on a different mob, which the next press cleared again. The backup now searches the locked mob's name first, and a swap that lands elsewhere stops further swaps for 5 seconds.

## 0.38.4

- Fixed the key targeting a mob but never attacking it when you have a lot of targets (Auto Quest easily adds 8). The game only runs the first 255 characters of the key's macro, and a long target list pushed the cast and attack lines past that. The key now always keeps your spell, attack and talk lines, plus as many searches as fit, highest priority first.
- `/spc key` shows the macro's length and how many of the lowest searches were left out.

## 0.38.3

- `/spc key` now shows, for each press, which click edge ran and what the game did in the next second: casts sent, done or failed, and any red error text. This is to find out why the key can target a mob and still not cast.

## 0.38.2

- Auto Quest no longer adds quest credit lines as mobs. "Screecher Spirits collected: 0/3" became a target called "Screecher Spirits collected". Objectives ending in collected, captured, rescued, freed and similar are skipped; "X destroyed" and "X defeated" keep the mob name.

## 0.38.1

- The KEY tag now sits on the bottom of the mob's portrait. It used to follow the name, so a long truncated name put it on top of the Questie map button.

## 0.38.1

- Removed the Add button from the add bar. Pressing Enter in the name box does the same thing, and the box is wider. Its tooltip now explains how searches work.

## 0.38.0

- Rebuilt on the DrangedAddons house UI kit, so SpawnCamp looks like the other DrangedAddons addons and matches EllesmereUI. The window, the log and every side panel use the kit's frame, buttons and EllesmereUI's font.
- **Look** in the settings replaces Skin: Match EllesmereUI (default), SpawnCamp default, EllesmereUI Style (flat, your accent colour), WoW Forever, Blizzard Style or Classic WoW UI. It changes straight away, no reload. In EllesmereUI Style the sword and bubble go flat and light up in the mode's colour; in the other looks they're red with gold trim.
- **Show minimap button** in the settings. Right-click the minimap button opens the settings. SpawnCamp also has a page under Options > AddOns that opens them.
- Edit boxes save when you press Enter or click away, and Esc puts the old value back. The spell filter still filters as you type.

## 0.37.1

- Removed the old layout's code from the window. Nothing changes on screen, and `UI.lua` is about 300 lines shorter. The README's window section shows the current layout.

## 0.37.0

- The new layout is the only layout. The Layout choice is gone, and the Skin choice (Modern / Classic) stays. New characters start on the Modern skin.
- The "< Log" text button no longer shows over the header icons. The Log icon (with its hover tooltip) opens and closes the log, and only shows when you have a target.

## 0.36.0

- New **Modern layout**, a redesign of the window around how SpawnCamp is used. Pick it under **Layout** in the gear settings. Skin and layout are now separate choices, so the 0.35 flat skin also works on the classic layout.
  - **Key bar** at the top: your key as a big chip (click to rebind), a coloured light and a plain line saying what the next press does: "On target", "Locked on its nameplate" or "Searching", with the mode, the mob and what happens next.
  - **Add bar always open** under it, in one row: type a name or search and press Enter, or My Target, Nearby, Quest and Auto Quest. No more "+ Add another target" step.
  - **Compact target cards** under a TARGETS heading with the count, top = highest priority. A coloured strip on each card's edge shows its mode, and the card your key is on gets a green edge and a **KEY** tag.
  - **Header icons** for Recent and Log, and **settings open beside the window** instead of stretching it.
  - A short hint when nothing is on your key.
- Settings: **Skin** (Classic / Modern) and **Layout** (Classic / Modern), with **Reload to apply** when either changes.

## 0.35.0

- New **Modern** look, picked under **Look** in the gear settings (Classic stays the default). Flat dark panels with thin borders and a title strip, like retail's newer frames. Buttons are flat with white text. Sword and bubble are flat squares that light up red (attack) or blue (talk) when picked, and each target box has a thin coloured strip on its left edge for its mode (gold for Auto Quest). Rare boxes keep their silver frame and dragon.
- Switching the look needs a reload: a **Reload to apply** button appears next to the choice.

## 0.34.2

- Adding a search starts it fresh. Typing a search you used before ("owl") kept the list of matches you had cleared last time, so those mobs were never found again. Every Add now clears that list, including adding the same text while it's still listed.

## 0.34.1

- The map button can be clicked on targets with long names. The click-to-target area over a name covered the whole name even when it was cut short, which put it over the map button.

## 0.34.0

- With Questie installed, each target box has a small map button at the top right of the name. Click it to pin that mob's spawns on your map and minimap, the same as Questie's Advanced Search > Show on Map. Click again to take them off. The icon is in colour while the pins are shown.
- On a search (like "owl") it pins every NPC in Questie's database with that text in its name that has spawns, up to 40.
- Clearing a target takes its pins off. Pins last until you reload, like Questie's own.

## 0.33.0

- Typed names are always a wildcard search now, even a full name: any mob with that text in its name, capitals ignored. Typing a name the addon has seen no longer turns it into an exact name.
- Searches are on the key. After your exact targets, the key tries `/target <text>` (the game's own part-of-a-name match), so it looks for "owl" straight away instead of waiting for a matching nameplate. A mob it finds is added under the search and found by exact name from then on.
- A search no longer turns into a single mob when a name matching it with different capitals shows up; that mob is added under the search like any other match.

## 0.32.3

- Fixed typed searches (like "owl") sometimes being saved as an exact name the second time you typed them, so the key looked for a mob literally called "owl" and did nothing. Only names the game has actually shown (a sighting or a saved tooltip) are matched to their spelling now.
- Searches saved that way are turned back into searches on login, with a line in chat saying so.
- When your only targets are searches that haven't matched a mob yet, the line next to the key says it's waiting instead of "Searching".

## 0.32.2

- Talk works by binding: once the key has your Talk NPC targeted, it becomes the game's own Interact with Target key, and the next press talks. Forever doesn't run the old talk button from the key's macro (0.32.1 didn't fix it). The line next to the key says "On target: next press talks". Change target and the key goes back to finding the NPC.

## 0.32.1

- Fixed Talk doing nothing when you press the key. With "cast on key down" on (the game default) the game ignored the key's click on its talk button. The talk button now acts on that click whatever the setting.

## 0.32.0

- Rare boxes carry the game's winged silver rare dragon around the portrait (the art Forever's target frame uses), mirrored so the wings spread out of the box, plus the small silver dragon badge before "Rare" / "Rare Elite".
- **Test rare** in the gear settings, next to Ignored rares: adds a pretend rare elite at the top of your targets with the alert, so you can see how it looks. Clear or Ignore removes it, and it's never saved or put on the ignore list.

## 0.31.1

- The small line under a target's ETA no longer spills over the Ignore and Attack buttons. It's shorter ("Avg 5:00", "No avg yet", "0:25 over avg") and is cut off at its column's width. Hover the ETA for what it means.

## 0.31.0

- **Ignore** on a rare's box: takes it off your key and adds it to the ignored rares, so it never pops up or alerts again, from any source (vignette, nameplate, group target).
- **Ignored rares** in the gear settings lists them. **Remove** gives a rare its pop-up back. The box at the top adds a name by hand, to ignore a rare before you meet it. Names match without caring about capitals. The list is per character.

## 0.30.0

- Rares your party or raid members have targeted pop up too: "Rare spotted: Lupos  (Bob's target)", with the silver box added. They don't need to be near you. Checked whenever a member changes target, and every 3 seconds for members too far away for that to fire.

## 0.29.0

- Rares are also found from their minimap vignette (the star the game shows for a rare), which reaches further than nameplates. The alert says "Rare spotted: <name>" with a rough distance and direction (e.g. "~150 yd NE"), and the silver box is added straight away. Your key's name search targets it once it's in reach. The nameplate check stays quiet for a rare already announced.
- Treasure vignettes and ones not on your minimap are skipped.
- `/spc vignettes` lists what the game gives addons right now, to check whether Forever shows rare vignettes in a zone. Without them, rares are found by nameplate as before.

## 0.28.0

- Rares pop up as a target. When a rare or rare elite nameplate comes into view, it's added at the top of your targets in a box with an ornate silver frame and a "Rare" / "Rare Elite" tag, the window opens, and a loud alert goes off. The key goes for it first.
- Clear on a rare's box stops that rare popping up again until you next log in. A rare you killed pops up again when it respawns.
- No rare list any more. The game marks rares on their nameplates (rare / rare elite), so nothing else is needed. The Rares button, the vanilla and SilverDragon data and the build script from 0.27.0 are gone.
- The switch is **Pop up rares** in the gear settings (on by default). With SilverDragon loaded the box still pops up, and the alert is left to SilverDragon.
- Detection range is nameplate range: up to 60 yards with nameplate distance at its maximum, plus any rare you target or mouse over.

## 0.27.0

- **Rares** button (next to Auto Quest): the rares in your zone, nearest first, with **Use** to put one on your key. Hover a row for its level, spawn points, when you last saw it and the vanilla respawn timer.
- Three sources, kept apart. Forever-only rares come from SilverDragon's Forever zone files (used with permission). Rares you see on Forever are saved by themselves, with where you were. The vanilla 1.12 list (vmangos) is a grey reference that's marked "vanilla data" until someone sees that rare on Forever. If its nameplate isn't rare here, it's marked "not rare here". **Show vanilla rares** off hides the grey ones.
- **Alert when a rare shows**: a raid-warning alert when a rare's nameplate comes into view, once every 5 minutes per rare. It stays quiet while SilverDragon is loaded, so you don't get two alerts, and for mobs already on your key.

## 0.26.1

- Fixed **Show all ranks** not changing the open spell list. Ticking or unticking it now rebuilds the list straight away. Rank and duplicate-name matching also ignores colour codes, spacing and capitals.
- With a macro picked, the Spell row is dimmed and marked "(not used)", with a note that the macro always wins. Set Macro to None to use the spell again.

## 0.26.0

- No more "key press didn't cast" lines in chat (out of range, not ready, another action in progress). The game's red text already says it. A line-of-sight error still makes the key look past that mob for a few seconds.
- Attack options: **Choose spell** lists your spellbook with icons and a filter box. **Show all ranks** off gives one line per spell, cast at your highest rank. On lists each rank, so you can pick a lower one. Dragging a spell onto the icon still works.
- Attack options: **Choose macro** lists your saved macros (/m) in place of the typed macro box. The key reads the macro each time it's rebuilt, so edits in /m apply without coming back here. If the macro is deleted or empty, the spell is used.
- A typed attack macro from an older version is kept in the saved file (attack.oldMacro) but no longer used. Chat says so once.

## 0.25.3

- The minimap button's tooltip shows only how to use it (click to open, drag to move). The list of mobs and their status is gone.

## 0.25.2

- Fixed the key letting go of the right mob and grabbing it again while you spam. After a "line of sight" error the target could lose to its own nameplate (the client can't always say the two are the same mob), so the key cleared it and re-targeted it. A target now only gives way to a different, higher-priority mob, never to itself or another mob of the same name.
- A dead-or-alive check the client won't answer for a moment no longer drops the key off the mob.
- Adding or clearing a target re-checks your current target instead of resetting the key to searching.

## 0.25.1

- A mob a search found shows "(found by "bhag")" and a **Lock in** button. Lock in keeps that mob as a normal target and removes the search, along with anything else the search added.

## 0.25.0

- The Auto Quest box has a **Show targets** button. It opens a list of the quest mobs Auto Quest is looking for, in the key's order, with progress, the quest, and whether each was seen nearby. Mobs past what fits in the key's macro are greyed out.

## 0.24.0

- Typed names can be part of a name. A name the addon already knows (nearby, quests, history, Recent) is matched ignoring capitals and stored as the game spells it, so "young panther" becomes Young Panther.
- Anything else becomes a search: every mob seen nearby whose name contains the text is added as its own target, under the search. Clearing one of those makes the search skip that name. If the full name turns up with different capitals, the search just becomes that mob.

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
