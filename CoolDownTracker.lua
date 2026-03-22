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
-- Column width: 34px  (~5 chars of GameFontNormalSmall @ ~6px/char + 4px pad)
-- Icon size:    28px  (centered in col, 3px margin each side)
-- Gap:           3px  between columns
-- Side padding:  4px  each side (8px total)
-- frameW(N) = N*34 + (N-1)*3 + 8  =  N*37 - 29
-- e.g. 6 cols = 227px, 5 = 190px, 4 = 153px, 3 = 116px
CDT_SUMM_COL_W    = 34   -- column width
CDT_SUMM_ICON_SZ  = 28   -- icon size
CDT_SUMM_GAP      = 3    -- gap between columns
CDT_SUMM_PAD      = 4    -- side padding each side
CDT_SUMM_NM_H     = 11   -- height of each name row
CDT_SUMM_NM_ROWS  = 3    -- name rows per column
-- Body height: icon row + gap + icon row + name rows + padding
-- = 28 + 3 + 28 + 3*11 + 2*4 = 28+3+28+33+8 = 100px
CDT_SUMM_BODY_H   = 100

-- ── Spell definitions ─────────────────────────────────────────────────────────
-- cr/cg/cb = class background tint (detail rows + summary icon border tint)
-- sumIcon  = short 2-line icon label used in summary mode (plain text placeholder
--            that sits over the real icon texture)
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
    if CDT_DB.x         == nil then CDT_DB.x         = 0         end
    if CDT_DB.y         == nil then CDT_DB.y         = 200       end
    if CDT_DB.shown     == nil then CDT_DB.shown     = true      end
    if CDT_DB.showMode  == nil then CDT_DB.showMode  = "always"  end
    if CDT_DB.viewMode  == nil then CDT_DB.viewMode  = "detail"  end
    if CDT_DB.readyMode == nil then CDT_DB.readyMode = "on"      end
    if CDT_DB.barDir    == nil then CDT_DB.barDir    = "H"       end
    if CDT_DB.spells    == nil then CDT_DB.spells    = {}        end
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
    -- Build displayName once here; reused every redraw tick with no allocation
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

-- Returns true if anything changed (entry removed or ready flipped).
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
    -- Update layout dirty flag when row count changed
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
CDT_BODY          = nil   -- detail body
CDT_SUMM_BODY     = nil   -- summary body
CDT_READY         = false
CDT_MOUSEOVER     = false
CDT_MO_PINNED     = false
CDT_MO_PIN_UNTIL  = 0
CDT_BODY_VISIBLE  = false
CDT_LAST_H        = -1
CDT_LAST_W        = -1

CDT_MODE_RAID      = false
CDT_MODE_MO        = false
CDT_MODE_SUMM      = false  -- true when viewMode == "summary"
CDT_READY_OFF_FLAG = false
CDT_BAR_VERT       = false

-- Dirty flags — avoid redundant work in the tick
CDT_HAS_ACTIVE   = false   -- true when any list has at least one entry
CDT_LAYOUT_DIRTY = false   -- true when row count changed (resize needed)

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

-- Detail mode frame banks
CDT_BLOCK_ROWS         = {}
CDT_ROW_CACHE          = {}
CDT_MAX_ROWS_PER_SPELL = 8

-- Summary mode frame banks
-- CDT_SUMM_COLS[spellIndex] = { icon, nm1, nm2, nm3, xOff, row (0 or 1) }
-- Allocated once at build time for all spells; show/hide driven by enabled count.
CDT_SUMM_COLS  = {}
-- Cache for summary to avoid redundant SetText/SetTextColor
-- CDT_SUMM_CACHE[spellIndex] = { nm1, nm2, nm3, tr, tg, tb, visible, xOff }
CDT_SUMM_CACHE = {}

-- ── Mode flag sync ────────────────────────────────────────────────────────────
function CDT_SyncModeFlags()
    CDT_MODE_RAID      = CDT_DB.showMode  == "raid"
    CDT_MODE_MO        = CDT_DB.showMode  == "mouseover"
    CDT_MODE_SUMM      = CDT_DB.viewMode  == "summary"
    CDT_READY_OFF_FLAG = CDT_DB.readyMode == "off"
    CDT_BAR_VERT       = CDT_MODE_MO and (CDT_DB.barDir == "V")
end

-- ── Summary layout helpers ────────────────────────────────────────────────────

-- Count how many spells are currently enabled.
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

