--[[
    Limbus module for EnemyBar2 (ported from LimbusHelper v1.06 by
    Kaius @ Bahamut and Linktri @ Asura).

    Tracks the four treasure-chest sectors in Apollyon and Temenos and shows
    whether each one gave the standard reward (3,000 units) or the bonus
    (5,000 units). Drawn with EnemyBar2's own bar textures and text style.
    After a bonus the gold bar drains for 5 seconds, then the zone resets.

    Apollyon chests: NW (-211, 542, 0)   NE (214, 542, 0)
                     SW (-109, -429, 0)  SE (112, -430, 0)
    Temenos chests:  N (-598, 457, 84)   W (-596, 177, 4)
                     E (-596, -102, 84)  C (-281, -423, -162)
]]

local config = require('config')
local images = require('images')
local texts  = require('texts')

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local APOLLYON = 38
local TEMENOS  = 37

local ZONE_NAME     = {[APOLLYON] = 'Apollyon', [TEMENOS] = 'Temenos'}
local ZONE_KEY      = {[APOLLYON] = 'apollyon', [TEMENOS] = 'temenos'}
local ZONE_ORDER    = {APOLLYON, TEMENOS}
local ZONE_SECTORS  = {
    [APOLLYON] = {'NW', 'SW', 'NE', 'SE'},
    [TEMENOS]  = {'N', 'W', 'E', 'C'},
}
local ZONE_CHESTS = {
    [APOLLYON] = {
        NW = {x = -211, y =  542, z = 0},
        NE = {x =  214, y =  542, z = 0},
        SW = {x = -109, y = -429, z = 0},
        SE = {x =  112, y = -430, z = 0},
    },
    [TEMENOS] = {
        N = {x = -598, y =  457, z =  84},
        W = {x = -596, y =  177, z =   4},
        E = {x = -596, y = -102, z =  84},
        C = {x = -281, y = -423, z = -162},
    },
}

local STANDARD_AMT    = 3000
local BONUS_AMT       = 5000
local CHEST_DIST      = 20   -- yalms; must be this close to a chest to count
local RECORD_COOLDOWN = 10   -- seconds between automatic recordings (debounce)
local RESET_DELAY     = 5    -- seconds after a bonus before the zone resets

local BAR_HEIGHT    = 12
local HEADER_GAP    = 6      -- space between header text and first bar
local ZONE_GAP      = 10     -- extra space between the two zones when both show
local MAX_ROWS      = 8
local MAX_HEADERS   = 2

-- Player-typed chat modes; Units text arriving here is ignored
local CHAT_MODES = {}
for _, m in ipairs({1, 2, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 212, 213, 214}) do
    CHAT_MODES[m] = true
end

-- Row colours. Every state draws a solid fill bar (EB2's bg_body texture is
-- nearly transparent, so an "empty" bar would be invisible in game).
local COL = {
    unopened = {fg = {170, 30, 30},  text = {255, 215, 215}},
    opened   = {fg = {0, 170, 60},   text = {255, 255, 255}},
    bonus    = {fg = {255, 200, 0},  text = {255, 250, 220}},
    header   = {80, 255, 128},
}

local STROKE = {width = 2, alpha = 180, red = 50, green = 50, blue = 50}

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
Limbus = {
    active_zone      = nil,
    debug            = false,
    tracking         = {[APOLLYON] = {}, [TEMENOS] = {}},  -- [zone][sector] = nil|'std'|'bonus'
    pending          = {},    -- pending[zone] = os.clock() time the bonus reset fires
    last_record_time = 0,
    state            = nil,   -- per-character config object
    display          = nil,   -- {headers = {}, rows = {}}
    cfg              = nil,   -- settings.limbus_bar
    x = 0, y = 0,
}

-- ---------------------------------------------------------------------------
-- Persistence (per character: data/limbus_<CharName>.xml)
-- ---------------------------------------------------------------------------
local state_defaults = {}
for zone_id, list in pairs(ZONE_SECTORS) do
    for _, s in ipairs(list) do
        state_defaults[ZONE_KEY[zone_id]..'_'..s] = false
    end
    state_defaults[ZONE_KEY[zone_id]..'_bonus'] = 'none'
