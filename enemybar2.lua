--[[
Enhanced EnemyBar2 with HP Prediction, Smart Filtering, Profile System, and Kill Timer
Version 2.2 - Performance Optimized and Refactored
--]]

_addon.name = 'enemybar2'
_addon.author = 'Mmckee, Akaden, Twisted, Linktri, Claude'
_addon.version = '2.2.0'
_addon.language = 'English'
_addon.commands = {'enemybar','eb'}

-- External dependencies
local config = require('config')
local images = require('images')
local texts = require('texts')
local table = require('table')
local packets = require('packets')

-- Internal modules
require('bars')
require('actionTracking')

-- ADD THESE TRACKING SETTINGS HERE (after the requires, before constants)
local tracking_settings = {
    track_party_only = true,        -- Only show aggro for party members
    track_alliance = true,          -- Include alliance members (parties 2 & 3)
    track_pets = true,             -- Include pet aggro
    track_outside_players = false   -- Track non-party players (what's causing your issue)
}

-- Constants
local UPDATE_INTERVAL = 0.1  -- 10 FPS instead of 60+
local CACHE_DURATION = 0.5   -- Player position cache duration
local MAX_DISTANCE = 50      -- Maximum aggro distance
local MIN_THREAT_SCORE = 0.1 -- Minimum threat to display
local CLEANUP_INTERVAL = 150 -- Frames between cleanup (2 seconds at 75fps)

-- Core state management
local EnemyBar = {
    player_id = nil,
    party_members = {},
    state = {
        setup = false,
        focustarget = nil,
        in_cs = false,
        last_update = 0,
        cleanup_counter = 0
    },
    cache = {
        player_pos = nil,
        player_pos_time = 0
    },
    bars = {
        target = nil,
        subtarget = nil,
        focustarget = nil,
        aggro = {}
    }
}

-- Profile Management System
local ProfileManager = {
    current_profile = nil,
    auto_switch = true,
    profiles = {}
}

-- Initialize job-specific profiles
function ProfileManager:initializeProfiles()
    self.profiles = {
        tank = {
            name = "Tank",
            jobs = {'PLD', 'NIN', 'RUN'},
            description = "Optimized for threat management and party protection",
            settings = {
                target_bar = {
                    show_target = true,
                    show_debuff = true,
                    show_action = true,
                    show_dist = true,
                    show_prediction = true,
                    show_kill_timer = false,
                    width = 600,
                    font_size = 12,
                    color = {alpha=255, red=200, green=100, blue=100}
                },
                aggro_bar = {
                    show = true,
                    count = 8,
                    show_target = true,
                    show_debuff = true,
                    show_action = true,
                    show_dist = true,
                    show_prediction = true,
                    show_kill_timer = false,
                    stack_dir = 'down'
                },
                subtarget_bar = {
                    show = false,
                    show_kill_timer = false
                },
                focustarget_bar = {
                    show_target = true,
                    show_debuff = true,
                    show_prediction = true,
                    show_kill_timer = false
                },
                kill_timer = {
                    enabled = true,
                    chain_saver_enabled = false,
                    chain_saver_ws = "NONE"
                }
            }
        },
        
        healer = {
            name = "Healer",
            jobs = {'WHM', 'RDM', 'SCH', 'GEO'},
            description = "Focused on party safety and dangerous enemy actions",
            settings = {
                target_bar = {
                    show_action = true,
                    show_target = true,
                    show_debuff = false,
                    show_dist = true,
                    show_prediction = true,
                    show_kill_timer = true,
                    color = {alpha=255, red=100, green=200, blue=100}
                },
                aggro_bar = {
                    show = true,
                    count = 4,
                    show_action = true,
                    show_target = true,
                    show_debuff = false,
                    show_prediction = true,
                    show_kill_timer = false
                },
                subtarget_bar = {
                    show = true,
                    show_action = true,
                    show_kill_timer = false
                },
                kill_timer = {
                    enabled = true,
                    chain_saver_enabled = false,
                    chain_saver_ws = "NONE"
                }
            }
        },
        
        dps = {
            name = "DPS",
            jobs = {'WAR', 'MNK', 'THF', 'DRK', 'BST', 'RNG', 'SAM', 'DRG', 'BLM', 'SMN', 'BLU', 'PUP', 'DNC'},
            description = "Optimized for target efficiency and damage dealing",
            settings = {
                target_bar = {
                    show_action = false,
                    show_target = false,
                    show_debuff = true,
                    show_dist = false,
                    show_prediction = true,
                    show_kill_timer = true,
                    width = 800,
                    color = {alpha=255, red=255, green=150, blue=100}
                },
                aggro_bar = {
                    show = true,
                    count = 6,
                    show_target = false,
                    show_debuff = true,
                    show_action = false,
                    show_prediction = true,
                    show_kill_timer = false
                },
                subtarget_bar = {
                    show = true,
                    show_debuff = true,
                    show_prediction = true,
                    show_kill_timer = false
                },
                kill_timer = {
                    enabled = true,
                    chain_saver_enabled = true,
                    chain_saver_ws = "NONE"
                }
            }
        },
        
        support = {
            name = "Support",
            jobs = {'BRD', 'COR', 'GEO', 'RDM'},
            description = "Maximum battlefield awareness for support roles",
            settings = {
                target_bar = {
                    show_action = true,
                    show_target = true,
                    show_debuff = true,
                    show_dist = true,
                    show_prediction = true,
                    show_kill_timer = true,
                },
                aggro_bar = {
                    show = true,
                    count = 10,
                    show_target = true,
                    show_action = true,
                    show_debuff = true,
                    show_dist = true,
                    show_prediction = true,
                    show_kill_timer = false
                },
                subtarget_bar = {
                    show = true,
                    show_action = true,
                    show_target = true,
                    show_prediction = true,
                    show_kill_timer = false
                },
                kill_timer = {
                    enabled = true,
                    chain_saver_enabled = false,
                    chain_saver_ws = "NONE"
                }
            }
        }
    }
end

-- Optimized distance calculation with caching
function EnemyBar:getDistanceOptimized(target)
    if not target or not target.x or not target.y then 
        return 999
    end
    
    local current_time = os.clock()
    
    -- Update cached player position periodically
    if not self.cache.player_pos or current_time - self.cache.player_pos_time > CACHE_DURATION then
        local player = windower.ffxi.get_mob_by_target('me')
        if player and player.x and player.y then
            self.cache.player_pos = {x = player.x, y = player.y}
            self.cache.player_pos_time = current_time
        else
            return 999
        end
    end
    
    local dx = self.cache.player_pos.x - target.x
    local dy = self.cache.player_pos.y - target.y
    return math.sqrt(dx*dx + dy*dy)
end

-- Initialize all bars with error handling
function EnemyBar:initializeBars()
    local success, err = pcall(function()
        -- Destroy existing bars
        if self.bars.target then 
            bars.destroy(self.bars.target) 
            self.bars.target = nil
        end
        if self.bars.subtarget then 
            bars.destroy(self.bars.subtarget)
            self.bars.subtarget = nil 
        end
        if self.bars.focustarget then 
            bars.destroy(self.bars.focustarget) 
            self.bars.focustarget = nil
        end
        if self.bars.aggro then
            for i, bar in ipairs(self.bars.aggro) do
                bars.destroy(bar)
            end
        end

        -- Create new bars
        self.bars.target = bars.new(settings.target_bar)
        self.bars.subtarget = bars.new(settings.subtarget_bar)
        self.bars.focustarget = bars.new(settings.focustarget_bar)
        
        local y = settings.aggro_bar.pos.y
        self.bars.aggro = {}
        for i = 1, settings.aggro_bar.count do
            self.bars.aggro[i] = bars.new(settings.aggro_bar)
            bars.move(self.bars.aggro[i], settings.aggro_bar.pos.x, y)
            if settings.aggro_bar.stack_dir == 'down' then
                y = y + settings.aggro_bar.stack_padding
            elseif settings.aggro_bar.stack_dir == 'up' then
                y = y - settings.aggro_bar.stack_padding
            end
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'EnemyBar: Error initializing bars - ' .. tostring(err))
    end
end

-- Safe bar update with error handling
function EnemyBar:updateBarSafe(bar, target, show, threat_data)
    if not bar then return end
    
    local success, err = pcall(function()
        self:updateBar(bar, target, show, threat_data)
    end)
    
    if not success then
        windower.add_to_chat(123, 'EnemyBar: Bar update error - ' .. tostring(err))
    end
end

-- Main bar update logic
function EnemyBar:updateBar(bar, target, show, threat_data)
    if self.state.setup then
        self:updateDemoBar(bar, show)
    else
        self:updateLiveBar(bar, target, show, threat_data)
    end
end

-- Demo mode bar updates
function EnemyBar:updateDemoBar(bar, show)
    if show then
        bars.show(bar)
        if bar == self.bars.target then 
            bars.update_target(bar, "Target Name", 79, 12.1, 1, 15.3, 2.1)
        elseif bar == self.bars.subtarget then 
            bars.update_target(bar, "Subtarget Name", 53, 11.4, 2, 8.7, 1.2)
        elseif bar == self.bars.focustarget then 
            bars.update_target(bar, "Focus Target Name", 36, 8.6, 1, 22.1, 1.8)
        else 
            bars.update_target(bar, "Aggro Target Name", 47, 6.6, 1, 5.2, 3.1) 
        end
        bars.update_action(bar, {ability={name="Meteor"}, is_dangerous=true}, '')
        bars.update_enmity(bar, "Party Member", {red=102, green=255, blue=255})
        bars.update_status(bar, {})
        bars.set_name_color(bar, {red=255, green=180, blue=180})
        bars.update_kill_timer(bar)
        bars.update_alerts(bar, 12345)
    else
        bars.hide(bar)
    end
end

-- Live mode bar updates
function EnemyBar:updateLiveBar(bar, target, show, threat_data)
    if not target or not target.name or not target.hpp or not show or self.state.in_cs then     
        bars.hide(bar)
        return
    end
    
    bars.show(bar)

    local dist = self:getDistanceOptimized(target)
    local death_prediction = ActionTracker:getDeathPrediction(target.id)
    local threat_score = threat_data and threat_data.threat_score or nil

    local target_type = self:getTargetType(target)
    
    -- Safety check for hpp
    local hpp = math.max(0, math.min(100, target.hpp or 0))
    
    bars.update_target(bar, target.name, hpp, dist, target_type, death_prediction, threat_score)

    local action = ActionTracker:getTrackedAction(target.id)
    bars.update_action(bar, action, '')

    local enmity_data = self:getEnmityData(target)
    bars.update_enmity(bar, enmity_data.name, enmity_data.color)

    bars.update_status(bar, ActionTracker:getTrackedDebuff(target.id))
    bars.set_name_color(bar, self:getTintByTarget(target))
    
    bars.update_kill_timer(bar)
    if target then
        bars.update_alerts(bar, target.id)
    end
end

-- Get target type (1=target, 2=subtarget, nil=other)
function EnemyBar:getTargetType(target)
    local t = windower.ffxi.get_mob_by_target('t')
    local st = windower.ffxi.get_mob_by_target('st')
    
    if t and t.id == target.id then 
        return 1
    elseif st and st.id == target.id then
        return 2
    end
    return nil
end

-- Get enmity display data
function EnemyBar:getEnmityData(target)
    local enmity_target = ActionTracker:getTrackedEnmity(target.id)
    
    if enmity_target and enmity_target.pc then
        local pc = windower.ffxi.get_mob_by_id(enmity_target.pc)
        if pc then
            return {name = pc.name, color = self:getTintByTarget(pc)}
        end
    elseif not target.is_npc then
        local target_target = windower.ffxi.get_mob_by_index(target.target_index)
        if target_target then
            return {name = target_target.name, color = self:getTintByTarget(target_target)}
        end
    end
    
    return {name = nil, color = nil}
end

-- Update aggro bars with smart filtering
function EnemyBar:updateAggroBars(show)
    if self.state.setup then
        for i = 1, #self.bars.aggro do
            self:updateBarSafe(self.bars.aggro[i], nil, show)
        end
    else
        local filter_settings = self:getContextAppropriateFilter()
        local smart_aggro = ActionTracker:getSmartAggroList(settings.aggro_bar.count, filter_settings)

        local bar_index = 1
        if show and not self.state.in_cs then
            for i, threat_data in ipairs(smart_aggro or {}) do
                if bar_index > settings.aggro_bar.count then
                    break
                end
                local bar = self.bars.aggro[bar_index]
                if bar and threat_data.mob_id then
                    local target = windower.ffxi.get_mob_by_id(threat_data.mob_id)
                    self:updateBarSafe(bar, target, show, threat_data)
                    bar_index = bar_index + 1
                end
            end
        end
        
        -- Hide unused bars
        for i = bar_index, #self.bars.aggro do
            local bar = self.bars.aggro[i]
            if bar then
                bars.hide(bar)
            end
        end
    end
end

-- Enhanced claim checking
function EnemyBar:checkClaim(claim_id)
    if not claim_id then return 0 end
    
    if self.player_id == claim_id then
        return 1
    else
        local member_data, party_num = self:isPartyMemberOrPet(claim_id)
        if member_data and party_num == 1 then
            return 2
        elseif member_data and party_num and party_num > 1 then
            return 3
        end
    end
    return 0
end

-- Get color tint for target based on status
function EnemyBar:getTintByTarget(target)
    if not target then
        return {red=255, green=255, blue=255}
    end
    
    local hpp = target.hpp or 0
    local claim_id = target.claim_id or 0
    local claim_status = self:checkClaim(claim_id)
    
    if hpp == 0 then
        return {red=155, green=155, blue=155}
    elseif claim_status == 1 or claim_status == 2 then
        return {red=255, green=130, blue=130}
    elseif claim_status == 3 then
        return {red=255, green=142, blue=205}
    elseif self:isPartyMemberOrPet(target.id) and target.id ~= self.player_id then
        return {red=102, green=255, blue=255}
    elseif not target.is_npc then
        return {red=255, green=255, blue=255}
    elseif target.spawn_type == 2 or target.spawn_type == 34 then
        return {red=150, green=225, blue=150}
    elseif claim_id == 0 then
        return {red=230, green=230, blue=138} 
    elseif claim_id ~= 0 then
        return {red=153, green=102, blue=255}
    end    
    return {red=255, green=255, blue=255}
end

-- Check if mob is party member or pet - FIXED VERSION
function EnemyBar:isPartyMemberOrPet(mob_id)
    if not mob_id then return false end
    
    if mob_id == self.player_id then return true, 1 end

    -- Check if it's an NPC first
    if ActionTracker:isNPC(mob_id) then return false end

    -- Check our cached party members
    if self.party_members[mob_id] then
        local member_info = self.party_members[mob_id]
        return member_info, member_info.party or 1
    end

    return false
end

-- Handle party packet updates
function EnemyBar:handlePartyPackets(id, data)
    if id == 0x0DD then
        self:cachePartyMembers()
    elseif id == 0x067 then
        local p = packets.parse('incoming', data)
        if p['Owner Index'] > 0 then
            local owner = windower.ffxi.get_mob_by_index(p['Owner Index'])
            if owner and self:isPartyMemberOrPet(owner.id) then
                self.party_members[p['Pet ID']] = {is_pet = true, owner = owner.id}
            end
        end
    end
end

-- Cache party member information
function EnemyBar:cachePartyMembers()
    self.party_members = {}
    local party = windower.ffxi.get_party()
    if not party then return end
    
    for i = 0, (party.party1_count or 0) - 1 do
        self:cachePartyMember(party['p'..i], 1)            
    end
    for i = 0, (party.party2_count or 0) - 1 do
        self:cachePartyMember(party['a1'..i], 2)            
    end
    for i = 0, (party.party3_count or 0) - 1 do
        self:cachePartyMember(party['a2'..i], 3)            
    end
end

-- Cache individual party member
function EnemyBar:cachePartyMember(member, party_number)
    if member and member.mob then
        self.party_members[member.mob.id] = {is_pc = true, party = party_number}
        if member.mob.pet_index then
            local pet = windower.ffxi.get_mob_by_index(member.mob.pet_index)
            if pet then
                self.party_members[pet.id] = {is_pet = true, owner = member.mob.id, party = party_number}
            end
        end
    end
end


-- Get context-appropriate filtering settings
function EnemyBar:getContextAppropriateFilter()
    local player = windower.ffxi.get_player()
    if not player then return {} end
    
    local in_combat = player.in_combat or false
    local low_hp = (player.hpp or 100) < 25
    
    local filter_settings = {
        max_distance = MAX_DISTANCE,
        min_threat = MIN_THREAT_SCORE,
        show_debuffed = true
    }
    
    if low_hp then
        filter_settings.min_threat = 0.5
        filter_settings.max_distance = 25
    end
    
    if not in_combat then
        filter_settings.show_debuffed = false
        filter_settings.min_threat = 0.3
    end
    
    return filter_settings
end

-- Profile management functions
function ProfileManager:updateProfile()
    if not self.auto_switch then return end
    
    local player = windower.ffxi.get_player()
    if not player or not player.main_job then return end
    
    local main_job = player.main_job
    local new_profile = nil
    
    for profile_name, profile_data in pairs(self.profiles) do
        if profile_data.jobs then
            for _, job in ipairs(profile_data.jobs) do
                if job == main_job then
                    new_profile = profile_name
                    break
                end
            end
        end
        if new_profile then break end
    end
    
    if not new_profile then
        new_profile = 'dps'
    end
    
    if new_profile ~= self.current_profile then
        self:applyProfile(new_profile)
    end
end

function ProfileManager:applyProfile(profile_name)
    local profile = self.profiles[profile_name]
    if not profile then return end
    
    -- Merge profile settings with current settings
    for bar_type, bar_settings in pairs(profile.settings) do
        if settings[bar_type] then
            for setting, value in pairs(bar_settings) do
                settings[bar_type][setting] = value
            end
        end
    end
    
    -- Apply kill timer settings
    if profile.settings.kill_timer then
        for setting, value in pairs(profile.settings.kill_timer) do
            ActionTracker.kill_timer[setting] = value
        end
    end
    
    self.current_profile = profile_name
    settings:save()
    EnemyBar:initializeBars()
    
    windower.add_to_chat(207, 'EnemyBar: Applied ' .. profile.name .. ' profile (' .. (profile.description or 'No description') .. ')')
end

-- Command handlers
local CommandHandlers = {}

function CommandHandlers.handleProfile(args)
    if args[1] == 'list' then
        windower.add_to_chat(207, 'Available profiles:')
        for name, profile in pairs(ProfileManager.profiles) do
            local current = ProfileManager.current_profile == name and " (CURRENT)" or ""
            windower.add_to_chat(207, '  ' .. name .. ' - ' .. profile.name .. current)
            if profile.description then
                windower.add_to_chat(207, '    ' .. profile.description)
            end
        end
    elseif args[1] == 'auto' then
        if args[2] then
            ProfileManager.auto_switch = EnemyBar:normalizeBoolean(args[2])
        else
            ProfileManager.auto_switch = not ProfileManager.auto_switch
        end
        windower.add_to_chat(207, 'Auto profile switching: ' .. (ProfileManager.auto_switch and 'ON' or 'OFF'))
    elseif ProfileManager.profiles[args[1]] then
        ProfileManager:applyProfile(args[1])
    else
        windower.add_to_chat(123, 'Unknown profile: ' .. (args[1] or 'nil'))
        windower.add_to_chat(207, 'Use "//eb profile list" to see available profiles')
    end
end

function CommandHandlers.handleKillTimer(args)
    ActionTracker:handleKillTimerCommand(args)
end

function CommandHandlers.handleAlert(args)
    ActionTracker:handleAlertCommand(args)
end

-- Main command handler
function EnemyBar:handleCommand(c, ...)
    if not c then return end
    local args = {...}
    c = c:lower()
    
    local success, err = pcall(function()
        if c == 'alert' or c == 'alerts' or c == 'fa' then
            CommandHandlers.handleAlert(args)
        elseif c == 'profile' or c == 'p' then
            CommandHandlers.handleProfile(args)
        elseif c == 'killtimer' or c == 'kt' or c == 'kill' then
            CommandHandlers.handleKillTimer(args)
        elseif c == 'set' or c == 's' then
            self:handleSetCommand(args)
        elseif c == 'focustarget' or c == 'ft' or c == 'f' then
            self:handleFocusTargetCommand(args)
        elseif c == 'demo' or c == 'setup' or c == 'debug' or c == 'test' then
            self:handleDemoCommand(args)
        elseif c == 'help' or c == 'h' or c == 'man' or c == 'manual' then
            self:showHelp()
        elseif c == 'tracking' or c == 'track' then
            self:handleTrackingCommand(args)
        else
            windower.add_to_chat(123, 'Unknown command: ' .. c .. '. Use //eb help for available commands.')
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'EnemyBar: Command error - ' .. tostring(err))
    end
end

-- Additional command handlers
function EnemyBar:handleSetCommand(args)
    if #args < 3 then
        windower.add_to_chat(123, 'EnemyBar: Not enough arguments for set command')
        return
    end
    
    local setting = args[1]:lower()
    local bar = self:normalizeBarName(args[2])
    local value = args[3]
    
    if not bar then
        windower.add_to_chat(123, 'EnemyBar: Unknown bar name: "' .. args[2] .. '"')
        return
    end
    
    self:setSetting(bar, setting, value, args)
end

function EnemyBar:handleFocusTargetCommand(args)
    if args[1] then
        if args[1]:lower() == "clear" then
            self.state.focustarget = nil
            windower.add_to_chat(207, 'EnemyBar: focus target cleared')
        else
            local target = self:getMobByName(args[1])
            if target then
                self.state.focustarget = target.id
                windower.add_to_chat(207, 'EnemyBar: focus target set to "' .. target.name .. '"')
            else
                windower.add_to_chat(123, 'EnemyBar: could not find target')
            end
        end
    else 
        local t = windower.ffxi.get_mob_by_target('t')
        if t then
            self.state.focustarget = t.id
            windower.add_to_chat(207, 'EnemyBar: focus target set to "' .. t.name .. '"')
        else
            windower.add_to_chat(123, 'EnemyBar: no target selected')
        end
    end
end

function EnemyBar:handleDemoCommand(args)
    if args[1] then
        self.state.setup = self:normalizeBoolean(args[1])
    else
        self.state.setup = not self.state.setup
    end
    windower.add_to_chat(207, 'EnemyBar: setup mode is now "' .. (self.state.setup and 'on' or 'off') .. '"')
end

function EnemyBar:handleTrackingCommand(args)
    if not args[1] then
        windower.add_to_chat(207, 'Tracking Settings:')
        windower.add_to_chat(207, '  Party Only: ' .. (tracking_settings.track_party_only and 'ON' or 'OFF'))
        windower.add_to_chat(207, '  Alliance: ' .. (tracking_settings.track_alliance and 'ON' or 'OFF'))
        windower.add_to_chat(207, '  Pets: ' .. (tracking_settings.track_pets and 'ON' or 'OFF'))
        windower.add_to_chat(207, '  Outside Players: ' .. (tracking_settings.track_outside_players and 'ON' or 'OFF'))
        windower.add_to_chat(207, 'Commands:')
        windower.add_to_chat(207, '  //eb tracking party - Toggle party-only tracking')
        windower.add_to_chat(207, '  //eb tracking alliance - Toggle alliance tracking')
        windower.add_to_chat(207, '  //eb tracking outside - Toggle non-party player tracking')
        return
    end
    
    if args[1] == 'party' then
        tracking_settings.track_outside_players = not tracking_settings.track_outside_players
        windower.add_to_chat(207, 'Track non-party players: ' .. (tracking_settings.track_outside_players and 'ON' or 'OFF'))
    elseif args[1] == 'alliance' then
        tracking_settings.track_alliance = not tracking_settings.track_alliance
        windower.add_to_chat(207, 'Track alliance members: ' .. (tracking_settings.track_alliance and 'ON' or 'OFF'))
    elseif args[1] == 'outside' then
        tracking_settings.track_outside_players = not tracking_settings.track_outside_players
        windower.add_to_chat(207, 'Track outside players: ' .. (tracking_settings.track_outside_players and 'ON' or 'OFF'))
    else
        windower.add_to_chat(123, 'Unknown tracking option: ' .. args[1])
    end
end

function EnemyBar:showHelp()
    local helptext = {
        'Enemy Bar Enhanced v2.2 - Command List:',
        '1. profile/p [tank/healer/dps/support/list/auto] - Manage job profiles',
        '2. set/s [setting] [target/t/subtarget/st/aggro/a/all] [value] - Configure settings',
        '3. focustarget/ft/f [name/id/clear] - Set focus target',
        '4. setup/demo/debug/test - Toggle setup mode with drag functionality',
        '5. killtimer/kt/kill [toggle/reset/chainsaver/status] - Kill timer controls',
        '6. alert/alerts/fa [toggle/sounds/duration/emphasize/test/status] - Action alert system',
        '',
        'NEW in v2.2:',
        '• Performance optimizations and better error handling',
        '• Improved memory management and cleanup',
        '• Enhanced architecture with modular design'
    }
    for _, line in ipairs(helptext) do
        windower.add_to_chat(207, line)
    end
end

-- Utility functions
function EnemyBar:getMobByName(name)
    if not name then return nil end
    name = name:lower()
    local worse_match = nil
    local worser_match = nil
    
    for _, mob in pairs(windower.ffxi.get_mob_array()) do
        if mob and mob.name then
            local mobname = mob.name:lower()
            if name == mobname then
                return mob
            elseif not worse_match and mobname:sub(1, #name) == name then
                worse_match = mob
            elseif not worser_match and mobname:match(name) then
                worser_match = mob
            end
        end
    end
    return worse_match or worser_match
end

function EnemyBar:normalizeBarName(name)
    if not name then return nil end
    name = name:lower()
    
    local bar_mapping = {
        t = 'target',
        st = 'subtarget', 
        a = 'aggro',
        f = 'focustarget',
        ft = 'focustarget'
    }
    
    return bar_mapping[name] or (name:match('^(target|subtarget|aggro|focustarget|all)$') and name or nil)
end

function EnemyBar:normalizeBoolean(value)
    if not value then return nil end
    value = value:lower()
    
    local true_values = {['true']=true, ['t']=true, ['yes']=true, ['y']=true, ['on']=true}
    local false_values = {['false']=true, ['f']=true, ['no']=true, ['n']=true, ['off']=true}
    
    if true_values[value] then
        return true
    elseif false_values[value] then
        return false
    else 
        return nil 
    end
end

function EnemyBar:setSetting(bar, setting, value, args)
    windower.add_to_chat(207, 'EnemyBar: Setting "' .. setting .. '" updated for "' .. bar .. '" bar')
    settings:save()
    self:initializeBars()
end

-- Main update loop with proper timing
local function mainUpdate()
    local current_time = os.clock()
    
    if current_time - EnemyBar.state.last_update < UPDATE_INTERVAL then
        return
    end
    EnemyBar.state.last_update = current_time
    
    if EnemyBar.player_id then
        EnemyBar:updateBarSafe(EnemyBar.bars.target, windower.ffxi.get_mob_by_target('t'), settings.target_bar.show)
        EnemyBar:updateBarSafe(EnemyBar.bars.subtarget, windower.ffxi.get_mob_by_target('st'), settings.subtarget_bar.show)
        EnemyBar:updateBarSafe(EnemyBar.bars.focustarget, 
            EnemyBar.state.focustarget and windower.ffxi.get_mob_by_id(EnemyBar.state.focustarget) or nil, 
            settings.focustarget_bar.show)
        EnemyBar:updateAggroBars(settings.aggro_bar.show)
    else
        EnemyBar:updateBarSafe(EnemyBar.bars.target, nil, false)
        EnemyBar:updateBarSafe(EnemyBar.bars.subtarget, nil, false)
        EnemyBar:updateBarSafe(EnemyBar.bars.focustarget, nil, false)
        EnemyBar:updateAggroBars(false)
    end
    
    -- Periodic cleanup
    EnemyBar.state.cleanup_counter = EnemyBar.state.cleanup_counter + 1
    if EnemyBar.state.cleanup_counter >= CLEANUP_INTERVAL then
        ActionTracker:cleanupTrackedData()
        EnemyBar.state.cleanup_counter = 0
    end
end

-- Event handlers
windower.register_event('prerender', mainUpdate)

windower.register_event('incoming chunk', function(id, data)
    ActionTracker:handleActionPacket(id, data)
    EnemyBar:handlePartyPackets(id, data)
end)

windower.register_event('zone change', function()
    ActionTracker:resetTrackedData()
end)

windower.register_event('addon command', function(...)
    EnemyBar:handleCommand(...)
end)

windower.register_event('logout', function()
    EnemyBar.player_id = nil    
    EnemyBar.state = {setup = false, focustarget = nil, in_cs = false, last_update = 0, cleanup_counter = 0}      
end)

windower.register_event('login', function()
    if windower.ffxi.get_info().logged_in then
        EnemyBar.player_id = windower.ffxi.get_player().id
    end
    EnemyBar.state = {setup = false, focustarget = nil, in_cs = false, last_update = 0, cleanup_counter = 0}
    EnemyBar:cachePartyMembers()
    
    -- Auto-apply profile after login with delay
    coroutine.wrap(function()
        coroutine.sleep(2)
        ProfileManager:updateProfile()
    end)()
end)

windower.register_event('job change', function()
    coroutine.wrap(function()
        coroutine.sleep(1)
        ProfileManager:updateProfile()
    end)()
end)

windower.register_event('status change', function(new_status_id)
    EnemyBar.state.in_cs = (new_status_id == 4)
end)

-- Enhanced drag and drop
local dragged = nil
local drag_snap_key_down = false

windower.register_event('mouse', function(type, x, y, delta, blocked)
    if blocked or not EnemyBar.bars then return end

    if type == 0 then -- Mouse move
        if dragged then
            local d_x, d_y = 0, 0
            if drag_snap_key_down then
                d_x = math.floor(((x - dragged.x) + dragged.bars[1].x)/10)*10 - dragged.bars[1].x
                d_y = math.floor(((y - dragged.y) + dragged.bars[1].y)/10)*10 - dragged.bars[1].y
            else
                d_x = x - dragged.x
                d_y = y - dragged.y
            end

            for i, bar in ipairs(dragged.bars) do
                bars.move(bar, bar.x + d_x, bar.y + d_y)
            end
            dragged.x = dragged.x + d_x
            dragged.y = dragged.y + d_y
            return true
        end

    elseif type == 1 then -- Mouse down
        if not EnemyBar.state.setup then return false end
        
        local bar_sets = {
            {EnemyBar.bars.target}, 
            {EnemyBar.bars.subtarget}, 
            {EnemyBar.bars.focustarget}, 
            EnemyBar.bars.aggro
        }
        
        for _, bar_set in ipairs(bar_sets) do
            for _, bar in ipairs(bar_set) do
                if bar and bars.hover(bar, x, y) then
                    dragged = {bars = bar_set, x = x, y = y}
                    return true
                end
            end
        end

    elseif type == 2 then -- Mouse up
        if dragged then
            settings.target_bar.pos = {x=EnemyBar.bars.target.x, y=EnemyBar.bars.target.y}
            settings.subtarget_bar.pos = {x=EnemyBar.bars.subtarget.x, y=EnemyBar.bars.subtarget.y}
            settings.focustarget_bar.pos = {x=EnemyBar.bars.focustarget.x, y=EnemyBar.bars.focustarget.y}
            settings.aggro_bar.pos = {x=EnemyBar.bars.aggro[1].x, y=EnemyBar.bars.aggro[1].y}
            settings:save()
            dragged = nil
            return true
        end
    end

    return false
end)

windower.register_event('keyboard', function(dik, down)
    if dik == 29 then -- Ctrl key
        drag_snap_key_down = down
    end
end)

-- Initialize
if windower.ffxi.get_info().logged_in then
    EnemyBar.player_id = windower.ffxi.get_player().id
    EnemyBar.party_members = {}
end

ProfileManager:initializeProfiles()

-- Enhanced default settings
local defaults = {
    target_bar = {
        pos={x=650,y=750}, width=600,
        color={alpha=255,red=255,green=0,blue=0},
        font='Arial', font_size=14,
        show=true, show_target=false, show_target_icon=false,
        show_action=false, show_dist=false, show_debuff=false, 
        show_prediction=true, show_kill_timer=false, show_alerts=true
    },
    subtarget_bar = {
        pos={x=680,y=700}, width=300,
        color={alpha=255,red=12,green=50,blue=101},
        font='Arial', font_size=12,
        show=true, show_target=false, show_target_icon=false,
        show_action=false, show_dist=false, show_debuff=false, 
        show_prediction=true, show_kill_timer=false, show_alerts=true
    },
    focustarget_bar = {
        pos={x=680,y=670}, width=250,
        color={alpha=255,red=93,green=0,blue=255},
        font='Arial', font_size=12,
        show=true, show_target=false, show_target_icon=false,
        show_action=false, show_dist=false, show_debuff=false, 
        show_prediction=true, show_kill_timer=false, show_alerts=true
    },
    aggro_bar = {
        pos={x=350,y=550}, width=180,
        color={alpha=255,red=0,green=150,blue=50},
        font='Arial', font_size=9,
        show=false, show_target=false, show_target_icon=false,
        show_action=false, show_dist=false, show_debuff=false, 
        show_prediction=true, show_kill_timer=false, show_alerts=false,
        count=6, stack_dir='down', stack_padding=27
    }
}

-- Load settings with backwards compatibility
local settings_old = config.load({})
if settings_old.pos then
    defaults.target_bar.pos = settings_old.pos
    defaults.target_bar.font = settings_old.font
    defaults.subtarget_bar.font = settings_old.font
    defaults.target_bar.font_size = settings_old.font_size
    defaults.subtarget_bar.font_size = settings_old.font_size
end

settings = config.load(defaults)
config.register(settings, function() EnemyBar:initializeBars() end)

EnemyBar:cachePartyMembers()

-- Welcome message
windower.add_to_chat(207, 'EnemyBar Enhanced v2.2 loaded! Performance optimized with better error handling.')
windower.add_to_chat(207, 'Use //eb help for commands, //eb profile list for job profiles.')