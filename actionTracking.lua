-- Enhanced Action Tracking System with Memory Management
-- Version 2.2 - Fixed Packet Handling and Error Resolution

local res = require('resources')
local packets = require('packets')  -- MISSING REQUIRE - This was causing the errors

-- Constants
local MAX_TRACKED_ENTRIES = 50
local HISTORY_DURATION = 15
local MIN_PREDICTION_SAMPLES = 4
local CLEANUP_FREQUENCY = 150
local CHAIN_SAVER_START = 26
local CHAIN_SAVER_END = 31
local ALERT_DURATION = 3

-- Message ID sets
local MESSAGE_IDS = {
    wears_off = {204, 206},
    tracked = {8, 4, 7, 11, 3, 6, 9, 5},
    starting = {8, 7, 9},
    completed = {4, 11, 3, 5, 6},
    spell = {8, 4},
    item = {5, 9},
    weapon_skill = {3, 7, 11},
    tracked_debuff = {2, 19, 7, 28, 11},
    damaging_spell = {2, 252},
    non_damaging_spell = {75, 236, 237, 268, 270, 271},
    kill = {809, 810}
}

-- Convert to sets for faster lookup
local function createSet(array)
    local set = {}
    for _, v in ipairs(array) do
        set[v] = true
    end
    return set
end

local msg_sets = {}
for name, ids in pairs(MESSAGE_IDS) do
    msg_sets[name] = createSet(ids)
end

-- Dangerous actions database
local DANGEROUS_ACTIONS = createSet({
    'Meteor', 'Flare', 'Death', 'Charm', 'Sleep', 'Bind', 'Petrify', 'Terror',
    'Sleepga', 'Bindga', 'Break', 'Breakga', 'Ancient Magic', 'Bomb Toss',
    'Self-Destruct', 'Final Sting', 'Hundred Fists', 'Mighty Strikes',
    'Tornado', 'Tornado II', 'Firaga IV', 'Firaga V', 'Firaga VI',
    'Blizzaga IV', 'Blizzaga V', 'Blizzaga VI', 'Thundaga IV', 'Thundaga V', 'Thundaga VI'
})

local CRITICAL_ACTIONS = createSet({
    'Meteor', 'Death', 'Self-Destruct', 'Final Sting', 'Ancient Magic',
    'Firaga VI', 'Blizzaga VI', 'Thundaga VI', 'Tornado II'
})

-- Action Tracker Module
ActionTracker = {
    tracked_actions = {},
    tracked_enmity = {},
    tracked_debuff = {},
    hp_tracker = {},
    
    kill_timer = {
        last_kill_time = 0,
        enabled = true,
        chain_saver_enabled = false,
        chain_saver_ws = "NONE",
        chain_saver_window_start = CHAIN_SAVER_START,
        chain_saver_window_end = CHAIN_SAVER_END
    },
    
    alert_system = {
        enabled = true,
        sounds_enabled = true,
        visual_alerts_enabled = true,
        alert_duration = ALERT_DURATION,
        emphasized_abilities = {},
        last_alert_time = 0,
        current_alert = nil
    },
    
    cleanup_counter = 0
}

-- Memory management: enforce size limits
function ActionTracker:enforceMemoryLimits()
    self:limitTableSize(self.tracked_actions, MAX_TRACKED_ENTRIES)
    self:limitTableSize(self.tracked_enmity, MAX_TRACKED_ENTRIES)
    self:limitTableSize(self.tracked_debuff, MAX_TRACKED_ENTRIES)
    self:limitTableSize(self.hp_tracker, MAX_TRACKED_ENTRIES)
end

function ActionTracker:limitTableSize(tbl, max_size)
    local count = 0
    local oldest_key = nil
    local oldest_time = math.huge
    
    for key, data in pairs(tbl) do
        count = count + 1
        local entry_time = type(data) == "table" and data.time or 0
        if entry_time < oldest_time then
            oldest_time = entry_time
            oldest_key = key
        end
    end
    
    while count > max_size and oldest_key do
        tbl[oldest_key] = nil
        count = count - 1
        
        oldest_key = nil
        oldest_time = math.huge
        for key, data in pairs(tbl) do
            local entry_time = type(data) == "table" and data.time or 0
            if entry_time < oldest_time then
                oldest_time = entry_time
                oldest_key = key
            end
        end
    end
end

-- Enhanced packet handling with error protection
function ActionTracker:handleActionPacket(id, data)
    local success, err = pcall(function()
        if id == 0x028 then
            local ai = windower.packets.parse_action(data)
            if ai then
                self:trackEnmity(ai)
                self:trackActions(ai)
                self:trackDebuffs(ai)
                self:handleActionAlerts(ai)
            end
        elseif id == 0x029 then
            self:handleStatusPacket(data)
        elseif id == 0x02D then
            self:handleDeathPacket(data)
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'ActionTracker: Packet error - ' .. tostring(err))
    end
