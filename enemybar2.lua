--[[
Enhanced EnemyBar2 with HP Prediction, Smart Filtering, Profile System, and Kill Timer
Version 2.5 - Limbus, TargetInfo and Debuffs modules
--]]

_addon.name = 'enemybar2'
_addon.author = 'Mmckee, Akaden, Twisted, Linktri, Claude'
_addon.version = '2.5.0'
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
require('limbus')
require('targetinfo')
require('debuffs')

-- Aggro tracking scope. Loaded from settings.tracking (see defaults below)
-- and applied by cachePartyMembers / scanClaimedMobs / the threat score.
--   alliance: include alliance parties 2 and 3
--   pets:     include party members' pets
--   outside:  include mobs on players outside your party/alliance
local tracking_settings = {alliance = true, pets = true, outside = false}

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
        last_claim_scan = 0,
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

        -- Text modules (limbus.lua, targetinfo.lua)
        Limbus:initialize(settings.limbus_bar)
        TargetInfo:initialize(settings.targetinfo_bar)
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
    -- valid_target == false means the mob despawned (fled / fetter removed);
    -- its stale entry keeps the last HP%, so hide on that too. Only the
    -- valid_target flag is checked here (not hpp), so 0% bars behave as before.
    if not target or not target.name or not target.hpp or not show or self.state.in_cs
       or target.valid_target == false then
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
        local smart_aggro = ActionTracker:getSmartAggroList(settings.aggro_bar.count, filter_settings, self.party_members)

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
        if tracking_settings.pets and p['Owner Index'] > 0 then
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
    if tracking_settings.alliance then
        for i = 0, (party.party2_count or 0) - 1 do
            self:cachePartyMember(party['a1'..i], 2)            
        end
        for i = 0, (party.party3_count or 0) - 1 do
            self:cachePartyMember(party['a2'..i], 3)            
        end
    end
end

-- Cache individual party member
function EnemyBar:cachePartyMember(member, party_number)
    if member and member.mob then
        self.party_members[member.mob.id] = {is_pc = true, party = party_number}
        if tracking_settings.pets and member.mob.pet_index then
            local pet = windower.ffxi.get_mob_by_index(member.mob.pet_index)
            if pet then
                self.party_members[pet.id] = {is_pet = true, owner = member.mob.id, party = party_number}
            end
        end
    end
end

-- Scan mob array for mobs that are a threat to the player or party.
-- Supplements packet-driven enmity tracking for mobs that are purely
-- meleeing without using abilities (which generate no 0x028 packets).
-- Catches two cases:
--   1. Mobs with claim_id matching the player or a party member (normal claim)
--   2. Mobs with no claim but actively targeting the player or a party member
--      (e.g. linked mobs, mobs engaged before the addon loaded)
-- Throttled to run at most once every 0.5 seconds.
local CLAIM_SCAN_INTERVAL = 0.5

