-- CoolDownTracker: Raid cooldown tracker for Turtle WoW
-- Slash: /cdt
-- Tracks raid members only via UNIT_CASTEVENT (SuperWoW)

-- ── Cached stdlib globals (hot-path locals) ───────────────────────────────────
local _GetTime = GetTime
local _floor   = math.floor
local _mod     = math.mod
local _getn    = table.getn

-- ── Layout constants ──────────────────────────────────────────────────────────
-- Detail mode
CDT_W        = 220   -- total frame width (detail mode)
CDT_HDR_H    = 15    -- header bar height (both modes)
CDT_ROW_H    = 15    -- height of each data row (detail)
CDT_ICON_SZ  = 14    -- spell icon size (detail)
CDT_ICON_X   = 2
CDT_LBL_X    = 19
CDT_LBL_W    = 68
CDT_NM_X     = 90
CDT_NM_W     = 86
CDT_TM_W     = 38

-- Summary mode
CDT_SUMM_COL_W    = 34
CDT_SUMM_ICON_SZ  = 28
CDT_SUMM_GAP      = 3
CDT_SUMM_PAD      = 4
CDT_SUMM_NM_H     = 11
CDT_SUMM_NM_ROWS  = 3
-- FIX 1: increased from 100 to 140 so second icon-row name strings don't overflow the background
CDT_SUMM_BODY_H   = 140

-- PullCheck panel
PC_HDR_H  = 13   -- height of the pullcheck header bar
PC_BODY_H = 13   -- height of a single prompt row
PC_RANGE  = 40   -- yard threshold for in-range check

-- ── Spell definitions ─────────────────────────────────────────────────────────
CDT_SPELL_DEFS = {
    {
        key="cshout",            label="C.Shout",          cd=600,
        icon="ability_bullrush",
        cr=0.78, cg=0.61, cb=0.43,
    },
    {
        key="croar",             label="C.Roar",           cd=600,
        icon="ability_druid_challangingroar",
        cr=1.0,  cg=0.49, cb=0.04,
    },
    {
        key="disarm",            label="Disarm",           cd=60,
        icon="ability_warrior_disarm",
        cr=0.78, cg=0.61, cb=0.43,
    },
    {
        key="loh",               label="Lay on Hands*",    cd=3600,
        icon="spell_holy_layonhands",
        cr=0.96, cg=0.55, cb=0.73,
    },
    {
        key="divineintervention",label="Div.Intervention", cd=3600,
        icon="spell_nature_timestop",
        cr=0.96, cg=0.55, cb=0.73,
    },
    {
        key="fearward",          label="Fear Ward",        cd=30,
        icon="spell_holy_excorcism",
        cr=1.0,  cg=1.0,  cb=1.0,
    },
    {
        key="spiritlink",        label="Spirit Link",      cd=180,
        icon="spell_shaman_spiritlink",
        cr=0.0,  cg=0.44, cb=0.87,
    },
    {
        key="innervate",         label="Innervate",        cd=360,
        icon="spell_nature_lightning",
        cr=1.0,  cg=0.49, cb=0.04,
    },
    {
        key="tranquility",       label="Tranquility*",     cd=1800,
        icon="spell_nature_tranquility",
        cr=1.0,  cg=0.49, cb=0.04,
    },
    {
        key="reincarn",          label="Reincarnation*",   cd=3600,
        icon="spell_nature_reincarnation",
        cr=0.0,  cg=0.44, cb=0.87,
    },
    {
        key="soulstone",         label="Soulstone",        cd=1800,
        icon="inv_misc_orb_04",
        cr=0.58, cg=0.51, cb=0.79,
    },
    {
        key="rebirth",           label="Rebirth*",         cd=1800,
        icon="spell_nature_reincarnation",
        cr=1.0,  cg=0.49, cb=0.04,
    },
}

-- spellId -> def
local _kd = {}
for _i = 1, _getn(CDT_SPELL_DEFS) do
    _kd[CDT_SPELL_DEFS[_i].key] = CDT_SPELL_DEFS[_i]
end
CDT_IDS = {}
CDT_IDS[1161]  = _kd["cshout"]
CDT_IDS[5209]  = _kd["croar"]
CDT_IDS[676]   = _kd["disarm"]
CDT_IDS[29166] = _kd["innervate"]
CDT_IDS[20484] = _kd["rebirth"]
CDT_IDS[20739] = _kd["rebirth"]
CDT_IDS[20742] = _kd["rebirth"]
CDT_IDS[20747] = _kd["rebirth"]
CDT_IDS[20748] = _kd["rebirth"]
CDT_IDS[633]   = _kd["loh"]
CDT_IDS[2800]  = _kd["loh"]
CDT_IDS[10310] = _kd["loh"]
CDT_IDS[20234] = _kd["loh"]
CDT_IDS[20235] = _kd["loh"]
CDT_IDS[19752] = _kd["divineintervention"]
CDT_IDS[6346]  = _kd["fearward"]
CDT_IDS[693]   = _kd["soulstone"]
CDT_IDS[20752] = _kd["soulstone"]
CDT_IDS[20755] = _kd["soulstone"]
CDT_IDS[20756] = _kd["soulstone"]
CDT_IDS[20757] = _kd["soulstone"]
CDT_IDS[20608] = _kd["reincarn"]
CDT_IDS[51363] = _kd["spiritlink"]
CDT_IDS[740]   = _kd["tranquility"]
CDT_IDS[8918]  = _kd["tranquility"]
CDT_IDS[9862]  = _kd["tranquility"]
CDT_IDS[9863]  = _kd["tranquility"]
_kd = nil

-- ── PullCheck healer-detection spell IDs ─────────────────────────────────────
PC_HEAL_IDS = {}
-- Flash Heal (Priest) ranks 1-9
PC_HEAL_IDS[2061]  = true
PC_HEAL_IDS[9472]  = true
PC_HEAL_IDS[9473]  = true
PC_HEAL_IDS[9474]  = true
PC_HEAL_IDS[10915] = true
PC_HEAL_IDS[10916] = true
PC_HEAL_IDS[10917] = true
PC_HEAL_IDS[25233] = true
PC_HEAL_IDS[25235] = true
-- Chain Heal (Shaman) ranks 1-4
PC_HEAL_IDS[1064]  = true
PC_HEAL_IDS[10622] = true
PC_HEAL_IDS[10623] = true
PC_HEAL_IDS[25422] = true
-- Rejuvenation (Druid) ranks 1-10
PC_HEAL_IDS[774]   = true
PC_HEAL_IDS[1058]  = true
PC_HEAL_IDS[1430]  = true
PC_HEAL_IDS[2090]  = true
PC_HEAL_IDS[2091]  = true
PC_HEAL_IDS[3627]  = true
PC_HEAL_IDS[8910]  = true
PC_HEAL_IDS[9839]  = true
PC_HEAL_IDS[9840]  = true
PC_HEAL_IDS[25299] = true
-- Regrowth (Druid) ranks 1-9
PC_HEAL_IDS[8936]  = true
PC_HEAL_IDS[8938]  = true
PC_HEAL_IDS[8939]  = true
PC_HEAL_IDS[8940]  = true
PC_HEAL_IDS[8941]  = true
PC_HEAL_IDS[9750]  = true
PC_HEAL_IDS[9856]  = true
PC_HEAL_IDS[9857]  = true
PC_HEAL_IDS[9858]  = true
-- Healing Touch (Druid) ranks 1-11
PC_HEAL_IDS[5185]  = true
PC_HEAL_IDS[5186]  = true
PC_HEAL_IDS[5187]  = true
PC_HEAL_IDS[5188]  = true
PC_HEAL_IDS[5189]  = true
PC_HEAL_IDS[6778]  = true
PC_HEAL_IDS[8903]  = true
PC_HEAL_IDS[9758]  = true
PC_HEAL_IDS[9888]  = true
PC_HEAL_IDS[9889]  = true
PC_HEAL_IDS[25297] = true
-- Daybreak (Paladin proc)
PC_HEAL_IDS[28562] = true
PC_HEAL_IDS[28563] = true

-- Config option tables
CDT_SHOW_OPTS  = { "always", "raid", "mouseover" }
CDT_READY_OPTS = { "on", "off" }
CDT_BAR_OPTS   = { "H", "V" }
CDT_VIEW_OPTS  = { "detail", "summary" }

-- Precomputed raid unit strings
CDT_RAID_UNITS = {}
for _i = 1, 40 do CDT_RAID_UNITS[_i] = "raid" .. _i end

-- ── GUID → name index ────────────────────────────────────────────────────────
CDT_GUID_TO_NAME = {}

function CDT_BuildGUIDIndex()
    for k in pairs(CDT_GUID_TO_NAME) do CDT_GUID_TO_NAME[k] = nil end
    local n = GetNumRaidMembers()
    if n and n > 0 then
        local units = CDT_RAID_UNITS
        for i = 1, n do
            local unit = units[i]
            local exists, guid = UnitExists(unit)
            if exists and guid then
                local name = UnitName(unit)
                if name then CDT_GUID_TO_NAME[guid] = name end
            end
        end
    end
    local exists, pguid = UnitExists("player")
    if exists and pguid then
        local pname = UnitName("player")
        if pname then CDT_GUID_TO_NAME[pguid] = pname end
    end
end

-- ── SavedVariables init ───────────────────────────────────────────────────────
function CDT_InitDB()
    if not CDT_DB then CDT_DB = {} end
    if CDT_DB.x           == nil then CDT_DB.x           = 0        end
    if CDT_DB.y           == nil then CDT_DB.y           = 200      end
    if CDT_DB.shown       == nil then CDT_DB.shown       = true     end
    if CDT_DB.showMode    == nil then CDT_DB.showMode    = "always" end
    if CDT_DB.viewMode    == nil then CDT_DB.viewMode    = "detail" end
    if CDT_DB.readyMode   == nil then CDT_DB.readyMode   = "on"     end
    if CDT_DB.barDir      == nil then CDT_DB.barDir      = "H"      end
    if CDT_DB.spells      == nil then CDT_DB.spells      = {}       end
    if CDT_DB.pullcheck   == nil then CDT_DB.pullcheck   = false    end
    if CDT_DB.manaThresh  == nil then CDT_DB.manaThresh  = 50       end
    local n = _getn(CDT_SPELL_DEFS)
    for i = 1, n do
        local d = CDT_SPELL_DEFS[i]
        if CDT_DB.spells[d.key] == nil then
            CDT_DB.spells[d.key] = true
        end
    end
    CDT_SyncModeFlags()
end

-- ── Entry storage ─────────────────────────────────────────────────────────────
CDT_BY_KEY = {}
for i = 1, _getn(CDT_SPELL_DEFS) do
    CDT_BY_KEY[CDT_SPELL_DEFS[i].key] = {}
end

-- ── Entry management ──────────────────────────────────────────────────────────

