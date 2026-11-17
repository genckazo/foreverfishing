-- UI.lua — main panel (4 tabs), minimap button, waypoint helper.
-- Everything movable; position persisted in SavedVariables.

local FF = ForeverFishing
local UI = {}
FF.UI = UI

local panel = nil
local minimapBtn = nil
local currentTab = "where"

local TABS = {
    { key = "where",   label = "Where to Fish" },
    { key = "prices",  label = "Prices" },
    { key = "session", label = "Session" },
    { key = "options", label = "Options" },
}

local function ensurePanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "FFPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(520, 420)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = ForeverFishingDB or {}
        db.panelPos = { self:GetPoint() }
        ForeverFishingDB = db
    end)
    panel.TitleBg:SetHeight(30)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.title:SetPoint("TOP", panel.TitleBg, "TOP", 0, -8)
    panel.title:SetText("ForeverFishing")
    panel:Hide()

    local db = ForeverFishingDB
    if db and db.panelPos then panel:SetPoint(unpack(db.panelPos)) end

    -- Tab buttons.
    local tabBtns = {}
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", "FFTab" .. t.key, panel, "UIPanelButtonTemplate")
        b:SetSize(110, 22)
        b:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 10 + (i - 1) * 115, 2)
        b:SetText(t.label)
        b:SetScript("OnClick", function() UI.ShowTab(t.key) end)
        tabBtns[t.key] = b
    end
    UI._tabBtns = tabBtns

    -- Content scroll frame.
    local scroll = CreateFrame("ScrollFrame", "FFScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame", "FFScrollChild", scroll)
    content:SetSize(470, 600)
    scroll:SetScrollChild(content)
    UI._content = content
    UI._scroll = scroll

    -- Refresh ticker for live tab content.
    local ticker = CreateFrame("Frame", nil, panel)
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 0.5 then return end
        self.elapsed = 0
        if panel:IsShown() then UI.Refresh() end
    end)
    return panel
end

function UI.Toggle()
    ensurePanel()
    if panel:IsShown() then panel:Hide() else UI.ShowTab(currentTab) panel:Show() end
end

function UI.ShowTab(key)
    currentTab = key
    ensurePanel()
    UI.Refresh()
end

function UI.Refresh()
    if not panel or not panel:IsShown() then return end
    for k, b in pairs(UI._tabBtns or {}) do
        if k == currentTab then b:Disable() else b:Enable() end
    end
    local c = UI._content
    for _, child in ipairs({ c:GetChildren() }) do child:Hide() child:SetParent(nil) end
    if currentTab == "where" then UI._RenderWhere(c)
    elseif currentTab == "prices" then UI._RenderPrices(c)
    elseif currentTab == "session" then UI._RenderSession(c)
    elseif currentTab == "options" then UI._RenderOptions(c) end
end

