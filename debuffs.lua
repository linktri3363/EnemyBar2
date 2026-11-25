--[[
    Debuffs module for EnemyBar2.

    Tracking is ported from the Debuffing addon (Xathe's Debuffed -> Auk's
    Debuffing -> Nsane's overhaul, maintained by Linktri; BSD 3-clause).
    Instead of Debuffing's text box, debuffs on your current target are drawn
    as status icons on the target bar: the newest sits at the bar's right
    edge and older ones shift left, each with a countdown timer under it.

    Icons (icons/buffs/<buff id>.png) come from XivParty's assets, which
    credit KenshiDRK's partybuffs.

    Commands: //eb df help
]]

require('luau')
local files   = require('files')
local packets = require('packets')
local texts   = require('texts')
local images  = require('images')
local config  = require('config')
local bit     = require('bit')
local others  = require('debuffs_bluemagic')

local BAR_HEIGHT = 12
local ICON_PATH  = windower.addon_path..'icons/buffs/'

local DEFAULT_CFG = {
    show = true, icon_size = 20, spacing = 6, max_icons = 10,
    anchor = 'left', x = 0, offset_y = 0,
    timers = true, timer_font = 'Grammara', timer_size = 8,
    show_th = true,
    keep_buff_after_timer = false, auto_update_enabled = false, auto_profiles_enabled = false,
}

local function log(msg) windower.add_to_chat(207, 'EnemyBar Debuffs: '..tostring(msg)) end

-- Settings live in EB2's settings.xml under <debuffs>
local function cfg()
    if settings and not settings.debuffs then settings.debuffs = DEFAULT_CFG end
    return settings and settings.debuffs or DEFAULT_CFG
end
local function save_cfg() if settings then settings:save() end end

-- ---------------------------------------------------------------------------
-- Tracking state (ported from Debuffing)
-- ---------------------------------------------------------------------------
local player, simulation_mode = nil, false
local owner_key = 'unknown'
local debuffed_mobs, TH, step_duration = {}, {}, {}
local purge_time = 0
local add_seq = 0
local function next_seq() add_seq = add_seq + 1; return add_seq end
local durations, duration_profiles = {}, {}

local debuffs_map = {}
local absorb_map = {
  [242]={effect=242,duration=90},[266]={effect=266,duration=90},[267]={effect=267,duration=90},[268]={effect=268,duration=90},
  [269]={effect=269,duration=90},[270]={effect=270,duration=90},[271]={effect=271,duration=90},[272]={effect=272,duration=90}
}
local ja_map = { [150]={effect=149,duration=90}, [170]={effect=149,duration=90} }
local EXTREMES = { [502]={effect=23,element=7,duration=100}, [503]={effect=142,element=7,duration=180} }
local BloodPact_map = { [580]={duration=90},[585]={duration=90},[611]={duration=90},[617]={duration=180},[633]={duration=15},[657]={duration=60},[963]={duration=90},[966]={duration=180} }
local JA_SPELLS = S{496,497,498,499,500,501}
local ERASE_ABILITIES=S{2370,2571,2714,2718,2775,2831}
local PARTIAL_ERASE_ABILITIES=S{1245,1273}

-- Step debuffs are keyed by the step's ability id; their icons are the
-- daze buff ids, one per level (lv.1..lv.5)
local STEP_ICON_BASE = { [201]=386, [202]=391, [203]=396, [312]=448 }

-- Auto-profile helpers
local current_profile = nil
local function _norm_key(s) return tostring(s or ''):lower() end
local function _job_profile_name()
    player = windower.ffxi.get_player()
    if not player or not player.main_job_id then return nil end
    local j = res.jobs[player.main_job_id]
    return j and (j.ens or j.en) or nil
end
local function _deepcopy(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=_deepcopy(v) end return r end
local function _ensure_profile_tables()
    duration_profiles[owner_key] = duration_profiles[owner_key] or {}
    duration_profiles[owner_key].profiles = duration_profiles[owner_key].profiles or {}
    durations[owner_key] = durations[owner_key] or {}
    durations[owner_key].spells = durations[owner_key].spells or {}
end
local function _resolve_profile_key(name)
    if not name then return nil end
    _ensure_profile_tables()
    local store = duration_profiles[owner_key].profiles
    local want = _norm_key(name)
    if store[want] then return want end
    for k, v in pairs(store) do
        local label = type(v) == 'table' and v.label or nil
        if _norm_key(k) == want or (label and _norm_key(label) == want) then return _norm_key(k) end
    end
    return want
end
local function _apply_job_profile()
    if not cfg().auto_profiles_enabled then current_profile = nil; return end
    _ensure_profile_tables()
    local pname = _job_profile_name(); if not pname then return end
    local key = _resolve_profile_key(pname)
    current_profile = key
    durations[owner_key].spells = {}
    local store = duration_profiles[owner_key].profiles
    store[key] = store[key] or { spells = {} }
    store[key].label = store[key].label or pname
    if store[key].spells then
        durations[owner_key].spells = _deepcopy(store[key].spells)
        log('Auto profile loaded: '..(store[key].label or key))
    else
        log('Auto profile new: '..(store[key].label or key))
    end
    config.save(duration_profiles, 'all')
    config.save(durations, 'all')
end
local function _sync_profile(spell_id, secs_or_nil)
    if not (cfg().auto_profiles_enabled and current_profile) then return end
    _ensure_profile_tables()
    local store = duration_profiles[owner_key].profiles
    store[current_profile] = store[current_profile] or { spells = {} }
    store[current_profile].spells[tostring(spell_id)] = secs_or_nil
    config.save(duration_profiles, 'all')
end

local function base_name(s) local b=s:match('^([^%(]+)') or s; return (b:gsub('%s+$','')) end
local function tlen(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
local function is_threnody_spell(id) local s=res.spells[id]; return s and s.en and s.en:find('Threnody') end
local function is_enemy(id) if not id then return false end local m=windower.ffxi.get_mob_by_id(id) return m and m.is_npc and (m.spawn_type==16 or m.claim_id~=0) end

local function is_helix_id(id) local s = res.spells[id]; return s and s.en and s.en:lower():find('helix') end

-- Damage labels (shown in the details panel)
local function dmg_label(n)
    return (n >= 1000) and ((math.floor(n/1000) == n/1000) and string.format('%.0fk', n/1000) or string.format('%.1fk', n/1000)) or tostring(n)
end
local function kaustra_store_dmg(tgt, effect_id, raw_param)
    local n = math.floor((tonumber(raw_param) or 0) / 4 / 100 + 0.5) * 100
    if debuffed_mobs[tgt] and debuffed_mobs[tgt][effect_id] then
        debuffed_mobs[tgt][effect_id].kaustra = true
        debuffed_mobs[tgt][effect_id].dmg_str = dmg_label(n)
    end
end
local function helix_store_dmg(tgt, effect_id, raw_param, spell_id)
    local dmg = tonumber(raw_param) or 0
    if dmg <= 0 then return end
    local n = math.floor(math.min(dmg, 10000) / 100 + 0.5) * 100
    if debuffed_mobs[tgt] and debuffed_mobs[tgt][effect_id] then
        debuffed_mobs[tgt][effect_id].helix = true
        debuffed_mobs[tgt][effect_id].dmg_str = dmg_label(n)
        debuffed_mobs[tgt][effect_id].element = res.spells[spell_id] and res.spells[spell_id].element
    end
end

-- Elemental shots (COR): recorded on the debuff they enhance
local SHOT_INFO = {
    [125] = {name = 'Fire Shot',    element = 0}, [126] = {name = 'Ice Shot',   element = 1},
    [127] = {name = 'Wind Shot',    element = 2}, [128] = {name = 'Earth Shot', element = 3},
    [129] = {name = 'Thunder Shot', element = 4}, [130] = {name = 'Water Shot', element = 5},
    [131] = {name = 'Light Shot',   element = 6}, [132] = {name = 'Dark Shot',  element = 7},
}
local function add_shot(entry, shot, stackable)
    if not entry then return end
    if entry.shot and not stackable then return end
    entry.shot = (entry.shot or 0) + 1
    entry.shot_id = shot
end
local function handle_shot(target, shot)
    local m = debuffed_mobs[target]; if not m then return end
    if shot == 125 then add_shot(m[128], shot, true)
    elseif shot == 126 then
        if m[4] and T{58,80}:contains(m[4].id) then add_shot(m[4], shot) end
        add_shot(m[129], shot, true)
    elseif shot == 127 then add_shot(m[130], shot, true)
    elseif shot == 128 then
        if m[13] and T{56,344,345}:contains(m[13].id) then add_shot(m[13], shot) end
        add_shot(m[131], shot, true)
    elseif shot == 129 then add_shot(m[132], shot, true)
    elseif shot == 130 then
        if m[3] and T{220,221}:contains(m[3].id) then add_shot(m[3], shot) end
        add_shot(m[133], shot, true)
    elseif shot == 131 then add_shot(m[134], shot)
    elseif shot == 132 then
        if m[5] and T{254,276,347,348}:contains(m[5].id) then add_shot(m[5], shot) end
        add_shot(m[135], shot)
    end
end

local function remove_debuff(target, effect, opts)
    opts = opts or {}
    if not (debuffed_mobs[target] and debuffed_mobs[target][effect]) then return end
    local e = debuffed_mobs[target][effect]

    -- Timer hint / auto-learn: when a debuff that outlived its timer finally
    -- wears off, its real duration is base + overtime.
    if type(e) == 'table' and e.expired_at and not e.no_hint and not opts.no_hint
    and not (simulation_mode and player and target == player.id)
    and cfg().keep_buff_after_timer then
        local sid = tonumber(e.id or 0) or 0
        if sid > 0 and type(e.name) == 'string' and not JA_SPELLS:contains(sid) then
            local up    = math.max(0, os.clock() - e.expired_at)
            local total = math.max(0, math.floor((tonumber(e.base_dur or 0) or 0) + up + 0.5))
            local clean = base_name(e.name)
            if cfg().auto_update_enabled then
                durations[owner_key] = durations[owner_key] or {}
                durations[owner_key].spells = durations[owner_key].spells or {}
                durations[owner_key].spells[tostring(sid)] = total
                config.save(durations, 'all')
                _sync_profile(sid, total)
                log(('Auto-updated: %s %ds'):format(clean, total))
            else
                log(('Timer hint: //eb df {%s} %d'):format(clean, total))
            end
        end
    end
    debuffed_mobs[target][effect] = nil
end

local function clear_target_debuffs(tid, opts)
    if not debuffed_mobs[tid] then return end
    for eff,_ in pairs(debuffed_mobs[tid]) do remove_debuff(tid, eff, opts) end
    debuffed_mobs[tid] = nil
end

local function handle_overwrites(target, new_spell_id, overwrites_list)
    if not debuffed_mobs[target] then return true end
    if is_threnody_spell(new_spell_id) then
        for eff, entry in pairs(debuffed_mobs[target]) do
            if type(entry) == 'table' and entry.name and type(entry.name) == 'string' and entry.name:find('Threnody') then remove_debuff(target, eff) end
        end
        return true
    end
    for _, entry in pairs(debuffed_mobs[target]) do
        local old_overwrites = (res.spells[entry.id] and res.spells[entry.id].overwrites) or {}
        for _, v in ipairs(old_overwrites) do if new_spell_id == v then return false end end
    end
    for effect, entry in pairs(debuffed_mobs[target]) do
        for _, v in ipairs(overwrites_list) do if entry.id == v then remove_debuff(target, effect) end end
    end
    return true
end

local function apply_debuff(target, effect, spell_id, duration, label_effect)
    if not debuffed_mobs[target] then debuffed_mobs[target] = {} end
    local overwrites = (res.spells[spell_id] and res.spells[spell_id].overwrites) or {}
    if not handle_overwrites(target, spell_id, overwrites) then return end
    local name = (others and others.blue_magic and others.blue_magic[spell_id] and others.blue_magic[spell_id].en)
              or (res.spells[spell_id] and res.spells[spell_id].en) or 'Unknown'
    debuffed_mobs[target][effect] = { id = spell_id, name = name, timer = os.clock() + (duration or 0), base_dur = tonumber(duration or 0) or 0, expired_at = nil }
    local needs_label = label_effect or (debuffs_map[spell_id] and type(debuffs_map[spell_id].effect) == 'table')
    if needs_label and res.buffs[effect] then
        debuffed_mobs[target][effect].name = name..' ('..res.buffs[effect].en..')'
    end
end

local function apply_ja_spells(target, spell_id)
    if not debuffed_mobs[target] then debuffed_mobs[target] = {} end
    local current = debuffed_mobs[target][1000]
    local tier = (current and current.name == spell_id) and math.min((current.tier or 1) + 1, 5) or 1
    local timer = (current and current.name == spell_id) and current.timer or (os.clock() + 60)
    debuffed_mobs[target][1000] = { id = spell_id, name = spell_id, tier = tier, timer = timer, base_dur = 60, expired_at = nil }
end

local function get_pet_owner(id)
    local pet = windower.ffxi.get_mob_by_id(id); if not pet then return id end
    for _,v in pairs(windower.ffxi.get_party()) do
        if type(v)=='table' and v.mob and v.mob.pet_index then
            local p=windower.ffxi.get_mob_by_index(v.mob.pet_index)
            if p and p.id==id then return v.mob.id end
        end
    end
    return id
end

local function is_ally(id)
    if not id then return false end
    local p = windower.ffxi.get_party()
    for _,slot in pairs(p) do
        if type(slot)=='table' and slot.mob then
            if slot.mob.id == id then return true end
            if slot.mob.pet_index then
                local pet = windower.ffxi.get_mob_by_index(slot.mob.pet_index)
                if pet and pet.id == id then return true end
            end
        end
    end
    return false
end

local function inc_action(act)
    if act.category == 4 then
        if act.param == 260 and act.targets[1].actions[1].message == 342 then
            local effect = act.targets[1].actions[1].param
            local target = act.targets[1].id
            if is_enemy(target) then remove_debuff(target, effect) end
        end
        if not is_ally(act.actor_id) then return end

        local SUCCESS_GENERIC = S{2,230,252,264,265}
        local SUCCESS_STATUS  = S{236,237,266,267,268,269,270,271,272,277,278,279,280}
        local FAIL_OR_IGNORE  = S{75,85,284,653,655,677,678,423}

        for i = 1, #act.targets do
            local tmsg  = act.targets[i].actions[1].message
            local tgt   = act.targets[i].id
            local spell = act.param
            local actor = tostring(act.actor_id)

            if is_enemy(tgt) then
                if T{2,252,264,265}:contains(tmsg) and JA_SPELLS:contains(act.param) then
                    apply_ja_spells(tgt, act.param)
                else
                    if T{33,34,35,36,37}:contains(spell) then spell = spell - 10 end
                    local bm = others and others.blue_magic and others.blue_magic[spell]
                    local effect   = bm and bm.status or (res.spells[spell] and res.spells[spell].status) or nil
                    local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                                  or (durations[owner_key] and durations[owner_key][actor] and durations[owner_key][actor][tostring(spell)])
                                  or (EXTREMES[spell] and EXTREMES[spell].duration)
                                  or (bm and bm.duration)
                                  or (res.spells[spell] and res.spells[spell].duration)
                                  or (debuffs_map[spell] and debuffs_map[spell].duration)
                                  or (absorb_map[spell] and absorb_map[spell].duration)
                                  or 0

                    if SUCCESS_STATUS:contains(tmsg) then
                        local msg_effect = act.targets[i].actions[1].param
                        if T{225,226,227,228,229}:contains(spell) then spell = spell - 5 end
                        local conflict = (spell == 719 and debuffed_mobs[tgt] and debuffed_mobs[tgt][133])
                                      or (spell == 535 and debuffed_mobs[tgt] and debuffed_mobs[tgt][128])
                                      or (spell == 705 and debuffed_mobs[tgt] and debuffed_mobs[tgt][132])
                        if not conflict then
                            local s_status = bm and bm.status or (res.spells[spell] and res.spells[spell].status)
                            if s_status and s_status == msg_effect then
                                apply_debuff(tgt, msg_effect, act.param, duration)
                            elseif debuffs_map[spell] and type(debuffs_map[spell].effect) == 'table' then
                                for _, v in pairs(debuffs_map[spell].effect) do apply_debuff(tgt, v, act.param, duration) end
                            elseif debuffs_map[spell] then
                                apply_debuff(tgt, debuffs_map[spell].effect, act.param, duration)
                            elseif EXTREMES[spell] then
                                apply_debuff(tgt, EXTREMES[spell].effect, act.param, duration)
                                if spell == 502 then kaustra_store_dmg(tgt, EXTREMES[spell].effect, act.targets[i].actions[1].param) end
                            elseif absorb_map[spell] then
                                local e = absorb_map[spell].effect
                                if type(e) == 'table' then for _,v in pairs(e) do apply_debuff(tgt, v, spell, duration) end
                                else apply_debuff(tgt, e, spell, duration) end
                            elseif msg_effect and msg_effect > 0 and res.buffs[msg_effect] then
                                -- Fallback: trust the effect the server says landed
                                apply_debuff(tgt, msg_effect, act.param, duration, s_status ~= nil)
                            end
                        end
                    elseif SUCCESS_GENERIC:contains(tmsg) then
                        if JA_SPELLS:contains(act.param) then
                            apply_ja_spells(tgt, act.param)
                        else
                            if effect then
                                apply_debuff(tgt, effect, act.param, duration)
                                if is_helix_id(act.param) then helix_store_dmg(tgt, effect, act.targets[i].actions[1].param, act.param) end
                            elseif debuffs_map[spell] then
                                apply_debuff(tgt, debuffs_map[spell].effect, spell, duration)
                            elseif EXTREMES[spell] then
                                apply_debuff(tgt, EXTREMES[spell].effect, act.param, duration)
                                if spell == 502 then kaustra_store_dmg(tgt, EXTREMES[spell].effect, act.targets[i].actions[1].param) end
                            elseif absorb_map[spell] then
                                local e = absorb_map[spell].effect
                                if type(e) == 'table' then for _,v in pairs(e) do apply_debuff(tgt, v, spell, duration) end
                                else apply_debuff(tgt, e, spell, duration) end
                            end
                        end
                    elseif (debuffs_map[spell] or absorb_map[spell] or EXTREMES[spell]) and not FAIL_OR_IGNORE:contains(tmsg) then
                        local map = debuffs_map[spell] and debuffs_map or (absorb_map[spell] and absorb_map or EXTREMES)
                        local e = map[spell].effect
                        if type(e) == 'table' then for _,v in pairs(e) do apply_debuff(tgt, v, spell, duration) end
                        else apply_debuff(tgt, e, spell, duration) end
                        if spell == 502 and EXTREMES[spell] then kaustra_store_dmg(tgt, EXTREMES[spell].effect, act.targets[i].actions[1].param) end
                    end
                end
            end
        end

    elseif act.category == 6 then
        if not is_ally(act.actor_id) then return end
        if SHOT_INFO[act.param] and act.targets[1].actions[1].message ~= 323 then
            local tgt = act.targets[1].id; if is_enemy(tgt) then handle_shot(tgt, act.param) end
        end

    elseif act.category == 13 then
        local owner = get_pet_owner(act.actor_id); if not is_ally(owner) then return end
        if T{611,657,963}:contains(act.param) then
            for i = 1, #act.targets do
                if T{320,267}:contains(act.targets[i].actions[1].message) then
                    local target = act.targets[i].id
                    if is_enemy(target) then
                        local spell = act.param
                        local effect = (BloodPact_map[spell] and BloodPact_map[spell].effect) or act.targets[i].actions[1].param
                        local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                                      or (durations[owner_key] and durations[owner_key][owner] and durations[owner_key][owner][tostring(spell)])
                                      or (BloodPact_map[spell] and BloodPact_map[spell].duration)
                                      or 0
                        local ja  = res.job_abilities[spell]
                        local buf = effect and res.buffs[effect]
                        if ja and buf then
                            debuffed_mobs[target] = debuffed_mobs[target] or {}
                            debuffed_mobs[target][effect] = { name = ja.en..' ('..buf.en..')', timer = os.clock() + duration, base_dur = duration, expired_at = nil }
                        end
                    end
                end
            end
        end

    elseif act.category == 14 then
        if not is_ally(act.actor_id) then return end
        for i = 1, #act.targets do
            if T{519,520,521,591}:contains(act.targets[i].actions[1].message) then
                local target = act.targets[i].id
                if is_enemy(target) then
                    local effect = act.param; local tier = act.targets[i].actions[1].param
                    step_duration[target] = step_duration[target] or {}
                    if tier == 1 or not step_duration[target][effect] then
                        step_duration[target][effect] = os.clock() + 60
                    elseif step_duration[target][effect] - os.clock() >= 90 then
                        step_duration[target][effect] = os.clock() + 120
                    else
                        step_duration[target][effect] = os.clock() + math.max(30, step_duration[target][effect] - os.clock() + 30)
                    end
                    debuffed_mobs[target] = debuffed_mobs[target] or {}
                    local prev = debuffed_mobs[target][effect]
                    debuffed_mobs[target][effect] = { name = res.job_abilities[effect].en.." lv."..tier, tier = tier,
                        timer = step_duration[target][effect], base_dur = 0, expired_at = nil, seq = prev and prev.seq or nil }
                end
            end
        end

    elseif act.category == 15 then
        if not is_ally(act.actor_id) then return end
        if T{372,375}:contains(act.param) and T{320,672}:contains(act.targets[1].actions[1].message) then
            local target = act.targets[1].id; if not is_enemy(target) then return end
            local effect = act.targets[1].actions[1].param; local spell = act.param; local actor = tostring(act.actor_id)
            local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                          or (durations[owner_key] and durations[owner_key][actor] and durations[owner_key][actor][tostring(spell)])
                          or (EXTREMES[spell] and EXTREMES[spell].duration)
                          or (res.spells[spell] and res.spells[spell].duration)
                          or (debuffs_map[spell] and debuffs_map[spell].duration)
                          or 0
            debuffed_mobs[target] = debuffed_mobs[target] or {}
            debuffed_mobs[target][effect] = { name = res.job_abilities[spell].en, timer = os.clock()+duration, base_dur = duration, expired_at = nil }
        end

    elseif T{1,7,8,11}:contains(act.category) then
        -- A mob that acts is no longer asleep/petrified/terrorized
        if debuffed_mobs[act.actor_id] then
            for _, eff in ipairs({2, 19, 7, 28, 193}) do
                if debuffed_mobs[act.actor_id] and debuffed_mobs[act.actor_id][eff] then remove_debuff(act.actor_id, eff) end
            end
        end
        if act.category == 11 then
            for i = 1, #act.targets do
                local t   = act.targets[i]
                local msg = t.actions[1].message
                if msg == 101 then
                    if ERASE_ABILITIES:contains(act.param) then clear_target_debuffs(t.id) end
                elseif msg == 159 then
                    if PARTIAL_ERASE_ABILITIES:contains(act.param) then remove_debuff(t.id, t.actions[1].param) end
                end
            end
        elseif act.category == 1 and act.targets[1].actions[1].has_add_effect and act.targets[1].actions[1].add_effect_message == 603 then
            TH[act.targets[1].id] = 'TH'..act.targets[1].actions[1].add_effect_param
        end

    elseif act.category == 3 and act.targets[1].actions[1].message == 608 then
        TH[act.targets[1].id] = 'TH'..act.targets[1].actions[1].param

    elseif act.category == 3 and act.targets[1].actions[1].message == 100 then
        local effect = act.targets[1].actions[1].param
        local spell  = act.param
        if S{150,170}:contains(spell) and effect == 149 then
            local name = (res.job_abilities[spell] and res.job_abilities[spell].en) or 'Unknown'
            local actor = act.actor_id; local target = act.targets[1].id; local merit_name = name:lower()
            local override = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                          or (durations[owner_key] and durations[owner_key][tostring(actor)] and durations[owner_key][tostring(actor)][tostring(spell)])
            local base  = (ja_map[spell] and ja_map[spell].duration) or 0
            local merit = (player and actor == player.id and player.merits) and (30 + ((player.merits[merit_name] or 0)-1)*15) or nil
            local duration = override or merit or base
            debuffed_mobs[target] = debuffed_mobs[target] or {}
            debuffed_mobs[target][effect] = { name = name, timer = os.clock()+duration, base_dur = duration, expired_at = nil }
        end
    end
end

local STEP_REMOVALS = {
    {ids = {386,387,388,389,390}, key = 201}, {ids = {391,392,393,394,395}, key = 202},
    {ids = {396,397,398,399,400}, key = 203}, {ids = {448,449,450,451,452}, key = 312},
}
local ABSORB_PAIRS = {[136]=266,[137]=267,[138]=268,[139]=269,[140]=270,[141]=271,[142]=272,[146]=242}

local function inc_action_message(arr)
    if T{6,20,113,406,605,646}:contains(arr.message_id) then
        if is_enemy(arr.target_id) then
            clear_target_debuffs(arr.target_id, { no_hint = true })
            TH[arr.target_id] = nil
        end
    elseif T{204,206}:contains(arr.message_id) then
        if is_enemy(arr.target_id) and debuffed_mobs[arr.target_id] then
            local tid, pid = arr.target_id, arr.param_1
            if arr.message_id == 206 then
                if ABSORB_PAIRS[pid] then
                    remove_debuff(tid, pid); remove_debuff(tid, ABSORB_PAIRS[pid])
                    if step_duration[tid] then step_duration[tid][ABSORB_PAIRS[pid]] = 0 end
                else
                    for _, sr in ipairs(STEP_REMOVALS) do
                        if T(sr.ids):contains(pid) then
                            remove_debuff(tid, sr.key)
                            if step_duration[tid] then step_duration[tid][sr.key] = 0 end
                            return
                        end
                    end
                    remove_debuff(tid, pid)
                end
            else
                remove_debuff(tid, pid)
            end
        end
    end
end

local function forget_mob(id)
    if debuffed_mobs[id] then clear_target_debuffs(id, { no_hint = true }) end
    TH[id] = nil
    step_duration[id] = nil
end

local function purge_missing_mobs()
    local self_id = player and player.id
    for id, _ in pairs(debuffed_mobs) do
        if id ~= self_id and not windower.ffxi.get_mob_by_id(id) then forget_mob(id) end
    end
    for id, _ in pairs(TH) do
        if not debuffed_mobs[id] and not windower.ffxi.get_mob_by_id(id) then TH[id] = nil end
    end
end

-- Expire timers on every tracked mob (not only the one on screen), so
-- keep_buff overtime and timer hints are measured from the real expiry.
local function expire_timers()
    local now = os.clock()
    for tid, tbl in pairs(debuffed_mobs) do
        for effect, sp in pairs(tbl) do
            if type(sp) == 'table' and (sp.timer or 0) < now then
                if cfg().keep_buff_after_timer then
                    if not sp.expired_at then sp.expired_at = sp.timer end
                else
                    remove_debuff(tid, effect)
                end
            end
        end
        if not next(tbl) then debuffed_mobs[tid] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Data files (data/debuff_durations.xml, data/debuff_profiles.xml)
-- On first run, learned durations/profiles are copied from the Debuffing addon.
-- ---------------------------------------------------------------------------
local DUR_FILE, PROF_FILE = 'data\\debuff_durations.xml', 'data\\debuff_profiles.xml'
local EMPTY_XML = [[<?xml version="1.0"?><settings></settings>]]

local function read_file(path)
    local f = io.open(path, 'r'); if not f then return nil end
    local s = f:read('*a'); f:close(); return s
end

local function ensure_file(rel, legacy_rel)
    if files.exists(rel) then return end
    local legacy = read_file(windower.addon_path..'..\\Debuffing\\'..legacy_rel)
    files.new(rel, true):write(legacy or EMPTY_XML)
    if legacy then log('Imported '..legacy_rel..' from the Debuffing addon.') end
end

local function load_data()
    if not windower.dir_exists(windower.addon_path..'data\\') then windower.create_dir(windower.addon_path..'data\\') end
    ensure_file(DUR_FILE, 'data\\durations.xml')
    ensure_file(PROF_FILE, 'data\\duration_profiles.xml')
    durations = config.load(DUR_FILE)
    duration_profiles = config.load(PROF_FILE)

    local info = windower.ffxi.get_info(); if not info.logged_in then return end
    player = windower.ffxi.get_player()
    owner_key = (player and player.name and player.name:lower()) or 'unknown'

    durations[owner_key] = durations[owner_key] or {}
    if durations[owner_key].global and not durations[owner_key].spells then
        durations[owner_key].spells = durations[owner_key].global; durations[owner_key].global = nil; config.save(durations, 'all')
    end
    durations[owner_key].spells = durations[owner_key].spells or {}
    duration_profiles[owner_key] = duration_profiles[owner_key] or {}
    duration_profiles[owner_key].profiles = duration_profiles[owner_key].profiles or {}

    if cfg().auto_profiles_enabled then _apply_job_profile() end
end

-- ---------------------------------------------------------------------------
-- Display: icons on the target bar + details panel
-- ---------------------------------------------------------------------------
Debuffs = { icons = nil, timers = nil, th = nil, built_for = nil, details = nil,
            details_built_for = nil, bar = nil, x = 0, y = 0, dx = 0, dy = 0 }

-- The details panel is a second draggable module (like TargetInfo)
DebuffDetails = { x = 0, y = 0 }

local STROKE = {width = 2, alpha = 180, red = 50, green = 50, blue = 50}

local DETAILS_DEFAULT = {pos = {x = 1300, y = 120}, font = 'Grammara', font_size = 0, show = true, show_shots = true}
local function dcfg()
    if settings and not settings.debuff_details then settings.debuff_details = DETAILS_DEFAULT end
    return settings and settings.debuff_details or DETAILS_DEFAULT
end

local ELEMENT_RGB = { [0]={255,22,12},[1]={0,255,255},[2]={51,255,20},[3]={255,255,28},
                      [4]={233,0,255},[5]={0,150,255},[6]={255,255,255},[7]={135,135,135} }
local GREEN, DARK, LABEL = {51,255,20}, {135,135,135}, {200,220,255}
local JA_ELEMENT = { [496]=0, [497]=1, [498]=2, [499]=3, [500]=4, [501]=5 }
local JA_NAME = { [496]='Fire', [497]='Ice', [498]='Wind', [499]='Earth', [500]='Lightning', [501]='Water' }
local function cs(rgb, s) return ('\\cs(%d,%d,%d)%s\\cr'):format(rgb[1], rgb[2], rgb[3], s) end

local function icon_for(effect, sp)
    local base = STEP_ICON_BASE[effect]
    if base then
        local tier = math.max(1, math.min(5, tonumber(sp and sp.tier) or 1))
        return base + tier - 1
    end
    if type(effect) == 'number' and effect >= 0 and effect <= 639 then return effect end
    return nil  -- JA-style elemental damage entries have no icon (details panel shows them)
end

local function new_text(size, font)
    return texts.new('', {
        pos = {x = 0, y = 0},
        text = {size = size, font = font, stroke = STROKE},
        flags = {bold = true, draggable = false}, bg = {visible = false},
    })
end

function Debuffs:destroyDisplay()
    for _, list in ipairs({self.icons or {}, self.timers or {}}) do
        for _, e in ipairs(list) do e:destroy() end
    end
    if self.th then self.th:destroy() end
    self.icons, self.timers, self.th, self.built_for = nil, nil, nil, nil
end

function Debuffs:buildDisplay()
    self:destroyDisplay()
    local c = cfg()
    local size = c.icon_size
    self.icons, self.timers = {}, {}
    for i = 1, c.max_icons do
        self.icons[i] = images.new({
            pos = {x = 0, y = 0}, visible = false,
            color = {alpha = 255, red = 255, green = 255, blue = 255},
            size = {width = size, height = size},
            texture = {path = '', fit = true},
            repeatable = {x = 1, y = 1}, draggable = false,
        })
        self.icons[i].last_path = nil
        self.timers[i] = new_text(c.timer_size, c.timer_font)
    end
    self.th = new_text(c.timer_size, c.timer_font)
    self.built_for = table.concat({size, c.max_icons, c.timer_size, c.timer_font}, '|')
end

function Debuffs:hideAll()
    for _, list in ipairs({self.icons or {}, self.timers or {}}) do
        for _, e in ipairs(list) do e:hide() end
    end
    if self.th then self.th:hide() end
end

local function fmt_timer(remain, expired_up)
    if expired_up then return cs(GREEN, '+'..math.floor(expired_up)) end
    local s = math.max(0, math.ceil(remain))
    local txt = s >= 1000 and (math.ceil(s / 60)..'m') or tostring(s)
    if s <= 10 then return cs({255,180,80}, txt) end
    return txt
end

-- Ordered entries (oldest first) for a mob: {icon=, remain=, up=}
function Debuffs:entriesFor(tid)
    local tbl, out = debuffed_mobs[tid], {}
    if not tbl then return out end
    local now = os.clock()
    for effect, sp in pairs(tbl) do
        if type(sp) == 'table' then
            sp.seq = sp.seq or next_seq()
            local icon = icon_for(effect, sp)
            if icon then
                out[#out+1] = {icon = icon, seq = sp.seq, remain = (sp.timer or 0) - now,
                               up = sp.expired_at and (now - sp.expired_at) or nil}
            end
        end
    end
    table.sort(out, function(a, b) return a.seq < b.seq end)
    return out
end

-- Screen x of the anchor point for the current bar
function Debuffs:anchorX(bar)
    local c = cfg()
    if c.anchor == 'right' then return bar.x + 1 + bar.width - c.x end
    return bar.x + 1 + c.x
end

function Debuffs:draw(bar, entries, th_text)
    local c = cfg()
    local size, gap = c.icon_size, c.spacing
    local n = math.min(#entries, c.max_icons)
    local left_anchor = c.anchor ~= 'right'
    local ax = self:anchorX(bar)
    local icon_y = bar.y + BAR_HEIGHT - size + c.offset_y
    local timer_y = bar.y + BAR_HEIGHT + 1 + c.offset_y
    local char_w = c.timer_size * 0.65
    self.x, self.y = ax, icon_y
    local far_edge = ax

    -- Newest at the anchor; older ones step away from it
    for slot = 1, c.max_icons do
        local img, txt = self.icons[slot], self.timers[slot]
        if slot <= n then
            local e = entries[#entries - slot + 1]
            local x
            if left_anchor then
                x = math.floor(ax + (slot - 1) * (size + gap))
                far_edge = x + size
            else
                x = math.floor(ax - slot * size - (slot - 1) * gap)
                far_edge = x
            end
            local path = ICON_PATH..e.icon..'.png'
            if img.last_path ~= path then img:path(path); img.last_path = path end
            img:pos(x, icon_y); img:show()
            if c.timers then
                local label = fmt_timer(e.remain, e.up)
                local plain = label:gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', '')
                txt:text(label)
                txt:pos(math.floor(x + (size - #plain * char_w) / 2), timer_y)
                txt:show()
            else
                txt:hide()
            end
        else
            img:hide(); txt:hide()
        end
    end

    -- TH sits just past the far end of the icon row
    if c.show_th and th_text then
        local w = #th_text * char_w
        local tx = left_anchor and (far_edge + 4) or (far_edge - w - 4)
        if n == 0 then tx = left_anchor and ax or (ax - w) end
        self.th:text(th_text)
        self.th:pos(math.floor(tx), icon_y + math.floor((size - c.timer_size) / 2) - 2)
        self.th:show()
    else
        self.th:hide()
    end
end

-- ---- details panel ---------------------------------------------------------
function DebuffDetails:destroy()
    if self.text then self.text:destroy() end
    self.text, self.built_for = nil, nil
end

function DebuffDetails:build()
    self:destroy()
    local d = dcfg()
    local size = d.font_size
    if not size or size <= 0 then
        size = settings and settings.target_bar and settings.target_bar.font_size or 12
    end
    self.x, self.y = d.pos.x or 0, d.pos.y or 0
    self.text = new_text(size, d.font)
    self.built_for = size..'|'..d.font
end

local function remain_suffix(sp, unit_secs, unit_name, unit_rgb)
    local now = os.clock()
    if sp.expired_at then
        local up = now - sp.expired_at
        if unit_secs then return ' · '..cs(GREEN, '+'..math.floor(up / unit_secs))..' '..cs(unit_rgb, unit_name) end
        return ' · '..cs(GREEN, '+'..math.floor(up))..'s'
    end
    local remain = math.max(0, (sp.timer or 0) - now)
    if unit_secs then return ' · '..math.floor(remain / unit_secs)..' '..cs(unit_rgb, unit_name) end
    return ' · '..math.ceil(remain)..'s'
end

-- Special entries only: Helix, Kaustra, elemental damage bonuses, shots
function DebuffDetails:linesFor(tid)
    local tbl, rows = debuffed_mobs[tid], {}
    if not tbl then return {} end
    local d = dcfg()
    for effect, sp in pairs(tbl) do
        if type(sp) == 'table' then
            sp.seq = sp.seq or next_seq()
            local line
            if sp.helix and sp.dmg_str then
                local rgb = ELEMENT_RGB[sp.element] or ELEMENT_RGB[6]
                line = cs(rgb, base_name(sp.name))..' '..cs(rgb, sp.dmg_str)..remain_suffix(sp, 10, 'tocks', rgb)
            elseif sp.kaustra and sp.dmg_str then
                line = cs(DARK, 'Kaustra')..' '..cs(DARK, sp.dmg_str)..remain_suffix(sp, 3, 'ticks', DARK)
            elseif effect == 1000 and JA_SPELLS:contains(sp.name) then
                local el = JA_ELEMENT[sp.name]
                local pct = math.max(1, math.min(5, tonumber(sp.tier) or 1)) * 5
                line = cs(ELEMENT_RGB[el], JA_NAME[sp.name]..' Damage')..' +'..pct..'%'..remain_suffix(sp)
            elseif sp.shot and d.show_shots then
                local info = SHOT_INFO[sp.shot_id]
                local rgb = info and ELEMENT_RGB[info.element] or ELEMENT_RGB[6]
                local count = sp.shot > 1 and (' x'..sp.shot) or ''
                line = cs(LABEL, base_name(sp.name)..':')..' '..cs(rgb, (info and info.name or 'Shot')..count)
            end
            if line then rows[#rows+1] = {seq = sp.seq, line = line} end
        end
    end
    table.sort(rows, function(a, b) return a.seq < b.seq end)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.line end
    return out
end

local DETAILS_DEMO = {
    cs(ELEMENT_RGB[4], 'Ionohelix II')..' '..cs(ELEMENT_RGB[4], '3.2k')..' · 4 '..cs(ELEMENT_RGB[4], 'tocks'),
    cs(DARK, 'Kaustra')..' '..cs(DARK, '1.5k')..' · 12 '..cs(DARK, 'ticks'),
    cs(ELEMENT_RGB[0], 'Fire Damage')..' +15% · 42s',
    cs(LABEL, 'Burn:')..' '..cs(ELEMENT_RGB[0], 'Fire Shot x2'),
}

function DebuffDetails:update(setup_mode, tid)
    local d = dcfg()
    local size = d.font_size
    if not size or size <= 0 then size = settings and settings.target_bar and settings.target_bar.font_size or 12 end
    if self.built_for ~= size..'|'..d.font then self:build() end
    if not d.show then self.text:hide(); return end
    local lines = setup_mode and DETAILS_DEMO or (tid and self:linesFor(tid) or {})
    if #lines == 0 then self.text:hide(); return end
    self.text:text(table.concat(lines, '\n'))
    self.text:pos(self.x, self.y)
    self.text:show()
end

function DebuffDetails:hover(x, y)
    return self.text ~= nil and self.text:visible() and self.text:hover(x, y) or false
end

function DebuffDetails:move(x, y)
    self.x, self.y = x, y
    dcfg().pos = {x = x, y = y}
    if self.text then self.text:pos(x, y) end
end

-- ---- dragging the icon row (setup mode): sideways only, clamped to the bar ----
function Debuffs:hover(x, y)
    if not self.icons then return false end
    for _, img in ipairs(self.icons) do
        if img:visible() and img:hover(x, y) then return true end
    end
    return false
end

function Debuffs:move(x, y)
    local bar = self.bar
    if not bar then return end
    local c = cfg()
    local offset = (c.anchor == 'right') and (bar.x + 1 + bar.width - x) or (x - bar.x - 1)
    c.x = math.max(0, math.min(bar.width, math.floor(offset)))
    self.x = self:anchorX(bar)  -- y never changes
    self:draw(bar, self.demo_entries, 'TH4')
end

local DEMO = {
    {icon = 2, remain = 0, up = 5}, {icon = 4, remain = 8}, {icon = 13, remain = 61}, {icon = 134, remain = 152},
}
Debuffs.demo_entries = DEMO

-- Called from EB2's main update loop with the target bar
function Debuffs:update(setup_mode, bar)
    local now = os.clock()
    expire_timers()
    if now > purge_time + 5 then purge_time = now; purge_missing_mobs() end

    local c = cfg()
    if c.anchor == nil then c.anchor = 'left' end
    if c.x == nil then c.x = 0 end
    local key = table.concat({c.icon_size, c.max_icons, c.timer_size, c.timer_font}, '|')
    if self.built_for ~= key then self:buildDisplay() end
    self.bar = bar

    local tid
    if not setup_mode then
        if simulation_mode and player then
            tid = player.id
        else
            local t = windower.ffxi.get_mob_by_target('t')
            tid = t and t.id
        end
    end
    DebuffDetails:update(setup_mode, tid)

    if not c.show or not bar or not bar.is_visible then self:hideAll(); return end
    if setup_mode then self:draw(bar, DEMO, 'TH4'); return end
    if not tid then self:hideAll(); return end
    self:draw(bar, self:entriesFor(tid), TH[tid])
end

-- ---------------------------------------------------------------------------
-- Commands: //eb df ... (also //eb debuffs, //eb debuffing)
-- ---------------------------------------------------------------------------
function Debuffs:handleCommand(args)
    local commands = T(args)
    player = windower.ffxi.get_player()
    if not player then return end
    local c = cfg()

    local function _trim(s) return (s or ''):match('^%s*(.-)%s*$') end
    local function _auto(s) return (s and s ~= '' and windower.convert_auto_trans) and windower.convert_auto_trans(s) or s end
    local function _unwrap_token(s)
        s = _trim(s or ''); if s == '' then return s end
        local first,last = s:sub(1,1), s:sub(-1); local pr = {['"']='"', ['{']='}', ['[']=']', ['<']='>'}
        if pr[first] and last == pr[first] then return s:sub(2, -2) end
        return s
    end
    local function _norm(s) return (_auto(_unwrap_token(s or '')):lower():gsub('[%s%p]+','')) end

    local function set_toggle(key, val, label)
        local v = tostring(val or ''):lower()
        if v == 'on' or v == 'true' or v == '1' then c[key] = true
        elseif v == 'off' or v == 'false' or v == '0' then c[key] = false
        else c[key] = not c[key] end
        save_cfg(); log((label or key)..': '..(c[key] and 'ON' or 'OFF'))
    end
    local function set_number(key, val, lo, hi, label)
        local n = tonumber(val)
        if not n or n < lo or n > hi then log(('%s must be %d-%d'):format(label, lo, hi)); return end
        c[key] = n; save_cfg(); log(label..' = '..n)
    end

    local function normalize_name(n) n=tostring(n or ''):gsub('^%s+',''):gsub('%s+$',''); return n~='' and n or nil end

    local function resolve_spell_id(raw)
        local q=_auto(_unwrap_token(raw)); local qn=_norm(q); local n=tonumber(q)
        if n and (res.spells[n] or (others and others.blue_magic and others.blue_magic[n])) then
            local name=(res.spells[n] and res.spells[n].en) or others.blue_magic[n].en; return n,name
        end
        local function score(name)
            if not name then return -1 end
            local a=_auto(name); local an=_norm(a)
            if a:lower()==q:lower() then return 4000
            elseif an==qn then return 3000
            elseif a:lower():find(q:lower(),1,true) then return 1500
            elseif an:find(qn,1,true) then return 1400
            else return -1 end
        end
        local best,bid,bname=-1,nil,nil
        for _,v in pairs(res.spells) do local sc=score(v and v.en); if sc>best then best,bid,bname=sc,v.id,v.en end end
        if others and others.blue_magic then
            for _,v in pairs(others.blue_magic) do local sc=score(v and v.en); if sc>best then best,bid,bname=sc,v.id,v.en end end
        end
        return bid,bname
    end

    local function show_help()
        local lines = {
            'Debuffs (//eb df, //eb debuffs):',
            '  on | off                     - show or hide debuff icons on the target bar',
            '  timer [on|off]               - timers under the icons',
            '  th [on|off]                  - Treasure Hunter level next to the icons',
            '  size <12-40> | max <1-20>    - icon size / most icons shown',
            '  spacing <0-30>               - gap between icons (pixels)',
            '  anchor left|right            - which end of the bar the icons start from',
            '  x <pixels>                   - distance from that end (or drag them in //eb setup)',
            '  y <pixels>                   - nudge the icons up (-) or down (+)',
            '  details [on|off]             - Helix/Kaustra damage, elemental damage, shots panel',
            '  shots [on|off]               - include elemental shots in the details panel',
            '  keep_buff [on|off]           - keep expired debuffs with a +seconds counter',
            '  auto [on|off]                - auto-learn durations (also toggles keep_buff)',
            '  auto_profiles [on|off]       - per-main-job duration profiles',
            '  {Spell Name}|ID <secs|remove> - set/remove a duration override',
            '  save|load|delete <name>, list - duration profiles',
            '  reset                        - remove all overrides (profiles untouched)',
            '  test {Spell}|ID [damage] [remove], test clear - simulate on yourself',
            '  clear                        - wipe all tracked debuffs',
        }
        for _, l in ipairs(lines) do windower.add_to_chat(207, l) end
    end

    if not commands[1] then show_help(); return end
    local cmd = tostring(commands[1]):lower()

    if cmd == 'help' or cmd == 'h' or cmd == '?' then
        show_help()

    elseif cmd == 'on' or cmd == 'off' then
        c.show = (cmd == 'on'); save_cfg(); log('Icons '..(c.show and 'shown' or 'hidden')..'.')

    elseif cmd == 'timer' or cmd == 'timers' then
        set_toggle('timers', commands[2], 'Timers')

    elseif cmd == 'th' then
        set_toggle('show_th', commands[2], 'Treasure Hunter')

    elseif cmd == 'size' then
        set_number('icon_size', commands[2], 12, 40, 'Icon size')

    elseif cmd == 'spacing' or cmd == 'gap' then
        set_number('spacing', commands[2], 0, 30, 'Icon spacing')

    elseif cmd == 'max' then
        set_number('max_icons', commands[2], 1, 20, 'Max icons')

    elseif cmd == 'anchor' then
        local a = tostring(commands[2] or ''):lower()
        if a ~= 'left' and a ~= 'right' then log('Usage: //eb df anchor left|right'); return end
        c.anchor = a; save_cfg(); log('Icons anchored '..a..' (newest at the '..a..' end).')

    elseif cmd == 'x' then
        local n = tonumber(commands[2])
        if not n or n < 0 then log('Usage: //eb df x <pixels from the anchored end>'); return end
        c.x = math.floor(n); save_cfg(); log('Icon position: '..c.x..'px from the '..(c.anchor or 'left')..' end.')

    elseif cmd == 'y' then
        local n = tonumber(commands[2])
        if not n then log('Usage: //eb df y <pixels>'); return end
        c.offset_y = math.floor(n); save_cfg(); log('Icon vertical nudge: '..c.offset_y)

    elseif cmd == 'details' then
        local d = dcfg()
        local v = tostring(commands[2] or ''):lower()
        if v == 'on' then d.show = true elseif v == 'off' then d.show = false else d.show = not d.show end
        save_cfg(); log('Details panel: '..(d.show and 'ON' or 'OFF'))

    elseif cmd == 'shots' then
        local d = dcfg()
        local v = tostring(commands[2] or ''):lower()
        if v == 'on' then d.show_shots = true elseif v == 'off' then d.show_shots = false else d.show_shots = not d.show_shots end
        save_cfg(); log('Shots in details panel: '..(d.show_shots and 'ON' or 'OFF'))

    elseif cmd == 'keep_buff' then
        set_toggle('keep_buff_after_timer', commands[2], 'Keep buff after timer')

    elseif cmd == 'auto' then
        local v = tostring(commands[2] or ''):lower()
        local new_auto = (v=='on' or v=='true' or v=='1') and true or (v=='off' or v=='false' or v=='0') and false or not c.auto_update_enabled
        c.auto_update_enabled = new_auto
        c.keep_buff_after_timer = new_auto
        save_cfg()
        log('Auto update: '..(new_auto and 'ON' or 'OFF')..' (keep buff after timer: '..(new_auto and 'ON' or 'OFF')..')')

    elseif cmd == 'auto_profiles' then
        local before = c.auto_profiles_enabled
        set_toggle('auto_profiles_enabled', commands[2], 'Auto profiles')
        if c.auto_profiles_enabled and not before then _apply_job_profile() end

    elseif cmd == 'reset' then
        durations[owner_key] = durations[owner_key] or {}; durations[owner_key].spells = {}; config.save(durations, 'all')
        log('All durations reverted to default.')

    elseif cmd == 'save' then
        local name = normalize_name(table.concat(commands, ' ', 2)); if not name then return log('Usage: //eb df save <name>') end
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local key = _resolve_profile_key(name)
        store[key] = { label = name, spells = _deepcopy(durations[owner_key].spells or {}) }
        config.save(duration_profiles, 'all')
        log(('Saved %s profile with %d entries.'):format(store[key].label or key, tlen(store[key].spells)))

    elseif cmd == 'load' then
        local name = normalize_name(table.concat(commands, ' ', 2)); if not name then return log('Usage: //eb df load <name>') end
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local key = _resolve_profile_key(name)
        if not store[key] then return log('Profile "'..name..'" not found.') end
        durations[owner_key].spells = _deepcopy(store[key].spells or {}); config.save(durations, 'all')
        log('Loaded '..(store[key].label or key)..' profile.')

    elseif cmd == 'list' then
        _ensure_profile_tables()
        local count = 0
        for k, pdata in pairs(duration_profiles[owner_key].profiles) do
            log(('%s (%d)'):format((pdata and pdata.label) or k, tlen(pdata and pdata.spells))); count = count + 1
        end
        if count == 0 then log('No profiles saved') end

    elseif cmd == 'delete' then
        local name = normalize_name(table.concat(commands, ' ', 2)); if not name then return log('Usage: //eb df delete <name>') end
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local key = _resolve_profile_key(name)
        if not store[key] then return log('Profile '..name..' not found') end
        local label = store[key].label or key
        store[key] = nil; config.save(duration_profiles, 'all'); log('Deleted '..label..' profile.')

    elseif cmd == 'test' then
        if tostring(commands[2] or ''):lower() == 'clear' then
            simulation_mode = false; clear_target_debuffs(player.id, { no_hint = true }); log('Test debuffs cleared'); return
        end
        if #commands < 2 then log('Usage: //eb df test {Spell}|ID [remove]'); return end
        local last_is_remove = tostring(commands[#commands]):lower() == 'remove'
        local name_end = last_is_remove and (#commands - 1) or #commands
        -- A trailing number after a spell name is damage (Helix / Kaustra)
        local dmg_val
        if name_end > 2 and tonumber(commands[name_end]) then dmg_val = tonumber(commands[name_end]); name_end = name_end - 1 end
        local raw_query = table.concat(commands, ' ', 2, name_end)
        local sid, sname
        local idq = tonumber(_auto(_unwrap_token(raw_query)))
        if idq and res.spells[idq] then sid,sname = idq, res.spells[idq].en
        elseif idq and others.blue_magic[idq] then sid,sname = idq, others.blue_magic[idq].en
        else sid,sname = resolve_spell_id(raw_query) end
        if not sid then log('Spell not found: incorrect spell name/id.'); return end

        local self_id = player.id; simulation_mode = true; debuffed_mobs[self_id] = debuffed_mobs[self_id] or {}
        if last_is_remove then
            for eff, ent in pairs(debuffed_mobs[self_id]) do
                if type(ent) == 'table' and (ent.id == sid or ent.name == sname) then remove_debuff(self_id, eff, { no_hint = true }) end
            end
            log('Removed test debuff: '..sname); return
        end
        local bm = others.blue_magic[sid]
        local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(sid)])
                       or (EXTREMES[sid] and EXTREMES[sid].duration)
                       or (bm and bm.duration) or (res.spells[sid] and res.spells[sid].duration)
                       or (absorb_map[sid] and absorb_map[sid].duration)
                       or 60
        if duration == 0 then duration = 60 end
        local s = res.spells[sid]
        if JA_SPELLS:contains(sid) then
            apply_ja_spells(self_id, sid)
            debuffed_mobs[self_id][1000].no_hint = true
            log('Test: '..sname..' (details panel)'); return
        end
        local effect = (bm and bm.status) or (s and s.status) or (EXTREMES[sid] and EXTREMES[sid].effect) or (absorb_map[sid] and absorb_map[sid].effect)
        if not effect or effect == 0 then log(sname..' has no status effect to show.'); return end
        apply_debuff(self_id, effect, sid, duration)
        if debuffed_mobs[self_id][effect] then debuffed_mobs[self_id][effect].no_hint = true end
        if dmg_val then
            if is_helix_id(sid) then helix_store_dmg(self_id, effect, dmg_val, sid)
            elseif sid == 502 then kaustra_store_dmg(self_id, effect, dmg_val) end
        end
        log(('Test: %s for %ds (shown on the target bar)'):format(sname, duration))

    elseif cmd == 'clear' then
        local ids = {}; for tid,_ in pairs(debuffed_mobs) do ids[#ids+1] = tid end
        for _,tid in ipairs(ids) do clear_target_debuffs(tid, { no_hint = true }) end
        TH = {}; step_duration = {}
        simulation_mode = false; log('All debuffs cleared')

    else
        if #commands <= 1 then log('Unknown command: '..cmd..' (try //eb df help)'); return end
        durations[owner_key] = durations[owner_key] or {}; durations[owner_key].spells = durations[owner_key].spells or {}
        local raw_query = table.concat(commands, ' ', 1, #commands - 1)
        local sid, sname = resolve_spell_id(raw_query); if not sid then log('Spell not found: incorrect spell name/id or outdated resources'); return end
        local last = tostring(commands[#commands] or ''):lower(); local secs = tonumber(last)
        if secs and secs >= 0 then
            durations[owner_key].spells[tostring(sid)] = secs; config.save(durations, 'all')
            _sync_profile(sid, secs)
            log('Duration for '..sname..' set to '..secs..' seconds')
        elseif last == 'remove' then
            durations[owner_key].spells[tostring(sid)] = nil; config.save(durations, 'all')
            _sync_profile(sid, nil)
            log('Duration for '..sname..' removed')
        else
            log('Invalid time. Use a non-negative number or "remove".')
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
windower.register_event('incoming chunk', function(id, data)
    if id == 0x028 then
        inc_action(windower.packets.parse_action(data))
    elseif id == 0x029 then
        inc_action_message({ target_id = data:unpack('I',0x09), param_1 = data:unpack('I',0x0D), message_id = data:unpack('H',0x19) % 32768 })
    elseif id == 0x00E then
        local packet = packets.parse('incoming', data)
        local npc  = packet['NPC']
        local mask = tonumber(packet['Mask']) or 0
        if bit.band(mask, 0x20) ~= 0 or ((packet['Status'] == 2 or packet['Status'] == 3) and packet['HP %'] == 0) then
            forget_mob(npc)
        elseif TH[npc] and packet['Status'] == 0 and packet['HP %'] == 100 then
            TH[npc] = nil
        end
    end
end)

windower.register_event('logout', 'zone change', function()
    debuffed_mobs, TH, step_duration = {}, {}, {}
    simulation_mode = false
    player = windower.ffxi.get_player()
end)

windower.register_event('load', 'login', function() load_data() end)

windower.register_event('job change', function()
    if cfg().auto_profiles_enabled then _apply_job_profile() end
end)

-- Exposed for tests / debugging
Debuffs._state = function() return debuffed_mobs, TH end
Debuffs._inc_action = inc_action
Debuffs._inc_action_message = inc_action_message