function CDT_AddEntry(name, spellId, targetName)
    local d = CDT_IDS[spellId]
    if not d then return end
    if CDT_DB.spells[d.key] == false then return end
    local now  = _GetTime()
    local list = CDT_BY_KEY[d.key]
    local n    = _getn(list)
    for i = 1, n do
        local e = list[i]
        if e.name == name then
            e.expireAt = now + d.cd
            e.ready    = false
            e.readyAt  = nil
            if targetName then
                e.target      = targetName
                e.displayName = name .. "(" .. targetName .. ")"
            end
            list.dirty      = true
            CDT_HAS_ACTIVE  = true
            CDT_LAYOUT_DIRTY = true
            return
        end
    end
    local dispName
    if d.key == "soulstone" and targetName then
        dispName = name .. "(" .. targetName .. ")"
    else
        dispName = name
    end
    list[n + 1] = {
        name        = name,
        displayName = dispName,
        target      = targetName,
        key         = d.key,
        cd          = d.cd,
        expireAt    = now + d.cd,
        ready       = false,
        readyAt     = nil,
    }
    list.dirty      = true
    CDT_HAS_ACTIVE  = true
    CDT_LAYOUT_DIRTY = true
end

function CDT_PruneList(list, now, readyOff)
    local w       = 0
    local n       = _getn(list)
    local changed = false
    for i = 1, n do
        local e = list[i]
        if now >= e.expireAt and not e.ready then
            e.ready   = true
            e.readyAt = now
            list.dirty = true
            changed    = true
        end
        local keep = true
        if e.ready and readyOff then
            if e.readyAt and now >= e.readyAt + 10 then
                keep    = false
                changed = true
            end
        end
        if keep then
            w = w + 1
            list[w] = e
        end
    end
    for i = w + 1, n do list[i] = nil end
    if w ~= n then CDT_LAYOUT_DIRTY = true end
    return changed
end

function CDT_SortList(list, now)
    local n = _getn(list)
    for i = 2, n do
        local e = list[i]
        local j = i - 1
        while j >= 1 do
            local prev = list[j]
            local swap = false
            if prev.ready and not e.ready then
                swap = true
            elseif not prev.ready and not e.ready
                   and (prev.expireAt - now) > (e.expireAt - now) then
                swap = true
            end
            if swap then
                list[j+1] = list[j]
                list[j]   = e
                j = j - 1
            else
                break
            end
        end
    end
end

-- ── Shift-click announce ──────────────────────────────────────────────────────
function CDT_AnnounceReady(key, label)
    local list = CDT_BY_KEY[key]
    if not list then return end
    local n     = _getn(list)
    local names = ""
    local count = 0
    for i = 1, n do
        local e = list[i]
        if e.ready then
            if count == 0 then names = e.name
            else names = names .. ", " .. e.name end
            count = count + 1
        end
    end
    if count == 0 then return end
    local msg = "[CDT] " .. label .. " READY: " .. names
    if GetNumRaidMembers() > 0 then
        SendChatMessage(msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(msg, "PARTY")
    else
        SendChatMessage(msg, "SAY")
    end
end

-- ── Global UI state ───────────────────────────────────────────────────────────
CDT_FRAME         = nil
CDT_HDR_FRAME     = nil   -- FIX 2: reference to header frame for vertical resize
CDT_HDR_TXT       = nil   -- FIX 2: reference to header text for hide/show
CDT_HDR_BTNS      = nil   -- FIX 2: reference to header buttons {clrBtn, cfgBtn}
CDT_BODY          = nil
CDT_SUMM_BODY     = nil
CDT_READY         = false
CDT_MOUSEOVER     = false
CDT_MO_PINNED     = false
CDT_MO_PIN_UNTIL  = 0
CDT_BODY_VISIBLE  = false
CDT_LAST_H        = -1
CDT_LAST_W        = -1

CDT_MODE_RAID      = false
CDT_MODE_MO        = false
CDT_MODE_SUMM      = false
CDT_READY_OFF_FLAG = false
CDT_BAR_VERT       = false

CDT_HAS_ACTIVE   = false
CDT_LAYOUT_DIRTY = false

CDT_SEC_STR = {}
for _i = 0, 59 do
    if _i < 10 then CDT_SEC_STR[_i] = ":0" .. _i
    else            CDT_SEC_STR[_i] = ":" .. _i end
end

CDT_CFG_FRAME      = nil
CDT_CONFIRM_FRAME  = nil
CDT_CFG_SHOW_BTNS  = {}
CDT_CFG_VIEW_BTNS  = {}
CDT_CFG_READY_BTNS = {}
CDT_CFG_BAR_BTNS   = {}
CDT_CFG_SPELL_CHKS = {}

CDT_BLOCK_ROWS         = {}
CDT_ROW_CACHE          = {}
CDT_MAX_ROWS_PER_SPELL = 8

CDT_SUMM_COLS  = {}
CDT_SUMM_CACHE = {}

-- ── PullCheck state ───────────────────────────────────────────────────────────
PC_FRAME         = nil
PC_HDR_TXT       = nil
PC_PROMPT_ROWS   = {}
PC_MAX_PROMPTS   = 8

PC_HEALERS       = {}
PC_HEALER_COUNT  = 0

PC_DETECT_COUNTS = {}
PC_PENDING       = {}
PC_PENDING_N     = 0
PC_IN_COMBAT     = false
PC_FIGHTS_SINCE_DETECT = 0
PC_SCANNING      = true
PC_MAX_FIGHTS    = 5

PC_H_IN    = 0
PC_H_TOT   = 0
PC_M_IN    = 0
PC_P_IN    = 0
PC_P_TOT   = 0

PC_MO_FRAME      = nil
PC_MO_ROWS       = {}
PC_MO_MAX        = 20

PC_CLR_FRAME     = nil

-- ── Mode flag sync ────────────────────────────────────────────────────────────
function CDT_SyncModeFlags()
    CDT_MODE_RAID      = CDT_DB.showMode  == "raid"
    CDT_MODE_MO        = CDT_DB.showMode  == "mouseover"
    CDT_MODE_SUMM      = CDT_DB.viewMode  == "summary"
    CDT_READY_OFF_FLAG = CDT_DB.readyMode == "off"
    CDT_BAR_VERT       = CDT_MODE_MO and (CDT_DB.barDir == "V")
end

-- ── Summary layout helpers ────────────────────────────────────────────────────

function CDT_CountEnabled()
    local count = 0
    local defs  = CDT_SPELL_DEFS
    local n     = _getn(defs)
    for i = 1, n do
        if CDT_DB.spells[defs[i].key] ~= false then
            count = count + 1
        end
    end
    return count
end

function CDT_SummWidth(enabledCount)
    if enabledCount < 1 then enabledCount = 1 end
    local cols = _floor((enabledCount + 1) / 2)
    return cols * CDT_SUMM_COL_W + (cols - 1) * CDT_SUMM_GAP + 2 * CDT_SUMM_PAD
end

-- ── FIX 2: Header resize for vertical mode ────────────────────────────────────
-- Reconfigures the header frame dimensions and child visibility based on current mode.
-- Called whenever showMode or barDir changes, and once at build time.
function CDT_ApplyHeaderLayout()
    if not CDT_HDR_FRAME then return end
    if CDT_BAR_VERT then
        -- Vertical strip: header fills the thin (CDT_HDR_H wide) full-height bar
        CDT_HDR_FRAME:SetWidth(CDT_HDR_H)
        CDT_HDR_FRAME:SetHeight(CDT_W)
        -- Hide text and buttons — no room in a 15px wide strip
        if CDT_HDR_TXT  then CDT_HDR_TXT:Hide()  end
        if CDT_HDR_BTNS then
            CDT_HDR_BTNS[1]:Hide()
            CDT_HDR_BTNS[2]:Hide()
        end
    else
        -- Normal horizontal header
        CDT_HDR_FRAME:SetWidth(CDT_W)
        CDT_HDR_FRAME:SetHeight(CDT_HDR_H)
        if CDT_HDR_TXT  then CDT_HDR_TXT:Show()  end
        if CDT_HDR_BTNS then
            CDT_HDR_BTNS[1]:Show()
            CDT_HDR_BTNS[2]:Show()
        end
    end
end

-- ── FIX 3: TOPLEFT-anchored body attachment ───────────────────────────────────
-- Re-anchors CDT_BODY and CDT_SUMM_BODY based on current bar orientation.
-- In normal mode bodies hang below the header.
-- In vertical mode bodies open to the right of the thin strip.
function CDT_RebuildBodyAnchor()
    if not CDT_BODY then return end
    CDT_BODY:ClearAllPoints()
    CDT_SUMM_BODY:ClearAllPoints()
    if CDT_BAR_VERT then
        -- Body opens to the right of the vertical strip
        CDT_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPRIGHT", 1, 0)
        CDT_SUMM_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPRIGHT", 1, 0)
    else
        -- Body hangs below the header (normal)
        CDT_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, -CDT_HDR_H)
        CDT_SUMM_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, -CDT_HDR_H)
    end
end

-- ── Visibility / resize ───────────────────────────────────────────────────────

function CDT_SetBodyVisible(vis)
    if not CDT_READY then return end
    if vis == CDT_BODY_VISIBLE then return end
    CDT_BODY_VISIBLE = vis
    if vis then
        if CDT_MODE_SUMM then
            CDT_BODY:Hide()
            CDT_SUMM_BODY:Show()
        else
            CDT_SUMM_BODY:Hide()
            CDT_BODY:Show()
        end
    else
        CDT_BODY:Hide()
        CDT_SUMM_BODY:Hide()
    end
    CDT_ResizeFrame()
end

function CDT_ApplyCollapsedSize()
    local w, h
    if CDT_BAR_VERT then
        -- FIX 2: vertical strip — narrow width, tall height
        w = CDT_HDR_H
        h = CDT_W
    else
        if CDT_MODE_SUMM then
            w = CDT_SummWidth(CDT_CountEnabled())
        else
            w = CDT_W
        end
        h = CDT_HDR_H
    end
    if CDT_LAST_W ~= w or CDT_LAST_H ~= h then
        CDT_LAST_W = w
        CDT_LAST_H = h
        CDT_FRAME:SetWidth(w)
        CDT_FRAME:SetHeight(h)
    end
end

