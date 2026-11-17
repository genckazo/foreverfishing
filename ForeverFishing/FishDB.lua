-- FishDB.lua — static, data-only knowledge base. Editable by the player.
-- ALL itemIDs and mapIDs below are Classic-Era hypotheses. WoW Forever has
-- custom/changed items, so each one MUST be verified against ForeverDB and
-- the results logged in COMPAT.md. Treat every ID here as unconfirmed.

local FF = ForeverFishing
local FishDB = {}
FF.FishDB = FishDB

-- Zone mapIDs (Classic mapID hypotheses — verify via probe/C_Map).
FishDB.ZONES = {
    barrens    = { id = 1413, name = "The Barrens" },
    stv        = { id = 1434, name = "Stranglethorn Vale" },
    tanaris    = { id = 1417, name = "Tanaris" },
    azshara    = { id = 1447, name = "Azshara" },
    feralas    = { id = 1444, name = "Feralas" },
    hinterlands= { id = 1425, name = "The Hinterlands" },
    desolace   = { id = 1411, name = "Desolace" },
    dustwallow = { id = 1445, name = "Dustwallow Marsh" },
    moonglade  = { id = 1450, name = "Moonglade" },
    wplague    = { id = 1422, name = "Western Plaguelands" },
    winterspring={ id = 1452, name = "Winterspring" },
    ashenvale  = { id = 1440, name = "Ashenvale" },
    stonetalon = { id = 1442, name = "Stonetalon Mountains" },
}

-- Pools: openWater = true means regular water; poolType otherwise.
FishDB.POOLS = {
    oilyBlackmouthSchool = { name = "Oily Blackmouth School", zones = { "barrens", "stonetalon", "dustwallow", "wplague", "ashenvale" } },
    firefinSchool        = { name = "Firefin Snapper School",  zones = { "barrens", "stv", "dustwallow", "ashenvale" } },
    sagefishSchool       = { name = "Sagefish School",         zones = { "desolace", "feralas", "hinterlands" } },
    deviateSchool        = { name = "Deviate Fish School",     zones = { "barrens" } },
    floatingWreckage     = { name = "Floating Wreckage",       zones = { "stv", "tanaris", "feralas", "azshara" } },
}

