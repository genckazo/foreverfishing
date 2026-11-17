-- Recommend.lua — scoring engine: expected gold/hour per zone for THIS
-- player, right now. All maths exposed via Explain() so nothing is a
-- black box. Works in unpriced mode (static tiers) when the price DB
-- is empty.

local FF = ForeverFishing
local Recommend = {}
FF.Recommend = Recommend

-- Catch rate assumption: casts per hour at a pool/open water.
local CASTS_PER_HOUR = 60

local function currentTime()
    local h, m = FF.API.GetServerTime()
    return h + (m or 0) / 60
end

local function inWindow(fish, hour)
    if not fish.timeWindow then return true end
    local f, t = fish.timeWindow[1], fish.timeWindow[2]
    if f <= t then return hour >= f and hour < t end
    -- overnight window e.g. {22, 6}
    return hour >= f or hour < t
end

local function inSeason(fish)
    if not fish.season then return true end
    local month = FF.API.GetMonth()
    for _, m in ipairs(fish.season) do
        if m == month then return true end
    end
    return false
end

-- Skill available to the player right now, including lure.
function Recommend.PlayerSkill()
    local skill, mod = FF.API.GetFishingSkill()
    skill = (skill or 0) + (mod or 0)
    local lure = FF.API.GetLureBonus()
    return skill, lure, skill + lure
end

-- Score one zone. Returns a table:
--  { zone, zoneName, goldPerHour, moneyFish={...}, pools={...},
--    lureAdvice, getawayNote, explain={lines...}, unpriced=bool }
function Recommend.ScoreZone(zoneKey, opts)
    opts = opts or {}
    local fishDB = FF.FishDB
    local zone = fishDB.ZONES[zoneKey]
    if not zone then return nil end
    local hour = currentTime()
    local baseSkill, lure, skill = Recommend.PlayerSkill()
    if opts.debugSkill then skill = opts.debugSkill + lure end

    local catchable = {}
    local totalShare = 0
    for _, f in ipairs(fishDB.FISH) do
        local inZone = false
        for _, z in ipairs(f.zones) do if z == zoneKey then inZone = true break end end
        if inZone and f.minSkill <= skill and inWindow(f, hour) and inSeason(f) then
            table.insert(catchable, f)
            totalShare = totalShare + (f.share or 0.1)
        end
    end

    local unpriced = not FF.PriceDB.HasAnyPrices()
    local expectedGold = 0
    local moneyFish = {}
    local explain = {}
    for _, f in ipairs(catchable) do
        local share = totalShare > 0 and ((f.share or 0.1) / totalShare) or 0
        local price, state = FF.PriceDB.BestPrice(f.itemID)
        local value
        if price then
            value = price
        else
            value = f.tier * 50 -- unpriced mode: static tier placeholder (copper)
            unpriced = true
        end
        local gold = share * CASTS_PER_HOUR * value
        expectedGold = expectedGold + gold
        table.insert(moneyFish, { name = f.name, share = share, price = price, state = state, gold = gold })
        table.insert(explain, string.format("  %s: share %.0f%% x %d casts/h x %s = %s",
            f.name, share * 100, CASTS_PER_HOUR,
            price and FF.FormatGold(price) or ("tier " .. f.tier .. " (unpriced)"),
            FF.FormatGold(gold)))
    end
    table.sort(moneyFish, function(a, b) return a.gold > b.gold end)

    -- Pools available in this zone.
    local pools = {}
    for key, p in pairs(fishDB.POOLS) do
        for _, z in ipairs(p.zones) do
            if z == zoneKey then table.insert(pools, p.name) break end
        end
    end

    -- Getaway honesty: highest noGetaway among catchable vs player skill.
    local worstNeed = 0
    for _, f in ipairs(catchable) do
        if f.noGetaway and f.noGetaway > worstNeed then worstNeed = f.noGetaway end
    end
    local getawayNote
    if worstNeed > 0 and skill < worstNeed then
        getawayNote = string.format("you: %d + %d lure = %d < %d needed — expect some getaways", baseSkill, lure, skill, worstNeed)
    elseif worstNeed > 0 then
        getawayNote = string.format("you: %d + %d lure = %d >= %d needed — no getaways expected", baseSkill, lure, skill, worstNeed)
    else
        getawayNote = "no skill gate in this zone at your level"
    end

    -- Lure advice: recommend a lure if it lifts skill across a threshold.
    local lureAdvice = "no lure needed"
    if worstNeed > 0 and skill < worstNeed and (skill + 100) >= worstNeed then
        lureAdvice = "apply a +100 lure (e.g. Aquadynamic Fish Attractor) to reach no-getaway"
    elseif lure == 0 and #catchable > 0 then
        lureAdvice = "optional lure for comfort"
    end

    return {
        zone = zoneKey, zoneName = zone.name,
        goldPerHour = expectedGold,
        moneyFish = moneyFish, pools = pools,
        lureAdvice = lureAdvice, getawayNote = getawayNote,
        explain = explain, unpriced = unpriced,
    }
end

-- Top 3 zones right now.
function Recommend.TopZones(opts)
    local scored = {}
    for _, z in ipairs(FF.FishDB.AllZones()) do
        local s = Recommend.ScoreZone(z, opts)
        if s and #s.moneyFish > 0 then table.insert(scored, s) end
    end
    table.sort(scored, function(a, b) return a.goldPerHour > b.goldPerHour end)
    local top = {}
    for i = 1, math.min(3, #scored) do table.insert(top, scored[i]) end
    return top, scored
end

-- Best zone name for a given fish item (for tooltips).
function Recommend.BestZoneForFish(itemID)
    local fish = FF.FishDB.ByItemID[itemID]
    if not fish then return nil end
    local best, bestGold = nil, -1
    for _, z in ipairs(fish.zones) do
        local s = Recommend.ScoreZone(z)
        if s then
            for _, mf in ipairs(s.moneyFish) do
                if mf.name == fish.name and s.goldPerHour > bestGold then
                    best, bestGold = z, s.goldPerHour
                end
            end
        end
    end
    return best and FF.FishDB.ZONES[best].name or nil
end