function CDT_ResizeFrame()
    if not CDT_READY then return end
    if not CDT_BODY_VISIBLE then
        CDT_ApplyCollapsedSize()
        return
    end

    local frameW, frameH

    if CDT_MODE_SUMM then
        local enabled = CDT_CountEnabled()
        frameW = CDT_SummWidth(enabled)
        -- FIX 1: use updated CDT_SUMM_BODY_H (140)
        frameH = CDT_HDR_H + CDT_SUMM_BODY_H
        CDT_SUMM_BODY:SetWidth(frameW)
    else
        local total = 0
        local defs  = CDT_SPELL_DEFS
        local nDefs = _getn(defs)
        for i = 1, nDefs do
            local key = defs[i].key
            if CDT_DB.spells[key] ~= false then
                local cnt = _getn(CDT_BY_KEY[key])
                total = total + (cnt > 0 and cnt or 1)
            end
        end
        local bodyH = total * CDT_ROW_H + 2
        CDT_BODY:SetHeight(bodyH)
        frameW = CDT_W
        frameH = CDT_HDR_H + bodyH
    end

    -- FIX 2: in vertical mode the main frame stays thin; body floats to the right
    if CDT_BAR_VERT then
        frameW = CDT_HDR_H
        frameH = CDT_W
    end

    if frameH ~= CDT_LAST_H or frameW ~= CDT_LAST_W then
        CDT_LAST_H = frameH
        CDT_LAST_W = frameW
        CDT_FRAME:SetWidth(frameW)
        CDT_FRAME:SetHeight(frameH)
    end
end

function CDT_UpdateVisibility()
    if not CDT_READY then return end
    local mode = CDT_DB.showMode
    if mode == "raid" then
        if GetNumRaidMembers() > 0 then CDT_FRAME:Show() else CDT_FRAME:Hide() end
        CDT_SetBodyVisible(true)
    elseif mode == "mouseover" then
        CDT_FRAME:Show()
        CDT_SetBodyVisible(CDT_MOUSEOVER or CDT_MO_PINNED)
    else
        if CDT_DB.shown then CDT_FRAME:Show() else CDT_FRAME:Hide() end
        CDT_SetBodyVisible(true)
    end
    PC_UpdateVisibility()
end

function CDT_MO_PinExpand()
    if CDT_DB.showMode ~= "mouseover" then return end
    CDT_MO_PINNED    = true
    CDT_MO_PIN_UNTIL = _GetTime() + 8
    CDT_SetBodyVisible(true)
end

-- ── Detail redraw ─────────────────────────────────────────────────────────────

function CDT_Redraw()
    if not CDT_READY then return end

    if not CDT_HAS_ACTIVE and not CDT_MODE_MO then return end

    local now      = _GetTime()
    local readyOff = CDT_READY_OFF_FLAG
    local defs     = CDT_SPELL_DEFS
    local nDefs    = _getn(defs)

    local anyActive = false
    for i = 1, nDefs do
        local list    = CDT_BY_KEY[defs[i].key]
        local changed = CDT_PruneList(list, now, readyOff)
        if changed or list.dirty then
            CDT_SortList(list, now)
            list.dirty = false
        end
        if _getn(list) > 0 then anyActive = true end
    end
    CDT_HAS_ACTIVE = anyActive

    if CDT_LAYOUT_DIRTY then
        CDT_ResizeFrame()
        CDT_LAYOUT_DIRTY = false
    end

    if CDT_MODE_SUMM then
        CDT_SummRedraw(now)
        return
    end

    if not CDT_BODY_VISIBLE then return end

    local yOff   = -2
    local secStr = CDT_SEC_STR

    for si = 1, nDefs do
        local def       = defs[si]
        local key       = def.key
        local blockRows = CDT_BLOCK_ROWS[si]
        local cache     = CDT_ROW_CACHE[si]

        if CDT_DB.spells[key] == false then
            for ri = 1, CDT_MAX_ROWS_PER_SPELL do
                local c = cache[ri]
                if c.visible then c.visible = false; blockRows[ri]:Hide() end
            end
        else
            local list    = CDT_BY_KEY[key]
            local count   = _getn(list)
            local numRows = count > 0 and count or 1
            local cr, cg, cb = def.cr, def.cg, def.cb

            for ri = 1, CDT_MAX_ROWS_PER_SPELL do
                local row = blockRows[ri]
                local c   = cache[ri]

                if ri <= numRows then
                    if c.yOff ~= yOff then
                        c.yOff = yOff
                        row:SetPoint("TOPLEFT", CDT_BODY, "TOPLEFT", 0, yOff)
                    end

                    local e = list[ri]

                    if ri == 1 then
                        if not c.lblShown then
                            c.lblShown = true
                            row.icon:Show(); row.lbl:Show()
                        end
                    else
                        if c.lblShown ~= false then
                            c.lblShown = false
                            row.icon:Hide(); row.lbl:Hide()
                        end
                    end

                    local nmTxt
                    if e then
                        nmTxt = e.displayName
                    else
                        nmTxt = "No casts yet"
                    end
                    if c.nm ~= nmTxt then c.nm = nmTxt; row.nm:SetText(nmTxt) end

                    local nnr, nng, nnb
                    if e then
                        nnr, nng, nnb = 1, 0.88, 0.6
                    else
                        nnr = cr * 0.55; nng = cg * 0.55; nnb = cb * 0.55
                        if nnr < 0.25 then nnr = 0.25 end
                        if nng < 0.25 then nng = 0.25 end
                        if nnb < 0.25 then nnb = 0.25 end
                    end
                    if c.nnr ~= nnr or c.nng ~= nng or c.nnb ~= nnb then
                        c.nnr, c.nng, c.nnb = nnr, nng, nnb
                        row.nm:SetTextColor(nnr, nng, nnb)
                    end

                    local tmTxt, tr, tg, tb
                    if not e then
                        tmTxt = "-"
                        tr = cr * 0.45; tg = cg * 0.45; tb = cb * 0.45
                        if tr < 0.2 then tr = 0.2 end
                        if tg < 0.2 then tg = 0.2 end
                        if tb < 0.2 then tb = 0.2 end
                    elseif e.ready then
                        tmTxt = "READY"; tr, tg, tb = 0.2, 1, 0.2
                    else
                        local rem = e.expireAt - now
                        local m   = _floor(rem / 60)
                        local s   = _floor(_mod(rem, 60))
                        tmTxt = m .. secStr[s]
                        local frac = rem / e.cd
                        if frac > 0.5 then      tr, tg, tb = 1, 0.2, 0.2
                        elseif frac > 0.2 then  tr, tg, tb = 1, 0.6, 0.1
                        else                    tr, tg, tb = 0.8, 0.8, 0.2 end
                    end
                    if c.tm ~= tmTxt then c.tm = tmTxt; row.tm:SetText(tmTxt) end
                    if c.tr ~= tr or c.tg ~= tg or c.tb ~= tb then
                        c.tr, c.tg, c.tb = tr, tg, tb
                        row.tm:SetTextColor(tr, tg, tb)
                    end

                    if not c.visible then c.visible = true; row:Show() end
                    yOff = yOff - CDT_ROW_H
                else
                    if c.visible then
                        c.visible = false; c.nm = ""; c.tm = ""
                        c.tr = -1; c.nnr = -1; c.yOff = nil; c.lblShown = nil
                        row:Hide()
                    end
                end
            end
        end
    end
end

-- ── Summary redraw ────────────────────────────────────────────────────────────

function CDT_SummRedraw(now)
    if not CDT_BODY_VISIBLE then return end

    local defs    = CDT_SPELL_DEFS
    local nDefs   = _getn(defs)
    local secStr  = CDT_SEC_STR
    local colW    = CDT_SUMM_COL_W
    local gap     = CDT_SUMM_GAP
    local pad     = CDT_SUMM_PAD
    local iconSz  = CDT_SUMM_ICON_SZ
    local nmH     = CDT_SUMM_NM_H

    local enabled = 0
    for i = 1, nDefs do
        if CDT_DB.spells[defs[i].key] ~= false then enabled = enabled + 1 end
    end
    if enabled < 1 then enabled = 1 end
    local cols = _floor((enabled + 1) / 2)

    local slot = 0

    for si = 1, nDefs do
        local def = defs[si]
        local key = def.key
        local sc  = CDT_SUMM_COLS[si]
        local ca  = CDT_SUMM_CACHE[si]

        if CDT_DB.spells[key] == false then
            if ca.visible then
                ca.visible = false
                sc.iconFrame:Hide()
                sc.nm[1]:Hide(); sc.nm[2]:Hide(); sc.nm[3]:Hide()
            end
        else
            local colIdx  = _mod(slot, cols)
            local rowIdx  = _floor(slot / cols)
            local xOff    = pad + colIdx * (colW + gap)
            local iconY
            local nmBaseY
            if rowIdx == 0 then
                iconY    = -pad
                nmBaseY  = -(pad + iconSz + 1)
            else
                iconY    = -(pad + iconSz + gap + CDT_SUMM_NM_ROWS * nmH + gap)
                nmBaseY  = -(pad + iconSz + gap + CDT_SUMM_NM_ROWS * nmH + gap + iconSz + 1)
            end

            if ca.xOff ~= xOff or ca.rowIdx ~= rowIdx then
                ca.xOff   = xOff
                ca.rowIdx = rowIdx
                sc.iconFrame:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT", xOff, iconY)
                for r = 1, 3 do
                    sc.nm[r]:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT",
                        xOff, nmBaseY - (r - 1) * nmH)
                end
            end

            if not ca.visible then
                ca.visible = true
                sc.iconFrame:Show()
                sc.nm[1]:Show(); sc.nm[2]:Show(); sc.nm[3]:Show()
            end

            local list     = CDT_BY_KEY[key]
            local n        = _getn(list)
            local readyNames = { nil, nil, nil }
            local readyCnt   = 0
            local soonest    = nil
            local soonestName = nil  -- FIX 4: track who has the soonest CD

            for i = 1, n do
                local e = list[i]
                if e.ready then
                    if readyCnt < 3 then
                        readyCnt = readyCnt + 1
                        readyNames[readyCnt] = e.name
                    end
                else
                    if soonest == nil or e.expireAt < soonest then
                        soonest     = e.expireAt
                        soonestName = e.name  -- FIX 4
                    end
                end
            end

            local txt = { "", "", "" }
            local tr, tg, tb = 0.2, 0.2, 0.2

            if readyCnt > 0 then
                for r = 1, 3 do txt[r] = readyNames[r] or "" end
                tr, tg, tb = 1, 0.88, 0.6
            elseif n == 0 then
                txt[1] = ""; txt[2] = "---"; txt[3] = ""
                tr, tg, tb = 0.22, 0.22, 0.3
            else
                -- FIX 4: show caster name in row 1, timer in row 2, row 3 empty
                txt[3] = ""
                if soonest then
                    local rem = soonest - now
                    if rem < 0 then rem = 0 end
                    local m = _floor(rem / 60)
                    local s = _floor(_mod(rem, 60))
                    txt[1] = soonestName or ""   -- FIX 4: caster name above timer
                    txt[2] = m .. secStr[s]
                    local lowestFrac = rem / def.cd
                    if lowestFrac > 0.5 then
                        tr, tg, tb = 1, 0.2, 0.2
                    elseif lowestFrac > 0.2 then
                        tr, tg, tb = 1, 0.6, 0.1
                    else
                        tr, tg, tb = 0.8, 0.8, 0.2
                    end
                else
                    txt[1] = ""; txt[2] = "---"
                    tr, tg, tb = 0.22, 0.22, 0.3
                end
            end

            for r = 1, 3 do
                local fs = sc.nm[r]
                if ca.nm[r] ~= txt[r] then
                    ca.nm[r] = txt[r]
                    fs:SetText(txt[r])
                end
            end
            if ca.tr ~= tr or ca.tg ~= tg or ca.tb ~= tb then
                ca.tr, ca.tg, ca.tb = tr, tg, tb
                sc.nm[1]:SetTextColor(tr, tg, tb)
                sc.nm[2]:SetTextColor(tr, tg, tb)
                sc.nm[3]:SetTextColor(tr, tg, tb)
            end

            slot = slot + 1
        end
    end
