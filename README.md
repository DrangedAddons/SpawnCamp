# SpawnCamp

WoW Forever addon for camping a mob: one key to tag it or talk to it, automatic chat and quest steps, and a respawn timer built from the kills it has seen.

`/spawncamp` (or `/spc`) opens the window. Target the mob and press **Add my target**, or type its exact name.

## Attack mode: getting the tag

Pick an instant spell (drag it from your spellbook onto the Spell box) and set a key. The key runs:

```
/cleartarget
/targetexact <mob>
/cast [@target,harm,nodead] <spell>
/startattack [@target,harm,nodead]
```

Spam the key while you wait. When the mob isn't there you end up with no target, so it never casts on anything else. When it spawns, the first press that lands targets it and casts.

The game requires a real keypress for every target and cast. SpawnCamp doesn't press anything for you and never will.

When the mob dies with your tag, SpawnCamp alerts you, unticks **Still hunting** and frees the key.

## Interact mode: NPCs, quests and chat

- **Target by name**: targets the NPC, then interacts with it.
- **Mouseover**: interacts with the NPC under your mouse.
- **Nearest**: the key becomes the game's Interact key. With soft-target interact on (there's a button for it) this also works on objects you can't target, such as chests and quest items.

Once a watched NPC's window opens, SpawnCamp hands in finished quests, takes available ones, accepts follow-ups, and picks chat options that match your list (one text fragment per line, in order). With **Pick the chat option when there's only one** ticked it also clicks through single-option pages. Hold **Shift** while interacting to handle a window yourself.

## Respawn timer

SpawnCamp logs a **death** when it sees a watched mob dead and a **spawn** when it sees a new one alive. It checks nameplates, your target and your mouseover several times a second. Each death followed by a spawn gives a respawn time. The window shows the earliest, average and latest. The timer list counts down to the earliest and says when the window is open or overdue.

- **Respawn alarm** goes off a set number of seconds before the earliest respawn, and again when the window opens.
- **Alert when it spawns** goes off when it's seen alive (by you, or by another SpawnCamp user if sharing is on).
- **It died now** / **It's up now** log a sighting by hand. Use them when you saw something the addon missed.
- **Respawn time (min) ... to ...** sets a known respawn time and overrides the history.
- Delete a bad entry with the red **x** in the history.

Limits:

- The addon only knows what it or other SpawnCamp users saw. A mob found already dead is logged with a **+** ("died at least this long ago"), and its respawn time counts as a lower bound.
- Nameplates only show nearby mobs, so camp within nameplate range.
- History is per realm and shared across your characters. Keys, spells and settings are per character.

## Sharing

With **Share sightings with group/guild** on, deaths and spawns you see go to party/raid and guild members running SpawnCamp. Theirs get logged for mobs you watch.

## Commands

- `/spawncamp`: open the window
- `/spawncamp add [name]`: watch your target, or a mob by name
- `/spawncamp died [name]` / `up [name]`: log a sighting now
- `/spawncamp timers`: show or hide the timer list
- `/spawncamp debug`: print what the addon can read from your target (for bug reports)