-- Fish entries. Fields:
--  itemID      Classic-era hypothesis — VERIFY against ForeverDB
--  name        display name
--  zones       keys into ZONES
--  pool        key into POOLS, or nil for open water
--  minSkill    minimum fishing skill to catch at all
--  noGetaway   skill at which catches stop getting away (approx)
--  timeWindow  {fromH, toH} server hours inclusive, or nil = any time
--  season      {months...} 1-12, or nil = all year
--  share       expected share of catches in its zone when available (0-1), editable
--  tier        static value tier 1(low)-5(high), used only in unpriced mode
--  cookedNote  flag only: cooked version may sell for more
FishDB.FISH = {
    {
        itemID = 6289, name = "Raw Brilliant Smallfish",
        zones = { "barrens", "stonetalon", "dustwallow", "ashenvale", "feralas", "hinterlands" },
        pool = nil, minSkill = 1, noGetaway = 20, timeWindow = nil, season = nil,
        share = 0.45, tier = 1, cookedNote = "Cooked Brilliant Smallfish sells slightly more.",
    },
    {
        itemID = 6361, name = "Oily Blackmouth",
        zones = { "barrens", "stonetalon", "dustwallow", "wplague", "ashenvale" },
        pool = "oilyBlackmouthSchool", minSkill = 25, noGetaway = 50, timeWindow = nil, season = nil,
        share = 0.25, tier = 2, cookedNote = nil,
    },
    {
        itemID = 6362, name = "Firefin Snapper",
        zones = { "barrens", "stv", "dustwallow", "ashenvale" },
        pool = "firefinSchool", minSkill = 50, noGetaway = 75, timeWindow = nil, season = nil,
        share = 0.20, tier = 2, cookedNote = "Firefin Snapper (cooked) used in quests; AH value varies.",
    },
    {
        itemID = 8365, name = "Raw Greater Sagefish",
        zones = { "desolace", "feralas", "hinterlands" },
        pool = "sagefishSchool", minSkill = 75, noGetaway = 100, timeWindow = nil, season = nil,
        share = 0.20, tier = 3, cookedNote = "Cooked Greater Sagefish sells more.",
    },
    {
        itemID = 6522, name = "Deviate Fish",
        zones = { "barrens" },
        pool = "deviateSchool", minSkill = 20, noGetaway = 45, timeWindow = nil, season = nil,
        share = 0.30, tier = 2, cookedNote = nil,
    },
    {
        itemID = 13756, name = "Raw Nightfin Snapper",   -- Era hypothesis, verify
        zones = { "feralas", "tanaris", "azshara", "hinterlands" },
        pool = nil, minSkill = 110, noGetaway = 225,
        timeWindow = { 0, 6 }, season = nil,
        share = 0.15, tier = 4, cookedNote = "Cooked Nightfin sells well.",
    },
    {
        itemID = 13754, name = "Raw Sunscale Salmon",    -- Era hypothesis, verify
        zones = { "feralas", "tanaris", "azshara", "hinterlands", "moonglade" },
        pool = nil, minSkill = 100, noGetaway = 200,
        timeWindow = { 6, 18 }, season = nil,
        share = 0.15, tier = 4, cookedNote = nil,
    },
    {
        itemID = 13759, name = "Raw Glowing Brightfish", -- Era hypothesis, verify
        zones = { "wplague", "winterspring", "hinterlands", "azshara" },
        pool = nil, minSkill = 150, noGetaway = 250, timeWindow = nil, season = nil,
        share = 0.10, tier = 4, cookedNote = nil,
    },
    {
        itemID = 13760, name = "Raw Mightfish",          -- Era hypothesis, verify
        zones = { "stonetalon", "desolace", "feralas", "tanaris" },
        pool = nil, minSkill = 175, noGetaway = 275, timeWindow = nil, season = nil,
        share = 0.10, tier = 5, cookedNote = "Cooked Mightfish is a top seller.",
    },
    {
        itemID = 13755, name = "Winter Squid",           -- Era hypothesis, verify (conflicts with Raw Redgill 13755 in some DBs — MUST verify)
        zones = { "tanaris", "winterspring", "azshara", "hinterlands" },
        pool = "floatingWreckage", minSkill = 200, noGetaway = 300,
        timeWindow = nil, season = { 12, 1, 2 },
        share = 0.12, tier = 5, cookedNote = nil,
    },
    {
        itemID = 13758, name = "Raw Summer Bass",        -- Era hypothesis, verify
        zones = { "stv", "tanaris", "feralas", "dustwallow" },
        pool = nil, minSkill = 150, noGetaway = 250, timeWindow = { 6, 18 },
        season = { 6, 7, 8 },
        share = 0.12, tier = 5, cookedNote = nil,
    },
    {
        itemID = 13761, name = "Stonescale Eel",         -- Era hypothesis, verify
        zones = { "azshara", "winterspring", "wplague", "hinterlands" },
        pool = nil, minSkill = 225, noGetaway = 325, timeWindow = nil, season = nil,
        share = 0.08, tier = 5, cookedNote = "Stonescale Eel (cooked) premium.",
    },
}

-- Quick lookup: itemID -> fish entry.
FishDB.ByItemID = {}
for _, f in ipairs(FishDB.FISH) do
    FishDB.ByItemID[f.itemID] = f
end

-- All zones that have at least one fish/pool, for the recommender.
function FishDB.AllZones()
    local set = {}
    for _, f in ipairs(FishDB.FISH) do
        for _, z in ipairs(f.zones) do set[z] = true end
    end
    for _, p in pairs(FishDB.POOLS) do
        for _, z in ipairs(p.zones) do set[z] = true end
    end
    local out = {}
    for z, _ in pairs(set) do table.insert(out, z) end
    table.sort(out)
    return out
end
