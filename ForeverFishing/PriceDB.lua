-- PriceDB.lua — Auction House scanner + persistent price store.
-- "Live prices" = prices scanned from the in-game AH, stored in
-- ForeverFishingDB SavedVariables, with scan age shown to the player.
-- The addon has NO internet access; this is the only price source.

local FF = ForeverFishing
local PriceDB = {}
FF.PriceDB = PriceDB

PriceDB.SCHEMA_VERSION = 1
PriceDB.STALE_SECONDS = 24 * 3600
PriceDB.SCAN_PAGE_DELAY = 0.35   -- throttle between pages; one query in flight max
PriceDB.MAX_PAGES = 200         -- safety cap for a full pass

local scanning = false
local scanPage = 0
local scanSeen = 0
local scanCallback = nil
local ticker = nil

local function DB()
    if not ForeverFishingDB then ForeverFishingDB = {} end
    if not ForeverFishingDB.prices then ForeverFishingDB.prices = {} end
    if not ForeverFishingDB.schema then ForeverFishingDB.schema = PriceDB.SCHEMA_VERSION end
    return ForeverFishingDB
end

-- Record one scanned price. Keeps last, min, 7-scan median, timestamp.
function PriceDB.Record(itemID, perUnit, when)
    if not itemID or not perUnit or perUnit <= 0 then return end
    local db = DB()
    local p = db.prices[itemID]
    if not p then
        p = { last = perUnit, min = perUnit, history = { perUnit }, scannedAt = when or time() }
        db.prices[itemID] = p
    else
        p.last = perUnit
        if perUnit < p.min then p.min = perUnit end
        table.insert(p.history, perUnit)
        if #p.history > 7 then table.remove(p.history, 1) end
        p.scannedAt = when or time()
    end
end

function PriceDB.Get(itemID)
    local db = DB()
    return db.prices[itemID]
end

function PriceDB.Median(itemID)
    local p = PriceDB.Get(itemID)
    if not p or #p.history == 0 then return nil end
    local h = {}
    for _, v in ipairs(p.history) do table.insert(h, v) end
    table.sort(h)
    local n = #h
    if n % 2 == 1 then return h[(n + 1) / 2] end
    return (h[n / 2] + h[n / 2 + 1]) / 2
end

-- Age in seconds of the freshest scan for this item.
function PriceDB.Age(itemID)
    local p = PriceDB.Get(itemID)
    if not p then return nil end
    return time() - (p.scannedAt or 0)
end

function PriceDB.IsStale(itemID)
    local a = PriceDB.Age(itemID)
    return a ~= nil and a > PriceDB.STALE_SECONDS
end

function PriceDB.FormatAge(itemID)
    local a = PriceDB.Age(itemID)
    if a == nil then return "never scanned" end
    if a < 60 then return a .. " sec ago" end
    if a < 3600 then return math.floor(a / 60) .. " min ago" end
    return math.floor(a / 3600) .. " h ago"
end

-- Best usable price: median if fresh, else last flagged stale, else nil.
function PriceDB.BestPrice(itemID)
    local p = PriceDB.Get(itemID)
    if not p then return nil, "unpriced" end
    if PriceDB.IsStale(itemID) then
        return p.last, "stale"
    end
    return PriceDB.Median(itemID) or p.last, "ok"
end

function PriceDB.HasAnyPrices()
    local db = DB()
    for _ in pairs(db.prices) do return true end
    return false
end

-- Full AH scan.
-- Modern clients (C_AuctionHouse): per-fish ItemKey searches, because
-- SendSearchQuery takes an ItemKey -- there is no text query. The first
-- version passed an empty string as argument #1 and the client rejected
-- it ("bad argument #1"). Era clients keep the legacy paging driver.
-- callback(fishCount, pagesScanned) fires when done.
local scanMode = nil
local scanQueue = nil
local scanKey = nil
local scanWait = 0
local scanPriced = 0

