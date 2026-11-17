-- UI.lua — main panel (4 tabs), minimap button, waypoint helper.
-- Everything movable; position persisted in SavedVariables.
-- v0.2.0 restyle: deep-water + gold theme, tabs inside the panel with a
-- gold active marker, divider lines, and a region pool — Refresh() runs
-- every 0.5s, and FontStrings/Textures are NOT returned by GetChildren(),
-- so the old cleanup leaked them on every single refresh.

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

-- Theme: deep water + gold. Solid colours and long-standing built-in
-- texture paths only, so it renders on any client flavour.
local THEME = {
    gold    = { 1.00, 0.82, 0.30 },
    goldDim = { 0.85, 0.68, 0.30 },
    teal    = { 0.35, 0.90, 1.00 },
    text    = { 0.92, 0.90, 0.84 },
    dim     = { 0.62, 0.62, 0.60 },
    warn    = { 1.00, 0.80, 0.20 },
    line    = { 0.55, 0.45, 0.20, 0.55 },
    bgTop   = { 0.03, 0.13, 0.20, 0.94 },
    bgBot   = { 0.01, 0.05, 0.09, 0.94 },
}

-- Region pool: everything a render creates is registered in `live` and
-- recycled by the next Refresh instead of leaking.
local pool = { fs = {}, tex = {}, btn = {} }
local live = {}

local function track(region, kind)
    region._ffKind = kind
    table.insert(live, region)
    return region
end

local function poolFS(parent)
    local fs = table.remove(pool.fs)
    if not fs then fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal") end
    fs:SetParent(parent)
    fs:ClearAllPoints()
    fs:Show()
    return track(fs, "fs")
end

local function poolTex(parent)
    local t = table.remove(pool.tex)
    if not t then t = parent:CreateTexture(nil, "ARTWORK") end
    t:SetParent(parent)
    t:ClearAllPoints()
    t:Show()
    return track(t, "tex")
end

local function poolBtn(parent)
    local b = table.remove(pool.btn)
    if not b then
        local ok, nb = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
        b = (ok and nb) or CreateFrame("Button", nil, parent)
    end
    b:SetParent(parent)
    b:ClearAllPoints()
    b:SetScript("OnClick", nil)
    b:Enable()
    b:Show()
    return track(b, "btn")
end

local function releaseLive()
    for _, r in ipairs(live) do
        r:Hide()
        if r._ffKind == "btn" then r:SetScript("OnClick", nil) end
        local bucket = pool[r._ffKind]
        if bucket then table.insert(bucket, r) end
    end
    live = {}
end

-- Create with the richest template the client actually has; an unknown
-- template name throws, so probe with pcall and fall back to a plain frame.
local function makePanel()
    local ok, p = pcall(CreateFrame, "Frame", "FFPanel", UIParent, "BasicFrameTemplateWithInset")
    if ok and p then return p end
    ok, p = pcall(CreateFrame, "Frame", "FFPanel", UIParent, "BasicFrameTemplate")
    if ok and p then return p end
    return CreateFrame("Frame", "FFPanel", UIParent)
end

