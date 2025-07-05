# EnemyBar Enhanced v2.2

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
//eb set [setting] [bar] [value]     - Configure bar settings
//eb setup                           - Toggle setup mode (drag bars)
//eb tracking [party/alliance/outside] - Configure tracking settings
```

### Utility
```
//eb help                            - Show command help
//eb demo                            - Toggle demo mode
```

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
```
//eb tracking party    - Toggle party-only tracking
//eb tracking alliance - Toggle alliance member tracking  
//eb tracking outside  - Toggle non-party player tracking
```

Default behavior tracks party/alliance members only to reduce noise.

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

### v2.2 (Current)
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
**Framework**: Windower 4 for Final Fantasy XI

## License

This addon is provided as-is for the FFXI community. Use at your own discretion.

## Support

For issues or feature requests, refer to the Windower community forums or FFXI addon development communities.

---

*EnemyBar Enhanced v2.2 - Bringing modern performance and features to classic FFXI enemy tracking.*
