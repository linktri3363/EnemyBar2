-- Enhanced Bars System with Optimizations and Error Handling
-- Version 2.2 - Performance Optimized and SYNTAX FIXED

-- Required libraries
local images = require('images')
local texts = require('texts')

-- Constants
local BAR_HEIGHT = 12
local FONT_SIZE_MULTIPLIER = 0.8
local ALERT_FADE_DURATION = 0.5
local UPDATE_INTERVAL = 0.1

-- Bar system module
bars = {
    x_res = windower.get_windower_settings().ui_x_res,
    y_res = windower.get_windower_settings().ui_y_res,
    update_batch = {},
    last_batch_update = 0
}

-- Create new bar with enhanced error handling
function bars.new(bar_settings)
    if not bar_settings then
        windower.add_to_chat(123, 'Bars: Cannot create bar - missing settings')
        return nil
    end
    
    local success, result = pcall(function()
        local bar = {
            -- Core properties
            width = bar_settings.width or 300,
            color = bar_settings.color or {alpha=255, red=255, green=255, blue=255},
            font = bar_settings.font or 'Arial',
            font_size = bar_settings.font_size or 12,
            
            -- Display flags
            show_dist = bar_settings.show_dist or false,
            show_target = bar_settings.show_target or false,
            show_target_icon = bar_settings.show_target_icon or false,
            show_action = bar_settings.show_action or false,
            show_debuff = bar_settings.show_debuff or false,
            show_prediction = bar_settings.show_prediction or true,
            show_kill_timer = bar_settings.show_kill_timer or false,
            show_alerts = bar_settings.show_alerts or true,
            
            -- State tracking
            last_update = 0,
            alert_flash_time = 0,
            is_visible = false,
            x = 0,
            y = 0
        }
        
        bars.initialize(bar)
        bars.move(bar, bar_settings.pos.x or 0, bar_settings.pos.y or 0)
        return bar
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error creating bar - ' .. tostring(result))
        return nil
    end
    
    return result
end

-- Destroy bar and cleanup resources
function bars.destroy(bar)
    if not bar then return end
    
    local success, err = pcall(function()
        -- Destroy all UI elements
        local elements = {
            'target_indicator_image', 'left_cap_image', 'background_body_image',
            'foreground_body_image', 'right_cap_image', 'name_text', 'action_text',
            'attention_arrow_image', 'target_name_text', 'distance_text',
            'target_status_image', 'prediction_text', 'threat_indicator_image',
            'kill_timer_text', 'chain_saver_indicator', 'alert_overlay',
            'alert_text', 'critical_flash'
        }
        
        for _, element in ipairs(elements) do
            if bar[element] and bar[element].destroy then
                bar[element]:destroy()
            end
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error destroying bar - ' .. tostring(err))
    end
end

-- Initialize bar UI elements
function bars.initialize(bar)
    if not bar then return end
    
    local success, err = pcall(function()
        -- Target indicator
        bar.target_indicator_image = images.new({
            pos = {x=0, y=0},
            visible = false,
            color = {alpha=bar.color.alpha, red=255, green=50, blue=50},
            size = {width=BAR_HEIGHT, height=BAR_HEIGHT},
            texture = {path=windower.addon_path.. 'target.png', fit=true},
            repeatable = {x=1, y=1},
            draggable = false
        })
        
        -- Background elements
        bar.left_cap_image = bars.createCapImage(bar, true)
        bar.right_cap_image = bars.createCapImage(bar, false)
        bar.background_body_image = bars.createBodyImage(bar, true)
        bar.foreground_body_image = bars.createBodyImage(bar, false)
        
        -- Text elements
        bar.name_text = bars.createNameText(bar)
        bar.action_text = bars.createActionText(bar)
        bar.target_name_text = bars.createTargetNameText(bar)
        bar.distance_text = bars.createDistanceText(bar)
        bar.prediction_text = bars.createPredictionText(bar)
        bar.kill_timer_text = bars.createKillTimerText(bar)
        bar.alert_text = bars.createAlertText(bar)
        
        -- Status and effect images
        bar.attention_arrow_image = bars.createAttentionArrow(bar)
        bar.target_status_image = bars.createStatusImage(bar)
        bar.threat_indicator_image = bars.createThreatIndicator(bar)
        bar.chain_saver_indicator = bars.createChainSaverIndicator(bar)
        
        -- Alert overlays
        bar.alert_overlay = bars.createAlertOverlay(bar)
        bar.critical_flash = bars.createCriticalFlash(bar)
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error initializing bar - ' .. tostring(err))
    end
end

-- Helper functions for creating UI elements
function bars.createCapImage(bar, is_left)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {
            alpha = bar.color.alpha,
            red = is_left and bar.color.red or bar.color.red/2,
            green = is_left and bar.color.green or bar.color.green/2,
            blue = is_left and bar.color.blue or bar.color.blue/2
        },
        size = {width=1, height=BAR_HEIGHT},
        texture = {path=windower.addon_path.. 'bg_cap.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createBodyImage(bar, is_background)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {
            alpha = is_background and bar.color.alpha or bar.color.alpha,
            red = bar.color.red,
            green = bar.color.green,
            blue = bar.color.blue
        },
        size = {width=bar.width, height=BAR_HEIGHT},
        texture = {path=windower.addon_path.. (is_background and 'bg_body.png' or 'fg_body.png'), fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createNameText(bar)
    return texts.new('${name|(Name)}: ${hpp|(100)}%', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size,
            font = bar.font,
            stroke = {width=2, alpha=180, red=50, green=50, blue=50}
        },
        flags = {bold=true, draggable=false, italic=false},
        bg = {visible=false}
    })
end

function bars.createActionText(bar)
    return texts.new('${action|(Action)}', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size * FONT_SIZE_MULTIPLIER,
            font = bar.font,
            stroke = {width=2, alpha=180, red=50, green=50, blue=50}
        },
        flags = {bold=true, draggable=false, right=true},
        bg = {visible=false}
    })