end

-- ── PullCheck: polling ────────────────────────────────────────────────────────

function PC_Poll()
    if not CDT_DB.pullcheck then return end
    local n = GetNumRaidMembers()
    if not n or n == 0 then
        PC_H_IN = 0; PC_H_TOT = 0; PC_M_IN = 0; PC_P_IN = 0; PC_P_TOT = 0
        PC_DrawHeader()
        return
    end

    local px, py, pz = UnitPosition("player")

    local thresh   = CDT_DB.manaThresh / 100
    local units    = CDT_RAID_UNITS
    local range    = PC_RANGE * PC_RANGE
    local hIn = 0; local hTot = 0; local mIn = 0; local pIn = 0

    for i = 1, n do
        local unit   = units[i]
        local exists = UnitExists(unit)
        if exists then
            local name = UnitName(unit)
            local inRange = false
            if px then
                local ux, uy, uz = UnitPosition(unit)
                if ux then
                    local dx = ux - px
                    local dy = uy - py
                    local dz = uz - pz
                    if (dx*dx + dy*dy + dz*dz) <= range then
                        inRange = true
                    end
                end
            end

            if inRange then pIn = pIn + 1 end

            if name and PC_HEALERS[name] then
                hTot = hTot + 1
                if inRange then
                    hIn = hIn + 1
                    local mana    = UnitMana(unit)
                    local manaMax = UnitManaMax(unit)
                    if manaMax and manaMax > 0 then
                        if (mana / manaMax) >= thresh then
                            mIn = mIn + 1
                        end
                    end
                end
            end
        end
    end

    PC_P_TOT = n
    PC_H_IN  = hIn
    PC_H_TOT = hTot
    PC_M_IN  = mIn
    PC_P_IN  = pIn

    PC_DrawHeader()
end

-- ── PullCheck: header redraw ──────────────────────────────────────────────────

PC_LAST_HDR = ""

function PC_DrawHeader()
    if not PC_HDR_TXT then return end
    local s = "H:" .. PC_H_IN .. "/" .. PC_H_TOT
           .. "  M:" .. PC_M_IN .. "/" .. PC_H_IN
           .. "  P:" .. PC_P_IN .. "/" .. PC_P_TOT
    if s ~= PC_LAST_HDR then
        PC_LAST_HDR = s
        PC_HDR_TXT:SetText(s)
    end
end

-- ── PullCheck: healer detection ───────────────────────────────────────────────

function PC_OnCombatStart()
    PC_IN_COMBAT = true
    for k in pairs(PC_DETECT_COUNTS) do PC_DETECT_COUNTS[k] = nil end
end

function PC_OnCombatEnd()
    PC_IN_COMBAT = false
    local found = false
    for name, count in pairs(PC_DETECT_COUNTS) do
        if count >= 3 and not PC_HEALERS[name] then
            local alreadyPending = false
            for i = 1, PC_PENDING_N do
                if PC_PENDING[i] == name then
                    alreadyPending = true
                    break
                end
            end
            if not alreadyPending then
                PC_PENDING_N = PC_PENDING_N + 1
                PC_PENDING[PC_PENDING_N] = name
                found = true
            end
        end
    end

    if found then
        PC_FIGHTS_SINCE_DETECT = 0
        PC_DrawPrompts()
    else
        PC_FIGHTS_SINCE_DETECT = PC_FIGHTS_SINCE_DETECT + 1
        if PC_FIGHTS_SINCE_DETECT >= PC_MAX_FIGHTS then
            PC_SCANNING = false
        end
    end

    PC_Poll()
end

function PC_RecordHealCast(name)
    if not PC_SCANNING then return end
    if not PC_IN_COMBAT then return end
    if PC_HEALERS[name] then return end
    local c = PC_DETECT_COUNTS[name]
    if c then
        PC_DETECT_COUNTS[name] = c + 1
    else
        PC_DETECT_COUNTS[name] = 1
    end
end

-- ── PullCheck: prompt rows ────────────────────────────────────────────────────

function PC_DrawPrompts()
    if not PC_FRAME then return end
    for i = 1, PC_MAX_PROMPTS do
        local row = PC_PROMPT_ROWS[i]
        if i <= PC_PENDING_N then
            row.lbl:SetText(PC_PENDING[i])
            row:Show()
        else
            row:Hide()
        end
    end
    PC_ResizeFrame()
end

function PC_ConfirmHealer(name)
    PC_HEALERS[name] = true
    PC_HEALER_COUNT  = PC_HEALER_COUNT + 1
    PC_RemovePending(name)
    PC_Poll()
end

function PC_RejectHealer(name)
    PC_RemovePending(name)
end

function PC_RemovePending(name)
    local found = false
    for i = 1, PC_PENDING_N do
        if PC_PENDING[i] == name then
            found = true
        end
        if found and i < PC_PENDING_N then
            PC_PENDING[i] = PC_PENDING[i + 1]
        end
    end
    if found then
        PC_PENDING[PC_PENDING_N] = nil
        PC_PENDING_N = PC_PENDING_N - 1
        PC_DrawPrompts()
    end
end

function PC_ClearHealers()
    for k in pairs(PC_HEALERS) do PC_HEALERS[k] = nil end
    PC_HEALER_COUNT = 0
    PC_Poll()
end

-- ── PullCheck: frame sizing ───────────────────────────────────────────────────

function PC_ResizeFrame()
    if not PC_FRAME then return end
    local h = PC_HDR_H + PC_PENDING_N * PC_BODY_H
    if h < PC_HDR_H then h = PC_HDR_H end
    PC_FRAME:SetHeight(h)
end

function PC_UpdateVisibility()
    if not PC_FRAME then return end
    if CDT_DB.pullcheck then
        PC_FRAME:Show()
    else
        PC_FRAME:Hide()
    end
end

-- ── PullCheck: mouseover tooltip ─────────────────────────────────────────────

function PC_ShowMO()
    if not PC_MO_FRAME then return end
    if PC_HEALER_COUNT == 0 then PC_MO_FRAME:Hide(); return end

    local px, py, pz = UnitPosition("player")
    local range      = PC_RANGE * PC_RANGE
    local thresh     = CDT_DB.manaThresh / 100
    local units      = CDT_RAID_UNITS
    local n          = GetNumRaidMembers()

    local row = 0
    for k, _ in pairs(PC_HEALERS) do
        local inRange = false
        local manaPct = 0
        if n and n > 0 then
            for i = 1, n do
                local unit = units[i]
                if UnitExists(unit) and UnitName(unit) == k then
                    if px then
                        local ux, uy, uz = UnitPosition(unit)
                        if ux then
                            local dx = ux - px
                            local dy = uy - py
                            local dz = uz - pz
                            if (dx*dx + dy*dy + dz*dz) <= range then
                                inRange = true
                            end
                        end
                    end
                    local mana    = UnitMana(unit)
                    local manaMax = UnitManaMax(unit)
                    if manaMax and manaMax > 0 then
                        manaPct = _floor((mana / manaMax) * 100)
                    end
                    break
                end
            end
        end

        row = row + 1
        if row <= PC_MO_MAX then
            local fs   = PC_MO_ROWS[row]
            local pct  = manaPct .. "%"
            local txt  = k .. "  " .. pct
            fs:SetText(txt)
            if inRange then
                fs:SetTextColor(1, 0.88, 0.6)
                fs:SetAlpha(1)
            else
                fs:SetTextColor(0.5, 0.44, 0.3)
                fs:SetAlpha(0.45)
            end
            fs:Show()
        end
    end
    for i = row + 1, PC_MO_MAX do PC_MO_ROWS[i]:Hide() end

    local tooltipH = 14 + row * 12 + 4
    if tooltipH < 20 then tooltipH = 20 end
    PC_MO_FRAME:SetHeight(tooltipH)
    PC_MO_FRAME:Show()
end

function PC_HideMO()
    if PC_MO_FRAME then PC_MO_FRAME:Hide() end
end

-- ── Build PullCheck UI ────────────────────────────────────────────────────────

