-- Core.lua — init, event bus, slash commands.

ForeverFishing = {}
local FF = ForeverFishing

-- Gold formatting: copper -> g/s/c.
function FF.FormatGold(copper)
    if not copper or copper <= 0 then return "0c" end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return c .. "c"
end

-- Simple event bus.
FF.events = {}
function FF.On(event, fn)
    FF.events[event] = FF.events[event] or {}
    table.insert(FF.events[event], fn)
end
function FF.Fire(event, ...)
    for _, fn in ipairs(FF.events[event] or {}) do pcall(fn, ...) end
end

-- Report a failed step to chat without ever throwing: one broken module
-- must never take the whole addon down ("never broken" guarantee).
local function safe(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local msg = "|cff33ccff[ForeverFishing]|r module '" .. tostring(name) .. "' failed: " .. tostring(err)
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
    end
    return ok
end
FF.safe = safe

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and select(1, ...) == "ForeverFishing" then
        safe("API", FF.API.Init)
        safe("PriceDB", FF.PriceDB.HookTooltips)
        safe("Session", FF.Session.Init)
        safe("Options", function()
            local opts = FF.Options.Get()
            if opts.overlayEnabled then FF.Session.ToggleOverlay(true) end
        end)
    elseif event == "PLAYER_LOGIN" then
        safe("UI", FF.UI.InitMinimap)
    elseif event == "AUCTION_HOUSE_SHOW" then
        safe("PriceDB", function()
            if FF.Options.Get().autoScanOnAH and not FF.PriceDB.IsScanning() then
                FF.PriceDB.StartScan()
            end
        end)
    elseif event == "CHAT_MSG_LOOT" then
        -- Catch detection: loot message "You receive item: X." / "Received ...".
        local msg = select(1, ...)
        local link = msg and string.match(msg, "|Hitem:(%d+)")
        if link then
            local id = tonumber(link)
            if FF.FishDB.ByItemID[id] then safe("Session", FF.Session.Catch, id) end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = select(1, ...), select(2, ...), select(3, ...)
        if unit == "player" and spellID == 7620 then -- Fishing (Classic spellID, verify via probe)
            safe("Session", FF.Session.Cast)
        end
    end
end)

-- Slash commands.
SLASH_FF1 = "/ff"
SlashCmdList["FF"] = function(msg)
    safe("slash", FF._Slash, msg)
end

function FF._Slash(msg)
    local cmd, arg = string.match(msg or "", "^(%S*)%s*(.*)$")
    cmd = string.lower(cmd or "")
    if cmd == "" or cmd == "panel" then
        FF.UI.Toggle()
    elseif cmd == "scan" then
        if arg == "start" then FF.PriceDB.StartScan()
        else FF.API.Print("Usage: /ff scan start") end
    elseif cmd == "best" then
        local top = FF.Recommend.TopZones(FF.Options.Get().debugSkill and { debugSkill = FF.Options.Get().debugSkill } or nil)
        if #top == 0 then FF.API.Print("No recommendations — scan the AH first (/ff scan start).") return end
        for i, z in ipairs(top) do
            FF.API.Print(string.format("#%d %s — est %s/h%s | %s | %s",
                i, z.zoneName, FF.FormatGold(z.goldPerHour), z.unpriced and " (unpriced mode)" or "",
                z.getawayNote, z.lureAdvice))
        end
    elseif cmd == "session" then
        FF.API.Print(FF.Session.SummaryText())
    elseif cmd == "reset" then
        FF.Session.Reset()
    else
        FF.API.Print("Commands: /ff panel | /ff scan start | /ff best | /ff session | /ff reset")
    end
end
