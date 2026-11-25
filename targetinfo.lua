--[[
    TargetInfo module for EnemyBar2 (based on the TargetInfo addon by Arcon,
    Copyright © 2013-2017, Windower; BSD 3-clause license, see LICENSE notes
    in README).

    Shows memory information for your current target (subtarget first):
      ID      full mob ID (includes zone and mob category)
      Hex ID  mob index in hex, the ID usually used for NM placeholders
      Speed   deviation from normal movement speed (+x% green, -x% red)
      Claim / Target  (optional) who has claim, or who the mob is targeting

    Drawn in EnemyBar2's text style; drag it in //eb setup like the other bars.
]]

local texts = require('texts')

-- font_size 0 = match the target bar's font size
local DEFAULT_CFG = {pos = {x = 1500, y = 65}, font = 'Grammara', font_size = 0,
                     show = true, show_full_id = true, show_hex_id = true,
                     show_speed = true, show_target_name = false}

local STROKE = {width = 2, alpha = 180, red = 50, green = 50, blue = 50}

local C_LABEL = '\\cs(200,220,255)'
local C_VALUE = '\\cs(255,255,255)'
local C_FAST  = '\\cs(80,255,128)'
local C_SLOW  = '\\cs(255,90,90)'
local C_SAME  = '\\cs(150,150,150)'
local C_END   = '\\cr'

TargetInfo = {
    text = nil,
    cfg  = nil,
    x = 0, y = 0,
}

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
function TargetInfo:destroyDisplay()
    if self.text then self.text:destroy() end
    self.text = nil
end

function TargetInfo:initialize(cfg)
    self:destroyDisplay()
    if not cfg then return end
    self.cfg = cfg
    self.x, self.y = cfg.pos.x or 0, cfg.pos.y or 0
    local size = cfg.font_size
    if not size or size <= 0 then
        size = settings and settings.target_bar and settings.target_bar.font_size or 12
    end
    self.text = texts.new('', {
        pos = {x = self.x, y = self.y},
        text = {size = size, font = cfg.font, stroke = STROKE},
        flags = {bold = true, draggable = false, italic = false},
        bg = {visible = false},
    })
end

local function round2(n)
    local sign = n < 0 and -1 or 1
    return sign * math.floor(math.abs(n) * 100 + 0.5) / 100
end

local function speed_text(mob)
    local ms = mob.movement_speed or 5
    -- Same formula as the original addon (status 5/85: mounted / chocobo)
    local speed = (mob.status == 5 or mob.status == 85) and round2(100 * (ms / 4)) or round2(100 * (ms / 5 - 1))
    local col = speed > 0 and C_FAST or speed < 0 and C_SLOW or C_SAME
    local num = speed == math.floor(speed) and ('%d'):format(speed) or tostring(speed)
    return col..(speed >= 0 and '+' or '')..num..'%'..C_END
end

local function line(label, value)
    return C_LABEL..label..C_END..' '..value
end

-- Builds the lines for a mob (or demo data)
function TargetInfo:buildLines(mob)
    local cfg, lines = self.cfg, {}
    if cfg.show_full_id then
        lines[#lines+1] = line('ID:', C_VALUE..('%08d'):format(mob.id)..C_END)
    end
    if cfg.show_hex_id then
        lines[#lines+1] = line('Hex ID:', C_VALUE..('%.3X'):format(mob.index)..C_END)
    end
    if cfg.show_speed then
        lines[#lines+1] = line('Speed:', speed_text(mob))
    end
    if cfg.show_target_name then
        local player = windower.ffxi.get_player()
        local claim  = mob.claim_id and mob.claim_id ~= 0 and windower.ffxi.get_mob_by_id(mob.claim_id)
        local target = mob.target_index and mob.target_index ~= 0 and windower.ffxi.get_mob_by_index(mob.target_index)
        if player and mob.id == player.id and mob.name then
            lines[#lines+1] = line('Target:', C_VALUE..mob.name..C_END)
        elseif claim and claim.id > 0 and claim.name then
            lines[#lines+1] = line('Claim:', C_VALUE..claim.name..C_END)
        elseif target and target.id > 0 and target.name then
            lines[#lines+1] = line('Target:', C_VALUE..target.name..C_END)
        end
    end
    return lines
end

local DEMO_MOB = {id = 16933428, index = 0x234, movement_speed = 6, status = 1, name = 'Demo'}

-- Called from EB2's main update loop (~10/s)
function TargetInfo:update(setup_mode)
    if not self.text then
        if settings and not settings.targetinfo_bar then settings.targetinfo_bar = DEFAULT_CFG end
        self:initialize(settings and settings.targetinfo_bar or DEFAULT_CFG)
    end
    if not self.text or not self.cfg then return end
    if not self.cfg.show then self.text:hide(); return end

    local mob
    if setup_mode then
        mob = DEMO_MOB
    else
        mob = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t')
        if not mob or not mob.id or mob.id <= 0 then self.text:hide(); return end
    end

    local lines = self:buildLines(mob)
    if #lines == 0 then self.text:hide(); return end
    self.text:text(table.concat(lines, '\n'))
    self.text:pos(self.x, self.y)
    self.text:show()
end

-- ---------------------------------------------------------------------------
-- Dragging (used by EB2's setup-mode mouse handler)
-- ---------------------------------------------------------------------------
function TargetInfo:hover(x, y)
    return self.text ~= nil and self.text:visible() and self.text:hover(x, y) or false
end

function TargetInfo:move(x, y)
    self.x, self.y = x, y
    if self.cfg then self.cfg.pos = {x = x, y = y} end
    if self.text then self.text:pos(x, y) end
end

-- ---------------------------------------------------------------------------
-- Commands: //eb ti ... or //eb targetinfo ...
-- ---------------------------------------------------------------------------
local LINE_OPTS = {
    id = 'show_full_id', fullid = 'show_full_id',
    hex = 'show_hex_id', hexid = 'show_hex_id',
    speed = 'show_speed',
    name = 'show_target_name', target = 'show_target_name', claim = 'show_target_name',
}
local LINE_LABELS = {show_full_id = 'ID', show_hex_id = 'Hex ID', show_speed = 'Speed', show_target_name = 'Claim/Target'}

function TargetInfo:handleCommand(args)
    local cmd = (args[1] or 'help'):lower()
    local function say(msg, col) windower.add_to_chat(col or 207, 'EnemyBar TargetInfo: '..msg) end
    if not self.cfg then say('Not initialized yet.', 123) return end

    if cmd == 'on' or cmd == 'off' then
        self.cfg.show = (cmd == 'on')
        settings:save()
        say('Module '..(self.cfg.show and 'enabled' or 'disabled')..'.')
    elseif LINE_OPTS[cmd] then
        local key = LINE_OPTS[cmd]
        local v = args[2] and args[2]:lower()
        if v == 'on' then self.cfg[key] = true
        elseif v == 'off' then self.cfg[key] = false
        else self.cfg[key] = not self.cfg[key] end
        settings:save()
        say(LINE_LABELS[key]..' line: '..(self.cfg[key] and 'ON' or 'OFF'))
    else
        local help = {
            'TargetInfo (//eb ti or //eb targetinfo):',
            '  on / off - Enable or disable the module',
            '  id [on/off] - Full ID line',
            '  hex [on/off] - Hex ID line (NM placeholder ID)',
            '  speed [on/off] - Movement speed line',
            '  name [on/off] - Claim / target name line',
            '  Move it with //eb setup like the other bars.',
        }
        for _, l in ipairs(help) do windower.add_to_chat(207, l) end
    end
end
