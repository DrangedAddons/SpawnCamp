# SpawnCamp

WoW Forever addon for camping a mob: one key to tag it or talk to it (chat, quest hand-ins and accepts), and a respawn timer built from the kills it has seen.

## The window

```
SpawnCamp                                                [gear] [x]
Key [ F ] [Unassign]                        Attacks Mechanized Sentry.
[ type or paste a mob name ] [Add] [My Target] [Nearby]
+--------------------------------------------------------------------+
| (portrait) Mechanized Sentry               [SWORD] [BUBBLE] [Clear] |
|            dead 2:05, due in 2:55                                   |
+--------------------------------------------------------------------+
Recent ----------------------------------------------------------------
(p) Other Mob        up, seen 0:12 ago                              x
```

- **Key**: your one SpawnCamp key, right on the front. Click it and press a key to assign or change it; **Unassign** removes it. It only does something while you have a **target** selected.
- **Target**: the mob your key works on. Set it by typing or pasting a name (**Add** or Enter), with **My Target** (your in-game target), or with **Use** in the **Nearby** list. **Clear** unsets it: the key then does nothing and goes back to its normal binding.
- **Sword / bubble**: big square buttons, one always pressed. The sword means your key targets the mob and casts your attack spell. The bubble means it targets the NPC and talks to it: chat, quest hand-ins, new and follow-up quests. Clicking the pressed one does nothing; clicking the other swaps them. **Right-click the sword** to set the spell or your own macro lines. **Right-click the bubble** for the chat and quest options.
- **Recent**: mobs you've targeted before, newest first, each with its timer. Click one to make it the target again; right-click it for its respawn log. **x** removes it.
- **Respawn log**: click the target's name, or right-click a Recent mob. It opens beside the window with respawn times, full history, alarms and the manual "it died / it's up" buttons.
- **Portrait**: the mob's real portrait once it has been seen (targeted, on a nameplate, moused over). Before that, an icon for its creature type (beast, humanoid, undead...), or a sword or scroll if that isn't known yet.
- **Gear**: sharing with **Party**, **Raid** and **Guild**, whether to show mobs you've already killed in Recent, sound, lock window.

Hostile mobs start on the sword and friendly ones on the bubble.

The game requires a real keypress for every target, cast and interact. SpawnCamp doesn't press anything for you and never will.

### What the key runs

```
/cleartarget
/targetexact Mechanized Sentry
/cast [@target,harm,nodead] <spell>        (sword)
/startattack [@target,harm,nodead]         (sword)
/click [help,nodead] SpawnCampInteract     (bubble)
```

If the mob isn't there you end up with no target, so nothing lands on anything else.

### Bubble options (right-click the bubble)

- **Hand in and accept quests** and **Click through chat**: both on by default. With several chat options it picks one matching your **Prefer** list, otherwise the first.
- **Quest reward**: which reward to take when a quest offers a choice. 1 (the default) = first. Empty = you pick.
- Hold **Shift** while talking to do a window yourself.
## Respawn timer

The timer starts when the mob dies and stops when it's seen alive again. That time is the respawn. The line shows `dead 2:05` while it's down (with `due in` once there's history), then `UP, respawned after 4:51`. The log shows the earliest, average and latest respawn.

**Where deaths and spawns come from.** You don't need to be in combat with the mob. (Forever doesn't let addons read the combat log, so there's no zone-wide death feed.)

- **Nameplates, your target, your mouseover**, read a few times a second. A watched mob seen dead is a death and seen alive is a spawn. Nameplates only cover mobs near you, so camp within nameplate range and turn enemy nameplates on (V).
- **Your key**: a target right after pressing it is your mob, and SpawnCamp follows it until it dies or leaves range.
- **Other SpawnCamp users** in your party, raid or guild (if sharing is on).
- **Manual**: "It died now" / "It's up now" in the log.

A mob first found already dead is logged with a **+** ("died at least this long ago"), since the real time of death isn't known.

Other alerts:

- **Respawn alarm**: goes off a set time before the earliest respawn, and again when the window opens.
- **Alert when it spawns**: goes off when it's seen alive.
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