end

function Limbus:initState()
    local player = windower.ffxi.get_player()
    if not player then return false end
    self.state = config.load('data/limbus_'..player.name..'.xml', state_defaults)
    self:loadState()
    return true
end

function Limbus:saveState()
    if not self.state then return end
    for zone_id, list in pairs(ZONE_SECTORS) do
        local key, bonus = ZONE_KEY[zone_id], 'none'
        for _, s in ipairs(list) do
            local st = self.tracking[zone_id][s]
            self.state[key..'_'..s] = st ~= nil
            if st == 'bonus' then bonus = s end
        end
        self.state[key..'_bonus'] = bonus
    end
    self.state:save()
end

function Limbus:loadState()
    if not self.state then return end
    for zone_id, list in pairs(ZONE_SECTORS) do
        local key = ZONE_KEY[zone_id]
        local bonus = self.state[key..'_bonus']
        self.tracking[zone_id] = {}
        for _, s in ipairs(list) do
            if bonus == s then
                self.tracking[zone_id][s] = 'bonus'
            elseif self.state[key..'_'..s] == true then
                self.tracking[zone_id][s] = 'std'
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function say(msg, col) windower.add_to_chat(col or 207, 'EnemyBar Limbus: '..msg) end

local function nearest_chest(zone_id, x, y, z)
    local best, best_d2 = nil, math.huge
    for sector, p in pairs(ZONE_CHESTS[zone_id]) do
        local dx, dy, dz = x - p.x, y - p.y, z - p.z
        local d2 = dx*dx + dy*dy + dz*dz
        if d2 < best_d2 then best, best_d2 = sector, d2 end
    end
    return best, best_d2
end

local function zone_for_sector(s)
    for zone_id, list in pairs(ZONE_SECTORS) do
        for _, v in ipairs(list) do
            if v == s then return zone_id end
        end
    end
end

local function valid_sector(zone_id, s)
    for _, v in ipairs(ZONE_SECTORS[zone_id]) do
        if v == s then return true end
    end
    return false
end

local function zone_by_name(name)
    name = (name or ''):lower()
    for zone_id, key in pairs(ZONE_KEY) do
        if key == name or key:sub(1, 1) == name then return zone_id end
    end
end

function Limbus:bonusSector(zone_id)
    for _, s in ipairs(ZONE_SECTORS[zone_id]) do
        if self.tracking[zone_id][s] == 'bonus' then return s end
    end
end

-- ---------------------------------------------------------------------------
-- Tracking logic
-- ---------------------------------------------------------------------------
function Limbus:resetZone(zone_id)
    self.tracking[zone_id] = {}
    self.pending[zone_id] = nil
    self:saveState()
end

function Limbus:startAutoReset(zone_id)
    self.pending[zone_id] = os.clock() + RESET_DELAY
end

function Limbus:record(zone_id, sector, amount)
    local is_bonus = amount == BONUS_AMT
    self.tracking[zone_id][sector] = is_bonus and 'bonus' or 'std'
    self:saveState()
    if is_bonus then
        say('BONUS ('..amount..') at '..ZONE_NAME[zone_id]..' '..sector..'! Resetting in '..RESET_DELAY..'s...', 158)
        self:startAutoReset(zone_id)
    else
        say('Standard ('..amount..') at '..ZONE_NAME[zone_id]..' '..sector..'.')
    end
end

function Limbus:enterZone(zone_id)
    self.active_zone = zone_id
    self:loadState()
    -- A saved bonus with no live countdown means the reset was interrupted
    local s = self:bonusSector(zone_id)
    if s and not self.pending[zone_id] then
        say('Pending bonus at '..ZONE_NAME[zone_id]..' '..s..' found; resetting shortly.')
        self:startAutoReset(zone_id)
    end
end

function Limbus:initCurrentZone()
    if not self:initState() then return end
    local info = windower.ffxi.get_info()
    if info and ZONE_NAME[info.zone] then
        self:enterZone(info.zone)
    else
        self.active_zone = nil
    end
end

