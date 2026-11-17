-- Options.lua - settings persisted in SavedVariables.

local FF = ForeverFishing
local Options = {}
FF.Options = Options

Options.defaults = {
    autoScanOnAH = true,        -- prompt/auto-scan when the AH opens
    scanPageDelay = 0.35,
    overlayEnabled = true,
    soundOnLureExpiry = true,
    debugSkill = nil,           -- test hook: artificially lower skill for recommendations
    weights = { price = 1.0 },  -- recommendation weights, editable
}

function Options.Get()
    if not ForeverFishingDB then ForeverFishingDB = {} end
    if not ForeverFishingDB.options then
        ForeverFishingDB.options = {}
        for k, v in pairs(Options.defaults) do ForeverFishingDB.options[k] = v end
    end
    return ForeverFishingDB.options
end

function Options.Set(key, value)
    Options.Get()[key] = value
end