function EnemyBar:scanClaimedMobs()
    local current_time = os.clock()
    if current_time - self.state.last_claim_scan < CLAIM_SCAN_INTERVAL then return end
    self.state.last_claim_scan = current_time

    if not self.player_id then return end

    -- Build a set of party member mob indexes for target_index comparison
    local party_indexes = {}
    local player_mob = windower.ffxi.get_mob_by_target('me')
    if player_mob then
        party_indexes[player_mob.index] = self.player_id
    end
    for member_id, _ in pairs(self.party_members) do
        local member_mob = windower.ffxi.get_mob_by_id(member_id)
        if member_mob then
            party_indexes[member_mob.index] = member_id
        end
    end

    local success, err = pcall(function()
        for _, mob in pairs(windower.ffxi.get_mob_array()) do
            -- isMobActive excludes despawned mobs, which keep their old
            -- claim_id and would otherwise be re-injected/refreshed forever.
            if mob and mob.id and ActionTracker:isMobActive(mob)
            and mob.is_npc and not mob.charmed then

                local aggressor_pc = nil

                -- Case 1: mob is claimed by player or party member
                if mob.claim_id and mob.claim_id ~= 0 then
                    if mob.claim_id == self.player_id or self.party_members[mob.claim_id]
                    or tracking_settings.outside then
                        aggressor_pc = mob.claim_id
                    end
                end

                -- Case 2: mob is actively targeting player or party member
                -- (catches unclaimed links and mobs engaged before addon load)
                if not aggressor_pc and mob.target_index and mob.target_index ~= 0 then
                    aggressor_pc = party_indexes[mob.target_index]
                end

                if aggressor_pc then
                    if not ActionTracker.tracked_enmity[mob.id] then
                        -- New entry — inject it
                        ActionTracker.tracked_enmity[mob.id] = {
                            mob = mob.id,
                            pc = aggressor_pc,
                            time = os.time()
                        }
                    else
                        -- Existing entry — refresh timestamp so it doesn't age out
                        -- while the mob is still actively threatening us.
                        -- Preserve pc from packet-driven data if present.
                        ActionTracker.tracked_enmity[mob.id].time = os.time()
                    end
                end
            end
        end
    end)

    if not success then
        windower.add_to_chat(123, 'EnemyBar: scanClaimedMobs error - ' .. tostring(err))
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
        elseif c == 'scan' then
            self:handleScanDebug()
        elseif c == 'help' or c == 'h' or c == 'man' or c == 'manual' then
            self:showHelp()
        elseif c == 'tracking' or c == 'track' then
            self:handleTrackingCommand(args)
        elseif c == 'limbus' or c == 'lh' then
            Limbus:handleCommand(args)
        elseif c == 'targetinfo' or c == 'ti' then
            TargetInfo:handleCommand(args)
        elseif c == 'df' or c == 'debuffs' or c == 'debuffing' then
            Debuffs:handleCommand(args)
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
        self:showSetHelp()
        return
    end
    
    local setting = args[1]:lower()
    local bar = self:normalizeBarName(args[2])
    local value = args[3]
    
    if not bar then
        windower.add_to_chat(123, 'EnemyBar: Unknown bar "' .. args[2] .. '". Use target/t, subtarget/st, focustarget/ft, aggro/a or all')
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

-- Push tracking_settings into everything that uses them
function EnemyBar:applyTrackingSettings()
    ActionTracker.track_outside_players = tracking_settings.outside
    self:cachePartyMembers()
    -- Drop enmity entries that no longer qualify; the claim scan re-adds valid ones
    for mob_id, data in pairs(ActionTracker.tracked_enmity) do
        if data.pc and data.pc ~= self.player_id and not self.party_members[data.pc]
        and not tracking_settings.outside then
            ActionTracker.tracked_enmity[mob_id] = nil
        end
    end
end

function EnemyBar:handleTrackingCommand(args)
    local opt = args[1] and args[1]:lower()
    local function onoff(v) return v and 'ON' or 'OFF' end

    if not opt then
        windower.add_to_chat(207, 'Aggro tracking:')
        windower.add_to_chat(207, '  Party/alliance only: ' .. onoff(not tracking_settings.outside))
        windower.add_to_chat(207, '  Alliance (parties 2-3): ' .. onoff(tracking_settings.alliance))
        windower.add_to_chat(207, '  Pets: ' .. onoff(tracking_settings.pets))
        windower.add_to_chat(207, '  Outside players: ' .. onoff(tracking_settings.outside))
        windower.add_to_chat(207, 'Commands (each takes optional on/off, otherwise toggles):')
        windower.add_to_chat(207, '  //eb tracking party    - Party/alliance only (turns outside players off)')
        windower.add_to_chat(207, '  //eb tracking alliance - Include alliance parties 2 and 3')
        windower.add_to_chat(207, '  //eb tracking pets     - Include party pets')
        windower.add_to_chat(207, '  //eb tracking outside  - Include mobs on players outside your party')
        return
    end

    local explicit = self:normalizeBoolean(args[2])
    local function set(key, current)
        if explicit == nil then return not current end
        return explicit
    end

    if opt == 'party' then
        -- "party only" is the opposite of tracking outside players
        tracking_settings.outside = not set('party', not tracking_settings.outside)
        windower.add_to_chat(207, 'Party/alliance only: ' .. onoff(not tracking_settings.outside))
    elseif opt == 'alliance' then
        tracking_settings.alliance = set('alliance', tracking_settings.alliance)
        windower.add_to_chat(207, 'Track alliance members: ' .. onoff(tracking_settings.alliance))
    elseif opt == 'pets' or opt == 'pet' then
        tracking_settings.pets = set('pets', tracking_settings.pets)
        windower.add_to_chat(207, 'Track pets: ' .. onoff(tracking_settings.pets))
    elseif opt == 'outside' then
        tracking_settings.outside = set('outside', tracking_settings.outside)
        windower.add_to_chat(207, 'Track outside players: ' .. onoff(tracking_settings.outside))
    else
        windower.add_to_chat(123, 'Unknown tracking option: ' .. opt .. '. Use party, alliance, pets or outside.')
        return
    end

    settings.tracking = {alliance = tracking_settings.alliance, pets = tracking_settings.pets, outside = tracking_settings.outside}
    settings:save()
    self:applyTrackingSettings()