function Limbus:handleText(original, mode)
    if not self.active_zone then return end
    if self.debug then say('[mode='..mode..'] '..original) end
    if CHAT_MODES[mode] then return end

    local zone_str, amt_str = original:match('Acquired (%a+) Units: (%d+)')
    if not zone_str then return end
    local amount = tonumber(amt_str)
    if amount ~= STANDARD_AMT and amount ~= BONUS_AMT then return end

    if zone_str ~= ZONE_NAME[self.active_zone] then
        say('Units message zone ('..zone_str..') does not match current zone - ignored.', 8)
        return
    end

    local me = windower.ffxi.get_mob_by_target('me')
    if not me then
        say('Chest reward ('..amount..') seen but position unreadable. Use //eb lh sector <sector> '..amount, 8)
        return
    end

    -- Not near a chest (e.g. a ??? reward): ignore
    local sector, d2 = nearest_chest(self.active_zone, me.x, me.y, me.z)
    if d2 > CHEST_DIST * CHEST_DIST then return end

    -- Debounce after the distance check so a ??? can't swallow a real chest
    local now = os.time()
    if now - self.last_record_time < RECORD_COOLDOWN then return end
    self.last_record_time = now

    self:record(self.active_zone, sector, amount)
end

-- ---------------------------------------------------------------------------
-- Display (EB2 look: tinted bar textures + bold stroked Arial)
-- ---------------------------------------------------------------------------
local function new_image(path)
    return images.new({
        pos = {x = 0, y = 0},
        visible = false,
        color = {alpha = 255, red = 255, green = 255, blue = 255},
        size = {width = 1, height = BAR_HEIGHT},
        texture = {path = windower.addon_path..path, fit = true},
        repeatable = {x = 1, y = 1},
        draggable = false,
    })
end

local function new_text(cfg, scale)
    return texts.new('', {
        pos = {x = 0, y = 0},
        text = {size = math.floor(cfg.font_size * (scale or 1) + 0.5), font = cfg.font, stroke = STROKE},
        flags = {bold = true, draggable = false, italic = false},
        bg = {visible = false},
    })
end