end

function bars.createTargetNameText(bar)
    return texts.new('${pc|(Target)}', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size,
            font = bar.font,
            stroke = {width=2, alpha=180, red=50, green=50, blue=50}
        },
        flags = {bold=true, draggable=false},
        bg = {visible=false}
    })
end

function bars.createDistanceText(bar)
    return texts.new('${dist|(0.0)}\'', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size * FONT_SIZE_MULTIPLIER,
            font = bar.font,
            stroke = {width=2, alpha=180, red=50, green=50, blue=50}
        },
        flags = {bold=true, draggable=false, right=true},
        bg = {visible=false}
    })
end

function bars.createPredictionText(bar)
    return texts.new('${time|(0.0s)}', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size * 0.7,
            font = bar.font,
            stroke = {width=2, alpha=180, red=50, green=50, blue=50}
        },
        flags = {bold=true, draggable=false},
        bg = {visible=false}
    })
end

function bars.createKillTimerText(bar)
    return texts.new('${kill_time|Last Kill: 0s}', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size * 0.9,
            font = bar.font,
            stroke = {width=2, alpha=180, red=50, green=50, blue=50}
        },
        flags = {bold=true, draggable=false},
        bg = {visible=false}
    })
end

function bars.createAlertText(bar)
    return texts.new('${alert_action|DANGER}', {
        pos = {x=0, y=0},
        text = {
            size = bar.font_size * 1.1,
            font = bar.font,
            stroke = {width=3, alpha=255, red=0, green=0, blue=0}
        },
        flags = {bold=true, draggable=false},
        bg = {visible=false}
    })
end