-- Compute summary frame width from enabled spell count.
-- cols = ceil(enabledCount / 2), min 1.
-- frameW = cols * CDT_SUMM_COL_W + (cols-1) * CDT_SUMM_GAP + 2 * CDT_SUMM_PAD
function CDT_SummWidth(enabledCount)
    if enabledCount < 1 then enabledCount = 1 end
    local cols = _floor((enabledCount + 1) / 2)  -- ceil(n/2) in Lua 5.0
    return cols * CDT_SUMM_COL_W + (cols - 1) * CDT_SUMM_GAP + 2 * CDT_SUMM_PAD
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
        w = CDT_HDR_H
        h = CDT_W
    else
        -- Collapsed horizontal width: use current expanded width so the bar
        -- matches the last known frame width. For simplicity use CDT_W for
        -- detail, dynamic width for summary.
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
        -- Summary: dynamic width, fixed body height
        local enabled = CDT_CountEnabled()
        frameW = CDT_SummWidth(enabled)
        frameH = CDT_HDR_H + CDT_SUMM_BODY_H
        CDT_SUMM_BODY:SetWidth(frameW)
    else
        -- Detail: fixed width, variable height
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

    -- Skip entirely when nothing is being tracked and we're not in mouseover mode.
    -- Mouseover mode still needs a tick to handle pin expiry and collapse.
    if not CDT_HAS_ACTIVE and not CDT_MODE_MO then return end

    local now      = _GetTime()
    local readyOff = CDT_READY_OFF_FLAG
    local defs     = CDT_SPELL_DEFS
    local nDefs    = _getn(defs)

    -- Prune all lists; sort only those marked dirty.
    -- Also recompute CDT_HAS_ACTIVE from scratch each tick so it self-heals.
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

    -- Resize only when something changed the row count
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

                    -- Use pre-built displayName (no allocation in hot path)
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
-- Hot path: zero allocations when display is stable.
-- Layout: two icon rows, each spell gets one column.
-- Columns are assigned left-to-right, top row filled first, then bottom row.
-- Disabled spells are skipped entirely — remaining cols shift left.
-- Frame width is recalculated only when enabled count changes (rare).
--
-- Per column:
--   icon     : 28×28 texture at top of column
--   nm[1..3] : up to 3 ready player names (gold)
--              OR timer of soonest-available player centered on row 2 (coloured)
--              OR "---" (dimmed) if no data
--
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

    -- Count enabled to know column layout
    local enabled = 0
    for i = 1, nDefs do
        if CDT_DB.spells[defs[i].key] ~= false then enabled = enabled + 1 end
    end
    if enabled < 1 then enabled = 1 end
    local cols = _floor((enabled + 1) / 2)   -- ceil(enabled/2)

    -- Assign x offsets and row indices to each enabled spell.
    -- col_index goes 0..cols-1 for row 0, then 0..cols-1 for row 1.
    local slot = 0  -- 0-based slot among enabled spells

    for si = 1, nDefs do
        local def = defs[si]
        local key = def.key
        local sc  = CDT_SUMM_COLS[si]
        local ca  = CDT_SUMM_CACHE[si]

        if CDT_DB.spells[key] == false then
            -- Disabled: hide column
            if ca.visible then
                ca.visible = false
                sc.iconFrame:Hide()
                sc.nm[1]:Hide(); sc.nm[2]:Hide(); sc.nm[3]:Hide()
            end
        else
            -- Compute position from slot
            local colIdx  = _mod(slot, cols)           -- column 0-based
            local rowIdx  = _floor(slot / cols)        -- 0 = top, 1 = bottom
            local xOff    = pad + colIdx * (colW + gap)
            -- Top icon row y: -pad  Bottom icon row y: -pad - iconSz - gap - nmH*3 - gap
            -- Body layout: pad, icon row 0, gap, nm rows 0, gap, icon row 1, gap, nm rows 1, pad
            -- = pad + iconSz + gap + 3*nmH + gap + iconSz + gap + 3*nmH + pad
            -- Precomputed: row0 icon top = -pad, row1 icon top = -(pad+iconSz+gap+3*nmH+gap)
            local iconY
            local nmBaseY
            if rowIdx == 0 then
                iconY    = -pad
                nmBaseY  = -(pad + iconSz + 1)
            else
                iconY    = -(pad + iconSz + gap + CDT_SUMM_NM_ROWS * nmH + gap)
                nmBaseY  = -(pad + iconSz + gap + CDT_SUMM_NM_ROWS * nmH + gap + iconSz + 1)
            end

            -- Reposition icon and name rows only when xOff/rowIdx changed
            if ca.xOff ~= xOff or ca.rowIdx ~= rowIdx then
                ca.xOff   = xOff
                ca.rowIdx = rowIdx
                sc.iconFrame:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT", xOff, iconY)
                for r = 1, 3 do
                    sc.nm[r]:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT",
                        xOff, nmBaseY - (r - 1) * nmH)
                end
            end

            -- Show icon frame if hidden
            if not ca.visible then
                ca.visible = true
                sc.iconFrame:Show()
                sc.nm[1]:Show(); sc.nm[2]:Show(); sc.nm[3]:Show()
            end

            -- Gather ready names and soonest timer from entry list
            local list     = CDT_BY_KEY[key]
            local n        = _getn(list)
            local readyNames = { nil, nil, nil }  -- up to 3
            local readyCnt   = 0
            local soonest    = nil   -- smallest expireAt among non-ready entries

            for i = 1, n do
                local e = list[i]
                if e.ready then
                    if readyCnt < 3 then
                        readyCnt = readyCnt + 1
                        readyNames[readyCnt] = e.name
                    end
                else
                    if soonest == nil or e.expireAt < soonest then
                        soonest = e.expireAt
                    end
                end
            end

            -- Build name row texts + colours
            -- Row 1-3: ready names, or row 2 = timer / "---", rows 1&3 blank
            local txt = { "", "", "" }
            local tr, tg, tb = 0.2, 0.2, 0.2  -- default: dim

            if readyCnt > 0 then
                -- Show up to 3 ready names, gold
                for r = 1, 3 do
                    txt[r] = readyNames[r] or ""
                end
                tr, tg, tb = 1, 0.88, 0.6
            elseif n == 0 then
                -- No data at all
                txt[1] = ""; txt[2] = "---"; txt[3] = ""
                tr, tg, tb = 0.22, 0.22, 0.3
            else
                -- Everyone on CD — show soonest timer on middle row
                txt[1] = ""; txt[3] = ""
                if soonest then
                    local rem = soonest - now
                    if rem < 0 then rem = 0 end
                    local m = _floor(rem / 60)
                    local s = _floor(_mod(rem, 60))
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
                    txt[2] = "---"
                    tr, tg, tb = 0.22, 0.22, 0.3
                end
            end

            -- Apply text changes only when value changed
            -- All 3 name rows share the same colour (gold for ready, timer colour otherwise)
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