local function element_list(d)
    local list = {}
    for _, h in ipairs(d.headers) do list[#list+1] = h end
    for _, r in ipairs(d.rows) do
        list[#list+1] = r.fg; list[#list+1] = r.label
    end
    return list
end

function Limbus:destroyDisplay()
    if not self.display then return end
    for _, e in ipairs(element_list(self.display)) do
        if e and e.destroy then e:destroy() end
    end
    self.display = nil
end

function Limbus:initialize(cfg)
    self:destroyDisplay()
    if not cfg then return end
    self.cfg = cfg
    self.x, self.y = cfg.pos.x or 0, cfg.pos.y or 0

    local d = {headers = {}, rows = {}}
    for i = 1, MAX_HEADERS do d.headers[i] = new_text(cfg, 0.9) end
    for i = 1, MAX_ROWS do
        d.rows[i] = {
            fg    = new_image('fg_body.png'),
            label = new_text(cfg, 1),
        }
    end
    self.display = d
end

function Limbus:hideAll()
    if not self.display then return end
    for _, e in ipairs(element_list(self.display)) do e:hide() end
end

-- Lays out and paints a list of zone views:
-- views = { {title=, rows={ {sector=, status=, frac=, remaining=} ...}} ... }
function Limbus:render(views)
    local d, cfg = self.display, self.cfg
    if not d then return end
    local w = cfg.width
    local spacing = cfg.row_spacing
    local text_dy = 3 + (14 - cfg.font_size) / 4
    local header_h = math.floor(cfg.font_size * 0.9) + HEADER_GAP + 4

    local y = self.y
    local hi, ri = 0, 0
    for vi, view in ipairs(views) do
        hi = hi + 1
        local h = d.headers[hi]
        h:text(view.title)
        h:color(unpack(COL.header))
        h:pos(self.x, y)
        h:show()
        y = y + header_h

        for _, rv in ipairs(view.rows) do
            ri = ri + 1
            local r = d.rows[ri]
            local c = COL[rv.status]
            -- Unopened shows a full red bar; others fill by their fraction
            local frac = rv.status == 'unopened' and 1 or (rv.frac or 0)
            r.fg:pos(self.x, y)
            local fw = math.floor(w * frac)
            if fw > 0 then
                r.fg:width(fw)
                r.fg:color(c.fg[1], c.fg[2], c.fg[3])
                r.fg:show()
            else
                r.fg:hide()
            end

            local tag = rv.status == 'bonus' and 'BONUS!' or rv.status == 'opened' and 'Opened' or 'Unopened'
            if rv.remaining then tag = tag..' '..rv.remaining..'s' end
            r.label:text(rv.sector..': '..tag)
            r.label:color(c.text[1], c.text[2], c.text[3])
            r.label:pos(self.x + math.floor(w / 100) + 2, y + text_dy)

            r.label:show()
            y = y + spacing
        end
        y = y + ZONE_GAP
    end

    -- Hide anything unused
    for i = hi + 1, MAX_HEADERS do d.headers[i]:hide() end
    for i = ri + 1, MAX_ROWS do
        local r = d.rows[i]
        r.fg:hide(); r.label:hide()
    end
end

function Limbus:zoneView(zone_id, now)
    local rows, opened = {}, 0
    for _, s in ipairs(ZONE_SECTORS[zone_id]) do
        local st = self.tracking[zone_id][s]
        local rv = {sector = s}
        if st == 'bonus' then
            rv.status = 'bonus'
            local fire = self.pending[zone_id]
            if fire then
                local left = math.max(0, fire - now)
                rv.frac = left / RESET_DELAY
                rv.remaining = math.ceil(left)
            else
                rv.frac = 1
            end
        elseif st == 'std' then
            rv.status, rv.frac = 'opened', 1
        else
            rv.status, rv.frac = 'unopened', 0
        end
        if st then opened = opened + 1 end
        rows[#rows+1] = rv
    end
    return {title = ZONE_NAME[zone_id]..'  '..opened..' / '..#rows, rows = rows}
end

local function demo_views()
    return {{
        title = 'Temenos  2 / 4',
        rows = {
            {sector = 'N', status = 'opened',   frac = 1},
            {sector = 'W', status = 'unopened', frac = 0},
            {sector = 'E', status = 'bonus',    frac = 0.6, remaining = 3},
            {sector = 'C', status = 'unopened', frac = 0},
        },
    }}
end

-- Called from EB2's main update loop (~10/s)
function Limbus:update(setup_mode)
    local now = os.clock()

    -- Fire any due auto-resets (independent of whether we're drawing)
    for zone_id, fire in pairs(self.pending) do
        if now >= fire then
            self:resetZone(zone_id)
            say(ZONE_NAME[zone_id]..' tracking reset. Find the next bonus!')
        end
    end

    if not self.display or not self.cfg then return end
    if not self.cfg.show then self:hideAll(); return end

    if setup_mode then
        self:render(demo_views())
    elseif self.active_zone then
        self:render({self:zoneView(self.active_zone, now)})
    elseif self.cfg.show_anywhere then
        local views = {}
        for _, z in ipairs(ZONE_ORDER) do views[#views+1] = self:zoneView(z, now) end
        self:render(views)
    else
        self:hideAll()
    end
end

-- ---------------------------------------------------------------------------
-- Dragging (used by EB2's setup-mode mouse handler)
-- ---------------------------------------------------------------------------
function Limbus:hover(x, y)
    if not self.display then return false end
    for _, e in ipairs(element_list(self.display)) do
        if e:visible() and e:hover(x, y) then return true end
    end
    return false
end

function Limbus:move(x, y)
    self.x, self.y = x, y
    if self.cfg then self.cfg.pos = {x = x, y = y} end
    -- Dragging only happens in setup mode, so redraw the demo immediately
    if self.display and self.cfg and self.cfg.show then self:render(demo_views()) end
end

-- ---------------------------------------------------------------------------
-- Commands: //eb limbus ... or //eb lh ...
-- ---------------------------------------------------------------------------
function Limbus:handleCommand(args)
    local cmd = (args[1] or 'help'):lower()

    if cmd == 'reset' then
        local which = args[2] and args[2]:lower()
        local zones
        if which == 'all' then
            zones = {APOLLYON, TEMENOS}
        elseif which then
            local z = zone_by_name(which)
            if not z then say('Usage: //eb lh reset [apollyon|temenos|all]', 123) return end
            zones = {z}
        elseif self.active_zone then
            zones = {self.active_zone}
        else
            zones = {APOLLYON, TEMENOS}
        end
        local names = {}
        for _, z in ipairs(zones) do
            self:resetZone(z)
            names[#names+1] = ZONE_NAME[z]
        end
        say('Tracking reset for '..table.concat(names, ' and ')..'.')

    elseif cmd == 'sector' then
        local s = (args[2] or ''):upper()
        local amount = tonumber(args[3])
        local zone_id = self.active_zone or zone_for_sector(s)
        if not zone_id then
            say('Unknown sector "'..s..'". Apollyon: NW NE SW SE | Temenos: N W E C', 123)
        elseif not valid_sector(zone_id, s) then
            say('Valid sectors for '..ZONE_NAME[zone_id]..': '..table.concat(ZONE_SECTORS[zone_id], ' '), 123)
        elseif args[3] and amount ~= STANDARD_AMT and amount ~= BONUS_AMT then
            say('Amount must be '..STANDARD_AMT..' or '..BONUS_AMT..'.', 123)
        elseif amount then
            self:record(zone_id, s, amount)
        elseif self.tracking[zone_id][s] then
            self.tracking[zone_id][s] = nil
            if not self:bonusSector(zone_id) then self.pending[zone_id] = nil end
            self:saveState()
            say(ZONE_NAME[zone_id]..' '..s..' marked Unopened.')
        else
            self:record(zone_id, s, STANDARD_AMT)
        end

    elseif cmd == 'show' or cmd == 'hide' or cmd == 'toggle' then
        if not self.cfg then return end
        if cmd == 'toggle' then
            self.cfg.show_anywhere = not self.cfg.show_anywhere
        else
            self.cfg.show_anywhere = (cmd == 'show')
        end
        settings:save()
        say('Show outside Limbus: '..(self.cfg.show_anywhere and 'ON' or 'OFF'))

    elseif cmd == 'on' or cmd == 'off' then
        if not self.cfg then return end
        self.cfg.show = (cmd == 'on')
        settings:save()
        say('Module '..(self.cfg.show and 'enabled' or 'disabled')..'.')

    elseif cmd == 'pos' then
        local me = windower.ffxi.get_mob_by_target('me')
        if not me then say('Cannot read player position.', 123) return end
        say(('Position x=%.2f y=%.2f z=%.2f'):format(me.x, me.y, me.z))
        if self.active_zone then
            local s, d2 = nearest_chest(self.active_zone, me.x, me.y, me.z)
            say(('Detected sector: %s (%.1f yalms from its chest)'):format(s, math.sqrt(d2)))
        else
            say('Not in Apollyon or Temenos.')
        end

    elseif cmd == 'debug' then
        self.debug = not self.debug
        say('Text debug: '..(self.debug and 'ON (echoing all incoming text in Limbus)' or 'OFF'))

    else
        local help = {
            'Limbus (//eb lh or //eb limbus):',
            '  reset [apollyon|temenos|all] - Reset tracking (auto-resets '..RESET_DELAY..'s after a bonus)',
            '  sector <sector> - Toggle a sector Opened/Unopened',
            '  sector <sector> <3000|5000> - Log a chest result by hand',
            '  show / hide / toggle - Show both zones outside Limbus',
            '  on / off - Enable or disable the module',
            '  pos - Print position and detected sector',
            '  debug - Echo incoming text (troubleshooting)',
            '  Sectors: Apollyon NW NE SW SE | Temenos N W E C',
            '  Move it with //eb setup like the other bars.',
        }
        for _, line in ipairs(help) do windower.add_to_chat(207, line) end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
windower.register_event('incoming text', function(original, modified, mode)
    Limbus:handleText(original, mode)
end)

windower.register_event('zone change', function(new_zone)
    if ZONE_NAME[new_zone] then
        Limbus:enterZone(new_zone)
    else
        Limbus.active_zone = nil
    end
end)

windower.register_event('load', function() Limbus:initCurrentZone() end)

windower.register_event('login', function()
    Limbus.state, Limbus.pending = nil, {}
    Limbus:initCurrentZone()
end)
