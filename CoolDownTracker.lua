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
CDT_SUMM_COL_W    = 30
CDT_SUMM_ICON_SZ  = 26
CDT_SUMM_GAP      = 2
CDT_SUMM_PAD      = 2
CDT_SUMM_NM_H     = 10
CDT_SUMM_NM_ROWS  = 2
CDT_SUMM_MIN_COLS = 1
CDT_SUMM_MIN_ROWS = 1
CDT_SUMM_MAX_COLS = 12
CDT_SUMM_MAX_ROWS = 6


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


-- Config option tables
CDT_SHOW_OPTS  = { "always", "raid", "mouseover" }
CDT_BAR_OPTS   = { "H", "V" }

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
    if CDT_DB.viewMode    == nil then CDT_DB.viewMode    = "summary" end
    if CDT_DB.readyMode   == nil then CDT_DB.readyMode   = "on"     end
    CDT_DB.viewMode  = "summary"
    CDT_DB.readyMode = "on"
    if CDT_DB.barDir      == nil then CDT_DB.barDir      = "H"      end
    if CDT_DB.summRows    == nil then CDT_DB.summRows    = 2        end
    if CDT_DB.summCols    == nil then CDT_DB.summCols    = 5        end
    if CDT_DB.spells      == nil then CDT_DB.spells      = {}       end
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
CDT_CFG_BAR_BTNS   = {}
CDT_CFG_SPELL_CHKS = {}
CDT_CFG_SUMM_ROWS_TXT = nil
CDT_CFG_SUMM_COLS_TXT = nil

CDT_BLOCK_ROWS         = {}
CDT_ROW_CACHE          = {}
CDT_MAX_ROWS_PER_SPELL = 8

CDT_SUMM_COLS  = {}
CDT_SUMM_CACHE = {}
CDT_SUMM_READY_NAMES = { nil, nil }
CDT_SUMM_TXT         = { "", "" }


-- ── Mode flag sync ────────────────────────────────────────────────────────────
function CDT_SyncModeFlags()
    CDT_MODE_RAID      = CDT_DB.showMode  == "raid"
    CDT_MODE_MO        = CDT_DB.showMode  == "mouseover"
    CDT_MODE_SUMM      = true
    CDT_READY_OFF_FLAG = false
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

function CDT_SummWidth()
    local cols = CDT_DB.summCols or 5
    if cols < CDT_SUMM_MIN_COLS then cols = CDT_SUMM_MIN_COLS end
    if cols > CDT_SUMM_MAX_COLS then cols = CDT_SUMM_MAX_COLS end
    return cols * CDT_SUMM_COL_W + (cols - 1) * CDT_SUMM_GAP + 2 * CDT_SUMM_PAD
end

