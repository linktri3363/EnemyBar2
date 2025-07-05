--[[
Legacy GUI Settings File - DEPRECATED
This file is maintained for backwards compatibility only.
All functionality has been moved to the main bars.lua system.

Version 2.2 - Compatibility Layer
--]]

-- Legacy compatibility notice
windower.add_to_chat(123, 'WARNING: gui_settings.lua is deprecated. Functionality moved to bars.lua')
windower.add_to_chat(207, 'EnemyBar v2.2: Legacy file loaded for compatibility only.')

-- Legacy variables for compatibility (no longer used)
targetBarHeight = 12
targetBarWidth = 598
subtargetBarHeight = 12
subtargetBarWidth = 198
visible = false

-- Legacy paths (maintained for compatibility)
bg_cap_path = windower.addon_path.. 'bg_cap.png'
bg_body_path = windower.addon_path.. 'bg_body.png'
fg_body_path = windower.addon_path.. 'fg_body.png'

center_screen = windower.get_windower_settings().x_res / 2 - targetBarWidth / 2

-- Legacy text settings (no longer used - moved to bars.lua)
text_settings = {
    pos = {x = center_screen, y = 50},
    text = {
        size = 14,
        font = 'Arial',
        fonts = {'Arial'},
        stroke = {width = 2, alpha = 127, red = 50, green = 50, blue = 50}
    },
    flags = {bold = true, draggable = false},
    bg = {visible = false}
}

-- Legacy image settings (no longer used - moved to bars.lua)
tbg_cap_settings = {
    pos = {x = center_screen, y = 50},
    visible = true,
    color = {alpha = 255, red = 150, green = 0, blue = 0},
    size = {width = 1, height = 598},
    texture = {path = bg_cap_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

-- More legacy settings (maintained for compatibility)
stbg_cap_settings = {
    pos = {x = center_screen, y = 50},
    visible = true,
    color = {alpha = 255, red = 0, green = 51, blue = 255},
    size = {width = 1, height = subtargetBarHeight},
    texture = {path = bg_cap_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

tbg_body_settings = {
    pos = {x = center_screen, y = 50},
    visible = true,
    color = {alpha = 255, red = 150, green = 0, blue = 0},
    size = {width = targetBarWidth, height = targetBarHeight},
    texture = {path = bg_body_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

stbg_body_settings = {
    pos = {x = center_screen + 400, y = 65},
    visible = true,
    color = {alpha = 255, red = 0, green = 51, blue = 255},
    size = {width = subtargetBarWidth, height = subtargetBarHeight},
    texture = {path = bg_body_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

tfgg_body_settings = {
    pos = {x = center_screen, y = 50},
    visible = true,
    color = {alpha = 200, red = 255, green = 0, blue = 0},
    size = {width = targetBarWidth, height = targetBarHeight},
    texture = {path = fg_body_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

tfg_body_settings = {
    pos = {x = center_screen, y = 50},
    visible = true,
    color = {alpha = 255, red = 255, green = 51, blue = 0},
    size = {width = targetBarWidth, height = targetBarHeight},
    texture = {path = fg_body_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

stfg_body_settings = {
    pos = {x = center_screen + 400, y = 65},
    visible = true,
    color = {alpha = 255, red = 0, green = 102, blue = 255},
    size = {width = subtargetBarWidth, height = subtargetBarHeight},
    texture = {path = fg_body_path, fit = true},
    repeatable = {x = 1, y = 1},
    draggable = false
}

-- Legacy defaults (maintained for migration purposes