end

function ActionTracker:handleStatusPacket(data)
    if not data then return end
    
    -- Safe packet unpacking with bounds checking
    local success, result = pcall(function()
        local message_id = data:unpack('H', 0x19)
        if not message_id then return end
        
        message_id = message_id % 0x8000
        
        if msg_sets.wears_off[message_id] then
            local param_1 = data:unpack('I', 0x0D)
            local target_id = data:unpack('I', 0x09)
            
            if self.tracked_debuff[target_id] and param_1 then
                self.tracked_debuff[target_id][param_1] = nil
            end
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'ActionTracker: Status packet error')
    end
end

function ActionTracker:handleDeathPacket(data)
    if not data then return end
    
    local success, result = pcall(function()
        local p = packets.parse('incoming', data)
        if p and p['Message'] and msg_sets.kill[p['Message']] then
            self:handleKillEvent()
        end
    end)
    
    if not success then
        windower.add_to_chat(123, 'ActionTracker: Death packet error')
    end
end

function ActionTracker:handleActionAlerts(ai)
    if not self.alert_system.enabled or not ai or not ai.actor_id then return end
    
    local target_id = self:getAlertTargetId()
    if not target_id or ai.actor_id ~= target_id then return end
    
    local action_name, alert_type = self:parseActionData(ai)
    
    if action_name then
        self:triggerActionAlert(action_name, alert_type, ai.actor_id)
    end
end

function ActionTracker:parseActionData(ai)
    local action_name = nil
    local alert_type = nil
    
    if ai.category == 7 then
        if ai.param == 28787 then
            action_name = "Interrupted!"
            alert_type = "interrupt"
        elseif ai.targets and ai.targets[1] and ai.targets[1].actions and ai.targets[1].actions[1] then
            local skill_id = ai.targets[1].actions[1].param
            if skill_id then
                local skill_data = res.monster_abilities[skill_id]
                action_name = skill_data and (skill_data.name or skill_data.en) or "Unknown Ability"
                alert_type = "weapon_skill"
            end
        end
    elseif ai.category == 8 then
        if ai.param == 28787 then
            action_name = "Interrupted!"
            alert_type = "interrupt"
        elseif ai.targets and ai.targets[1] and ai.targets[1].actions and ai.targets[1].actions[1] then
            local spell_id = ai.targets[1].actions[1].param
            if spell_id then
                local spell_data = res.spells[spell_id]
                action_name = spell_data and (spell_data.name or spell_data.en) or "Unknown Spell"
                alert_type = "magic"
            end
        end
    end
    
    return action_name, alert_type
end

function ActionTracker:getAlertTargetId()
    local target = windower.ffxi.get_mob_by_target('t')
    if target and target.is_npc then
        return target.id
    end
    
    local btarget = windower.ffxi.get_mob_by_target('bt')
    if btarget then
        return btarget.id
    end
    
    return nil
end

function ActionTracker:triggerActionAlert(action_name, alert_type, actor_id)
    local current_time = os.clock()
    
    self.alert_system.current_alert = {
        action_name = action_name,
        alert_type = alert_type,
        actor_id = actor_id,
        start_time = current_time,
        is_emphasized = self:isActionEmphasized(action_name),
        is_critical = CRITICAL_ACTIONS[action_name] or false
    }
    
    self.alert_system.last_alert_time = current_time
    
    if self.alert_system.current_alert.is_critical then
        windower.add_to_chat(207, 'CRITICAL ALERT: ' .. action_name .. '!')
    end
    
    if self.alert_system.sounds_enabled then
        self:playAlertSound(action_name, alert_type)
    end
end

function ActionTracker:isActionEmphasized(action_name)
    if not action_name then return false end
    local clean_name = action_name:gsub("%s+", ""):lower()
    return self.alert_system.emphasized_abilities[clean_name] or false
end

function ActionTracker:playAlertSound(action_name, alert_type)
    if self:isActionEmphasized(action_name) or CRITICAL_ACTIONS[action_name] then
        windower.add_to_chat(207, 'CRITICAL: ' .. action_name .. '!')
    elseif alert_type == "interrupt" then
        windower.add_to_chat(207, 'Interrupted!')
    elseif DANGEROUS_ACTIONS[action_name] then
        windower.add_to_chat(207, 'WARNING: ' .. action_name)
    end
end