local function ensurePanel()
    if panel then return panel end
    panel = makePanel()
    -- Plain-frame fallback has no inset/title bar: give it a backdrop so it
    -- is still a visible, bordered window on any client.
    if not panel.TitleBg then
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true,
        })
        panel:SetBackdropColor(0.02, 0.08, 0.13, 0.94)
        panel:SetBackdropBorderColor(0.55, 0.45, 0.20, 0.9)
    end
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
    panel:SetScript("OnShow", function() UI.Refresh() end)

    -- Deep-water gradient behind the content (title bar keeps the
    -- template look). Solid colour first; gradient is a guarded bonus.
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -56)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    bg:SetColorTexture(unpack(THEME.bgTop))
    if CreateColor and bg.SetGradient then
        pcall(function()
            bg:SetGradient("VERTICAL",
                CreateColor(THEME.bgBot[1], THEME.bgBot[2], THEME.bgBot[3], THEME.bgBot[4]),
                CreateColor(THEME.bgTop[1], THEME.bgTop[2], THEME.bgTop[3], THEME.bgTop[4]))
        end)
    end

    if panel.TitleBg then panel.TitleBg:SetHeight(30) end
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -7)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_01")
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if panel.TitleBg then
        panel.title:SetPoint("TOP", panel.TitleBg, "TOP", 0, -8)
    else
        panel.title:SetPoint("TOP", panel, "TOP", 0, -10)
    end
    panel.title:SetText("ForeverFishing")
    panel.title:SetTextColor(unpack(THEME.gold))
    panel:Hide()

    local db = ForeverFishingDB
    if db and db.panelPos then panel:SetPoint(unpack(db.panelPos)) end

    -- Tab buttons, inside the panel under the title bar. The active tab
    -- gets gold text and a gold underline bar. Icons are built-in game
    -- textures (shipped with every client, all OS); a missing icon just
    -- renders blank, it never errors.
    local TAB_ICONS = {
        where   = "Interface\\Icons\\INV_Misc_Fish_01",
        prices  = "Interface\\Icons\\INV_Misc_Coin_02",
        session = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        options = "Interface\\Icons\\INV_Misc_Gear_01",
    }
    local tabBtns = {}
    for i, t in ipairs(TABS) do
        local ok, b = pcall(CreateFrame, "Button", "FFTab" .. t.key, panel, "UIPanelButtonTemplate")
        if not ok or not b then b = CreateFrame("Button", "FFTab" .. t.key, panel) end
        b:SetSize(120, 22)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + (i - 1) * 124, -30)
        b:SetText(t.label)
        local ticon = b:CreateTexture(nil, "ARTWORK")
        ticon:SetSize(14, 14)
        ticon:SetPoint("LEFT", b, "LEFT", 6, 0)
        ticon:SetTexture(TAB_ICONS[t.key] or TAB_ICONS.where)
        b:SetScript("OnClick", function() UI.ShowTab(t.key) end)
        local bar = b:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(unpack(THEME.gold))
        bar:SetHeight(2)
        bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 1)
        bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 1)
        bar:Hide()
        b._ffBar = bar
        tabBtns[t.key] = b
    end
    UI._tabBtns = tabBtns

    -- Content scroll frame (template if present, plain otherwise).
    local okS, scroll = pcall(CreateFrame, "ScrollFrame", "FFScroll", panel, "UIPanelScrollFrameTemplate")
    if not okS or not scroll then scroll = CreateFrame("ScrollFrame", "FFScroll", panel) end
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -58)
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
        local fs = b.GetFontString and b:GetFontString()
        if k == currentTab then
            if fs then fs:SetTextColor(unpack(THEME.gold)) end
            if b._ffBar then b._ffBar:Show() end
        else
            if fs then fs:SetTextColor(unpack(THEME.text)) end
            if b._ffBar then b._ffBar:Hide() end
        end
    end
    releaseLive()
    local c = UI._content
    if currentTab == "where" then UI._RenderWhere(c)
    elseif currentTab == "prices" then UI._RenderPrices(c)
    elseif currentTab == "session" then UI._RenderSession(c)
    elseif currentTab == "options" then UI._RenderOptions(c) end
end

local function addLine(parent, text, y, color)
    local fs = poolFS(parent)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    fs:SetWidth(450)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(unpack(color or THEME.text))
    return y - 16
end

local function addDivider(parent, y)
    local t = poolTex(parent)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y - 3)
    t:SetSize(452, 1)
    t:SetColorTexture(unpack(THEME.line))
    return y - 10
end