end

function EnemyBar:handleScanDebug()
    local player_mob = windower.ffxi.get_mob_by_target('me')
    local player_obj = windower.ffxi.get_player()

    windower.add_to_chat(207, '=== EnemyBar Scan Debug ===')
    windower.add_to_chat(207, 'player_id: ' .. tostring(self.player_id))
    windower.add_to_chat(207, 'player mob index: ' .. tostring(player_mob and player_mob.index or 'nil'))
    windower.add_to_chat(207, 'get_player().id: ' .. tostring(player_obj and player_obj.id or 'nil'))

    -- Dump tracked_enmity
    local enmity_count = 0
    for id, data in pairs(ActionTracker.tracked_enmity) do
        local mob = windower.ffxi.get_mob_by_id(id)
        windower.add_to_chat(207, 'enmity: ' .. tostring(mob and mob.name or id) .. 
            ' pc=' .. tostring(data.pc) .. ' age=' .. tostring(os.time() - data.time) .. 's')
        enmity_count = enmity_count + 1
    end
    if enmity_count == 0 then
        windower.add_to_chat(207, 'tracked_enmity: EMPTY')
    end

    -- Dump nearby NPCs with their claim_id and target_index
    windower.add_to_chat(207, '--- Nearby NPCs (within 20) ---')
    local player_pos = player_mob and {x=player_mob.x, y=player_mob.y} or nil
    for _, mob in pairs(windower.ffxi.get_mob_array()) do
        if mob and mob.id and mob.hpp and mob.hpp > 0 and mob.is_npc then
            local dist = 999
            if player_pos and mob.x and mob.y then
                local dx = player_pos.x - mob.x
                local dy = player_pos.y - mob.y
                dist = math.sqrt(dx*dx + dy*dy)
            end
            if dist < 20 then
                windower.add_to_chat(207, mob.name .. 
                    ' idx=' .. tostring(mob.index) ..
                    ' claim=' .. tostring(mob.claim_id) ..
                    ' target_idx=' .. tostring(mob.target_index) ..
                    ' status=' .. tostring(mob.status) ..
                    ' valid=' .. tostring(mob.valid_target))
            end
        end
    end
end

