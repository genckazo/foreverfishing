-- Session.lua - live session stats: casts, catches, gold/hour, catch log,
-- lure expiry and zone skill warnings. NO automation of any kind:
-- nothing here casts, loots, or recasts.

local FF = ForeverFishing
local Session = {}
FF.Session = Session

local sess = nil
local overlay = nil
local ticker = nil
local lastLureCheck = 0
local warnedZone = nil

local function newSession()
    return {
        startTime = time(),
        casts = 0,
        catches = {},       -- itemID -> count
        goldEarned = 0,
        lureWarned = false,
    }
end

function Session.Start()
    sess = newSession()
    FF.API.Print("Session started.")
end

function Session.Reset()
    sess = newSession()
    FF.API.Print("Session reset.")
end

function Session.IsActive() return sess ~= nil end

function Session.Cast()
    if not sess then Session.Start() end
    sess.casts = sess.casts + 1
    Session._RefreshOverlay()
end

function Session.Catch(itemID)
    if not sess then Session.Start() end
    sess.catches[itemID] = (sess.catches[itemID] or 0) + 1
    local price = FF.PriceDB.Median(itemID) or (FF.PriceDB.Get(itemID) and FF.PriceDB.Get(itemID).last)
    if price then sess.goldEarned = sess.goldEarned + price end
    Session._RefreshOverlay()
end

function Session.Stats()
    if not sess then return nil end
    local dur = time() - sess.startTime
    local gph = dur > 0 and (sess.goldEarned / dur) * 3600 or 0
    return {
        duration = dur, casts = sess.casts, catches = sess.catches,
        goldEarned = sess.goldEarned, goldPerHour = gph,
    }
end

function Session.SummaryText()
    local s = Session.Stats()
    if not s then return "No session yet. Cast a line to start one." end
    local lines = {
        string.format("Session: %d casts, %d catches, %s earned, %s/h (over %d min)",
            s.casts, s.catches and 0 or 0, FF.FormatGold(s.goldEarned), FF.FormatGold(s.goldPerHour), math.floor(s.duration / 60)),
    }
    local total = 0
    for _, c in pairs(s.catches) do total = total + c end
    lines[1] = string.format("Session: %d casts, %d catches, %s earned, %s/h (over %d min)",
        s.casts, total, FF.FormatGold(s.goldEarned), FF.FormatGold(s.goldPerHour), math.floor(s.duration / 60))
    for itemID, count in pairs(s.catches) do
        local fish = FF.FishDB.ByItemID[itemID]
        table.insert(lines, string.format("  %s x%d", fish and fish.name or ("item " .. itemID), count))
    end
    return table.concat(lines, "\n")
end

-- Movable overlay showing live stats while fishing.
function Session._RefreshOverlay()
    if not overlay then return end
    local s = Session.Stats()
    if not s then overlay:Hide() return end
    local total = 0
    for _, c in pairs(s.catches) do total = total + c end
    overlay.text:SetText(string.format("FF  casts %d | catches %d | %s | %s/h",
        s.casts, total, FF.FormatGold(s.goldEarned), FF.FormatGold(s.goldPerHour)))
    overlay:Show()
end

function Session.ToggleOverlay(show)
    if not overlay then
        overlay = CreateFrame("Frame", "FFSessionOverlay", UIParent)
        overlay:SetSize(320, 24)
        overlay:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        overlay:SetMovable(true)
        overlay:EnableMouse(true)
        overlay:RegisterForDrag("LeftButton")
        overlay:SetScript("OnDragStart", overlay.StartMoving)
        overlay:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local db = ForeverFishingDB or {}
            db.overlayPos = { self:GetPoint() }
            ForeverFishingDB = db
        end)
        overlay:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true })
        overlay:SetBackdropColor(0.02, 0.08, 0.13, 0.78)
        overlay:SetBackdropBorderColor(0.55, 0.45, 0.20, 0.9)
        overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        overlay.text:SetPoint("CENTER")
        overlay.text:SetTextColor(0.95, 0.90, 0.78)
        overlay:Hide()
        local db = ForeverFishingDB
        if db and db.overlayPos then overlay:SetPoint(unpack(db.overlayPos)) end
    end
    if show then Session._RefreshOverlay() else overlay:Hide() end
end

-- Throttled ticker: lure expiry warning + zone skill warning.
function Session.Init()
    if ticker then return end
    ticker = CreateFrame("Frame")
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 1.0 then return end -- 1 s cadence, well above the 0.2 s floor
        self.elapsed = 0
        Session._Tick()
    end)
end

function Session._Tick()
    -- Lure expiry: if a lure buff was present and is now gone, warn once.
    local lure = FF.API.GetLureBonus()
    if Session._hadLure and lure == 0 and not (sess and sess.lureWarned) then
        FF.API.Print("Lure expired.")
        FF.API.PlaySound(62649) -- UI error-ish beep; nil-guarded
        if sess then sess.lureWarned = true end
    end
    Session._hadLure = (lure > 0)

    -- Zone warning: entering a zone where top fish no-getaway exceeds skill+lure.
    local mapID = FF.API.GetCurrentZone()
    if mapID and warnedZone ~= mapID then
        warnedZone = mapID
        for key, z in pairs(FF.FishDB.ZONES) do
            if z.id == mapID then
                local skill, lureBonus, total = FF.Recommend.PlayerSkill()
                for _, f in ipairs(FF.FishDB.FISH) do
                    local inZone = false
                    for _, zz in ipairs(f.zones) do if zz == key then inZone = true break end end
                    if inZone and f.minSkill <= total and f.noGetaway and total < f.noGetaway then
                        FF.API.Print(string.format("Zone note: %s needs %d skill to avoid getaways (you have %d). Apply a lure.",
                            f.name, f.noGetaway, total))
                        break
                    end
                end
                break
            end
        end
    end
end