function PC_Build()
    PC_FRAME = CreateFrame("Frame", "PCFrame", UIParent)
    PC_FRAME:SetWidth(CDT_W)
    PC_FRAME:SetHeight(PC_HDR_H)
    PC_FRAME:SetPoint("TOPLEFT", CDT_FRAME, "BOTTOMLEFT", 0, -1)
    PC_FRAME:EnableMouse(true)

    local pcBg = PC_FRAME:CreateTexture(nil, "BACKGROUND")
    pcBg:SetAllPoints(PC_FRAME)
    pcBg:SetTexture(0.03, 0.05, 0.03, 0.88)

    local hdr = CreateFrame("Frame", "PCHdr", PC_FRAME)
    hdr:SetWidth(CDT_W); hdr:SetHeight(PC_HDR_H)
    hdr:SetPoint("TOPLEFT", PC_FRAME, "TOPLEFT", 0, 0)
    local hdrBg = hdr:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetAllPoints(hdr); hdrBg:SetTexture(0.08, 0.14, 0.08, 0.95)

    local pullLbl = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pullLbl:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    pullLbl:SetTextColor(0.5, 0.8, 0.5)
    pullLbl:SetText("Pull")

    PC_HDR_TXT = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PC_HDR_TXT:SetPoint("LEFT", hdr, "LEFT", 30, 0)
    PC_HDR_TXT:SetTextColor(0.88, 0.88, 0.7)
    PC_HDR_TXT:SetText("H:0/0  M:0/0  P:0/0")

    local scanBtn = CreateFrame("Button", "PCScanBtn", hdr)
    scanBtn:SetWidth(16); scanBtn:SetHeight(11)
    scanBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -20, -2)
    local scanBg = scanBtn:CreateTexture(nil, "BACKGROUND")
    scanBg:SetAllPoints(scanBtn); scanBg:SetTexture(0.1, 0.3, 0.1, 0.9)
    local scanTxt = scanBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanTxt:SetAllPoints(scanBtn); scanTxt:SetText("[S]"); scanTxt:SetTextColor(0.4, 1, 0.4)
    scanBtn:SetScript("OnClick", function()
        PC_SCANNING            = true
        PC_FIGHTS_SINCE_DETECT = 0
    end)

    local clrBtn = CreateFrame("Button", "PCClrBtn", hdr)
    clrBtn:SetWidth(16); clrBtn:SetHeight(11)
    clrBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -2, -2)
    local clrBg = clrBtn:CreateTexture(nil, "BACKGROUND")
    clrBg:SetAllPoints(clrBtn); clrBg:SetTexture(0.3, 0.1, 0.1, 0.9)
    local clrTxt = clrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clrTxt:SetAllPoints(clrBtn); clrTxt:SetText("[C]"); clrTxt:SetTextColor(1, 0.4, 0.4)
    clrBtn:SetScript("OnClick", function()
        if PC_CLR_FRAME:IsVisible() then PC_CLR_FRAME:Hide()
        else
            PC_CLR_FRAME:ClearAllPoints()
            PC_CLR_FRAME:SetPoint("TOP", PC_FRAME, "BOTTOM", 0, -2)
            PC_CLR_FRAME:Show()
        end
    end)

    PC_FRAME:SetScript("OnEnter", function()
        PC_Poll()
        PC_ShowMO()
    end)
    PC_FRAME:SetScript("OnLeave", function()
        PC_HideMO()
    end)

    for i = 1, PC_MAX_PROMPTS do
        local row = CreateFrame("Frame", "PCPrompt_"..i, PC_FRAME)
        row:SetWidth(CDT_W); row:SetHeight(PC_BODY_H)
        row:SetPoint("TOPLEFT", PC_FRAME, "TOPLEFT", 0, -(PC_HDR_H + (i-1)*PC_BODY_H))

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row); rowBg:SetTexture(0.06, 0.1, 0.06, 0.9)

        local detLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        detLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        detLbl:SetTextColor(0.6, 0.6, 0.6)
        detLbl:SetText("Healer detected:")
        detLbl:SetWidth(80); detLbl:SetJustifyH("LEFT")

        local nmLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nmLbl:SetPoint("LEFT", row, "LEFT", 86, 0)
        nmLbl:SetTextColor(1, 0.88, 0.6)
        nmLbl:SetWidth(80); nmLbl:SetJustifyH("LEFT")
        row.lbl = nmLbl

        local yBtn = CreateFrame("Button", "PCYBtn_"..i, row)
        yBtn:SetWidth(16); yBtn:SetHeight(11)
        yBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -1)
        local yBg = yBtn:CreateTexture(nil, "BACKGROUND")
        yBg:SetAllPoints(yBtn); yBg:SetTexture(0.1, 0.4, 0.1, 0.9)
        local yTxt = yBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        yTxt:SetAllPoints(yBtn); yTxt:SetText("Y"); yTxt:SetTextColor(0.3, 1, 0.3)
        local captureRow = i
        yBtn:SetScript("OnClick", function()
            local name = PC_PENDING[captureRow]
            if name then PC_ConfirmHealer(name) end
        end)

        local nBtn = CreateFrame("Button", "PCNBtn_"..i, row)
        nBtn:SetWidth(16); nBtn:SetHeight(11)
        nBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
        local nBg = nBtn:CreateTexture(nil, "BACKGROUND")
        nBg:SetAllPoints(nBtn); nBg:SetTexture(0.4, 0.1, 0.1, 0.9)
        local nTxt = nBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nTxt:SetAllPoints(nBtn); nTxt:SetText("N"); nTxt:SetTextColor(1, 0.3, 0.3)
        nBtn:SetScript("OnClick", function()
            local name = PC_PENDING[captureRow]
            if name then PC_RejectHealer(name) end
        end)

        row:Hide()
        PC_PROMPT_ROWS[i] = row
    end

    PC_MO_FRAME = CreateFrame("Frame", "PCMOFrame", UIParent)
    PC_MO_FRAME:SetWidth(120)
    PC_MO_FRAME:SetHeight(20)
    PC_MO_FRAME:SetFrameStrata("TOOLTIP")
    PC_MO_FRAME:SetPoint("TOPLEFT", PC_FRAME, "TOPRIGHT", 4, 0)
    PC_MO_FRAME:EnableMouse(false)
    PC_MO_FRAME:Hide()

    local moBg = PC_MO_FRAME:CreateTexture(nil, "BACKGROUND")
    moBg:SetAllPoints(PC_MO_FRAME); moBg:SetTexture(0.04, 0.06, 0.04, 0.95)

    local moTitle = PC_MO_FRAME:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moTitle:SetPoint("TOPLEFT", PC_MO_FRAME, "TOPLEFT", 4, -3)
    moTitle:SetTextColor(0.5, 0.8, 0.5); moTitle:SetText("Healers")

    for i = 1, PC_MO_MAX do
        local fs = PC_MO_FRAME:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", PC_MO_FRAME, "TOPLEFT", 4, -(14 + (i-1)*12))
        fs:SetWidth(112); fs:SetJustifyH("LEFT")
        fs:Hide()
        PC_MO_ROWS[i] = fs
    end

    PC_CLR_FRAME = CreateFrame("Frame", "PCClrFrame", UIParent)
    PC_CLR_FRAME:SetWidth(140); PC_CLR_FRAME:SetHeight(44)
    PC_CLR_FRAME:SetFrameStrata("TOOLTIP"); PC_CLR_FRAME:EnableMouse(true)
    PC_CLR_FRAME:Hide()

    local clrFBg = PC_CLR_FRAME:CreateTexture(nil, "BACKGROUND")
    clrFBg:SetAllPoints(PC_CLR_FRAME); clrFBg:SetTexture(0.08, 0.04, 0.04, 0.97)
    local clrFLbl = PC_CLR_FRAME:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clrFLbl:SetPoint("TOP", PC_CLR_FRAME, "TOP", 0, -8)
    clrFLbl:SetTextColor(1, 0.7, 0.7); clrFLbl:SetText("Clear healer list?")

    local cfYBtn = CreateFrame("Button", "PCClrYBtn", PC_CLR_FRAME)
    cfYBtn:SetWidth(40); cfYBtn:SetHeight(14)
    cfYBtn:SetPoint("BOTTOMLEFT", PC_CLR_FRAME, "BOTTOMLEFT", 8, 6)
    local cfYBg = cfYBtn:CreateTexture(nil, "BACKGROUND")
    cfYBg:SetAllPoints(cfYBtn); cfYBg:SetTexture(0.1, 0.4, 0.1, 0.9)
    local cfYTxt = cfYBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cfYTxt:SetAllPoints(cfYBtn); cfYTxt:SetText("Y"); cfYTxt:SetTextColor(0.3, 1, 0.3)
    cfYBtn:SetScript("OnClick", function()
        PC_ClearHealers()
        PC_CLR_FRAME:Hide()
    end)

    local cfNBtn = CreateFrame("Button", "PCClrNBtn", PC_CLR_FRAME)
    cfNBtn:SetWidth(40); cfNBtn:SetHeight(14)
    cfNBtn:SetPoint("BOTTOMRIGHT", PC_CLR_FRAME, "BOTTOMRIGHT", -8, 6)
    local cfNBg = cfNBtn:CreateTexture(nil, "BACKGROUND")
    cfNBg:SetAllPoints(cfNBtn); cfNBg:SetTexture(0.3, 0.1, 0.1, 0.9)
    local cfNTxt = cfNBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cfNTxt:SetAllPoints(cfNBtn); cfNTxt:SetText("N"); cfNTxt:SetTextColor(1, 0.3, 0.3)
    cfNBtn:SetScript("OnClick", function() PC_CLR_FRAME:Hide() end)

    PC_UpdateVisibility()
    PC_DrawHeader()
end

-- ── Build main UI ─────────────────────────────────────────────────────────────