-- ── Build main UI ─────────────────────────────────────────────────────────────

function CDT_Build()
    CDT_FRAME = CreateFrame("Frame", "CDTMainFrame", UIParent)
    CDT_FRAME:SetWidth(CDT_W)
    CDT_FRAME:SetHeight(CDT_HDR_H)
    CDT_FRAME:SetMovable(true)
    CDT_FRAME:EnableMouse(true)
    CDT_FRAME:RegisterForDrag("LeftButton")
    CDT_FRAME:SetClampedToScreen(true)
    CDT_FRAME:SetPoint("CENTER", UIParent, "CENTER", CDT_DB.x, CDT_DB.y)

    CDT_FRAME:SetScript("OnDragStart", function() CDT_FRAME:StartMoving() end)
    CDT_FRAME:SetScript("OnDragStop", function()
        CDT_FRAME:StopMovingOrSizing()
        local scale   = CDT_FRAME:GetEffectiveScale()
        local uiScale = UIParent:GetScale()
        CDT_DB.x = CDT_FRAME:GetLeft() * scale - GetScreenWidth()  * uiScale / 2
        CDT_DB.y = CDT_FRAME:GetTop()  * scale - GetScreenHeight() * uiScale / 2
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
    local hdr = CreateFrame("Frame", "CDTHeader", CDT_FRAME)
    hdr:SetWidth(CDT_W); hdr:SetHeight(CDT_HDR_H)
    hdr:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, 0)
    local hBg = hdr:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints(hdr); hBg:SetTexture(0.1, 0.1, 0.3, 0.95)
    local hTxt = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTxt:SetPoint("LEFT", hdr, "LEFT", 5, 0)
    hTxt:SetText("|cffaabbff[CDT]|r CoolDown Tracker")

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

    -- ── Detail body ──
    CDT_BODY = CreateFrame("Frame", "CDTBody", CDT_FRAME)
    CDT_BODY:SetWidth(CDT_W)
    CDT_BODY:SetHeight(10)
    CDT_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, -CDT_HDR_H)
    local bodyBg = CDT_BODY:CreateTexture(nil, "BACKGROUND")
    bodyBg:SetAllPoints(CDT_BODY)
    bodyBg:SetTexture(0.02, 0.02, 0.04, 0.85)

    -- ── Summary body ──
    CDT_SUMM_BODY = CreateFrame("Frame", "CDTSummBody", CDT_FRAME)
    CDT_SUMM_BODY:SetWidth(CDT_W)
    CDT_SUMM_BODY:SetHeight(CDT_SUMM_BODY_H)
    CDT_SUMM_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, -CDT_HDR_H)
    CDT_SUMM_BODY:Hide()
    local summBg = CDT_SUMM_BODY:CreateTexture(nil, "BACKGROUND")
    summBg:SetAllPoints(CDT_SUMM_BODY)
    summBg:SetTexture(0.02, 0.02, 0.04, 0.85)

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
    -- One column frame bank per spell. All allocated at build time; we show/hide
    -- and reposition them based on which spells are enabled.
    -- Each column: one icon Frame (holds texture) + 3 FontStrings for names.
    -- No per-tick allocation.
    local colW   = CDT_SUMM_COL_W
    local iconSz = CDT_SUMM_ICON_SZ
    local nmH    = CDT_SUMM_NM_H

    for si = 1, nDefs do
        local def = defs[si]

        -- Icon container frame (lets us clip icon texture cleanly)
        local iconFrame = CreateFrame("Frame", "CDTSummIcon_"..si, CDT_SUMM_BODY)
        iconFrame:SetWidth(iconSz); iconFrame:SetHeight(iconSz)
        iconFrame:SetPoint("TOPLEFT", CDT_SUMM_BODY, "TOPLEFT", 0, 0)

        -- Class-tinted background behind icon
        local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
        iconBg:SetAllPoints(iconFrame)
        iconBg:SetTexture(def.cr * 0.3, def.cg * 0.3, def.cb * 0.3, 0.95)

        -- Spell icon texture
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(iconFrame)
        iconTex:SetTexture("Interface\\Icons\\" .. def.icon)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Thin class-coloured border stripe at bottom of icon (group identity)
        local iconStripe = iconFrame:CreateTexture(nil, "OVERLAY")
        iconStripe:SetHeight(2); iconStripe:SetWidth(iconSz)
        iconStripe:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
        iconStripe:SetTexture(def.cr, def.cg, def.cb, 0.9)

        iconFrame:Hide()

        -- 3 name FontStrings, each CDT_SUMM_COL_W wide
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
    local tick = CreateFrame("Frame", "CDTTick", UIParent)
    local acc  = 0
    tick:SetScript("OnUpdate", function()
        acc = acc + arg1
        if acc < 2 then return end
        acc = 0
        if CDT_MODE_RAID then
            if GetNumRaidMembers() > 0 then CDT_FRAME:Show() else CDT_FRAME:Hide() end
        end
        if CDT_MO_PINNED and _GetTime() >= CDT_MO_PIN_UNTIL then
            CDT_MO_PINNED = false
            if CDT_MODE_MO and not CDT_MOUSEOVER then CDT_SetBodyVisible(false) end
        end
        CDT_Redraw()
    end)

    CDT_READY = true
    CDT_BuildConfirm()
    CDT_BuildConfig()
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
-- yOff layout:
--   -16   divider
--   -22   "Show:" label
--   -35   show mode buttons (always / raid / mouseover)
--   -53   desc always
--   -63   desc raid
--   -73   desc mouseover
--   -85   divider
--   -90   "View:" label
--   -103  view mode buttons (detail / summary)
--   -115  divider
--   -120  "Collapsed bar (mouseover):" label
--   -133  H / V buttons
--   -147  desc H/V
--   -159  divider
--   -164  "Ready:" label
--   -177  on / off buttons
--   -191  desc on
--   -201  desc off
--   -213  divider
--   -218  "Track spells:" label
--   -218 - 4 - i*14   per spell row
--   after last spell: star disclaimer (2 lines × 10px + 4px margin = 24px)