function ActionTracker:getCurrentAlert()
    if not self.alert_system.current_alert then return nil end
    
    local current_time = os.clock()
    local elapsed = current_time - self.alert_system.current_alert.start_time
    
    if elapsed > self.alert_system.alert_duration then
        self.alert_system.current_alert = nil
        return nil
    end
    
    return self.alert_system.current_alert
end

function ActionTracker:trackHPChanges(target_id, current_hp, current_time)
    if not target_id or not current_hp or not current_time then
        return nil
    end
    
    if not self.hp_tracker[target_id] then
        self.hp_tracker[target_id] = {
            samples = {},
            last_prediction = nil,
            trend = 0,
            last_hp = current_hp
        }
    end
    
    local tracker = self.hp_tracker[target_id]
    
    if current_hp ~= tracker.last_hp then
        table.insert(tracker.samples, {
            hp = current_hp,
            time = current_time
        })
        tracker.last_hp = current_hp
        
        local cutoff = current_time - HISTORY_DURATION
        tracker.samples = self:filterSamplesByTime(tracker.samples, cutoff)
        
        if #tracker.samples >= MIN_PREDICTION_SAMPLES then
            tracker.last_prediction = self:calculateDeathPrediction(tracker.samples)
        end
    end
    
    return tracker.last_prediction
end

function ActionTracker:filterSamplesByTime(samples, cutoff)
    local filtered = {}
    for _, sample in ipairs(samples) do
        if sample.time > cutoff then
            table.insert(filtered, sample)
        end
    end
    return filtered
end

