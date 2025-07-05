--[[
Legacy Target Bar File - DEPRECATED
This file is maintained for backwards compatibility only.
All functionality has been moved to the main bars.lua system.

Version 2.2 - Compatibility Layer
--]]

-- Legacy compatibility notice
windower.add_to_chat(123, 'WARNING: targetBar.lua is deprecated. Functionality moved to bars.lua')

-- Legacy function (maintained for compatibility - no longer functional)
function render_target_bar(...)
    -- Legacy function notification
    windower.add_to_chat(123, 'Legacy function render_target_bar() called')
    windower.add_to_chat(207, 'EnemyBar v2.2: Target rendering now handled by enhanced bars.lua system')
    windower.add_to_chat(207, 'Use //eb setup to configure positioning with the new drag-and-drop system')
    
    -- This function no longer performs any rendering
    -- All target bar functionality has been moved to:
    -- - bars.lua for UI rendering
    -- - enemybar2.lua for logic and updates
    -- - actionTracking.lua for data management
    
    return false
end

-- Legacy compatibility wrapper (does nothing)
function legacy_target_update()
    -- Placeholder for any old code that might call this
    return
end

-- Migration guidance
windower.add_to_chat(207, 'EnemyBar v2.2: Legacy targetBar.lua loaded for compatibility.')
windower.add_to_chat(207, 'All target bar rendering is now handled by the new modular system.')
windower.add_to_chat(207, 'Benefits of the new system:')
windower.add_to_chat(207, '  • Better performance with throttled updates')
windower.add_to_chat(207, '  • Enhanced error handling and stability')
windower.add_to_chat(207, '  • Improved visual effects and alerts')
windower.add_to_chat(207, '  • Memory leak prevention')
windower.add_to_chat(207, '  • Drag-and-drop positioning')
windower.add_to_chat(207, 'Use //eb help for new commands and features.')