function CDT_BuildConfig()
    local spellCount = _getn(CDT_SPELL_DEFS)
    -- Height: 230 base + spells + 28 for star disclaimer
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
            -- Switch bodies and resize immediately
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
            -- Summary width may change when spell filter changes
            if CDT_MODE_SUMM and CDT_BODY_VISIBLE then
                CDT_LAST_W = -1
                CDT_ResizeFrame()
                CDT_Redraw()
            end
        end)

        CDT_CFG_SPELL_CHKS[i] = { box=box, lbl=lbl, key=def.key }
    end

    -- Star disclaimer below spell list
    local starY = -218 - 4 - spellCount * 14 - 6
    local starDisc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    starDisc:SetPoint("TOPLEFT", f, "TOPLEFT", 8, starY)
    starDisc:SetTextColor(0.55, 0.52, 0.28)
    starDisc:SetWidth(194)
    starDisc:SetJustifyH("LEFT")
    starDisc:SetText("* cooldown may be reduced by talents or set bonuses — timer is approximate")

    CDT_CFG_FRAME = f
    CDT_CFG_UpdateButtons()
end

function CDT_CFG_UpdateButtons()
    -- Show mode
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

    -- View mode
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

    -- Bar orientation
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

    -- Ready mode
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

    -- Spell filter
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

    if arg3 == "CAST" then
        local spellId = tonumber(arg4)
        if not CDT_IDS[spellId] then return end

        local name = CDT_GUID_TO_NAME[arg1]
        if not name then return end

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
        CDT_FRAME:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        CDT_DB.x = 0; CDT_DB.y = 200
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
        DEFAULT_CHAT_FRAME:AddMessage("  /cdt test     - add test entries")
    end
end