function CDT_Build()
    CDT_FRAME = CreateFrame("Frame", "CDTMainFrame", UIParent)
    CDT_FRAME:SetWidth(CDT_W)
    CDT_FRAME:SetHeight(CDT_HDR_H)
    CDT_FRAME:SetMovable(true)
    CDT_FRAME:EnableMouse(true)
    CDT_FRAME:RegisterForDrag("LeftButton")
    CDT_FRAME:SetClampedToScreen(true)

    -- FIX 3: Anchor TOPLEFT instead of CENTER so body expansion only goes downward.
    -- x/y in CDT_DB are stored as offsets from screen center (same as before),
    -- but we convert to a TOPLEFT position at load time.
    do
        local uiScale = UIParent:GetScale()
        local screenW = GetScreenWidth()  * uiScale
        local screenH = GetScreenHeight() * uiScale
        local tlX = screenW / 2 + CDT_DB.x
        local tlY = screenH / 2 + CDT_DB.y
        CDT_FRAME:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tlX, tlY)
    end

    CDT_FRAME:SetScript("OnDragStart", function() CDT_FRAME:StartMoving() end)
    CDT_FRAME:SetScript("OnDragStop", function()
        CDT_FRAME:StopMovingOrSizing()
        -- FIX 3: recompute center-relative offsets from the new TOPLEFT position
        local uiScale = UIParent:GetScale()
        local screenW = GetScreenWidth()  * uiScale
        local screenH = GetScreenHeight() * uiScale
        local scale   = CDT_FRAME:GetEffectiveScale()
        CDT_DB.x = CDT_FRAME:GetLeft()  * scale - screenW / 2
        CDT_DB.y = CDT_FRAME:GetTop()   * scale - screenH / 2
    end)
    CDT_FRAME:SetScript("OnEnter", function()
        if CDT_DB.showMode == "mouseover" then
            CDT_MOUSEOVER = true
            CDT_SetBodyVisible(true)
        end
    end)
    CDT_FRAME:SetScript("OnLeave", function()
        if CDT_DB.showMode == "mouseover" then
            CDT_MOUSEOVER = false
            if not CDT_MO_PINNED then CDT_SetBodyVisible(false) end
        end
    end)

    local mainBg = CDT_FRAME:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints(CDT_FRAME)
    mainBg:SetTexture(0, 0, 0, 0.8)

    -- ── Header ──
    -- FIX 2: store reference in CDT_HDR_FRAME so we can resize it for vertical mode
    local hdr = CreateFrame("Frame", "CDTHeader", CDT_FRAME)
    hdr:SetWidth(CDT_W); hdr:SetHeight(CDT_HDR_H)
    hdr:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, 0)
    CDT_HDR_FRAME = hdr

    local hBg = hdr:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints(hdr); hBg:SetTexture(0.1, 0.1, 0.3, 0.95)

    local hTxt = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTxt:SetPoint("LEFT", hdr, "LEFT", 5, 0)
    hTxt:SetText("|cffaabbff[CDT]|r CoolDown Tracker")
    CDT_HDR_TXT = hTxt

    local clrBtn = CreateFrame("Button", "CDTClrBtn", hdr)
    clrBtn:SetWidth(26); clrBtn:SetHeight(11)
    clrBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -30, -2)
    local clrBg = clrBtn:CreateTexture(nil, "BACKGROUND")
    clrBg:SetAllPoints(clrBtn); clrBg:SetTexture(0.4, 0.12, 0.12, 0.9)
    local clrTxt = clrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clrTxt:SetAllPoints(clrBtn); clrTxt:SetText("CLR"); clrTxt:SetTextColor(1, 0.5, 0.5)
    clrBtn:SetScript("OnClick", function()
        if CDT_CONFIRM_FRAME:IsVisible() then CDT_CONFIRM_FRAME:Hide()
        else CDT_ShowConfirm() end
    end)

    local cfgBtn = CreateFrame("Button", "CDTCfgBtn", hdr)
    cfgBtn:SetWidth(26); cfgBtn:SetHeight(11)
    cfgBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -2, -2)
    local cfgBg = cfgBtn:CreateTexture(nil, "BACKGROUND")
    cfgBg:SetAllPoints(cfgBtn); cfgBg:SetTexture(0.12, 0.12, 0.4, 0.9)
    local cfgTxt = cfgBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cfgTxt:SetAllPoints(cfgBtn); cfgTxt:SetText("CFG"); cfgTxt:SetTextColor(0.6, 0.6, 1)
    cfgBtn:SetScript("OnClick", function()
        if CDT_CFG_FRAME:IsVisible() then CDT_CFG_FRAME:Hide()
        else CDT_CFG_UpdateButtons(); CDT_CFG_FRAME:Show() end
    end)

    -- FIX 2: store button references for hide/show in vertical mode
    CDT_HDR_BTNS = { clrBtn, cfgBtn }

    -- ── Detail body ──
    CDT_BODY = CreateFrame("Frame", "CDTBody", CDT_FRAME)
    CDT_BODY:SetWidth(CDT_W)
    CDT_BODY:SetHeight(10)
    -- FIX 3: anchor set via CDT_RebuildBodyAnchor() after this block
    local bodyBg = CDT_BODY:CreateTexture(nil, "BACKGROUND")
    bodyBg:SetAllPoints(CDT_BODY)
    bodyBg:SetTexture(0.02, 0.02, 0.04, 0.85)

    -- ── Summary body ──
    CDT_SUMM_BODY = CreateFrame("Frame", "CDTSummBody", CDT_FRAME)
    CDT_SUMM_BODY:SetWidth(CDT_W)
    -- FIX 1: use the corrected CDT_SUMM_BODY_H (140) so bg covers second row
    CDT_SUMM_BODY:SetHeight(CDT_SUMM_BODY_H)
    CDT_SUMM_BODY:Hide()
    local summBg = CDT_SUMM_BODY:CreateTexture(nil, "BACKGROUND")
    summBg:SetAllPoints(CDT_SUMM_BODY)
    summBg:SetTexture(0.02, 0.02, 0.04, 0.85)

    -- FIX 3 + FIX 2: set body anchors based on current mode
    CDT_RebuildBodyAnchor()

    -- ── Preallocate detail rows ──
    local defs      = CDT_SPELL_DEFS
    local nDefs     = _getn(defs)
    local ROW_SHADE = 0.14

    for si = 1, nDefs do
        local def = defs[si]
        CDT_BLOCK_ROWS[si] = {}
        CDT_ROW_CACHE[si]  = {}

        for ri = 1, CDT_MAX_ROWS_PER_SPELL do
            local row = CreateFrame("Frame", "CDTRow_"..si.."_"..ri, CDT_BODY)
            row:SetWidth(CDT_W); row:SetHeight(CDT_ROW_H)
            row:SetPoint("TOPLEFT", CDT_BODY, "TOPLEFT", 0, 0)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            bg:SetTexture(def.cr * ROW_SHADE, def.cg * ROW_SHADE, def.cb * ROW_SHADE, 0.95)

            local stripe = row:CreateTexture(nil, "BORDER")
            stripe:SetWidth(2); stripe:SetHeight(CDT_ROW_H)
            stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            stripe:SetTexture(def.cr * 0.8, def.cg * 0.8, def.cb * 0.8, 0.9)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(CDT_ICON_SZ); icon:SetHeight(CDT_ICON_SZ)
            icon:SetPoint("LEFT", row, "LEFT", CDT_ICON_X + 2, 0)
            icon:SetTexture("Interface\\Icons\\" .. def.icon)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.icon = icon

            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", row, "LEFT", CDT_LBL_X + 2, 0)
            lbl:SetWidth(CDT_LBL_W); lbl:SetJustifyH("LEFT")
            lbl:SetText(def.label)
            lbl:SetTextColor(0.55 + def.cr*0.45, 0.55 + def.cg*0.45, 0.55 + def.cb*0.45)
            row.lbl = lbl

            if ri == 1 then
                local spellKey   = def.key
                local spellLabel = def.label
                local cz = CreateFrame("Button", "CDTClickZone_"..si, row)
                cz:SetWidth(CDT_LBL_X + 2 + CDT_LBL_W); cz:SetHeight(CDT_ROW_H)
                cz:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                cz:SetFrameLevel(row:GetFrameLevel() + 1)
                cz:RegisterForClicks("LeftButtonUp")
                cz:SetScript("OnClick", function()
                    if IsShiftKeyDown() then CDT_AnnounceReady(spellKey, spellLabel) end
                end)
            end

            local nm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nm:SetPoint("LEFT", row, "LEFT", CDT_NM_X, 0)
            nm:SetWidth(CDT_NM_W); nm:SetJustifyH("LEFT")
            row.nm = nm

            local tm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tm:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            tm:SetWidth(CDT_TM_W); tm:SetJustifyH("RIGHT")
            row.tm = tm

            row:Hide()
            CDT_BLOCK_ROWS[si][ri] = row
            CDT_ROW_CACHE[si][ri]  = {
                nm="", tm="", tr=-1, tg=-1, tb=-1,
                nnr=-1, nng=-1, nnb=-1,
                visible=false, lblShown=nil, yOff=nil,
            }
        end
    end

    -- ── Preallocate summary columns ──
    local colW   = CDT_SUMM_COL_W
    local iconSz = CDT_SUMM_ICON_SZ
    local nmH    = CDT_SUMM_NM_H

    for si = 1, nDefs do
        local def = defs[si]

        local iconFrame = CreateFrame("Frame", "CDTSummIcon_"..si, CDT_SUMM_BODY)
        iconFrame:SetWidth(iconSz); iconFrame:SetHeight(iconSz)
        iconFrame:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT", 0, 0)

        local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
        iconBg:SetAllPoints(iconFrame)
        iconBg:SetTexture(def.cr * 0.3, def.cg * 0.3, def.cb * 0.3, 0.95)

        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(iconFrame)
        iconTex:SetTexture("Interface\\Icons\\" .. def.icon)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local iconStripe = iconFrame:CreateTexture(nil, "OVERLAY")
        iconStripe:SetHeight(2); iconStripe:SetWidth(iconSz)
        iconStripe:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
        iconStripe:SetTexture(def.cr, def.cg, def.cb, 0.9)

        iconFrame:Hide()

        local nmFs = {}
        for r = 1, 3 do
            local fs = CDT_SUMM_BODY:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetWidth(colW)
            fs:SetHeight(nmH)
            fs:SetJustifyH("CENTER")
            fs:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT", 0, 0)
            fs:Hide()
            nmFs[r] = fs
        end

        CDT_SUMM_COLS[si]  = { iconFrame=iconFrame, nm=nmFs }
        CDT_SUMM_CACHE[si] = {
            nm     = { "", "", "" },
            tr=-1, tg=-1, tb=-1,
            visible=false,
            xOff   = nil,
            rowIdx = nil,
        }
    end

    -- ── Ticker ──
    local tick    = CreateFrame("Frame", "CDTTick", UIParent)
    local acc     = 0
    local pcAcc   = 0
    tick:SetScript("OnUpdate", function()
        acc   = acc   + arg1
        pcAcc = pcAcc + arg1

        if acc >= 2 then
            acc = 0
            if CDT_MODE_RAID then
                if GetNumRaidMembers() > 0 then CDT_FRAME:Show() else CDT_FRAME:Hide() end
            end
            if CDT_MO_PINNED and _GetTime() >= CDT_MO_PIN_UNTIL then
                CDT_MO_PINNED = false
                if CDT_MODE_MO and not CDT_MOUSEOVER then CDT_SetBodyVisible(false) end
            end
            CDT_Redraw()
        end

        if pcAcc >= 5 then
            pcAcc = 0
            if CDT_DB.pullcheck and not PC_IN_COMBAT then
                if GetNumRaidMembers() > 0 then
                    PC_Poll()
                end
            end
        end
    end)

    CDT_READY = true
    CDT_BuildConfirm()
    CDT_BuildConfig()
    PC_Build()
    -- FIX 2: apply header layout for current mode (handles vertical strip correctly)
    CDT_ApplyHeaderLayout()
    CDT_UpdateVisibility()
    CDT_Redraw()
end

-- ── Confirm clear popup ───────────────────────────────────────────────────────

function CDT_BuildConfirm()
    local f = CreateFrame("Frame", "CDTConfirmFrame", UIParent)
    f:SetWidth(160); f:SetHeight(60)
    f:SetFrameStrata("TOOLTIP"); f:SetMovable(false); f:EnableMouse(true); f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f); bg:SetTexture(0.08, 0.04, 0.04, 0.97)
    local border = f:CreateTexture(nil, "BORDER")
    border:SetAllPoints(f); border:SetTexture(0.5, 0.2, 0.2, 0.6)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOP", f, "TOP", 0, -10)
    lbl:SetTextColor(1, 0.7, 0.7); lbl:SetText("Clear all cooldown data?")

    local yesBtn = CreateFrame("Button", "CDTConfirmYes", f)
    yesBtn:SetWidth(60); yesBtn:SetHeight(16)
    yesBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    local yesBg = yesBtn:CreateTexture(nil, "BACKGROUND")
    yesBg:SetAllPoints(yesBtn); yesBg:SetTexture(0.4, 0.1, 0.1, 0.9)
    local yesTxt = yesBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yesTxt:SetAllPoints(yesBtn); yesTxt:SetText("Yes, clear"); yesTxt:SetTextColor(1, 0.5, 0.5)
    yesBtn:SetScript("OnClick", function()
        local defs = CDT_SPELL_DEFS
        for i = 1, _getn(defs) do
            local list = CDT_BY_KEY[defs[i].key]
            local n    = _getn(list)
            for j = 1, n do list[j] = nil end
            list.dirty = false
        end
        CDT_HAS_ACTIVE   = false
        CDT_LAYOUT_DIRTY = true
        CDT_Redraw(); f:Hide()
    end)

    local noBtn = CreateFrame("Button", "CDTConfirmNo", f)
    noBtn:SetWidth(50); noBtn:SetHeight(16)
    noBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    local noBg = noBtn:CreateTexture(nil, "BACKGROUND")
    noBg:SetAllPoints(noBtn); noBg:SetTexture(0.15, 0.15, 0.15, 0.9)
    local noTxt = noBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noTxt:SetAllPoints(noBtn); noTxt:SetText("Cancel"); noTxt:SetTextColor(0.7, 0.7, 0.7)
    noBtn:SetScript("OnClick", function() f:Hide() end)

    CDT_CONFIRM_FRAME = f
