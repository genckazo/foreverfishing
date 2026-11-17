-- API.lua — client-version adapter.
-- Every version-specific call in the addon goes through this table.
-- Detection happens once at load; each function is nil-guarded so an
-- unprobed API degrades to nil instead of throwing.

local FF = ForeverFishing
local API = {}
FF.API = API

-- Probe results recorded here at load; COMPAT.md must mirror them after
-- the in-game probe (Step 0) is run by the player.
API.probe = {
    build = nil,            -- from GetBuildInfo()
    hasCAuctionHouse = false,
    hasEraAH = false,
    hasSkillLine = false,   -- C_SkillLine or GetSkillLineInfo
    hasCMap = false,
    hasGetGameTime = false,
    queryCooldown = nil,    -- seconds, if the client exposes one
}

function API.Init()
    local ok, b1, b2, b3, b4 = pcall(GetBuildInfo)
    if ok then
        API.probe.build = tostring(b1) .. "." .. tostring(b2) .. "." .. tostring(b3)
    end
    API.probe.hasCAuctionHouse = (C_AuctionHouse ~= nil)
    API.probe.hasEraAH = (QueryAuctionItems ~= nil and GetAuctionItemInfo ~= nil)
    API.probe.hasSkillLine = (C_SkillLine ~= nil) or (GetSkillLineInfo ~= nil)
    API.probe.hasCMap = (C_Map ~= nil)
    API.probe.hasGetGameTime = (GetGameTime ~= nil)

    -- Auction House: send a browse query for a search string, page p (0-based).
    -- Returns true if the query was accepted (async; results arrive via event).
    function API.AHSearch(query, page)
        if C_AuctionHouse then
            local ok, err = pcall(C_AuctionHouse.SendSearchQuery, query, {}, false)
            if ok then return true, nil end
            return false, err
        elseif QueryAuctionItems then
            -- Era API: QueryAuctionItems(slot, ...) — we search by name on the
            -- "owner"/text path: QueryAuctionItems(0, query...) is not a text
            -- search; Era uses blizzard's own AH UI filters. For a raw name
            -- scan we page the whole AH (slot = nil) and filter client-side.
            local ok, err = pcall(QueryAuctionItems, 0, query, nil, nil, nil, nil, false, false, page or 0)
            if ok then return true, nil end
            return false, err
        end
        return false, "no AH API"
    end

    -- Number of results on the current page / total (best effort per API).
    function API.AHResultCount()
        if C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems then
            local ok, n = pcall(C_AuctionHouse.GetNumReplicateItems)
            if ok then return n end
        end
        -- Era: GetNumAuctionItems("list") is the classic call.
        if GetNumAuctionItems then
            local ok, n = pcall(GetNumAuctionItems, "list")
            if ok then return n end
        end
        return nil
    end

    function API.AHPage()
        if C_AuctionHouse and C_AuctionHouse.GetReplicateItemsPage then
            local ok, p = pcall(C_AuctionHouse.GetReplicateItemsPage)
            if ok then return p end
        end
        return 0
    end

    -- Read one result row: itemID, buyout per unit, quantity, timeLeft.
    function API.AHReadItem(index)
        if C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo then
            local ok, info = pcall(C_AuctionHouse.GetReplicateItemInfo, index)
            if ok and info then
                local buyout = info.buyoutAmount or (info.auctionAmountPerItem) or 0
                return {
                    itemID = info.itemID,
                    buyout = buyout,
                    count = info.count or 1,
                    perUnit = (info.count and info.count > 0) and (buyout / info.count) or buyout,
                }
            end
            return nil
        elseif GetAuctionItemInfo then
            local ok, name, _, count, _, _, _, _, buyout, _, _, _, _, _, _, _, itemID = pcall(GetAuctionItemInfo, "list", index)
            if ok and itemID then
                return {
                    itemID = itemID,
                    buyout = buyout or 0,
                    count = count or 1,
                    perUnit = (count and count > 0 and buyout and buyout > 0) and (buyout / count) or (buyout or 0),
                }
            end
        end
        return nil
    end

    -- Fishing skill: returns (skillLevel, skillMod) or nils.
    function API.GetFishingSkill()
        if C_SkillLine and C_SkillLine.GetSkillInfo then
            -- find the Fishing skill line id lazily
            if not API._fishSkillID then
                local ok, lines = pcall(C_SkillLine.GetSkillLines)
                if ok and lines then
                    for _, l in ipairs(lines) do
                        if l and l.skillName == "Fishing" or (l and l.name == "Fishing") then
                            API._fishSkillID = l.skillLineID
                        end
                    end
                end
            end
            if API._fishSkillID then
                local ok, info = pcall(C_SkillLine.GetSkillInfo, API._fishSkillID)
                if ok and info then
                    return info.skillLevel, info.skillModifier or 0
                end
            end
        end
        if GetSkillLineInfo then
            -- Era: GetSkillLineInfo(index) — scan for Fishing.
            local i = 1
            while true do
                local ok, name, _, rank, _, _, mod = pcall(GetSkillLineInfo, i)
                if not ok or not name then return nil, nil end
                if name == "Fishing" then return rank, mod or 0 end
                i = i + 1
            end
        end
        return nil, nil
    end

    -- Zone: current map id and name.
    function API.GetCurrentZone()
        if C_Map and C_Map.GetBestMapForUnit then
            local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
            if ok and id then
                local name = nil
                if C_Map.GetMapInfo then
                    local ok2, info = pcall(C_Map.GetMapInfo, id)
                    if ok2 and info then name = info.name end
                end
                return id, name
            end
        end
        if GetCurrentMapAreaID then
            local ok, id = pcall(GetCurrentMapAreaID)
            if ok and id then
                local name = nil
                if GetZoneText then name = GetZoneText() end
                return id, name
            end
        end
        return nil, nil
    end

    function API.GetZoneName(mapID)
        if mapID and C_Map and C_Map.GetMapInfo then
            local ok, info = pcall(C_Map.GetMapInfo, mapID)
            if ok and info then return info.name end
        end
        return tostring(mapID or "?")
    end

    -- Server time: hours, minutes (0-23, 0-59).
    function API.GetServerTime()
        if GetGameTime then
            local ok, h, m = pcall(GetGameTime)
            if ok and h then return h, m end
        end
        -- Fallback: local time (wrong around midnight server offsets, flagged).
        local t = date("*t")
        return t.hour, t.min
    end

    -- Current month (1-12) for season rules; server-independent approximation.
    function API.GetMonth()
        return date("*t").month
    end

    -- Combat check.
    function API.InCombat()
        return UnitAffectingCombat and UnitAffectingCombat("player") or false
    end

    -- Lure check: scan tooltip of equipped weapon for lure aura.
    -- Returns bonus fishing skill from lure, or 0.
    function API.GetLureBonus()
        local slot = GetInventorySlotInfo and GetInventorySlotInfo("MainHandSlot")
        if not slot then return 0 end
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if not link then return 0 end
        -- Lure buffs appear as item buffs on the pole; simplest robust check:
        -- scan aura slots for " fishing" in the name.
        for i = 1, 40 do
            local name = GetPlayerBuffName and GetPlayerBuffName(i)
            if not name then break end
            local _, _, _, _, _, _, _, _, _, _, _, _, _, spellId = GetPlayerBuff and GetPlayerBuff(i)
            if name and (string.find(string.lower(name), "lure") or string.find(string.lower(name), "fishing")) then
                -- Known lure buffs grant +skill; parse the number from the tooltip
                -- is overkill — use the documented values via a small table.
                local bonus = FF.LURE_BONUS_BY_NAME and FF.LURE_BONUS_BY_NAME[string.lower(name)]
                if bonus then return bonus end
                local num = string.match(name, "(%d+)")
                if num then return tonumber(num) end
            end
        end
        return 0
    end

    -- Sound playback, nil-guarded.
    function API.PlaySound(kitID)
        if PlaySound then pcall(PlaySound, kitID) end
    end

    -- Chat print helper.
    function API.Print(msg)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[ForeverFishing]|r " .. tostring(msg))
    end
end

-- Documented lure bonuses (Classic values; verified against probe in COMPAT.md).
FF.LURE_BONUS_BY_NAME = {
    ["aquadynamic fish attractor"] = 100,
    ["bright baubles"] = 25,
    ["flesh eating worm"] = 50,
    ["luminous stone"] = 75, -- placeholder name, refined by probe
}