local function addLine(parent, text, y, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    fs:SetWidth(450)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    if color then fs:SetTextColor(unpack(color)) end
    return y - 16
end

local function addButton(parent, label, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(140, 20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return y - 26
end

function UI._RenderWhere(c)
    local y = -8
    local opts = FF.Options.Get()
    local debug = opts.debugSkill and { debugSkill = opts.debugSkill } or nil
    local top = FF.Recommend.TopZones(debug)
    if #top == 0 then
        y = addLine(c, "No zones available. Scan the AH first: /ff scan start", y, { 1, 0.8, 0.2 })
    end
    for i, z in ipairs(top) do
        y = addLine(c, string.format("#%d  %s — est %s/h%s", i, z.zoneName,
            FF.FormatGold(z.goldPerHour), z.unpriced and "  [UNPRICED MODE — static tiers]" or ""), y, { 0.4, 0.9, 1 })
        y = addLine(c, "   " .. z.getawayNote, y)
        y = addLine(c, "   Lure: " .. z.lureAdvice, y)
        if #z.pools > 0 then
            y = addLine(c, "   Pools: " .. table.concat(z.pools, ", "), y)
        end
        local fishNames = {}
        for j = 1, math.min(3, #z.moneyFish) do table.insert(fishNames, z.moneyFish[j].name) end
        y = addLine(c, "   Money fish: " .. table.concat(fishNames, ", "), y)
        y = addLine(c, "   Why this zone:", y, { 1, 1, 0.6 })
        for _, line in ipairs(z.explain) do y = addLine(c, line, y, { 0.8, 0.8, 0.8 }) end
        y = addButton(c, "Waypoint", y, function() UI.SetWaypoint(z.zone) end)
        y = y - 8
    end
    c:SetHeight(math.max(200, -y + 20))
end

function UI._RenderPrices(c)
    local y = -8
    if not FF.PriceDB.HasAnyPrices() then
        y = addLine(c, "No prices yet — open the Auction House or /ff scan start", y, { 1, 0.8, 0.2 })
    end
    y = addLine(c, string.format("%-24s %10s %10s %12s %s", "Fish", "Last", "Median", "Age", "Best zone"), y, { 1, 1, 0.6 })
    for _, f in ipairs(FF.FishDB.FISH) do
        local p = FF.PriceDB.Get(f.itemID)
        local last = p and FF.FormatGold(p.last) or "—"
        local med = FF.PriceDB.Median(f.itemID)
        med = med and FF.FormatGold(med) or "—"
        local age = FF.PriceDB.FormatAge(f.itemID)
        local stale = FF.PriceDB.IsStale(f.itemID)
        local best = FF.Recommend.BestZoneForFish(f.itemID) or "—"
        local col = stale and { 0.6, 0.6, 0.6 } or nil
        y = addLine(c, string.format("%-24s %10s %10s %12s %s%s", f.name, last, med, age, best, stale and " (stale)" or ""), y, col)
    end
    c:SetHeight(math.max(200, -y + 20))
end

function UI._RenderSession(c)
    local y = -8
    y = addLine(c, FF.Session.SummaryText(), y)
    c:SetHeight(math.max(200, -y + 40))
end

function UI._RenderOptions(c)
    local y = -8
    local opts = FF.Options.Get()
    y = addLine(c, "Scan behaviour:", y, { 1, 1, 0.6 })
    y = addButton(c, opts.autoScanOnAH and "Auto-scan on AH: ON" or "Auto-scan on AH: OFF", y,
        function() FF.Options.Set("autoScanOnAH", not opts.autoScanOnAH) UI.Refresh() end)
    y = addLine(c, "Overlay while fishing:", y, { 1, 1, 0.6 })
    y = addButton(c, opts.overlayEnabled and "Overlay: ON" or "Overlay: OFF", y,
        function() FF.Options.Set("overlayEnabled", not opts.overlayEnabled) FF.Session.ToggleOverlay(opts.overlayEnabled) UI.Refresh() end)
    y = addLine(c, "Debug (test): lower skill for recommendations:", y, { 1, 1, 0.6 })
    local skills = { nil, 100, 140, 200 }
    local labels = { "off", "100", "140", "200" }
    for i, s in ipairs(skills) do
        local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        b:SetSize(60, 20)
        b:SetPoint("TOPLEFT", c, "TOPLEFT", 8 + (i - 1) * 66, y)
        b:SetText(labels[i])
        b:SetScript("OnClick", function() FF.Options.Set("debugSkill", s) UI.Refresh() end)
        if opts.debugSkill == s then b:Disable() end
    end
    y = y - 30
    c:SetHeight(math.max(200, -y + 20))
end

-- Waypoint: TomTom if present (feature-detected), else text directions.
function UI.SetWaypoint(zoneKey)
    local zone = FF.FishDB.ZONES[zoneKey]
    if not zone then return end
    if TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, zone.id, nil, nil, { title = zone.name .. " (fishing)" })
        FF.API.Print("TomTom waypoint set: " .. zone.name)
    else
        FF.API.Print("No TomTom — travel to " .. zone.name .. " and fish its pools/open water.")
    end
end

-- Minimap button.
function UI.InitMinimap()
    if minimapBtn then return end
    minimapBtn = CreateFrame("Button", "FFMinimapBtn", Minimap)
    minimapBtn:SetSize(32, 32)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
    local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_01")
    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapBtn:SetScript("OnClick", function() UI.Toggle() end)
    minimapBtn:RegisterForClicks("LeftButtonUp")
end