end

function CDT_ShowConfirm()
    CDT_CONFIRM_FRAME:ClearAllPoints()
    CDT_CONFIRM_FRAME:SetPoint("TOP", CDT_FRAME, "BOTTOM", 0, -4)
    CDT_CONFIRM_FRAME:Show()
end

-- ── Config popup ──────────────────────────────────────────────────────────────

function CDT_BuildConfig()
    local spellCount = _getn(CDT_SPELL_DEFS)
    local cfgH = 230 + spellCount * 14 + 28 + 60
    local f = CreateFrame("Frame", "CDTConfigFrame", UIParent)
    f:SetWidth(210); f:SetHeight(cfgH)
    f:SetPoint("TOPLEFT", CDT_FRAME, "TOPRIGHT", 4, 0)
    f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f); bg:SetTexture(0.05, 0.05, 0.15, 0.97)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -5)
    title:SetTextColor(0.7, 0.7, 1); title:SetText("CDT Config")

    local closeBtn = CreateFrame("Button", "CDTConfigClose", f)
    closeBtn:SetWidth(16); closeBtn:SetHeight(13)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeTxt:SetAllPoints(closeBtn); closeTxt:SetTextColor(0.9, 0.3, 0.3); closeTxt:SetText("[X]")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local function MakeDivider(yOff)
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetHeight(1); d:SetWidth(200)
        d:SetPoint("TOPLEFT", f, "TOPLEFT", 5, yOff)
        d:SetTexture(0.3, 0.3, 0.55, 0.8)
    end

    -- ── Show mode ──
    MakeDivider(-16)
    local showLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -22)
    showLbl:SetTextColor(0.8, 0.8, 1); showLbl:SetText("Show:")

    local showOpts = CDT_SHOW_OPTS
    for idx = 1, _getn(showOpts) do
        local mode = showOpts[idx]
        local btn = CreateFrame("Button", "CDTShowBtn"..idx, f)
        btn:SetWidth(60); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (idx-1)*67, -35)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(btn); bbg:SetTexture(0.15, 0.15, 0.3, 0.9)
        btn.bg = bbg
        local btxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btxt:SetAllPoints(btn); btxt:SetText(mode); btn.txt = btxt
        local m = mode
        btn:SetScript("OnClick", function()
            CDT_DB.showMode = m
            CDT_SyncModeFlags()
            CDT_CFG_UpdateButtons()
            -- FIX 2: update header layout and body anchors when mode changes
            CDT_ApplyHeaderLayout()
            CDT_RebuildBodyAnchor()
            CDT_LAST_H = -1; CDT_LAST_W = -1
            CDT_UpdateVisibility()
        end)
        CDT_CFG_SHOW_BTNS[idx] = btn
    end

    local descAlways = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descAlways:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -53)
    descAlways:SetTextColor(0.45, 0.45, 0.55); descAlways:SetWidth(198)
    descAlways:SetJustifyH("LEFT"); descAlways:SetText("always: always visible")

    local descRaid = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descRaid:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -63)
    descRaid:SetTextColor(0.45, 0.45, 0.55); descRaid:SetWidth(198)
    descRaid:SetJustifyH("LEFT"); descRaid:SetText("raid: show only in raid group")

    local descMO = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descMO:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -73)
    descMO:SetTextColor(0.45, 0.45, 0.55); descMO:SetWidth(198)
    descMO:SetJustifyH("LEFT"); descMO:SetText("mouseover: collapse to titlebar")

    -- ── View mode ──
    MakeDivider(-85)
    local viewLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -90)
    viewLbl:SetTextColor(0.8, 0.8, 1); viewLbl:SetText("View:")

    local viewOpts = CDT_VIEW_OPTS
    for idx = 1, _getn(viewOpts) do
        local mode = viewOpts[idx]
        local btn = CreateFrame("Button", "CDTViewBtn"..idx, f)
        btn:SetWidth(56); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (idx-1)*62, -103)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(btn); bbg:SetTexture(0.15, 0.15, 0.3, 0.9)
        btn.bg = bbg
        local btxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btxt:SetAllPoints(btn); btxt:SetText(mode); btn.txt = btxt
        local m = mode
        btn:SetScript("OnClick", function()
            CDT_DB.viewMode = m
            CDT_SyncModeFlags()
            CDT_CFG_UpdateButtons()
            CDT_LAST_H = -1; CDT_LAST_W = -1
            if CDT_BODY_VISIBLE then
                if CDT_MODE_SUMM then
                    CDT_BODY:Hide(); CDT_SUMM_BODY:Show()
                else
                    CDT_SUMM_BODY:Hide(); CDT_BODY:Show()
                end
            end
            CDT_Redraw()
        end)
        CDT_CFG_VIEW_BTNS[idx] = btn
    end

    -- ── Bar orientation ──
    MakeDivider(-115)
    local barLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -120)
    barLbl:SetTextColor(0.8, 0.8, 1); barLbl:SetText("Collapsed bar (mouseover):")

    local barOpts = CDT_BAR_OPTS
    for idx = 1, _getn(barOpts) do
        local dir = barOpts[idx]
        local btn = CreateFrame("Button", "CDTBarBtn"..idx, f)
        btn:SetWidth(30); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (idx-1)*34, -133)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(btn); bbg:SetTexture(0.15, 0.15, 0.3, 0.9)
        btn.bg = bbg
        local btxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btxt:SetAllPoints(btn); btxt:SetText(dir); btn.txt = btxt
        local d = dir
        btn:SetScript("OnClick", function()
            if CDT_DB.showMode ~= "mouseover" then return end
            CDT_DB.barDir = d
            CDT_SyncModeFlags()
            CDT_CFG_UpdateButtons()
            -- FIX 2: reapply header layout and body anchors when bar dir changes
            CDT_ApplyHeaderLayout()
            CDT_RebuildBodyAnchor()
            CDT_LAST_H = -1; CDT_LAST_W = -1
            CDT_ResizeFrame()
        end)
        CDT_CFG_BAR_BTNS[idx] = btn
    end

    local descBar = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -147)
    descBar:SetTextColor(0.45, 0.45, 0.55); descBar:SetWidth(198)
    descBar:SetJustifyH("LEFT"); descBar:SetText("H: horizontal strip  V: vertical strip")

    -- ── Ready mode ──
    MakeDivider(-159)
    local readyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readyLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -164)
    readyLbl:SetTextColor(0.8, 0.8, 1); readyLbl:SetText("Ready:")

    local readyOpts = CDT_READY_OPTS
    for idx = 1, _getn(readyOpts) do
        local mode = readyOpts[idx]
        local btn = CreateFrame("Button", "CDTReadyBtn"..idx, f)
        btn:SetWidth(56); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (idx-1)*62, -177)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(btn); bbg:SetTexture(0.15, 0.15, 0.3, 0.9)
        btn.bg = bbg
        local btxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btxt:SetAllPoints(btn); btxt:SetText(mode); btn.txt = btxt
        local m = mode
        btn:SetScript("OnClick", function()
            CDT_DB.readyMode = m
            CDT_SyncModeFlags()
            CDT_CFG_UpdateButtons()
        end)
        CDT_CFG_READY_BTNS[idx] = btn
    end

    local descOn = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descOn:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -191)
    descOn:SetTextColor(0.45, 0.45, 0.55); descOn:SetWidth(198)
    descOn:SetJustifyH("LEFT"); descOn:SetText("on: keep row with READY text")

    local descOff = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descOff:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -201)
    descOff:SetTextColor(0.45, 0.45, 0.55); descOff:SetWidth(198)
    descOff:SetJustifyH("LEFT"); descOff:SetText("off: remove row 10s after READY")

    -- ── Spell filter ──
    MakeDivider(-213)
    local spellsLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellsLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -218)
    spellsLbl:SetTextColor(0.8, 0.8, 1); spellsLbl:SetText("Track spells:")

    CDT_CFG_SPELL_CHKS = {}
    for i = 1, spellCount do
        local def  = CDT_SPELL_DEFS[i]
        local yOff = -218 - 4 - i * 14

        local box = CreateFrame("Frame", "CDTSpellBox"..i, f)
        box:SetWidth(10); box:SetHeight(10)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 8, yOff + 2)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(box); boxBg:SetTexture(0.15, 0.15, 0.3, 0.9)
        box.bg = boxBg
        local boxTick = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        boxTick:SetAllPoints(box); boxTick:SetText("x"); box.tick = boxTick

        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 22, yOff)
        lbl:SetTextColor(def.cr, def.cg, def.cb); lbl:SetText(def.label)

        local btn = CreateFrame("Button", "CDTSpellBtn"..i, f)
        btn:SetWidth(190); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 5, yOff)
        local k = def.key
        btn:SetScript("OnClick", function()
            CDT_DB.spells[k] = (CDT_DB.spells[k] == false) and true or false
            CDT_CFG_UpdateButtons()
            if CDT_MODE_SUMM and CDT_BODY_VISIBLE then
                CDT_LAST_W = -1
                CDT_ResizeFrame()
                CDT_Redraw()
            end
        end)

        CDT_CFG_SPELL_CHKS[i] = { box=box, lbl=lbl, key=def.key }
    end

    -- Star disclaimer
    local starY = -218 - 4 - spellCount * 14 - 6
    local starDisc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    starDisc:SetPoint("TOPLEFT", f, "TOPLEFT", 8, starY)
    starDisc:SetTextColor(0.55, 0.52, 0.28)
    starDisc:SetWidth(194); starDisc:SetJustifyH("LEFT")
    starDisc:SetText("* cooldown may be reduced by talents or set bonuses — timer is approximate")

    -- ── PullCheck section ──
    local pcY = starY - 28
    MakeDivider(pcY)

    local pcLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pcLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, pcY - 6)
    pcLbl:SetTextColor(0.5, 0.8, 0.5); pcLbl:SetText("Pull Check:")

    local pcToggle = CreateFrame("Button", "CDTPCToggle", f)
    pcToggle:SetWidth(46); pcToggle:SetHeight(14)
    pcToggle:SetPoint("TOPLEFT", f, "TOPLEFT", 3, pcY - 18)
    local pcTogBg = pcToggle:CreateTexture(nil, "BACKGROUND")
    pcTogBg:SetAllPoints(pcToggle); pcTogBg:SetTexture(0.15, 0.15, 0.3, 0.9)
    pcToggle.bg = pcTogBg
    local pcTogTxt = pcToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pcTogTxt:SetAllPoints(pcToggle); pcToggle.txt = pcTogTxt
    pcToggle:SetScript("OnClick", function()
        CDT_DB.pullcheck = not CDT_DB.pullcheck
        CDT_CFG_UpdateButtons()
        PC_UpdateVisibility()
    end)
    CDT_CFG_PC_TOGGLE = pcToggle

    local manaLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    manaLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, pcY - 34)
    manaLbl:SetTextColor(0.8, 0.8, 1); manaLbl:SetText("Mana threshold:")

    CDT_CFG_MANA_VAL = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    CDT_CFG_MANA_VAL:SetPoint("TOPLEFT", f, "TOPLEFT", 110, pcY - 34)
    CDT_CFG_MANA_VAL:SetTextColor(1, 0.88, 0.6)
    CDT_CFG_MANA_VAL:SetText(CDT_DB.manaThresh .. "%")

    local slider = CreateFrame("Slider", "CDTManaSlider", f, "OptionsSliderTemplate")
    slider:SetWidth(180); slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", f, "TOPLEFT", 8, pcY - 46)
    slider:SetMinMaxValues(10, 100)
    slider:SetValueStep(10)
    slider:SetValue(CDT_DB.manaThresh)
    CDTManaSliderLow:SetText("")
    CDTManaSliderHigh:SetText("")
    CDTManaSliderText:SetText("")
    slider:SetScript("OnValueChanged", function()
        local v = _floor(slider:GetValue() / 10 + 0.5) * 10
        if v < 10  then v = 10  end
        if v > 100 then v = 100 end
        CDT_DB.manaThresh = v
        CDT_CFG_MANA_VAL:SetText(v .. "%")
    end)
    CDT_CFG_MANA_SLIDER = slider

    CDT_CFG_FRAME = f
    CDT_CFG_UpdateButtons()
