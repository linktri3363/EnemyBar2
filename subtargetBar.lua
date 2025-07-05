--[[
Legacy Subtarget Bar File - DEPRECATED
This file is maintained for backwards compatibility only.
All functionality has been moved to the main bars.lua system.

Version 2.2 - Compatibility Layer
--]]

-- Legacy compatibility notice
windower.add_to_chat(123, 'WARNING: subtargetBar.lua is deprecated. Functionality moved to bars.lua')

-- Legacy function (maintained for compatibility - no longer functional)
function render_subtarget_bar(...)
    -- Legacy function notification
    windower.add_to_chat(123, 'Legacy function render_subtarget_bar() called')
    windower.add_to_chat(207, 'EnemyBar v2.2: Subtarget rendering now handled by enhanced bars.lua system')
    
    -- This function no longer performs any rendering
    -- All subtarget bar functionality has been moved to:
    -- - bars.lua for UI rendering and management
    -- - enemybar2.lua for update logic and state management
    -- - actionTracking.lua for data processing and threat calculation
    
    -- Legacy behavior simulation (for compatibility)
    if visible == true then
        local subtarget = windower.ffxi.get_mob_by_target('st')
        
        if subtarget ~= nil then
            -- Log that subtarget was detected (for debugging legacy integration)
            windower.add_to_chat(207, 'Legacy: Subtarget detected - ' .. (subtarget.name or 'Unknown'))
            windower.add_to_chat(207, 'New system handles this automatically via bars.lua')
        end
    end
    
    return false
end

-- Legacy compatibility functions (placeholders)
function legacy_subtarget_update()
    -- Placeholder for any old code that might call this
    return
end

function legacy_subtarget_hide()
    -- Placeholder for any old code that might call this
    return
end

function legacy_subtarget_show()
    -- Placeholder for any old code that might call this
    return
end

-- Legacy variables (maintained for compatibility)
local legacy_subtarget_visible = false
local legacy_subtarget_width = 198
local legacy_subtarget_height = 12

-- Migration guidance
windower.add_to_chat(207, 'EnemyBar v2.2: Legacy subtargetBar.lua loaded for compatibility.')
windower.add_to_chat(207, 'All subtarget bar functionality is now integrated into the main system.')
windower.add_to_chat(207, 'New features for subtarget bar:')
windower.add_to_chat(207, '  • HP prediction with death countdown')
windower.add_to_chat(207, '  • Enhanced threat level indicators')
windower.add_to_chat(207, '  • Action alerts for dangerous abilities')
windower.add_to_chat(207, '  • Improved status effect icons')
windower.add_to_chat(207, '  • Kill timer integration')
windower.add_to_chat(207, 'Configure with: //eb set [setting] subtarget [value]')