function PriceDB.StartScan(callback)
    if scanning then FF.API.Print("Scan already running.") return false end
    if FF.API.InCombat() then FF.API.Print("Cannot scan during combat.") return false end
    if FF.API.AHIsOpen and not FF.API.AHIsOpen() then
        FF.API.Print("Open the Auction House first, then /ff scan start.")
        return false
    end
    scanning = true
    scanPage = 0
    scanSeen = 0
    scanPriced = 0
    scanCallback = callback
    if FF.API.probe.hasCAuctionHouse then
        scanMode = "modern"
        scanQueue = {}
        for id in pairs(FF.FishDB.ByItemID) do table.insert(scanQueue, id) end
        table.sort(scanQueue)
        scanKey = nil
        scanWait = 0
        FF.API.Print("AH scan started (" .. #scanQueue .. " fish)...")
    else
        scanMode = "era"
        local ok, err = FF.API.AHSearch("", 0)
        if not ok then
            scanning = false
            FF.API.Print("Scan failed to start: " .. tostring(err))
            return false
        end
        FF.API.Print("AH scan started...")
    end
    if not ticker then
        ticker = CreateFrame("Frame")
        ticker.elapsed = 0
        ticker:SetScript("OnUpdate", function(self, dt)
            self.elapsed = self.elapsed + dt
            if self.elapsed < PriceDB.SCAN_PAGE_DELAY then return end
            self.elapsed = 0
            PriceDB._ScanTick()
        end)
    end
    ticker:Show()
    return true
end

function PriceDB.StopScan(reason)
    scanning = false
    if ticker then ticker:Hide() end
    FF.API.Print("Scan stopped (" .. tostring(reason) .. "). Fish seen this pass: " .. scanSeen)
    if scanCallback then scanCallback(scanSeen, scanPage) end
end

function PriceDB.IsScanning() return scanning end

function PriceDB._ScanTick()
    if not scanning then if ticker then ticker:Hide() end return end
    if FF.API.InCombat() then return end -- pause during combat, resume after
    if scanMode == "modern" then
        PriceDB._ScanTickModern()
    else
        PriceDB._ScanTickEra()
    end
end

-- Modern driver: one ItemKey query in flight; poll until results are
-- ready, record the cheapest per-unit buyout, move to the next fish.
function PriceDB._ScanTickModern()
    if scanKey then
        if FF.API.AHResultsReady(scanKey) then
            local per = FF.API.AHCheapestPerUnit(scanKey)
            if per and per > 0 then
                PriceDB.Record(scanKey.itemID, per)
                scanSeen = scanSeen + 1
                scanPriced = scanPriced + 1
            end
            scanKey = nil
            scanWait = 0
        else
            scanWait = scanWait + PriceDB.SCAN_PAGE_DELAY
            if scanWait >= 4 then scanKey = nil scanWait = 0 end
            return
        end
    end
    local nextID = scanQueue and table.remove(scanQueue, 1)
    if not nextID then
        PriceDB.StopScan("done, priced " .. scanPriced .. " fish")
        return
    end
    local key = FF.API.AHItemKey(nextID)
    local ok, err = FF.API.AHSearchItem(key)
    if ok then
        scanKey = key
        scanWait = 0
    else
        FF.API.Print("Query rejected for item " .. tostring(nextID) .. ": " .. tostring(err))
    end
end

-- Era driver: read current page, record fish, advance page.
function PriceDB._ScanTickEra()
    local total = FF.API.AHResultCount()
    local page = FF.API.AHPage()
    local n = total or 50
    for i = 1, n do
        local row = FF.API.AHReadItem(i)
        if row and row.itemID and FF.FishDB.ByItemID[row.itemID] and row.perUnit and row.perUnit > 0 then
            PriceDB.Record(row.itemID, row.perUnit)
            scanSeen = scanSeen + 1
        end
    end
    scanPage = page + 1
    if scanPage >= PriceDB.MAX_PAGES then
        PriceDB.StopScan("page cap reached")
        return
    end
    local ok, err = FF.API.AHSearch("", scanPage)
    if not ok then
        PriceDB.StopScan("query rejected: " .. tostring(err))
    end
end

-- Tooltip hook: attach price + best zone to fish tooltips.
function PriceDB.HookTooltips()
    local function addInfo(tooltip, itemID)
        local fish = FF.FishDB.ByItemID[itemID]
        if not fish then return end
        local price, state = PriceDB.BestPrice(itemID)
        local age = PriceDB.FormatAge(itemID)
        if price then
            local grey = (state == "stale")
            local col = grey and "|cff999999" or "|cff1eff00"
            tooltip:AddLine("FF: " .. col .. FF.FormatGold(price) .. "|r median, last " ..
                col .. FF.FormatGold(FF.PriceDB.Get(itemID).last) .. "|r (" .. age .. ")")
        else
            tooltip:AddLine("FF: |cffffd100no price yet — /ff scan|r")
        end
        local best = FF.Recommend and FF.Recommend.BestZoneForFish(itemID)
        if best then
            tooltip:AddLine("FF best zone: |cff33ccff" .. best .. "|r")
        end
    end
    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and tonumber(string.match(link, "item:(%d+)"))
            if id then addInfo(tt, id) end
        end)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and tonumber(string.match(link, "item:(%d+)"))
            if id then addInfo(tt, id) end
        end)
    end
end
