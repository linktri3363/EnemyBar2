# EnemyBar Enhanced v2.5

An advanced enemy tracking and threat management addon for Final Fantasy XI (Windower).

## Overview

EnemyBar Enhanced provides comprehensive enemy tracking with HP prediction, smart aggro filtering, action alerts, and job-specific profiles. This version features significant performance optimizations, improved error handling, and a modular architecture.

## Features

### Core Features
- **Target/Subtarget/Focus Target Bars** - Visual HP bars with enhanced information
- **Smart Aggro List** - Intelligent threat-based enemy filtering 
- **HP Prediction System** - Death countdown timers based on damage trends
- **Action Alert System** - Visual/audio warnings for dangerous enemy abilities
- **Kill Timer** - Track time since last kill with chain saver functionality
- **Job-Specific Profiles** - Auto-switching configurations optimized per job
- **Limbus Chest Tracker** - Tracks the four treasure chests in Apollyon and Temenos (formerly the LimbusHelper addon)
- **TargetInfo** - Target's ID, hex ID and movement speed (formerly the TargetInfo addon)
- **Debuff Icons** - Your party's debuffs on the target, as icons with timers on the target bar (formerly the Debuffing addon)

### Enhanced Tracking
- **Threat Scoring** - Advanced algorithm considering distance, HP, enmity, and debuffs
- **Party Integration** - Tracks party/alliance member aggro and pets
- **Status Effects** - Visual indicators for sleep, bind, petrify, terror
- **Memory Management** - Automatic cleanup and optimization
- **Error Handling** - Robust error recovery and logging

## Installation

1. Place all files in your Windower addons directory:
   ```
   Windower4/addons/enemybar2/
   ```

2. Required files:
   - `enemybar2.lua` - Main addon file
   - `actionTracking.lua` - Action and threat tracking
   - `bars.lua` - UI rendering system
   - `limbus.lua` - Limbus chest tracker
   - `targetinfo.lua` - Target ID / hex ID / speed
   - `debuffs.lua`, `debuffs_bluemagic.lua` - Debuff tracking and icons
   - `icons/buffs/` - Status effect icons
   - `settings.xml` - Configuration file
   - Image assets (bg_cap.png, bg_body.png, fg_body.png, etc.)

3. Load the addon:
   ```
   //lua load enemybar2
   ```

## Commands

### Profile Management
```
//eb profile list                    - Show available profiles
//eb profile tank/healer/dps/support - Apply specific profile  
//eb profile auto [on/off]           - Toggle auto profile switching
```

### Target Management
```
//eb focustarget [name/clear]        - Set/clear focus target
//eb focustarget                     - Set current target as focus
```

### Kill Timer
```
//eb killtimer [toggle]              - Toggle kill timer display
//eb killtimer reset                 - Reset kill timer
//eb killtimer chainsaver [toggle]   - Toggle chain saver
//eb killtimer chainsaver ws [name]  - Set chain saver weapon skill
//eb killtimer status                - Show current settings
```

### Action Alerts
```
//eb alert [toggle]                  - Toggle alert system
//eb alert sounds [on/off]           - Toggle alert sounds
//eb alert duration [seconds]        - Set alert duration
//eb alert emphasize add [ability]   - Add emphasized ability
//eb alert emphasize remove [ability] - Remove emphasized ability
//eb alert emphasize list            - List emphasized abilities
//eb alert test [ws/magic/critical]  - Test alert system
//eb alert status                    - Show alert settings
```

### Configuration
```
//eb set <setting> <bar> <value>     - Change a bar setting (saved). //eb set alone lists settings
//eb setup                           - Toggle setup mode (drag bars)
//eb tracking [party/alliance/pets/outside] [on/off] - Aggro tracking scope
```

`<bar>` is `target`/`t`, `subtarget`/`st`, `focustarget`/`ft`, `aggro`/`a`, or `all`.

| Setting | Value | Notes |
| --- | --- | --- |
| `show` | on/off/toggle | Show or hide the bar |
| `show_dist` (`dist`), `show_action` (`action`), `show_target` (`target`), `show_target_icon` (`icon`), `show_debuff` (`debuff`), `show_prediction` (`prediction`), `show_kill_timer` (`killtimer`), `show_alerts` (`alerts`) | on/off/toggle | Optional parts of the bar |
| `width`, `font_size` (`size`) | number | |
| `x`, `y` | number | Screen position |
| `font` | font name | |
| `color` | R G B [alpha] | 0-255 each, e.g. `//eb set color t 255 0 0` |
| `count`, `stack_padding` (`padding`), `stack_dir` (`dir`) | number / up or down | Aggro bars only |