function ActionTracker:calculateDeathPrediction(samples)
    if #samples < 2 then return nil end
    
    local oldest = samples[1]
    local newest = samples[#samples]
    local time_diff = newest.time - oldest.time
    local hp_diff = oldest.hp - newest.hp
    
    if time_diff > 2 and hp_diff > 0 then
        local trend = hp_diff / time_diff
        if trend > 0.1 then
            return newest.hp / trend
        end
    end
    
    return nil
end

function ActionTracker:trackEnmity(ai)
    if not ai or not ai.actor_id then return end
    
    local mob_id = ai.actor_id
    
    if not self:isNPC(mob_id) then return end
    
    local mob = windower.ffxi.get_mob_by_id(mob_id)
    if not mob or not mob.hpp or mob.hpp == 0 then return end
    
    local target_id = ai.targets and ai.targets[1] and ai.targets[1].id or nil
    
    if not self.tracked_enmity[mob_id] then
        self.tracked_enmity[mob_id] = {}
    end
    
    self.tracked_enmity[mob_id].mob = mob_id
    self.tracked_enmity[mob_id].time = os.time()
    
    if target_id and not self:isNPC(target_id) then
        self.tracked_enmity[mob_id].pc = target_id
    end
end

function ActionTracker:trackActions(ai)
    if not ai or not ai.actor_id then return end
    
    local mob_id = ai.actor_id
    
    if not self:isNPC(mob_id) then return end
    
    local mob = windower.ffxi.get_mob_by_id(mob_id)
    if not mob or not mob.hpp or mob.hpp == 0 then return end
    
    if ai.category == 1 then return end
    
    if ai.category ~= 7 and ai.category ~= 8 then return end
    
    local action_data = {
        mob = mob_id,
        time = os.time(),
        complete = false,
        ability = nil,
        is_dangerous = false
    }
    
    if ai.targets and ai.targets[1] and ai.targets[1].actions and ai.targets[1].actions[1] then
        local param = ai.targets[1].actions[1].param
        if param then
            if ai.category == 7 then
                local skill_data = res.monster_abilities[param]
                if skill_data then
                    action_data.ability = skill_data
                    action_data.is_dangerous = DANGEROUS_ACTIONS[skill_data.name] or DANGEROUS_ACTIONS[skill_data.en] or false
                end
            elseif ai.category == 8 then
                local spell_data = res.spells[param]
                if spell_data then
                    action_data.ability = spell_data
                    action_data.is_dangerous = DANGEROUS_ACTIONS[spell_data.name] or DANGEROUS_ACTIONS[spell_data.en] or false
                end
            end
        end
    end
    
    self.tracked_actions[mob_id] = action_data
end

function ActionTracker:trackDebuffs(ai)
    if not ai or not ai.targets then return end
    
    local time = os.time()
    
    for _, target in ipairs(ai.targets) do
        if target.actions then
            for _, action in ipairs(target.actions) do
                if action.message and msg_sets.tracked_debuff[action.message] then
                    local target_id = target.id
                    local effect_id = action.param
                    
                    if target_id and effect_id then
                        if not self.tracked_debuff[target_id] then
                            self.tracked_debuff[target_id] = {}
                        end
                        
                        local duration = self:getDebuffDuration(effect_id)
                        
                        self.tracked_debuff[target_id][effect_id] = {
                            time = time,
                            duration = duration
                        }
                    end
                end
            end
        end
    end
end

function ActionTracker:getDebuffDuration(effect_id)
    local durations = {
        [2] = 90, [19] = 90, [7] = 30, [11] = 60, [28] = 15
    }
    return durations[effect_id] or 60
end

function ActionTracker:getSmartAggroList(max_count, filter_settings)
    local threats = {}
    local player = windower.ffxi.get_mob_by_target('me')
    if not player then return {} end
    
    local player_pos = {x = player.x, y = player.y}
    local current_time = os.time()
    
    for mob_id, enmity_data in pairs(self.tracked_enmity) do
        local mob = windower.ffxi.get_mob_by_id(mob_id)
        if mob and mob.hpp and mob.hpp > 0 and mob.x and mob.y then
            self:trackHPChanges(mob_id, mob.hpp, current_time)
            
            local threat_score = self:calculateThreatScore(mob, enmity_data, player_pos)
            local distance = self:getDistance(player_pos, mob)
            
            local should_show = self:shouldShowThreat(threat_score, distance, mob_id, filter_settings)
            
            if should_show then
                table.insert(threats, {
                    mob_id = mob_id,
                    threat_score = threat_score,
                    distance = distance,
                    hpp = mob.hpp,
                    death_prediction = self:getDeathPrediction(mob_id)
                })
            end
        end
    end
    
    table.sort(threats, function(a, b) 
        local a_dying = a.death_prediction and a.death_prediction < 5
        local b_dying = b.death_prediction and b.death_prediction < 5
        
        if a_dying and a.threat_score < 2 then
            return false
        elseif b_dying and b.threat_score < 2 then
            return true
        else
            return a.threat_score > b.threat_score 
        end
    end)
    
    local result = {}
    for i = 1, math.min(max_count or 6, #threats) do
        table.insert(result, threats[i])
    end
    
    return result
end

function ActionTracker:calculateThreatScore(mob, enmity_data, player_pos)
    if not mob or not player_pos or not mob.x or not mob.y or not mob.hpp then 
        return 0 
    end
    
    local distance = self:getDistance(player_pos, mob)
    if distance > 50 then return 0 end
    
    local distance_factor = math.max(0, (50 - distance) / 50)
    local hp_factor = mob.hpp / 100
    local player = windower.ffxi.get_player()
    if player and player.main_job and (player.main_job == 'PLD' or player.main_job == 'NIN' or player.main_job == 'RUN') then
        hp_factor = 1.2 - hp_factor
    end
    
    local enmity_factor = self:calculateEnmityFactor(enmity_data)
    local debuff_factor = self:calculateDebuffFactor(mob.id)
    local action_factor = self:calculateActionFactor(mob.id)
    local prediction_factor = self:calculatePredictionFactor(mob.id)
    
    return math.max(0, distance_factor * hp_factor * enmity_factor * 
                       debuff_factor * action_factor * prediction_factor)
end

function ActionTracker:calculateEnmityFactor(enmity_data)
    if not enmity_data then return 0.5 end
    
    local player_obj = windower.ffxi.get_player()
    if player_obj and enmity_data.pc == player_obj.id then
        return 3.0  -- Player has aggro - highest priority
    end
    
    -- Check if the target is a party/alliance member using our own function
    local is_party_member = self:isPartyMemberOrPet(enmity_data.pc)
    
    if is_party_member then
        -- For now, treat all party/alliance members the same
        -- We'll add more detailed tracking settings later
        return 2.0  -- Party/alliance member
    end
    
    -- If it's not a party member, give it very low priority to filter it out
    return 0.1  -- Very low priority, effectively filtered out
end

function ActionTracker:calculateDebuffFactor(mob_id)
    if self.tracked_debuff[mob_id] then
        for effect_id, _ in pairs(self.tracked_debuff[mob_id]) do
            if msg_sets.tracked_debuff[effect_id] then
                return 0.1
            end
        end
    end
    return 1.0
end

function ActionTracker:calculateActionFactor(mob_id)
    local action = self.tracked_actions[mob_id]
    if action and not action.complete then
        local action_name = action.ability and (action.ability.name or action.ability.en)
        if DANGEROUS_ACTIONS[action_name] then
            return 4.0
        else
            return 1.8
        end
    end
    return 1.0
end

function ActionTracker:calculatePredictionFactor(mob_id)
    local death_time = self:getDeathPrediction(mob_id)
    if death_time and death_time < 10 then
        return 0.3
    elseif death_time and death_time < 20 then
        return 0.7
    end
    return 1.0
end

function ActionTracker:shouldShowThreat(threat_score, distance, mob_id, filter_settings)
    if not filter_settings then return true end
    
    if threat_score < (filter_settings.min_threat or 0) then
        return false
    end
    
    if distance > (filter_settings.max_distance or 50) then
        return false
    end
    
    if not filter_settings.show_debuffed then
        if self.tracked_debuff[mob_id] then
            for effect_id, _ in pairs(self.tracked_debuff[mob_id]) do
                if msg_sets.tracked_debuff[effect_id] then
                    return false
                end
            end
        end
    end
    
    return true
end

function ActionTracker:handleKillEvent()
    self.kill_timer.last_kill_time = os.time()
    
    if self.kill_timer.chain_saver_enabled then
        coroutine.wrap(function()
            coroutine.sleep(self.kill_timer.chain_saver_window_start)
            self:checkChainSaver()
        end)()
    end
end

function ActionTracker:checkChainSaver()
    if not self.kill_timer.chain_saver_enabled then return end
    
    local current_time = os.time()
    local time_since_kill = current_time - self.kill_timer.last_kill_time
    
    if time_since_kill >= self.kill_timer.chain_saver_window_start and 
       time_since_kill <= self.kill_timer.chain_saver_window_end then
        
        local player = windower.ffxi.get_player()
        if player and player.vitals and player.vitals.tp >= 1000 then
            if self.kill_timer.chain_saver_ws ~= "NONE" and self.kill_timer.chain_saver_ws ~= "" then
                windower.add_to_chat(207, 'Chain Saver Triggered: ' .. player.vitals.tp .. ' TP')
                windower.chat.input('/ws "' .. self.kill_timer.chain_saver_ws .. '" <t>')
            end
        end
    end
end

function ActionTracker:getTimeSinceKill()
    if self.kill_timer.last_kill_time == 0 then
        return nil
    end
    
    local current_time = os.time()
    local time_diff = current_time - self.kill_timer.last_kill_time
    
    if time_diff > 300 then
        return "Too Long - Focus!"
    end
    
    return time_diff
end

function ActionTracker:getKillTimerColor(time_since_kill)
    if not time_since_kill or type(time_since_kill) == "string" then
        return {red=192, green=192, blue=192}
    end
    
    if time_since_kill < 10 then
        return {red=100, green=255, blue=100}
    elseif time_since_kill < 30 then
        return {red=255, green=255, blue=100}
    elseif time_since_kill < 60 then
        return {red=255, green=200, blue=100}
    else
        return {red=255, green=100, blue=100}
    end
end

-- Command handlers and utility functions
function ActionTracker:handleKillTimerCommand(args)
    if not args[1] or args[1] == 'toggle' then
        self:toggleKillTimer()
    elseif args[1] == 'reset' then
        self:resetKillTimer()
    elseif args[1] == 'chainsaver' then
        if not args[2] or args[2] == 'toggle' then
            self:toggleChainSaver()
        elseif args[2] == 'ws' then
            local ws_name = table.concat(args, ' ', 3)
            self:setChainSaverWS(ws_name)
        end
    elseif args[1] == 'status' then
        self:showKillTimerStatus()
    else
        self:showKillTimerHelp()
    end
end

function ActionTracker:handleAlertCommand(args)
    if not args[1] or args[1] == 'toggle' then
        self:toggleAlertSystem()
    elseif args[1] == 'sounds' then
        if args[2] then
            self.alert_system.sounds_enabled = self:normalizeBoolean(args[2])
            windower.add_to_chat(207, 'Alert Sounds: ' .. (self.alert_system.sounds_enabled and 'ON' or 'OFF'))
        else
            self:toggleAlertSounds()
        end
    elseif args[1] == 'duration' then
        if args[2] and tonumber(args[2]) then
            self:setAlertDuration(tonumber(args[2]))
        else
            windower.add_to_chat(123, 'Please specify duration in seconds')
        end
    elseif args[1] == 'emphasize' then
        self:handleEmphasizeCommand(args)
    elseif args[1] == 'test' then
        self:handleTestCommand(args)
    elseif args[1] == 'status' then
        self:showAlertStatus()
    else
        self:showAlertHelp()
    end
end

function ActionTracker:handleEmphasizeCommand(args)
    if args[2] == 'list' then
        self:listEmphasizedAbilities()
    elseif args[2] == 'add' and args[3] then
        local ability_name = table.concat(args, ' ', 3)
        self:addEmphasizedAbility(ability_name)
    elseif args[2] == 'remove' and args[3] then
        local ability_name = table.concat(args, ' ', 3)
        self:removeEmphasizedAbility(ability_name)
    else
        windower.add_to_chat(207, 'Alert Emphasize Commands:')
        windower.add_to_chat(207, '  //eb alert emphasize list - Show emphasized abilities')
        windower.add_to_chat(207, '  //eb alert emphasize add [ability] - Add emphasis')
        windower.add_to_chat(207, '  //eb alert emphasize remove [ability] - Remove emphasis')
    end
end

function ActionTracker:handleTestCommand(args)
    local test_target_id = nil
    local target = windower.ffxi.get_mob_by_target('t')
    if target and target.is_npc then
        test_target_id = target.id
        windower.add_to_chat(207, 'Testing alert on target: ' .. target.name)
    else
        test_target_id = 12345
        windower.add_to_chat(207, 'Alert Test: Target an enemy to see visual alerts')
    end
    
    if args[2] == 'ws' then
        self:triggerActionAlert("Test Weapon Skill", "weapon_skill", test_target_id)
    elseif args[2] == 'magic' then
        self:triggerActionAlert("Test Magic", "magic", test_target_id)
    elseif args[2] == 'critical' then
        self:triggerActionAlert("Meteor", "magic", test_target_id)
    else
        windower.add_to_chat(207, 'Test options: ws, magic, critical')
        windower.add_to_chat(207, 'Target an enemy first to see visual alerts')
    end
end

function ActionTracker:toggleAlertSystem()
    self.alert_system.enabled = not self.alert_system.enabled
    windower.add_to_chat(207, 'Alert System: ' .. (self.alert_system.enabled and 'ON' or 'OFF'))
end

function ActionTracker:toggleAlertSounds()
    self.alert_system.sounds_enabled = not self.alert_system.sounds_enabled
    windower.add_to_chat(207, 'Alert Sounds: ' .. (self.alert_system.sounds_enabled and 'ON' or 'OFF'))
end

function ActionTracker:setAlertDuration(duration)
    if duration and duration > 0 then
        self.alert_system.alert_duration = duration
        windower.add_to_chat(207, 'Alert Duration set to: ' .. duration .. ' seconds')
    end
end

function ActionTracker:addEmphasizedAbility(ability_name)
    if not ability_name then return end
    local clean_name = ability_name:gsub("%s+", ""):lower()
    self.alert_system.emphasized_abilities[clean_name] = true
    windower.add_to_chat(207, 'Added emphasis for: ' .. ability_name)
end

function ActionTracker:removeEmphasizedAbility(ability_name)
    if not ability_name then return end
    local clean_name = ability_name:gsub("%s+", ""):lower()
    self.alert_system.emphasized_abilities[clean_name] = nil
    windower.add_to_chat(207, 'Removed emphasis for: ' .. ability_name)
end

function ActionTracker:listEmphasizedAbilities()
    windower.add_to_chat(207, 'Emphasized Abilities:')
    local count = 0
    for ability, _ in pairs(self.alert_system.emphasized_abilities) do
        windower.add_to_chat(207, '  - ' .. ability)
        count = count + 1
    end
    if count == 0 then
        windower.add_to_chat(207, '  (none)')
    end
end

function ActionTracker:normalizeBoolean(value)
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

function ActionTracker:toggleKillTimer()
    self.kill_timer.enabled = not self.kill_timer.enabled
    windower.add_to_chat(207, 'Kill Timer: ' .. (self.kill_timer.enabled and 'ON' or 'OFF'))
end

function ActionTracker:resetKillTimer()
    self.kill_timer.last_kill_time = 0
    windower.add_to_chat(207, 'Kill Timer reset')
end

function ActionTracker:toggleChainSaver()
    self.kill_timer.chain_saver_enabled = not self.kill_timer.chain_saver_enabled
    windower.add_to_chat(207, 'Chain Saver: ' .. (self.kill_timer.chain_saver_enabled and 'ON' or 'OFF'))
end

function ActionTracker:setChainSaverWS(ws_name)
    self.kill_timer.chain_saver_ws = ws_name or "NONE"
    windower.add_to_chat(207, 'Chain Saver WS set to: ' .. self.kill_timer.chain_saver_ws)
end

function ActionTracker:showKillTimerStatus()
    windower.add_to_chat(207, 'Kill Timer Status:')
    windower.add_to_chat(207, '  Enabled: ' .. (self.kill_timer.enabled and 'ON' or 'OFF'))
    windower.add_to_chat(207, '  Chain Saver: ' .. (self.kill_timer.chain_saver_enabled and 'ON' or 'OFF'))
    windower.add_to_chat(207, '  Chain Saver WS: ' .. self.kill_timer.chain_saver_ws)
    local time_since = self:getTimeSinceKill()
    if time_since then
        windower.add_to_chat(207, '  Time Since Kill: ' .. tostring(time_since))
    else
        windower.add_to_chat(207, '  Time Since Kill: No kills tracked')
    end
end

function ActionTracker:showKillTimerHelp()
    windower.add_to_chat(207, 'Kill Timer Commands:')
    windower.add_to_chat(207, '  //eb killtimer [toggle] - Toggle kill timer display')
    windower.add_to_chat(207, '  //eb killtimer reset - Reset kill timer')
    windower.add_to_chat(207, '  //eb killtimer chainsaver [toggle] - Toggle chain saver')
    windower.add_to_chat(207, '  //eb killtimer chainsaver ws [weapon skill] - Set chain saver WS')
    windower.add_to_chat(207, '  //eb killtimer status - Show current settings')
end

function ActionTracker:showAlertStatus()
    windower.add_to_chat(207, 'Alert System Status:')
    windower.add_to_chat(207, '  Enabled: ' .. (self.alert_system.enabled and 'ON' or 'OFF'))
    windower.add_to_chat(207, '  Sounds: ' .. (self.alert_system.sounds_enabled and 'ON' or 'OFF'))
    windower.add_to_chat(207, '  Duration: ' .. self.alert_system.alert_duration .. ' seconds')
    local count = 0
    for _ in pairs(self.alert_system.emphasized_abilities) do count = count + 1 end
    windower.add_to_chat(207, '  Emphasized Abilities: ' .. count)
end

function ActionTracker:showAlertHelp()
    windower.add_to_chat(207, 'Alert System Commands:')
    windower.add_to_chat(207, '  //eb alert [toggle] - Toggle alert system')
    windower.add_to_chat(207, '  //eb alert sounds [on/off] - Toggle alert sounds')
    windower.add_to_chat(207, '  //eb alert duration [seconds] - Set alert duration')
    windower.add_to_chat(207, '  //eb alert emphasize [add/remove/list] - Manage emphasized abilities')
    windower.add_to_chat(207, '  //eb alert test [ws/magic/critical] - Test alerts')
    windower.add_to_chat(207, '  //eb alert status - Show current settings')
end

-- Public getter functions
function ActionTracker:getTrackedAction(mob_id)
    return self.tracked_actions[mob_id]
end

function ActionTracker:getTrackedEnmity(mob_id)
    return self.tracked_enmity[mob_id]
end

function ActionTracker:getTrackedDebuff(mob_id)
    return self.tracked_debuff[mob_id]
end

function ActionTracker:getDeathPrediction(mob_id)
    local tracker = self.hp_tracker[mob_id]
    return tracker and tracker.last_prediction or nil
end

function ActionTracker:isNPC(mob_id)
    if not mob_id then return false end
    
    local is_pc = mob_id < 0x01000000
    local is_pet = mob_id > 0x01000000 and mob_id % 0x1000 > 0x700

    if is_pc or is_pet then return false end

    local mob = windower.ffxi.get_mob_by_id(mob_id)
    if not mob then return nil end
    return mob.is_npc and not mob.charmed
end

function ActionTracker:getDistance(pos1, pos2)
    if not pos1 or not pos2 or not pos1.x or not pos1.y or not pos2.x or not pos2.y then
        return 999
    end
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    return math.sqrt(dx*dx + dy*dy)
end

function ActionTracker:isPartyMemberOrPet(mob_id)
    if not mob_id then return false end
    
    local player = windower.ffxi.get_player()
    if not player then return false end
    
    -- Check if it's the player themselves
    if mob_id == player.id then return true end
    
    -- Check if it's an NPC (monsters don't count as party members)
    if self:isNPC(mob_id) then return false end
    
    local party = windower.ffxi.get_party()
    if not party then return false end
    
    -- Check party members (party1)
    for i = 0, (party.party1_count or 0) - 1 do
        local member = party['p'..i]
        if member and member.mob and member.mob.id == mob_id then
            return true
        end
        -- Check pets
        if member and member.mob and member.mob.pet_index then
            local pet = windower.ffxi.get_mob_by_index(member.mob.pet_index)
            if pet and pet.id == mob_id then
                return true
            end
        end
    end
    
    -- Check alliance members (party2 and party3)
    for i = 0, (party.party2_count or 0) - 1 do
        local member = party['a1'..i]
        if member and member.mob and member.mob.id == mob_id then
            return true
        end
        -- Check pets
        if member and member.mob and member.mob.pet_index then
            local pet = windower.ffxi.get_mob_by_index(member.mob.pet_index)
            if pet and pet.id == mob_id then
                return true
            end
        end
    end
    
    for i = 0, (party.party3_count or 0) - 1 do
        local member = party['a2'..i]
        if member and member.mob and member.mob.id == mob_id then
            return true
        end
        -- Check pets
        if member and member.mob and member.mob.pet_index then
            local pet = windower.ffxi.get_mob_by_index(member.mob.pet_index)
            if pet and pet.id == mob_id then
                return true
            end
        end
    end
    
    return false
end

function ActionTracker:cleanupTrackedData()
    local time = os.time()
    local player = windower.ffxi.get_mob_by_target("me")
    
    for id, action in pairs(self.tracked_actions) do
        if not action.complete and time - action.time > 30 then
            self.tracked_actions[id] = nil
        elseif action.complete and time - action.time > 3 then
            self.tracked_actions[id] = nil
        end
    end

    for id, enmity in pairs(self.tracked_enmity) do
        if time - enmity.time > 5 then
            local mob = windower.ffxi.get_mob_by_id(enmity.mob)
            if not mob or not mob.hpp or mob.hpp == 0 then
                self.tracked_enmity[id] = nil
            elseif mob.status == 0 then
                self.tracked_enmity[id] = nil
            elseif player and self:getDistance(player, mob) > 50 then
                self.tracked_enmity[id] = nil
            end
        end
    end

    for id, debuffs in pairs(self.tracked_debuff) do
        local mob = windower.ffxi.get_mob_by_id(id)
        if not mob or not mob.hpp or mob.hpp == 0 then
            self.tracked_debuff[id] = nil
        else
            for effect_id, debuff in pairs(debuffs) do
                if time - debuff.time > debuff.duration * 1.5 then 
                    self.tracked_debuff[id][effect_id] = nil
                end
            end
        end
    end
    
    for id, tracker in pairs(self.hp_tracker) do
        local mob = windower.ffxi.get_mob_by_id(id)
        if not mob or not mob.hpp or mob.hpp == 0 then
            self.hp_tracker[id] = nil
        elseif #tracker.samples > 0 then
            local last_sample_time = tracker.samples[#tracker.samples].time
            if time - last_sample_time > 30 then
                self.hp_tracker[id] = nil
            end
        end
    end

    self:enforceMemoryLimits()
end

function ActionTracker:resetTrackedData()
    self.tracked_actions = {}
    self.tracked_enmity = {}
    self.tracked_debuff = {}
    self.hp_tracker = {}
    self.kill_timer.last_kill_time = 0
    self.alert_system.current_alert = nil
end

-- Helper functions for external access
function get_current_alert()
    return ActionTracker:getCurrentAlert()
end

function get_death_prediction(target_id)
    return ActionTracker:getDeathPrediction(target_id)
end

function get_death_prediction_color(seconds_left)
    if not seconds_left then 
        return {red=255, green=255, blue=255}
    end
    
    if seconds_left < 5 then
        return {red=255, green=50, blue=50}
    elseif seconds_left < 15 then
        return {red=255, green=150, blue=50}
    elseif seconds_left < 30 then
        return {red=255, green=200, blue=100}
    else
        return {red=150, green=255, blue=150}
    end
end

function get_time_since_kill()
    return ActionTracker:getTimeSinceKill()
end

function get_kill_timer_color(time_since_kill)
    return ActionTracker:getKillTimerColor(time_since_kill)
end

function toggle_kill_timer()
    ActionTracker:toggleKillTimer()
end

function reset_kill_timer()
    ActionTracker:resetKillTimer()
end

function toggle_chain_saver()
    ActionTracker:toggleChainSaver()
end

function set_chain_saver_ws(ws_name)
    ActionTracker:setChainSaverWS(ws_name)
end

function toggle_alert_system()
    ActionTracker:toggleAlertSystem()
end

function toggle_alert_sounds()
    ActionTracker:toggleAlertSounds()
end

function set_alert_duration(duration)
    ActionTracker:setAlertDuration(duration)
end

function add_emphasized_ability(ability_name)
    ActionTracker:addEmphasizedAbility(ability_name)
end

function remove_emphasized_ability(ability_name)
    ActionTracker:removeEmphasizedAbility(ability_name)
end

function list_emphasized_abilities()
    ActionTracker:listEmphasizedAbilities()
end

function trigger_action_alert(action_name, alert_type, actor_id)
    ActionTracker:triggerActionAlert(action_name, alert_type, actor_id)
end

function clean_tracked_actions()
    ActionTracker:cleanupTrackedData()
end

function reset_tracked_actions()
    ActionTracker:resetTrackedData()
end