local function addButton(parent, label, y, onClick, x, w)
    local b = poolBtn(parent)
    b:SetSize(w or 140, 20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 8, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

function UI._RenderWhere(c)
    local y = -8
    local opts = FF.Options.Get()
    local debug = opts.debugSkill and { debugSkill = opts.debugSkill } or nil
    local top = FF.Recommend.TopZones(debug)
    if #top == 0 then
        y = addLine(c, "No zones available. Scan the AH first: /ff scan start", y, THEME.warn)
    end
    for i, z in ipairs(top) do
        if i > 1 then y = addDivider(c, y) end
        y = addLine(c, string.format("#%d  %s — est %s/h%s", i, z.zoneName,
            FF.FormatGold(z.goldPerHour), z.unpriced and "  [UNPRICED MODE — static tiers]" or ""),
            y, i == 1 and THEME.gold or THEME.teal)
        y = addLine(c, "   " .. z.getawayNote, y)
        y = addLine(c, "   Lure: " .. z.lureAdvice, y)
        if #z.pools > 0 then
            y = addLine(c, "   Pools: " .. table.concat(z.pools, ", "), y)
        end
        local fishNames = {}
        for j = 1, math.min(3, #z.moneyFish) do table.insert(fishNames, z.moneyFish[j].name) end
        y = addLine(c, "   Money fish: " .. table.concat(fishNames, ", "), y)
        y = addLine(c, "   Why this zone:", y, THEME.goldDim)
        for _, line in ipairs(z.explain) do y = addLine(c, line, y, THEME.dim) end
        addButton(c, "Waypoint", y, function() UI.SetWaypoint(z.zone) end)
        y = y - 26 - 8
    end
    c:SetHeight(math.max(200, -y + 20))
end

function UI._RenderPrices(c)
    local y = -8
    if not FF.PriceDB.HasAnyPrices() then
        y = addLine(c, "No prices yet — open the Auction House or /ff scan start", y, THEME.warn)
    end
    y = addLine(c, string.format("%-24s %10s %10s %12s %s", "Fish", "Last", "Median", "Age", "Best zone"), y, THEME.goldDim)
    y = addDivider(c, y + 4)
    for _, f in ipairs(FF.FishDB.FISH) do
        local p = FF.PriceDB.Get(f.itemID)
        local last = p and FF.FormatGold(p.last) or "—"
        local med = FF.PriceDB.Median(f.itemID)
        med = med and FF.FormatGold(med) or "—"
        local age = FF.PriceDB.FormatAge(f.itemID)
        local stale = FF.PriceDB.IsStale(f.itemID)
        local best = FF.Recommend.BestZoneForFish(f.itemID) or "—"
        local col = stale and THEME.dim or THEME.text
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
    y = addLine(c, "Scan behaviour:", y, THEME.goldDim)
    addButton(c, opts.autoScanOnAH and "Auto-scan on AH: ON" or "Auto-scan on AH: OFF", y,
        function() FF.Options.Set("autoScanOnAH", not opts.autoScanOnAH) UI.Refresh() end)
    y = y - 26
    y = addLine(c, "Overlay while fishing:", y, THEME.goldDim)
    addButton(c, opts.overlayEnabled and "Overlay: ON" or "Overlay: OFF", y,
        function() FF.Options.Set("overlayEnabled", not opts.overlayEnabled) FF.Session.ToggleOverlay(opts.overlayEnabled) UI.Refresh() end)
    y = y - 26
    y = addLine(c, "Debug (test): lower skill for recommendations:", y, THEME.goldDim)
    local skills = { nil, 100, 140, 200 }
    local labels = { "off", "100", "140", "200" }
    for i, s in ipairs(skills) do
        local b = addButton(c, labels[i], y, function() FF.Options.Set("debugSkill", s) UI.Refresh() end, 8 + (i - 1) * 66, 60)
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
    local ring = minimapBtn:CreateTexture(nil, "ARTWORK")
    ring:SetSize(54, 54)
    ring:SetPoint("CENTER")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapBtn:SetScript("OnClick", function() UI.Toggle() end)
    minimapBtn:RegisterForClicks("LeftButtonUp")
end