function CDT_SummBodyH()
    local rows = CDT_DB.summRows or 2
    if rows < CDT_SUMM_MIN_ROWS then rows = CDT_SUMM_MIN_ROWS end
    if rows > CDT_SUMM_MAX_ROWS then rows = CDT_SUMM_MAX_ROWS end
    local blockH = CDT_SUMM_ICON_SZ + CDT_SUMM_NM_ROWS * CDT_SUMM_NM_H
    return 2 * CDT_SUMM_PAD + rows * blockH + (rows - 1) * CDT_SUMM_GAP
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
        CDT_BODY:Hide()
        CDT_SUMM_BODY:Show()
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
        w = CDT_SummWidth()
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

    frameW = CDT_SummWidth()
    frameH = CDT_HDR_H + CDT_SummBodyH()
    CDT_SUMM_BODY:SetWidth(frameW)
    CDT_SUMM_BODY:SetHeight(CDT_SummBodyH())

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
    local defs     = CDT_SPELL_DEFS
    local nDefs    = _getn(defs)

    local anyActive = false
    for i = 1, nDefs do
        local list    = CDT_BY_KEY[defs[i].key]
        local changed = CDT_PruneList(list, now, false)
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

    CDT_SummRedraw(now)
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

    local cols = CDT_DB.summCols or 5
    local rows = CDT_DB.summRows or 2
    if cols < CDT_SUMM_MIN_COLS then cols = CDT_SUMM_MIN_COLS end
    if cols > CDT_SUMM_MAX_COLS then cols = CDT_SUMM_MAX_COLS end
    if rows < CDT_SUMM_MIN_ROWS then rows = CDT_SUMM_MIN_ROWS end
    if rows > CDT_SUMM_MAX_ROWS then rows = CDT_SUMM_MAX_ROWS end
    local maxSlots = cols * rows

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
                sc.nm[1]:Hide(); sc.nm[2]:Hide()
            end
        else
            if slot >= maxSlots then
                if ca.visible then
                    ca.visible = false
                    sc.iconFrame:Hide()
                    sc.nm[1]:Hide(); sc.nm[2]:Hide()
                end
                slot = slot + 1
            else
            local colIdx  = _mod(slot, cols)
            local rowIdx  = _floor(slot / cols)
            local xOff    = pad + colIdx * (colW + gap)
            local blockStep = iconSz + CDT_SUMM_NM_ROWS * nmH + gap
            local iconY    = -(pad + rowIdx * blockStep)
            local nmBaseY  = -(pad + rowIdx * blockStep + iconSz + 1)

            if ca.xOff ~= xOff or ca.rowIdx ~= rowIdx then
                ca.xOff   = xOff
                ca.rowIdx = rowIdx
                sc.iconFrame:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT", xOff, iconY)
                for r = 1, CDT_SUMM_NM_ROWS do
                    sc.nm[r]:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT",
                        xOff, nmBaseY - (r - 1) * nmH)
                end
            end

            if not ca.visible then
                ca.visible = true
                sc.iconFrame:Show()
                sc.nm[1]:Show(); sc.nm[2]:Show()
            end

            local list     = CDT_BY_KEY[key]
            local n        = _getn(list)
            local readyNames = CDT_SUMM_READY_NAMES
            local readyCnt   = 0
            local soonest    = nil
            local soonestName = nil

            readyNames[1] = nil; readyNames[2] = nil

            for i = 1, n do
                local e = list[i]
                if e.ready then
                    if readyCnt < CDT_SUMM_NM_ROWS then
                        readyCnt = readyCnt + 1
                        readyNames[readyCnt] = e.name
                    end
                else
                    if soonest == nil or e.expireAt < soonest then
                        soonest     = e.expireAt
                        soonestName = e.name
                    end
                end
            end

            local txt = CDT_SUMM_TXT
            local tr, tg, tb = 0.2, 0.2, 0.2

            if readyCnt > 0 then
                txt[1] = readyNames[1] or ""
                txt[2] = readyNames[2] or ""
                tr, tg, tb = 1, 0.88, 0.6
            elseif n == 0 then
                txt[1] = ""; txt[2] = "---"
                tr, tg, tb = 0.22, 0.22, 0.3
            else
                if soonest then
                    local rem = soonest - now
                    if rem < 0 then rem = 0 end
                    local m = _floor(rem / 60)
                    local s = _floor(_mod(rem, 60))
                    txt[1] = soonestName or ""
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

            for r = 1, CDT_SUMM_NM_ROWS do
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
            end

            slot = slot + 1
            end
        end
    end
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
    CDT_SUMM_BODY:SetHeight(CDT_SummBodyH())
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
        for r = 1, CDT_SUMM_NM_ROWS do
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
            nm     = { "", "" },
            tr=-1, tg=-1, tb=-1,
            visible=false,
            xOff   = nil,
            rowIdx = nil,
        }
    end

    -- ── Ticker ──
    local tick    = CreateFrame("Frame", "CDTTick", UIParent)
    local acc     = 0
    tick:SetScript("OnUpdate", function()
        acc   = acc   + arg1

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
    end)

    CDT_READY = true
    CDT_BuildConfirm()
    CDT_BuildConfig()
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
    local cfgH = 230 + spellCount * 14 + 28
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

    -- ── Bar orientation ──
    MakeDivider(-85)
    local barLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -90)
    barLbl:SetTextColor(0.8, 0.8, 1); barLbl:SetText("Collapsed bar (mouseover):")

    local barOpts = CDT_BAR_OPTS
    for idx = 1, _getn(barOpts) do
        local dir = barOpts[idx]
        local btn = CreateFrame("Button", "CDTBarBtn"..idx, f)
        btn:SetWidth(30); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (idx-1)*34, -103)
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
    descBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -117)
    descBar:SetTextColor(0.45, 0.45, 0.55); descBar:SetWidth(198)
    descBar:SetJustifyH("LEFT"); descBar:SetText("H: horizontal strip  V: vertical strip")

    -- ── Summary grid layout ──
    MakeDivider(-129)
    local gridLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gridLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -134)
    gridLbl:SetTextColor(0.8, 0.8, 1); gridLbl:SetText("Summary grid (fixed):")

    local rowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -148)
    rowLbl:SetTextColor(0.7, 0.7, 0.9); rowLbl:SetText("Rows")

    local rowMinus = CreateFrame("Button", "CDTSummRowsMinus", f)
    rowMinus:SetWidth(16); rowMinus:SetHeight(14)
    rowMinus:SetPoint("TOPLEFT", f, "TOPLEFT", 48, -148)
    rowMinus:SetScript("OnClick", function()
        CDT_DB.summRows = CDT_DB.summRows - 1
        if CDT_DB.summRows < CDT_SUMM_MIN_ROWS then CDT_DB.summRows = CDT_SUMM_MIN_ROWS end
        CDT_LAST_H = -1; CDT_LAST_W = -1
        CDT_CFG_UpdateButtons(); CDT_ResizeFrame(); CDT_Redraw()
    end)
    local rowMinusTxt = rowMinus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowMinusTxt:SetAllPoints(rowMinus); rowMinusTxt:SetText("-")

    local rowPlus = CreateFrame("Button", "CDTSummRowsPlus", f)
    rowPlus:SetWidth(16); rowPlus:SetHeight(14)
    rowPlus:SetPoint("TOPLEFT", f, "TOPLEFT", 94, -148)
    rowPlus:SetScript("OnClick", function()
        CDT_DB.summRows = CDT_DB.summRows + 1
        if CDT_DB.summRows > CDT_SUMM_MAX_ROWS then CDT_DB.summRows = CDT_SUMM_MAX_ROWS end
        CDT_LAST_H = -1; CDT_LAST_W = -1
        CDT_CFG_UpdateButtons(); CDT_ResizeFrame(); CDT_Redraw()
    end)
    local rowPlusTxt = rowPlus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowPlusTxt:SetAllPoints(rowPlus); rowPlusTxt:SetText("+")

    CDT_CFG_SUMM_ROWS_TXT = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    CDT_CFG_SUMM_ROWS_TXT:SetPoint("TOPLEFT", f, "TOPLEFT", 69, -148)
    CDT_CFG_SUMM_ROWS_TXT:SetTextColor(0.9, 0.9, 0.9)

    local colLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 126, -148)
    colLbl:SetTextColor(0.7, 0.7, 0.9); colLbl:SetText("Cols")

    local colMinus = CreateFrame("Button", "CDTSummColsMinus", f)
    colMinus:SetWidth(16); colMinus:SetHeight(14)
    colMinus:SetPoint("TOPLEFT", f, "TOPLEFT", 166, -148)
    colMinus:SetScript("OnClick", function()
        CDT_DB.summCols = CDT_DB.summCols - 1
        if CDT_DB.summCols < CDT_SUMM_MIN_COLS then CDT_DB.summCols = CDT_SUMM_MIN_COLS end
        CDT_LAST_H = -1; CDT_LAST_W = -1
        CDT_CFG_UpdateButtons(); CDT_ResizeFrame(); CDT_Redraw()
    end)
    local colMinusTxt = colMinus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colMinusTxt:SetAllPoints(colMinus); colMinusTxt:SetText("-")

    local colPlus = CreateFrame("Button", "CDTSummColsPlus", f)
    colPlus:SetWidth(16); colPlus:SetHeight(14)
    colPlus:SetPoint("TOPLEFT", f, "TOPLEFT", 192, -148)
    colPlus:SetScript("OnClick", function()
        CDT_DB.summCols = CDT_DB.summCols + 1
        if CDT_DB.summCols > CDT_SUMM_MAX_COLS then CDT_DB.summCols = CDT_SUMM_MAX_COLS end
        CDT_LAST_H = -1; CDT_LAST_W = -1
        CDT_CFG_UpdateButtons(); CDT_ResizeFrame(); CDT_Redraw()
    end)
    local colPlusTxt = colPlus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colPlusTxt:SetAllPoints(colPlus); colPlusTxt:SetText("+")

    CDT_CFG_SUMM_COLS_TXT = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    CDT_CFG_SUMM_COLS_TXT:SetPoint("TOPLEFT", f, "TOPLEFT", 184, -148)
    CDT_CFG_SUMM_COLS_TXT:SetTextColor(0.9, 0.9, 0.9)

    local gridDesc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gridDesc:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -161)
    gridDesc:SetTextColor(0.45, 0.45, 0.55); gridDesc:SetWidth(194)
    gridDesc:SetJustifyH("LEFT"); gridDesc:SetText("Disabled spells no longer resize the summary panel.")

    -- ── Spell filter ──
    MakeDivider(-173)
    local spellsLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellsLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -178)
    spellsLbl:SetTextColor(0.8, 0.8, 1); spellsLbl:SetText("Track spells:")

    CDT_CFG_SPELL_CHKS = {}
    for i = 1, spellCount do
        local def  = CDT_SPELL_DEFS[i]
        local yOff = -178 - 4 - i * 14

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
            if CDT_BODY_VISIBLE then
                CDT_LAST_W = -1
                CDT_ResizeFrame()
                CDT_Redraw()
            end
        end)

        CDT_CFG_SPELL_CHKS[i] = { box=box, lbl=lbl, key=def.key }
    end

    -- Star disclaimer
    local starY = -178 - 4 - spellCount * 14 - 6
    local starDisc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    starDisc:SetPoint("TOPLEFT", f, "TOPLEFT", 8, starY)
    starDisc:SetTextColor(0.55, 0.52, 0.28)
    starDisc:SetWidth(194); starDisc:SetJustifyH("LEFT")
    starDisc:SetText("* cooldown may be reduced by talents or set bonuses — timer is approximate")


    CDT_CFG_FRAME = f
    CDT_CFG_UpdateButtons()
end

function CDT_CFG_UpdateButtons()
    if CDT_CFG_SUMM_ROWS_TXT then CDT_CFG_SUMM_ROWS_TXT:SetText(tostring(CDT_DB.summRows or 2)) end
    if CDT_CFG_SUMM_COLS_TXT then CDT_CFG_SUMM_COLS_TXT:SetText(tostring(CDT_DB.summCols or 5)) end

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

end

-- ── Events ────────────────────────────────────────────────────────────────────

local ev = CreateFrame("Frame", "CDTEventFrame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:RegisterEvent("UNIT_CASTEVENT")

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
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r CoolDown Tracker commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt          - toggle show/hide")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt show/hide- force show or hide")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt clear    - clear all entries")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt reset    - move frame to center")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt cfg      - open config window")
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt test     - add CDT test entries")
    end
end