end

function CDT_CFG_UpdateButtons()
    local showOpts = CDT_SHOW_OPTS
    local curShow  = CDT_DB.showMode
    for idx = 1, _getn(showOpts) do
        local btn = CDT_CFG_SHOW_BTNS[idx]
        if btn then
            if curShow == showOpts[idx] then
                btn.bg:SetTexture(0.15, 0.45, 0.15, 0.95)
                btn.txt:SetTextColor(0.3, 1, 0.3)
            else
                btn.bg:SetTexture(0.15, 0.15, 0.3, 0.9)
                btn.txt:SetTextColor(0.65, 0.65, 0.65)
            end
        end
    end

    local viewOpts = CDT_VIEW_OPTS
    local curView  = CDT_DB.viewMode
    for idx = 1, _getn(viewOpts) do
        local btn = CDT_CFG_VIEW_BTNS[idx]
        if btn then
            if curView == viewOpts[idx] then
                btn.bg:SetTexture(0.15, 0.45, 0.15, 0.95)
                btn.txt:SetTextColor(0.3, 1, 0.3)
            else
                btn.bg:SetTexture(0.15, 0.15, 0.3, 0.9)
                btn.txt:SetTextColor(0.65, 0.65, 0.65)
            end
        end
    end

    local barOpts = CDT_BAR_OPTS
    local curBar  = CDT_DB.barDir
    local isMO    = (curShow == "mouseover")
    for idx = 1, _getn(barOpts) do
        local btn = CDT_CFG_BAR_BTNS[idx]
        if btn then
            if isMO and curBar == barOpts[idx] then
                btn.bg:SetTexture(0.15, 0.45, 0.15, 0.95)
                btn.txt:SetTextColor(0.3, 1, 0.3)
            elseif isMO then
                btn.bg:SetTexture(0.15, 0.15, 0.3, 0.9)
                btn.txt:SetTextColor(0.65, 0.65, 0.65)
            else
                btn.bg:SetTexture(0.08, 0.08, 0.08, 0.5)
                btn.txt:SetTextColor(0.25, 0.25, 0.25)
            end
        end
    end

    local readyOpts = CDT_READY_OPTS
    local curReady  = CDT_DB.readyMode
    for idx = 1, _getn(readyOpts) do
        local btn = CDT_CFG_READY_BTNS[idx]
        if btn then
            if curReady == readyOpts[idx] then
                btn.bg:SetTexture(0.15, 0.45, 0.15, 0.95)
                btn.txt:SetTextColor(0.3, 1, 0.3)
            else
                btn.bg:SetTexture(0.15, 0.15, 0.3, 0.9)
                btn.txt:SetTextColor(0.65, 0.65, 0.65)
            end
        end
    end

    local chks = CDT_CFG_SPELL_CHKS
    for i = 1, _getn(chks) do
        local chk = chks[i]
        if chk then
            if CDT_DB.spells[chk.key] ~= false then
                chk.box.bg:SetTexture(0.15, 0.45, 0.15, 0.95)
                chk.box.tick:SetTextColor(0.3, 1, 0.3)
            else
                chk.box.bg:SetTexture(0.2, 0.1, 0.1, 0.9)
                chk.box.tick:SetTextColor(0.5, 0.2, 0.2)
            end
        end
    end

    if CDT_CFG_PC_TOGGLE then
        if CDT_DB.pullcheck then
            CDT_CFG_PC_TOGGLE.bg:SetTexture(0.15, 0.45, 0.15, 0.95)
            CDT_CFG_PC_TOGGLE.txt:SetText("on")
            CDT_CFG_PC_TOGGLE.txt:SetTextColor(0.3, 1, 0.3)
        else
            CDT_CFG_PC_TOGGLE.bg:SetTexture(0.2, 0.1, 0.1, 0.9)
            CDT_CFG_PC_TOGGLE.txt:SetText("off")
            CDT_CFG_PC_TOGGLE.txt:SetTextColor(0.5, 0.2, 0.2)
        end
    end

    if CDT_CFG_MANA_VAL then
        CDT_CFG_MANA_VAL:SetText(CDT_DB.manaThresh .. "%")
    end
    if CDT_CFG_MANA_SLIDER then
        CDT_CFG_MANA_SLIDER:SetValue(CDT_DB.manaThresh)
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────

local ev = CreateFrame("Frame", "CDTEventFrame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:RegisterEvent("UNIT_CASTEVENT")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")

ev:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        CDT_InitDB()
        CDT_BuildGUIDIndex()
        if not CDT_READY then CDT_Build() end
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CoolDownTracker]|r ready - /cdt for help")
        CDT_UpdateVisibility()
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        CDT_BuildGUIDIndex()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        PC_OnCombatStart()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        PC_OnCombatEnd()
        return
    end

    -- UNIT_CASTEVENT
    if arg3 == "CAST" then
        local spellId = tonumber(arg4)

        if CDT_IDS[spellId] then
            local name = CDT_GUID_TO_NAME[arg1]
            if name then
                local targetName = nil
                if arg2 and arg2 ~= "" then
                    targetName = CDT_GUID_TO_NAME[arg2]
                    if not targetName then
                        local _, pguid = UnitExists("player")
                        if pguid == arg2 then targetName = UnitName("player") end
                    end
                end
                CDT_AddEntry(name, spellId, targetName)
                CDT_MO_PinExpand()
                CDT_Redraw()
            end
        end

        if PC_HEAL_IDS[spellId] and PC_SCANNING and PC_IN_COMBAT then
            local name = CDT_GUID_TO_NAME[arg1]
            if name then PC_RecordHealCast(name) end
        end
    end
end)

-- ── Slash commands ────────────────────────────────────────────────────────────

SLASH_CDTRACKER1 = "/cdt"
SLASH_CDTRACKER2 = "/cooldowntracker"
SlashCmdList["CDTRACKER"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "toggle" or msg == "" then
        if CDT_FRAME:IsVisible() then
            CDT_FRAME:Hide(); CDT_DB.shown = false
            DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r Hidden. /cdt to show.")
        else
            CDT_FRAME:Show(); CDT_DB.shown = true
            DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r Shown.")
        end
    elseif msg == "hide" then
        CDT_FRAME:Hide(); CDT_DB.shown = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r Hidden.")
    elseif msg == "show" then
        CDT_FRAME:Show(); CDT_DB.shown = true
    elseif msg == "clear" then
        local defs = CDT_SPELL_DEFS
        for i = 1, _getn(defs) do
            local list = CDT_BY_KEY[defs[i].key]
            local n    = _getn(list)
            for j = 1, n do list[j] = nil end
            list.dirty = false
        end
        CDT_HAS_ACTIVE   = false
        CDT_LAYOUT_DIRTY = true
        CDT_Redraw()
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r Entries cleared.")
    elseif msg == "reset" then
        CDT_FRAME:ClearAllPoints()
        local uiScale = UIParent:GetScale()
        local screenW = GetScreenWidth()  * uiScale
        local screenH = GetScreenHeight() * uiScale
        CDT_DB.x = 0; CDT_DB.y = 200
        CDT_FRAME:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", screenW/2 + 0, screenH/2 + 200)
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r Frame repositioned.")
    elseif msg == "cfg" or msg == "config" then
        if CDT_CFG_FRAME:IsVisible() then CDT_CFG_FRAME:Hide()
        else CDT_CFG_UpdateButtons(); CDT_CFG_FRAME:Show() end
    elseif msg == "test" then
        CDT_AddEntry("Thrall",    1161,  nil)
        CDT_AddEntry("Cairne",    5209,  nil)
        CDT_AddEntry("Tyrande",   29166, nil)
        CDT_AddEntry("Malfurion", 20484, nil)
        CDT_AddEntry("Uther",     633,   nil)
        CDT_AddEntry("Gul'dan",   20757, "Thrall")
        CDT_AddEntry("Rehgar",    20608, nil)
        CDT_AddEntry("Uther",     19752, nil)
        CDT_AddEntry("Anduin",    6346,  nil)
        CDT_AddEntry("Hamuul",    9863,  nil)
        CDT_AddEntry("Garrosh",   676,   nil)
        CDT_Redraw()
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r Test entries added.")
    elseif msg == "pctest" then
        PC_HEALERS["Tyrande"]  = true
        PC_HEALERS["Anduin"]   = true
        PC_HEALERS["Uther"]    = true
        PC_HEALERS["Malfurion"]= true
        PC_HEALERS["Rehgar"]   = true
        PC_HEALER_COUNT = 5
        PC_PENDING[1] = "Hamuul"
        PC_PENDING[2] = "Velen"
        PC_PENDING_N  = 2
        PC_DrawPrompts()
        PC_Poll()
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r PullCheck test data added.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r CoolDown Tracker commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt          - toggle show/hide")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt show/hide- force show or hide")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt clear    - clear all entries")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt reset    - move frame to center")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt cfg      - open config window")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt test     - add CDT test entries")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt pctest   - add PullCheck test data")
    end
end