function bars.createAttentionArrow(bar)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {alpha=bar.color.alpha, red=bar.color.red, green=bar.color.green, blue=bar.color.blue},
        size = {width=BAR_HEIGHT, height=BAR_HEIGHT},
        texture = {path=windower.addon_path.. 'attention.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createStatusImage(bar)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        size = {width=18, height=BAR_HEIGHT},
        texture = {path=windower.addon_path.. 'icons/sleep.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createThreatIndicator(bar)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {alpha=200, red=255, green=200, blue=50},
        size = {width=4, height=BAR_HEIGHT},
        texture = {path=windower.addon_path.. 'bg_body.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createChainSaverIndicator(bar)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {alpha=150, red=255, green=255, blue=100},
        size = {width=6, height=BAR_HEIGHT},
        texture = {path=windower.addon_path.. 'bg_body.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createAlertOverlay(bar)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {alpha=200, red=255, green=0, blue=0},
        size = {width=bar.width+100, height=50},
        texture = {path=windower.addon_path.. 'bg_body.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

function bars.createCriticalFlash(bar)
    return images.new({
        pos = {x=0, y=0},
        visible = false,
        color = {alpha=255, red=255, green=0, blue=0},
        size = {width=bar.width+20, height=30},
        texture = {path=windower.addon_path.. 'bg_body.png', fit=true},
        repeatable = {x=1, y=1},
        draggable = false
    })
end

-- Move bar to new position
function bars.move(bar, x, y)
    if not bar then return end
    
    local success, err = pcall(function()
        bar.x = x
        bar.y = y
        
        -- Position main elements
        if bar.target_indicator_image then bar.target_indicator_image:pos(x-16, y) end
        if bar.left_cap_image then bar.left_cap_image:pos(x, y) end
        if bar.background_body_image then bar.background_body_image:pos(x+1, y) end
        if bar.foreground_body_image then bar.foreground_body_image:pos(x+1, y) end
        if bar.right_cap_image then bar.right_cap_image:pos(x+1+bar.width, y) end
        
        -- Position text elements
        local text_y_offset = 3 + (14 - bar.font_size) / 4
        if bar.name_text then bar.name_text:pos(x + math.floor(bar.width/100), y + text_y_offset) end
        if bar.action_text then bar.action_text:pos(-(bars.x_res - (x + bar.width - math.floor(bar.width/100))), y - bar.font_size + 2) end
        
        -- Position target elements
        if bar.attention_arrow_image then bar.attention_arrow_image:pos(x + bar.width + 8, y) end
        if bar.target_name_text then bar.target_name_text:pos(x + bar.width + 24, y - math.floor(bar.font_size/2) + 2) end
        if bar.distance_text then bar.distance_text:pos(-(bars.x_res - (x - 20)), y - math.floor(bar.font_size/2) + 4) end
        if bar.target_status_image then bar.target_status_image:pos(x + bar.width + 4, y) end
        
        -- Position enhanced elements
        if bar.prediction_text then bar.prediction_text:pos(x + math.floor(bar.width/2), y - math.floor(bar.font_size/2) - 2) end
        if bar.threat_indicator_image then bar.threat_indicator_image:pos(x - 6, y) end
        if bar.kill_timer_text then bar.kill_timer_text:pos(x - 56, y - math.floor(bar.font_size) - 8) end
        if bar.chain_saver_indicator then bar.chain_saver_indicator:pos(x - 12, y) end
        
        -- Position alert elements
        if bar.alert_overlay then bar.alert_overlay:pos(x - 50, y - 19) end
        if bar.alert_text then bar.alert_text:pos(x + math.floor(bar.width/2) - 30, y + 1) end
        if bar.critical_flash then bar.critical_flash:pos(x - 10, y - 9) end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error moving bar - ' .. tostring(err))
    end
end

-- Show bar with error handling
function bars.show(bar)
    if not bar then return end
    
    local success, err = pcall(function()
        bar.is_visible = true
        
        -- Show core elements
        if bar.left_cap_image then bar.left_cap_image:show() end
        if bar.background_body_image then bar.background_body_image:show() end
        if bar.foreground_body_image then bar.foreground_body_image:show() end
        if bar.right_cap_image then bar.right_cap_image:show() end
        if bar.name_text then bar.name_text:show() end
        
        -- Show optional elements
        if bar.show_dist and bar.distance_text then
            bar.distance_text:show()
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error showing bar - ' .. tostring(err))
    end
end

-- Hide bar with cleanup
function bars.hide(bar)
    if not bar then return end
    
    local success, err = pcall(function()
        bar.is_visible = false
        
        -- Hide all elements
        local elements = {
            'distance_text', 'target_indicator_image', 'left_cap_image',
            'background_body_image', 'foreground_body_image', 'right_cap_image',
            'name_text', 'action_text', 'attention_arrow_image', 'target_name_text',
            'target_status_image', 'prediction_text', 'threat_indicator_image',
            'kill_timer_text', 'chain_saver_indicator', 'alert_overlay',
            'alert_text', 'critical_flash'
        }
        
        for _, element in ipairs(elements) do
            if bar[element] and bar[element].hide then
                bar[element]:hide()
            end
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error hiding bar - ' .. tostring(err))
    end
end

-- Set HP bar value with bounds checking
function bars.set_value(bar, value)
    if not bar or not bar.foreground_body_image or not bar.background_body_image then return end
    
    local success, err = pcall(function()
        -- Clamp value between 0 and 1
        value = math.max(0, math.min(1, value or 0))
        
        local new_width = math.floor(value * bar.width)
        bar.foreground_body_image:width(new_width)
        bar.background_body_image:width(bar.width)
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error setting bar value - ' .. tostring(err))
    end
end

-- Set name text color safely
function bars.set_name_color(bar, color)
    if not bar or not color then return end
    
    local success, err = pcall(function()
        -- Provide default color values
        local r = color.red or 255
        local g = color.green or 255
        local b = color.blue or 255
        
        if bar.name_text then bar.name_text:color(r, g, b) end
        if bar.action_text then bar.action_text:color(r, g, b) end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error setting name color - ' .. tostring(err))
    end
end

-- Update target information with validation
function bars.update_target(bar, name, hpp, dist, target_type, death_prediction, threat_score)
    if not bar then return end
    
    local success, err = pcall(function()
        -- Validate and set name and HP
        if bar.name_text then
            bar.name_text.name = name or "Unknown"
            bar.name_text.hpp = math.max(0, math.min(100, hpp or 0))
        end
        
        -- Set HP bar value
        bars.set_value(bar, (hpp or 0) / 100)

        -- Update distance display
        if bar.distance_text then
            bar.distance_text.dist = string.format('%.1f', dist or 0)
        end

        -- Update target type indicator
        bars.update_target_indicator(bar, target_type)
        
        -- Update death prediction
        bars.update_prediction_display(bar, death_prediction)
        
        -- Update threat indicator
        bars.update_threat_display(bar, threat_score)
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error updating target - ' .. tostring(err))
    end
end

-- Update target type indicator
function bars.update_target_indicator(bar, target_type)
    if not bar or not bar.target_indicator_image or not bar.show_target_icon then return end
    
    if target_type == 1 then
        bar.target_indicator_image:color(255, 100, 100, 255)
        bar.target_indicator_image:show()
    elseif target_type == 2 then
        bar.target_indicator_image:color(100, 100, 255, 255)
        bar.target_indicator_image:show()
    else
        bar.target_indicator_image:hide()
    end
end

-- Update death prediction display
function bars.update_prediction_display(bar, death_prediction)
    if not bar or not bar.prediction_text or not bar.show_prediction then return end
    
    if death_prediction and death_prediction < 60 then
        local time_text = death_prediction < 1 and "<1s" or string.format('%.0fs', death_prediction)
        bar.prediction_text.time = time_text
        
        local pred_color = get_death_prediction_color(death_prediction)
        if pred_color then
            bar.prediction_text:color(pred_color.red, pred_color.green, pred_color.blue)
            bars.set_name_color(bar, pred_color)
        end
        bar.prediction_text:show()
    else
        bar.prediction_text:hide()
    end
end

-- Update threat level indicator
function bars.update_threat_display(bar, threat_score)
    if not bar or not bar.threat_indicator_image then return end
    
    if threat_score and threat_score > 2.0 then
        bar.threat_indicator_image:color(255, 100, 100, 200)
        bar.threat_indicator_image:show()
    elseif threat_score and threat_score > 1.0 then
        bar.threat_indicator_image:color(255, 200, 100, 150)
        bar.threat_indicator_image:show()
    else
        bar.threat_indicator_image:hide()
    end
end

-- Update kill timer display
function bars.update_kill_timer(bar)
    if not bar or not bar.show_kill_timer or not bar.kill_timer_text then 
        if bar.kill_timer_text then bar.kill_timer_text:hide() end
        if bar.chain_saver_indicator then bar.chain_saver_indicator:hide() end
        return 
    end
    
    local success, err = pcall(function()
        local time_since_kill = get_time_since_kill and get_time_since_kill() or nil
        
        if time_since_kill then
            if type(time_since_kill) == "string" then
                bar.kill_timer_text.kill_time = time_since_kill
                bar.kill_timer_text:color(192, 192, 192)
            else
                bar.kill_timer_text.kill_time = string.format("Last Kill: %ds", time_since_kill)
                
                local timer_color = get_kill_timer_color and get_kill_timer_color(time_since_kill)
                if timer_color then
                    bar.kill_timer_text:color(timer_color.red, timer_color.green, timer_color.blue)
                end
                
                -- Chain saver indicator
                if bar.chain_saver_indicator and ActionTracker and ActionTracker.kill_timer then
                    local kt = ActionTracker.kill_timer
                    if kt.chain_saver_enabled and 
                       time_since_kill >= kt.chain_saver_window_start and 
                       time_since_kill <= kt.chain_saver_window_end then
                        bar.chain_saver_indicator:show()
                    else
                        bar.chain_saver_indicator:hide()
                    end
                end
            end
            
            bar.kill_timer_text:show()
        else
            bar.kill_timer_text.kill_time = "Last Kill: --"
            bar.kill_timer_text:color(150, 150, 150)
            bar.kill_timer_text:show()
            if bar.chain_saver_indicator then bar.chain_saver_indicator:hide() end
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error updating kill timer - ' .. tostring(err))
    end
end

-- Enhanced alert display system
function bars.update_alerts(bar, target_id)
    if not bar or not bar.show_alerts then return end
    
    local success, err = pcall(function()
        local current_alert = get_current_alert and get_current_alert() or nil
        
        if not current_alert then
            bars.hide_all_alerts(bar)
            bars.restore_original_colors(bar)
            return
        end
        
        -- Only show alerts for the correct target
        if not bars.should_show_alert(current_alert, target_id) then
            bars.hide_all_alerts(bar)
            return
        end
        
        -- Show alert text
        if bar.alert_text then
            bar.alert_text.alert_action = current_alert.action_name
            bar.alert_text:color(255, 255, 255) -- White text
            bar.alert_text:show()
        end
        
        -- Apply alert-specific styling
        bars.apply_alert_styling(bar, current_alert)
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error updating alerts - ' .. tostring(err))
    end
end

-- Check if alert should be shown for this target
function bars.should_show_alert(current_alert, target_id)
    -- Test alerts (ID 12345) only show on target bar
    if current_alert.actor_id == 12345 then
        local current_target = windower.ffxi.get_mob_by_target('t')
        return current_target and target_id == current_target.id
    end
    
    -- Real alerts only show for the specific enemy
    return current_alert.actor_id == target_id
end

-- Apply alert-specific visual styling
function bars.apply_alert_styling(bar, current_alert)
    if current_alert.is_critical or current_alert.is_emphasized then
        -- Critical alert - red overlay
        if bar.alert_overlay then
            bar.alert_overlay:color(255, 0, 0, 200)
            bar.alert_overlay:show()
        end
    elseif current_alert.alert_type == "magic" then
        -- Magic alert - purple overlay
        if bar.alert_overlay then
            bar.alert_overlay:color(150, 50, 200, 150)
            bar.alert_overlay:show()
        end
        if bar.alert_text then 
            bar.alert_text:color(255, 200, 255) 
        end
    else
        -- Weapon skill alert - orange overlay
        if bar.alert_overlay then
            bar.alert_overlay:color(200, 120, 0, 150)
            bar.alert_overlay:show()
        end
        if bar.alert_text then 
            bar.alert_text:color(255, 255, 150) 
        end
    end
end

-- Hide all alert elements
function bars.hide_all_alerts(bar)
    if bar.alert_overlay then bar.alert_overlay:hide() end
    if bar.alert_text then bar.alert_text:hide() end
    if bar.critical_flash then bar.critical_flash:hide() end
end

-- Restore original bar colors
function bars.restore_original_colors(bar)
    if bar.background_body_image then 
        bar.background_body_image:color(bar.color.red, bar.color.green, bar.color.blue, bar.color.alpha)
    end
    if bar.foreground_body_image then 
        bar.foreground_body_image:color(bar.color.red, bar.color.green, bar.color.blue, bar.color.alpha)
    end
end

-- Update action display with enhanced formatting
function bars.update_action(bar, action_data, debug)
    if not bar or not bar.action_text then return end
    
    local success, err = pcall(function()
        if action_data and bar.show_action then
            local action_name = action_data.ability and 
                               (action_data.ability.name or action_data.ability.en) or "Unknown"
            
            -- Color code dangerous actions
            if action_data.is_dangerous then
                bar.action_text:color(255, 100, 100)
                action_name = "⚠ " .. action_name
            else
                bar.action_text:color(255, 255, 255)
            end
            
            bar.action_text.action = action_name
            bar.action_text:show()
        else
            bar.action_text:hide()
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error updating action - ' .. tostring(err))
    end
end

-- Update enmity display
function bars.update_enmity(bar, name, color)
    if not bar then return end
    
    local success, err = pcall(function()
        if name and bar.show_target then
            if color and bar.attention_arrow_image and bar.target_name_text then
                bar.attention_arrow_image:color(color.red, color.green, color.blue)
                bar.target_name_text:color(color.red, color.green, color.blue)
            end
            if bar.target_name_text then
                bar.target_name_text.pc = name
                bar.target_name_text:show()
            end
            if bar.attention_arrow_image then
                bar.attention_arrow_image:show()
            end
        else
            if bar.target_name_text then bar.target_name_text:hide() end
            if bar.attention_arrow_image then bar.attention_arrow_image:hide() end
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error updating enmity - ' .. tostring(err))
    end
end

-- Update status effect display with priority system
function bars.update_status(bar, status)
    if not bar or not bar.target_status_image or not bar.show_debuff then 
        if bar.target_status_image then bar.target_status_image:hide() end
        return 
    end
    
    local success, err = pcall(function()
        if not status then
            bar.target_status_image:hide()
            return
        end
        
        -- Priority order: Sleep > Petrify > Terror > Bind
        local status_priority = {
            {ids = {2, 19}, icon = 'sleep.png'},
            {ids = {7}, icon = 'petrified.png'},
            {ids = {28}, icon = 'terror.png'},
            {ids = {11}, icon = 'bound.png'}
        }
        
        for _, status_type in ipairs(status_priority) do
            for _, id in ipairs(status_type.ids) do
                if status[id] then
                    bar.target_status_image:path(windower.addon_path.. 'icons/' .. status_type.icon)
                    bar.target_status_image:show()
                    if bar.attention_arrow_image then bar.attention_arrow_image:hide() end
                    if bar.target_name_text then bar.target_name_text:hide() end
                    return
                end
            end
        end
        
        bar.target_status_image:hide()
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Error updating status - ' .. tostring(err))
    end
end

-- Enhanced hover detection
function bars.hover(bar, x, y)
    if not bar then return false end
    
    local success, result = pcall(function()
        local elements = {
            bar.foreground_body_image, bar.background_body_image,
            bar.left_cap_image, bar.right_cap_image,
            bar.distance_text, bar.target_indicator_image,
            bar.name_text, bar.action_text,
            bar.attention_arrow_image, bar.target_name_text,
            bar.target_status_image, bar.prediction_text,
            bar.threat_indicator_image, bar.kill_timer_text,
            bar.chain_saver_indicator, bar.alert_overlay, bar.alert_text
        }
        
        for _, element in ipairs(elements) do
            if element and element.hover and element:hover(x, y) then
                return true
            end
        end
        return false
    end)
    
    if not success then
        return false
    end
    
    return result
end

-- Performance optimization: check if update is needed
function bars.needs_update(bar, current_time)
    if not bar then return true end
    
    current_time = current_time or os.clock()
    
    if current_time - bar.last_update < UPDATE_INTERVAL then
        return false
    end
    
    bar.last_update = current_time
    return true
end

-- Batch update system for performance
function bars.add_to_batch(bar, update_func)
    if not bars.update_batch then
        bars.update_batch = {}
    end
    
    table.insert(bars.update_batch, {bar = bar, func = update_func})
end

function bars.process_batch()
    local current_time = os.clock()
    
    if current_time - bars.last_batch_update < UPDATE_INTERVAL then
        return
    end
    
    if bars.update_batch and #bars.update_batch > 0 then
        for _, update_item in ipairs(bars.update_batch) do
            local success, err = pcall(update_item.func)
            if not success then
                windower.add_to_chat(123, 'Bars: Batch update error - ' .. tostring(err))
            end
        end
        bars.update_batch = {}
    end
    
    bars.last_batch_update = current_time
end

-- Utility function for safe color application
function bars.safe_color(element, r, g, b, a)
    if not element or not element.color then return end
    
    local success, err = pcall(function()
        element:color(r or 255, g or 255, b or 255, a or 255)
    end)
    
    if not success then
        windower.add_to_chat(123, 'Bars: Color error - ' .. tostring(err))
    end
end

-- Get bar state for debugging
function bars.get_state(bar)
    if not bar then return nil end
    
    return {
        visible = bar.is_visible,
        position = {x = bar.x, y = bar.y},
        width = bar.width,
        last_update = bar.last_update,
        show_flags = {
            dist = bar.show_dist,
            target = bar.show_target,
            action = bar.show_action,
            debuff = bar.show_debuff,
            prediction = bar.show_prediction,
            kill_timer = bar.show_kill_timer,
            alerts = bar.show_alerts
        }
    }
end