function EnemyBar:showHelp()
    local helptext = {
        'Enemy Bar Enhanced v2.5 - Command List:',
        '1. profile/p [tank/healer/dps/support/list/auto] - Manage job profiles',
        '2. set/s [setting] [target/t/subtarget/st/focustarget/ft/aggro/a/all] [value] - Configure bars (//eb set for list)',
        '3. focustarget/ft/f [name/id/clear] - Set focus target',
        '4. setup/demo/debug/test - Toggle setup mode with drag functionality',
        '5. killtimer/kt/kill [toggle/reset/chainsaver/status] - Kill timer controls',
        '6. alert/alerts/fa [toggle/sounds/duration/emphasize/test/status] - Action alert system',
        '7. tracking [party/alliance/pets/outside] [on/off] - Aggro tracking scope',
        '8. limbus/lh [reset/sector/show/hide/toggle/on/off/pos/debug] - Limbus chest tracker (//eb lh help)',
        '9. targetinfo/ti [on/off/id/hex/speed/name] - Target ID, hex ID and speed (//eb ti help)',
        '10. df/debuffs [help] - Debuff icons and timers on the target bar (//eb df help)',
        '',
        'NEW in v2.3 - v2.5:',
        '• Limbus chest tracker for Apollyon and Temenos (formerly LimbusHelper)',
        '• TargetInfo: target ID, hex ID and speed (formerly the TargetInfo addon)',
        '• Debuff icons with timers on the target bar (formerly the Debuffing addon)'
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
        t = 'target', target = 'target',
        st = 'subtarget', subtarget = 'subtarget',
        a = 'aggro', aggro = 'aggro',
        f = 'focustarget', ft = 'focustarget', focustarget = 'focustarget', focus = 'focustarget',
        all = 'all',
    }
    return bar_mapping[name]
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

-- Settings that //eb set can change, by type. 'aggro' marks aggro-only settings.
local SETTABLE = {
    show = 'bool', show_target = 'bool', show_target_icon = 'bool', show_action = 'bool',
    show_dist = 'bool', show_debuff = 'bool', show_prediction = 'bool',
    show_kill_timer = 'bool', show_alerts = 'bool',
    width = 'number', font_size = 'number', x = 'number', y = 'number', prediction_x = 'number',
    font = 'string', color = 'color',
    count = 'aggro_number', stack_padding = 'aggro_number', stack_dir = 'aggro_dir',
}
-- Short names: //eb set dist t on  ==  //eb set show_dist t on
local SETTING_ALIASES = {
    target = 'show_target', icon = 'show_target_icon', target_icon = 'show_target_icon',
    action = 'show_action', dist = 'show_dist', distance = 'show_dist', debuff = 'show_debuff',
    prediction = 'show_prediction', killtimer = 'show_kill_timer', kill_timer = 'show_kill_timer',
    alerts = 'show_alerts', size = 'font_size', padding = 'stack_padding', dir = 'stack_dir',
}