Examples: `//eb set dist t on`, `//eb set width aggro 400`, `//eb set count a 4`.
With auto profile switching on, changing jobs can overwrite these (`//eb profile auto off` to keep them).

### Utility
```
//eb help                            - Show command help
//eb demo                            - Toggle demo mode
```

### Limbus Chest Tracker
`//eb lh` and `//eb limbus` both work.
```
//eb lh reset [apollyon/temenos/all]  - Reset tracking (no argument: current zone, or both outside Limbus)
//eb lh sector <sector>               - Toggle a sector between Opened and Unopened
//eb lh sector <sector> <3000/5000>   - Log a chest result by hand (5000 logs a bonus)
//eb lh show / hide / toggle          - Show both zones outside Limbus
//eb lh on / off                      - Enable or disable the module
//eb lh pos                           - Print position, detected sector and distance to its chest
//eb lh debug                         - Echo incoming text in Limbus (troubleshooting)
//eb lh help                          - Show Limbus commands
```

### TargetInfo
`//eb ti` and `//eb targetinfo` both work.
```
//eb ti on / off          - Enable or disable the module
//eb ti id [on/off]       - Full ID line
//eb ti hex [on/off]      - Hex ID line
//eb ti speed [on/off]    - Movement speed line
//eb ti name [on/off]     - Claim / target name line (off by default)
//eb ti help              - Show TargetInfo commands
```

### Debuffs
`//eb df`, `//eb debuffs` and `//eb debuffing` all work.
```
//eb df on / off                      - Show or hide the debuff icons
//eb df timer [on/off]                - Timers under the icons
//eb df th [on/off]                   - Treasure Hunter level next to the icons
//eb df size <12-40>                  - Icon size (default 20)
//eb df max <1-20>                    - Most icons shown (default 10)
//eb df anchor left|right             - Which end of the bar the icons start from (default left)
//eb df x <pixels>                    - Distance from that end (or drag the icons in //eb setup)
//eb df y <pixels>                    - Nudge the icons up (-) or down (+)
//eb df details [on/off]              - Details panel (Helix, Kaustra, elemental damage, shots)
//eb df shots [on/off]                - Include elemental shots in the details panel
//eb df keep_buff [on/off]            - Keep expired debuffs with a +seconds counter
//eb df auto [on/off]                 - Auto-learn real durations (also turns keep_buff on/off)
//eb df auto_profiles [on/off]        - Per-main-job duration profiles
//eb df {Spell Name}|ID <secs|remove> - Set or remove a duration override
//eb df save|load|delete <name>, list - Duration profiles
//eb df reset                         - Remove all duration overrides
//eb df test {Spell}|ID [damage] [remove] - Simulate a debuff (damage for Helix/Kaustra)
//eb df test clear                    - Remove simulated debuffs
//eb df clear                         - Wipe all tracked debuffs
```

## Debuff Icons

Tracks the debuffs your party and pets land on enemies (spells, blue magic, absorbs, steps,
blood pacts, Angon/Tomahawk-type abilities) and shows the ones on your current target as
status icons on the target bar:

- The icons start from an anchor point on the bar. With the default left anchor, the newest
  debuff sits at the anchor and older ones shift right (`anchor right` mirrors this).
- A timer under each icon counts down in seconds and turns orange in the last 10 seconds.
  With `keep_buff` on, an expired debuff stays with a green `+seconds` overtime counter until
  the game says it wore off, which is how real durations are learned.
- Step debuffs show the daze icon for their current level.
- The Treasure Hunter level (e.g. `TH4`) appears just past the end of the icon row.
- Debuffs clear when they wear off, when the mob dies or despawns, and when Erase-type
  abilities remove them; sleep, petrify and terror clear when the mob acts.

The icons follow the target bar wherever you drag it. In `//eb setup`, sample icons appear on
the target bar; drag them to slide the row along the bar (they only move sideways and stay
within the bar). `x`, `y` and `size` fine-tune them.

### Details panel
Things an icon can't show appear in a separate text panel, hidden whenever there's nothing to show:

- **Helix**: damage and remaining tocks, in the element's color (e.g. `Ionohelix II 3.2k · 4 tocks`)
- **Kaustra**: damage and remaining ticks
- **Elemental damage bonuses**: e.g. `Fire Damage +15% · 42s`, climbing as it stacks
- **Elemental shots**: which shot enhanced which debuff (e.g. `Burn: Fire Shot x2`)

It uses the same outlined text as the other modules, matches the target bar's font size by
default, and is dragged separately in `//eb setup`. Settings live under `debuff_details` in
`data/settings.xml` (`pos`, `font`, `font_size`, `show`, `show_shots`).