function EnemyBar:showSetHelp()
    local names = {}
    for k in pairs(SETTABLE) do names[#names+1] = k end
    table.sort(names)
    windower.add_to_chat(207, 'Usage: //eb set <setting> <target|subtarget|focustarget|aggro|all> <value>')
    windower.add_to_chat(207, '  Settings: ' .. table.concat(names, ', '))
    windower.add_to_chat(207, '  On/off settings take on/off (or toggle); color takes R G B [alpha] (0-255)')
    windower.add_to_chat(207, '  Aggro only: count, stack_padding, stack_dir (up/down)')
    windower.add_to_chat(207, '  Short names: dist, action, target, icon, debuff, prediction, killtimer, alerts, size')
end

function EnemyBar:setSetting(bar, setting, value, args)
    setting = SETTING_ALIASES[setting] or setting
    local kind = SETTABLE[setting]
    if not kind then
        windower.add_to_chat(123, 'EnemyBar: Unknown setting "' .. setting .. '"')
        self:showSetHelp()
        return
    end

    local bar_names = bar == 'all' and {'target', 'subtarget', 'focustarget', 'aggro'} or {bar}
    if kind:sub(1, 6) == 'aggro_' then
        if bar ~= 'aggro' then
            windower.add_to_chat(123, 'EnemyBar: "' .. setting .. '" only applies to the aggro bars')
            return
        end
        kind = kind:sub(7)
    end

    -- Validate and convert the value once
    local parsed
    if kind == 'bool' then
        if value:lower() ~= 'toggle' then
            parsed = self:normalizeBoolean(value)
            if parsed == nil then
                windower.add_to_chat(123, 'EnemyBar: "' .. setting .. '" needs on/off or toggle')
                return
            end
        end
    elseif kind == 'number' then
        parsed = tonumber(value)
        if not parsed or (setting ~= 'x' and setting ~= 'y' and setting ~= 'prediction_x' and parsed <= 0)
        or (setting == 'prediction_x' and parsed < 0) then
            windower.add_to_chat(123, 'EnemyBar: "' .. setting .. '" needs a positive number')
            return
        end
    elseif kind == 'dir' then
        parsed = value:lower()
        if parsed ~= 'up' and parsed ~= 'down' then
            windower.add_to_chat(123, 'EnemyBar: stack_dir must be up or down')
            return
        end
    elseif kind == 'color' then
        local r, g, b, a = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6] or 255)
        local function ok(v) return v and v >= 0 and v <= 255 end
        if not (ok(r) and ok(g) and ok(b) and ok(a)) then
            windower.add_to_chat(123, 'EnemyBar: color needs R G B [alpha], each 0-255')
            return
        end
        parsed = {red = r, green = g, blue = b, alpha = a}
    else
        parsed = value
    end

    for _, name in ipairs(bar_names) do
        local bs = settings[name .. '_bar']
        if setting == 'x' or setting == 'y' then
            bs.pos = {x = bs.pos.x, y = bs.pos.y}
            bs.pos[setting] = parsed
        elseif kind == 'bool' and parsed == nil then
            bs[setting] = not bs[setting]
        else
            bs[setting] = parsed
        end
    end

    local shown = kind == 'color' and table.concat({args[3], args[4], args[5], args[6] or '255'}, ' ')
        or (kind == 'bool' and parsed == nil) and 'toggled' or tostring(parsed)
    windower.add_to_chat(207, 'EnemyBar: ' .. setting .. ' = ' .. shown .. ' for ' .. (bar == 'all' and 'all bars' or bar .. ' bar'))
    if ProfileManager.auto_switch then
        windower.add_to_chat(207, 'EnemyBar: note - auto profile switching can override this on job change (//eb profile auto off)')
    end
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

    local ok, lerr = pcall(Limbus.update, Limbus, EnemyBar.state.setup)
    if not ok then
        windower.add_to_chat(123, 'EnemyBar: Limbus update error - ' .. tostring(lerr))
    end
    ok, lerr = pcall(TargetInfo.update, TargetInfo, EnemyBar.state.setup)
    if not ok then
        windower.add_to_chat(123, 'EnemyBar: TargetInfo update error - ' .. tostring(lerr))
    end
    
    if EnemyBar.player_id then
        EnemyBar:scanClaimedMobs()
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

    -- Debuff icons ride on the target bar, so draw them after it updates
    local dok, derr = pcall(Debuffs.update, Debuffs, EnemyBar.state.setup, EnemyBar.bars.target)
    if not dok then
        windower.add_to_chat(123, 'EnemyBar: Debuffs update error - ' .. tostring(derr))
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
    EnemyBar.state = {setup = false, focustarget = nil, in_cs = false, last_update = 0, last_claim_scan = 0, cleanup_counter = 0}      
end)

windower.register_event('login', function()
    if windower.ffxi.get_info().logged_in then
        EnemyBar.player_id = windower.ffxi.get_player().id
    end
    EnemyBar.state = {setup = false, focustarget = nil, in_cs = false, last_update = 0, last_claim_scan = 0, cleanup_counter = 0}
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
            -- Anchor = whatever is being dragged: the first bar of a set, or the Limbus module
            local anchor = dragged.module or dragged.bars[1]
            if dragged.prediction then
                anchor = {x = dragged.bars[1].x + (dragged.bars[1].prediction_x or math.floor(dragged.bars[1].width/2)), y = 0}
            end
            local d_x, d_y = 0, 0
            if drag_snap_key_down then
                d_x = math.floor(((x - dragged.x) + anchor.x)/10)*10 - anchor.x
                d_y = math.floor(((y - dragged.y) + anchor.y)/10)*10 - anchor.y
            else
                d_x = x - dragged.x
                d_y = y - dragged.y
            end

            if dragged.prediction then
                -- Death prediction: slides along its bar only (y is ignored)
                for _, bar in ipairs(dragged.bars) do
                    local px = bar.prediction_x or math.floor(bar.width/2)
                    bar.prediction_x = math.max(0, math.min(bar.width, px + d_x))
                    bars.move(bar, bar.x, bar.y)
                end
            elseif dragged.module then
                dragged.module:move(dragged.module.x + d_x, dragged.module.y + d_y)
            else
                for i, bar in ipairs(dragged.bars) do
                    bars.move(bar, bar.x + d_x, bar.y + d_y)
                end
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
        
        -- Modules first: the debuff icons sit on top of the target bar, so they
        -- must win the click (they only slide sideways along the bar)
        for _, module in ipairs({Debuffs, DebuffDetails, Limbus, TargetInfo}) do
            if module:hover(x, y) then
                dragged = {module = module, x = x, y = y}
                return true
            end
        end

        -- Death prediction text: grab it to slide it along its bar
        local set_keys = {'target_bar', 'subtarget_bar', 'focustarget_bar', 'aggro_bar'}
        for i, bar_set in ipairs(bar_sets) do
            for _, bar in ipairs(bar_set) do
                local pt = bar and bar.prediction_text
                if pt and pt:visible() and pt:hover(x, y) then
                    dragged = {bars = bar_set, prediction = set_keys[i], x = x, y = y}
                    return true
                end
            end
        end

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
            if dragged.prediction then
                settings[dragged.prediction].prediction_x = dragged.bars[1].prediction_x
            end
            settings.target_bar.pos = {x=EnemyBar.bars.target.x, y=EnemyBar.bars.target.y}
            settings.subtarget_bar.pos = {x=EnemyBar.bars.subtarget.x, y=EnemyBar.bars.subtarget.y}
            settings.focustarget_bar.pos = {x=EnemyBar.bars.focustarget.x, y=EnemyBar.bars.focustarget.y}
            settings.aggro_bar.pos = {x=EnemyBar.bars.aggro[1].x, y=EnemyBar.bars.aggro[1].y}
            settings.limbus_bar.pos = {x=Limbus.x, y=Limbus.y}
            settings.targetinfo_bar.pos = {x=TargetInfo.x, y=TargetInfo.y}
            settings.debuff_details.pos = {x=DebuffDetails.x, y=DebuffDetails.y}
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
    },
    tracking = {alliance=true, pets=true, outside=false},
    debuffs = {
        show=true, icon_size=20, spacing=6, max_icons=10, anchor='left', x=0, offset_y=0,
        timers=true, timer_font='Grammara', timer_size=8, show_th=true,
        keep_buff_after_timer=false, auto_update_enabled=false, auto_profiles_enabled=false
    },
    debuff_details = {
        pos={x=1300,y=120}, font='Grammara', font_size=0,   -- 0 = match the target bar
        show=true, show_shots=true
    },
    targetinfo_bar = {
        pos={x=1500,y=65},
        font='Grammara', font_size=0,   -- 0 = match the target bar's font size
        show=true, show_full_id=true, show_hex_id=true, show_speed=true, show_target_name=false
    },
    limbus_bar = {
        pos={x=150,y=500},
        font='Grammara', font_size=8, row_spacing=14,
        show=true, show_anywhere=false
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
config.register(settings, function()
    tracking_settings.alliance = settings.tracking.alliance
    tracking_settings.pets     = settings.tracking.pets
    tracking_settings.outside  = settings.tracking.outside
    ActionTracker.track_outside_players = tracking_settings.outside
    EnemyBar:initializeBars()
end)

EnemyBar:cachePartyMembers()

-- Welcome message
windower.add_to_chat(207, 'EnemyBar Enhanced v2.5 loaded! Limbus (//eb lh), TargetInfo (//eb ti) and Debuffs (//eb df) included.')
windower.add_to_chat(207, 'Use //eb help for commands, //eb profile list for job profiles.')