Learned durations and profiles are saved in `data/debuff_durations.xml` and
`data/debuff_profiles.xml`. On first load these are imported from the Debuffing addon's
`data/` folder if it's installed. Settings live under `debuffs` in `data/settings.xml`.

If you used the standalone Debuffing addon, unload it (`//lua unload debuffing`) and remove it from
`scripts/init.txt`.

## TargetInfo

Shows memory information for your subtarget, or your target if you have no subtarget,
in EB2's bold outlined text:

- **ID**: The full ID, which includes zone information and mob category
- **Hex ID**: The mob's index in hex, the ID usually used for NM placeholders
- **Speed**: Deviation from normal movement speed, green when faster (+x%), red when slower (-x%)
- **Claim / Target** (optional): who has claim on the mob, or who it's targeting

It hides when you have no target. Drag it in `//eb setup` like the other bars; its position is saved.
Settings (`targetinfo_bar` in `data/settings.xml`): `pos`, `font`, `font_size`, `show`,
`show_full_id`, `show_hex_id`, `show_speed`, `show_target_name`. `font_size` 0 (the default)
matches the target bar's font size and follows it if that changes.

If you used the standalone TargetInfo addon, unload it (`//lua unload targetinfo`) and remove it from
`scripts/init.txt`.

## Limbus Chest Tracker

Each zone in Limbus has four treasure-chest sectors. Opening a chest gives either the
standard reward (3,000 units) or the bonus reward (5,000 units). The tracker shows which
sectors you've opened, highlights the bonus, and resets the zone 5 seconds after a bonus so
you can start looking for the next one.

- **Sectors**: Apollyon `NW NE SW SE`, Temenos `N W E C`
- **Automatic detection**: Reads the "Acquired ... Units" message and works out the sector from
  the nearest chest. Rewards from anything that isn't near a chest (such as a ???) are ignored,
  and so are lines typed in player chat.
- **Display**: One line per sector in EB2's bold, outlined text
  - Red: Unopened
  - Green: Opened
  - Gold "BONUS!": the bonus chest, shown for the 5 seconds before the zone resets
- **Visibility**: Shows automatically in Apollyon and Temenos. `//eb lh show` (or `toggle`) also shows
  both zones everywhere else; `//eb lh hide` turns that off again.
- **Moving it**: `//eb setup` shows a sample of the module; drag it anywhere like the other bars
  (hold Ctrl to snap to a 10-pixel grid). Its position is saved.
- **Saved progress**: Per character in `data/limbus_<CharName>.xml`, so several characters running at
  once never overwrite each other. A reset interrupted by a reload or crash finishes on the next load.
- **Settings** (`limbus_bar` in `data/settings.xml`): `pos`, `font`, `font_size`,
  `row_spacing`, `show`, `show_anywhere`

If you previously used the standalone LimbusHelper addon, unload it (`//lua unload limbushelper`) and
remove it from `scripts/init.txt` so the two don't both draw an overlay.

## Job Profiles

### Tank Profile (PLD, NIN, RUN)
- **Focus**: Threat management and party protection
- **Features**: Enhanced enmity tracking, action alerts, expanded aggro list
- **Optimized for**: Maintaining aggro, monitoring dangerous abilities

### Healer Profile (WHM, RDM, SCH, GEO)  
- **Focus**: Party safety and dangerous enemy actions
- **Features**: Prominent action alerts, kill timer, reduced clutter
- **Optimized for**: Healing timing, emergency response

### DPS Profile (WAR, MNK, THF, DRK, BST, RNG, SAM, DRG, BLM, SMN, BLU, PUP, DNC)
- **Focus**: Target efficiency and damage optimization
- **Features**: Kill timer, chain saver, death prediction, debuff tracking
- **Optimized for**: Target switching, skill chain timing

### Support Profile (BRD, COR, GEO, RDM)
- **Focus**: Maximum battlefield awareness
- **Features**: All tracking enabled, comprehensive aggro list
- **Optimized for**: Party support, crowd control, buff management

## Bar Configuration

### Target Bar
- Shows current target information
- HP prediction with death countdown
- Action alerts for dangerous abilities
- Configurable size, position, and display options

### Subtarget Bar  
- Displays subtarget information
- Integrated with threat tracking
- Smaller, streamlined interface

### Focus Target Bar
- Persistent tracking of chosen target
- Useful for monitoring specific enemies
- Independent of current target selection

### Aggro Bars
- Smart filtered list of threatening enemies
- Threat-based sorting and display
- Configurable count and stacking direction

## Tracking Settings

### Party Tracking
Each option takes `on`/`off`, or toggles with no value. Settings are saved.
```
//eb tracking            - Show current tracking settings
//eb tracking party      - Party/alliance only (the opposite of outside)
//eb tracking alliance   - Include alliance parties 2 and 3
//eb tracking pets       - Include party members' pets
//eb tracking outside    - Include mobs on players outside your party/alliance
```

By default EB2 tracks your party, alliance and pets, and ignores mobs on outside players.
With `outside` on, those mobs appear on the aggro list at a lower priority than mobs on your party.

## Technical Features

### Performance Optimizations
- **Throttled Updates**: 10 FPS update rate vs continuous
- **Position Caching**: Reduces distance calculations
- **Memory Limits**: Automatic cleanup of old data
- **Batch Processing**: Grouped UI updates

### Error Handling
- Graceful packet parsing failures
- Protected function calls with error logging
- Automatic recovery from UI errors
- Memory leak prevention

### Architecture
- **Modular Design**: Separated concerns (UI, logic, data)
- **Event-Driven**: Efficient packet and game event handling
- **Configurable**: Extensive customization options
- **Backwards Compatible**: Legacy file support

## Troubleshooting

### Common Issues

**Bars not showing:**
- Check if addon is loaded: `//addon list`
- Verify you're not in a cutscene
- Try toggling setup mode: `//eb setup`

**Performance issues:**
- Reduce aggro bar count: `//eb set count aggro [number]`
- Disable unused features in profile settings

**Tracking problems:**
- Verify party tracking settings: `//eb tracking`
- Check if you're in a party/alliance
- Reset tracked data: zone change or relog

### Debug Commands
```
//eb demo              - Test with sample data
//eb alert test        - Test alert system  
//eb killtimer status  - Check timer state
```

## File Structure

```
enemybar2/
├── enemybar2.lua          - Main addon controller
├── actionTracking.lua     - Threat and action tracking
├── bars.lua              - UI rendering system  
├── limbus.lua            - Limbus chest tracker
├── targetinfo.lua        - Target ID / hex ID / speed
├── debuffs.lua           - Debuff tracking and icons
├── debuffs_bluemagic.lua - Blue magic data for debuff tracking
├── icons/buffs/          - Status effect icons (<buff id>.png)
├── licenses/             - Licenses of incorporated addons
├── settings.xml          - User configuration
├── gui_settings.lua      - Legacy compatibility
├── subtargetBar.lua      - Legacy compatibility  
├── targetBar.lua         - Legacy compatibility
└── icons/               - Status effect icons
    ├── sleep.png
    ├── bound.png
    ├── petrified.png
    └── terror.png
```

## Version History

### v2.5 (Current)
- Added debuff icons with timers on the target bar (tracking ported from the Debuffing addon)
- Icons anchor to either end of the bar and slide sideways in setup mode
- Details panel for Helix/Kaustra damage, elemental damage bonuses and elemental shots

### v2.4
- Added the TargetInfo module (based on Arcon's TargetInfo addon), with its own draggable position

### v2.3
- `//eb set` now actually changes bar settings (it previously only redrew the bars)
- `//eb tracking` options now take effect and are saved; added `pets`
- Added the Limbus chest tracker module (ported from LimbusHelper v1.06): text-only, with its own draggable position

### v2.2
- Performance optimizations and memory management
- Enhanced error handling and stability  
- Modular architecture refactor
- Improved action alert system
- Better party/alliance tracking

### Previous Versions
- v2.1: Added job profiles and smart filtering
- v2.0: Introduced HP prediction and kill timer
- v1.x: Basic enemy bar functionality

## Credits

**Original Authors**: Mmckee, Akaden, Twisted, Linktri  
**Enhanced Version**: Claude (AI Assistant)  
**Limbus module**: Based on LimbusHelper by Kaius @ Bahamut and Linktri @ Asura  
**TargetInfo module**: Based on TargetInfo by Arcon (Copyright © 2013-2017, Windower; BSD 3-clause license)  
**Debuffs module**: Tracking from Debuffing (Xathe's Debuffed, Auk's Debuffing, Nsane's overhaul, maintained by Linktri; BSD 3-clause, see `licenses/Debuffing-LICENSE.txt`)  
**Status icons**: From XivParty's assets, which credit KenshiDRK's partybuffs  
**Framework**: Windower 4 for Final Fantasy XI

## License

This addon is provided as-is for the FFXI community. Use at your own discretion.

## Support

For issues or feature requests, refer to the Windower community forums or FFXI addon development communities.

---

*EnemyBar Enhanced v2.5 - Bringing modern performance and features to classic FFXI enemy tracking.*
