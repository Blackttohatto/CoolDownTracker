-- CoolDownTracker: Raid cooldown tracker for Turtle WoW
-- Slash: /cdt
-- Tracks raid members only via UNIT_CASTEVENT (SuperWoW)

-- ── Cached stdlib globals (hot-path locals) ───────────────────────────────────
local _GetTime = GetTime
local _floor   = math.floor
local _mod     = math.mod
local _getn    = table.getn

-- ── Layout constants ──────────────────────────────────────────────────────────
CDT_W        = 220   -- total frame width
CDT_HDR_H    = 15    -- header bar height
CDT_ROW_H    = 15    -- height of each data row
CDT_ICON_SZ  = 14    -- spell icon square size
CDT_ICON_X   = 2     -- icon left margin
CDT_LBL_X    = 19    -- spell label left edge (icon + gap)
CDT_LBL_W    = 68    -- spell label width
CDT_NM_X     = 90    -- player name left edge
CDT_NM_W     = 86    -- player name width
CDT_TM_W     = 38    -- timer width (right-anchored)

-- ── Spell definitions ─────────────────────────────────────────────────────────
-- Ordered exactly as they appear top-to-bottom in the frame.
-- cr/cg/cb = class background tint colour
-- icon     = filename under Interface\Icons\ (no path, no extension)
CDT_SPELL_DEFS = {
    {
        key="cshout",     label="C.Shout",         cd=600,
        icon="ability_bullrush",
        cr=0.78, cg=0.61, cb=0.43,   -- Warrior tan
    },
    {
        key="croar",      label="C.Roar",           cd=600,
        icon="ability_druid_challangingroar",
        cr=1.0,  cg=0.49, cb=0.04,   -- Druid orange
    },
    {
        key="loh",        label="Lay on Hands",     cd=3600,
        icon="spell_holy_layonhands",
        cr=0.96, cg=0.55, cb=0.73,   -- Paladin pink
    },
    {
        key="hop",        label="Bless. of Prot.",  cd=300,
        icon="spell_holy_sealofprotection",
        cr=0.96, cg=0.55, cb=0.73,   -- Paladin pink
    },
    {
        key="spiritlink", label="Spirit Link",      cd=180,
        icon="spell_shaman_spiritlink",
        cr=0.0,  cg=0.44, cb=0.87,   -- Shaman blue
    },
    {
        key="innervate",  label="Innervate",        cd=360,
        icon="spell_nature_lightning",
        cr=1.0,  cg=0.49, cb=0.04,   -- Druid orange
    },
    {
        key="reincarn",   label="Reincarnation",    cd=3600,
        icon="spell_nature_reincarnation",
        cr=0.0,  cg=0.44, cb=0.87,   -- Shaman blue
    },
    {
        key="soulstone",  label="Soulstone",        cd=1800,
        icon="inv_misc_orb_04",
        cr=0.58, cg=0.51, cb=0.79,   -- Warlock purple
    },
    {
        key="rebirth",    label="Rebirth",          cd=1800,
        icon="spell_nature_reincarnation",
        cr=1.0,  cg=0.49, cb=0.04,   -- Druid orange
    },
}

-- spellId -> def  (all rank aliases included)
-- Build a temporary key->def map just for this block, then discard it.
local _kd = {}
for _i = 1, _getn(CDT_SPELL_DEFS) do
    _kd[CDT_SPELL_DEFS[_i].key] = CDT_SPELL_DEFS[_i]
end
CDT_IDS = {}
CDT_IDS[1161]  = _kd["cshout"]
CDT_IDS[5209]  = _kd["croar"]
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
CDT_IDS[1022]  = _kd["hop"]
CDT_IDS[5599]  = _kd["hop"]
CDT_IDS[10278] = _kd["hop"]
CDT_IDS[20757] = _kd["soulstone"]
CDT_IDS[20608] = _kd["reincarn"]
CDT_IDS[51363] = _kd["spiritlink"]
_kd = nil  -- let GC collect it

-- Config option tables — allocated once, never reallocated
CDT_SHOW_OPTS  = { "always", "raid", "mouseover" }
CDT_READY_OPTS = { "on", "off" }

-- Precomputed raid unit strings — avoids "raid"..i allocation in the event handler
CDT_RAID_UNITS = {}
for _i = 1, 40 do CDT_RAID_UNITS[_i] = "raid" .. _i end

-- ── SavedVariables init ───────────────────────────────────────────────────────
function CDT_InitDB()
    if not CDT_DB then CDT_DB = {} end
    if CDT_DB.x         == nil then CDT_DB.x         = 0        end
    if CDT_DB.y         == nil then CDT_DB.y         = 200      end
    if CDT_DB.shown     == nil then CDT_DB.shown     = true     end
    if CDT_DB.showMode  == nil then CDT_DB.showMode  = "always" end
    if CDT_DB.readyMode == nil then CDT_DB.readyMode = "on"     end
    if CDT_DB.spells    == nil then CDT_DB.spells    = {}       end
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
-- CDT_BY_KEY[spellkey] = ordered array of entry tables.
-- Entry fields: name, target (soulstone only), key, cd, expireAt, ready, readyAt
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
            if targetName then e.target = targetName end
            return
        end
    end
    list[n + 1] = {
        name     = name,
        target   = targetName,
        key      = d.key,
        cd       = d.cd,
        expireAt = now + d.cd,
        ready    = false,
        readyAt  = nil,
    }
end

-- Prune one spell list in-place (no new table created).
function CDT_PruneList(list, now, readyOff)
    local w = 0
    local n = _getn(list)
    for i = 1, n do
        local e = list[i]
        if now >= e.expireAt and not e.ready then
            e.ready   = true
            e.readyAt = now
        end
        local keep = true
        if e.ready and readyOff then
            if e.readyAt and now >= e.readyAt + 10 then
                keep = false
            end
        end
        if keep then
            w = w + 1
            list[w] = e
        end
    end
    for i = w + 1, n do
        list[i] = nil
    end
end

-- Sort one spell list by time remaining ascending; ready entries go last.
-- Insertion sort (table.sort unavailable in Lua 5.0).
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

-- ── Global UI state ───────────────────────────────────────────────────────────
CDT_FRAME         = nil
CDT_BODY          = nil
CDT_READY         = false
CDT_MOUSEOVER     = false
CDT_MO_PINNED     = false
CDT_MO_PIN_UNTIL  = 0
CDT_BODY_VISIBLE  = false
CDT_LAST_H        = -1      -- dirty flag: last frame height set

-- Cached mode flags — updated on config change, avoids string compares in ticker
CDT_MODE_RAID      = false  -- true when showMode == "raid"
CDT_MODE_MO        = false  -- true when showMode == "mouseover"
CDT_READY_OFF_FLAG = false  -- true when readyMode == "off"

-- Precomputed seconds strings ":00"..":59" — eliminates concat allocations in timer
CDT_SEC_STR = {}
for _i = 0, 59 do
    if _i < 10 then
        CDT_SEC_STR[_i] = ":0" .. _i
    else
        CDT_SEC_STR[_i] = ":" .. _i
    end
end

CDT_CFG_FRAME      = nil
CDT_CONFIRM_FRAME  = nil
CDT_CFG_SHOW_BTNS  = {}
CDT_CFG_READY_BTNS = {}
CDT_CFG_SPELL_CHKS = {}

-- Preallocated row frames, one bank per spell.
-- CDT_BLOCK_ROWS[spellIndex][rowIndex] = frame
-- CDT_ROW_CACHE[spellIndex][rowIndex]  = display-value cache table
CDT_BLOCK_ROWS        = {}
CDT_ROW_CACHE         = {}
CDT_MAX_ROWS_PER_SPELL = 8

-- ── Cached mode flag sync ─────────────────────────────────────────────────────
-- Call whenever showMode or readyMode changes (config buttons + InitDB).
function CDT_SyncModeFlags()
    CDT_MODE_RAID      = CDT_DB.showMode  == "raid"
    CDT_MODE_MO        = CDT_DB.showMode  == "mouseover"
    CDT_READY_OFF_FLAG = CDT_DB.readyMode == "off"
end

-- ── Visibility / resize ───────────────────────────────────────────────────────

function CDT_SetBodyVisible(vis)
    if not CDT_READY then return end
    if vis == CDT_BODY_VISIBLE then return end
    CDT_BODY_VISIBLE = vis
    if vis then CDT_BODY:Show() else CDT_BODY:Hide() end
    CDT_ResizeFrame()
end

function CDT_ResizeFrame()
    if not CDT_READY then return end
    if not CDT_BODY_VISIBLE then
        if CDT_LAST_H ~= CDT_HDR_H then
            CDT_LAST_H = CDT_HDR_H
            CDT_FRAME:SetHeight(CDT_HDR_H)
        end
        return
    end
    local total  = 0
    local defs   = CDT_SPELL_DEFS
    local nDefs  = _getn(defs)
    for i = 1, nDefs do
        local key = defs[i].key
        if CDT_DB.spells[key] ~= false then
            local cnt = _getn(CDT_BY_KEY[key])
            total = total + (cnt > 0 and cnt or 1)
        end
    end
    local bodyH  = total * CDT_ROW_H + 2
    local frameH = CDT_HDR_H + bodyH
    if frameH ~= CDT_LAST_H then
        CDT_LAST_H = frameH
        CDT_BODY:SetHeight(bodyH)
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

-- ── Redraw ────────────────────────────────────────────────────────────────────
-- Hot path. Zero allocations when display is stable.

function CDT_Redraw()
    if not CDT_READY then return end
    local now      = _GetTime()
    local readyOff = CDT_READY_OFF_FLAG
    local defs     = CDT_SPELL_DEFS
    local nDefs    = _getn(defs)

    -- Prune + sort every spell list
    for i = 1, nDefs do
        local key  = defs[i].key
        local list = CDT_BY_KEY[key]
        CDT_PruneList(list, now, readyOff)
        CDT_SortList(list, now)
    end

    CDT_ResizeFrame()
    if not CDT_BODY_VISIBLE then return end

    local yOff   = -2  -- running vertical cursor inside CDT_BODY
    local secStr = CDT_SEC_STR

    for si = 1, nDefs do
        local def       = defs[si]
        local key       = def.key
        local blockRows = CDT_BLOCK_ROWS[si]
        local cache     = CDT_ROW_CACHE[si]

        if CDT_DB.spells[key] == false then
            -- Spell filtered out — hide all rows in this block
            for ri = 1, CDT_MAX_ROWS_PER_SPELL do
                local c = cache[ri]
                if c.visible then
                    c.visible = false
                    blockRows[ri]:Hide()
                end
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
                    -- Reposition row only when yOff actually changed
                    if c.yOff ~= yOff then
                        c.yOff = yOff
                        row:SetPoint("TOPLEFT", CDT_BODY, "TOPLEFT", 0, yOff)
                    end

                    local e = list[ri]  -- nil = placeholder row

                    -- Spell icon + label: first row of each block only
                    if ri == 1 then
                        if not c.lblShown then
                            c.lblShown = true
                            row.icon:Show()
                            row.lbl:Show()
                        end
                    else
                        if c.lblShown ~= false then
                            c.lblShown = false
                            row.icon:Hide()
                            row.lbl:Hide()
                        end
                    end

                    -- Player name
                    local nmTxt
                    if e then
                        if key == "soulstone" and e.target then
                            nmTxt = e.name .. " > " .. e.target
                        else
                            nmTxt = e.name
                        end
                    else
                        nmTxt = "No casts yet"
                    end
                    if c.nm ~= nmTxt then
                        c.nm = nmTxt
                        row.nm:SetText(nmTxt)
                    end

                    -- Name colour: gold for live entries, dimmed class colour for placeholder
                    local nnr, nng, nnb
                    if e then
                        nnr, nng, nnb = 1, 0.88, 0.6
                    else
                        nnr = cr * 0.55
                        nng = cg * 0.55
                        nnb = cb * 0.55
                        if nnr < 0.25 then nnr = 0.25 end
                        if nng < 0.25 then nng = 0.25 end
                        if nnb < 0.25 then nnb = 0.25 end
                    end
                    if c.nnr ~= nnr or c.nng ~= nng or c.nnb ~= nnb then
                        c.nnr, c.nng, c.nnb = nnr, nng, nnb
                        row.nm:SetTextColor(nnr, nng, nnb)
                    end

                    -- Timer
                    local tmTxt, tr, tg, tb
                    if not e then
                        tmTxt = "-"
                        tr = cr * 0.45; tg = cg * 0.45; tb = cb * 0.45
                        if tr < 0.2 then tr = 0.2 end
                        if tg < 0.2 then tg = 0.2 end
                        if tb < 0.2 then tb = 0.2 end
                    elseif e.ready then
                        tmTxt = "READY"
                        tr, tg, tb = 0.2, 1, 0.2
                    else
                        local rem  = e.expireAt - now
                        local m    = _floor(rem / 60)
                        local s    = _floor(_mod(rem, 60))
                        tmTxt = m .. secStr[s]
                        local frac = rem / e.cd
                        if frac > 0.5 then
                            tr, tg, tb = 1, 0.2, 0.2
                        elseif frac > 0.2 then
                            tr, tg, tb = 1, 0.6, 0.1
                        else
                            tr, tg, tb = 0.8, 0.8, 0.2
                        end
                    end
                    if c.tm ~= tmTxt then
                        c.tm = tmTxt
                        row.tm:SetText(tmTxt)
                    end
                    if c.tr ~= tr or c.tg ~= tg or c.tb ~= tb then
                        c.tr, c.tg, c.tb = tr, tg, tb
                        row.tm:SetTextColor(tr, tg, tb)
                    end

                    if not c.visible then
                        c.visible = true
                        row:Show()
                    end
                    yOff = yOff - CDT_ROW_H

                else
                    -- Hide surplus rows in this block
                    if c.visible then
                        c.visible  = false
                        c.nm       = ""
                        c.tm       = ""
                        c.tr       = -1
                        c.nnr      = -1
                        c.yOff     = nil
                        c.lblShown = nil
                        row:Hide()
                    end
                end
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

    -- ── Body ──
    CDT_BODY = CreateFrame("Frame", "CDTBody", CDT_FRAME)
    CDT_BODY:SetWidth(CDT_W)
    CDT_BODY:SetHeight(10)   -- resized by CDT_ResizeFrame
    CDT_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, -CDT_HDR_H)
    local bodyBg = CDT_BODY:CreateTexture(nil, "BACKGROUND")
    bodyBg:SetAllPoints(CDT_BODY)
    bodyBg:SetTexture(0.02, 0.02, 0.04, 0.85)

    -- ── Preallocate all row frames ──
    -- 9 spells × CDT_MAX_ROWS_PER_SPELL rows each.
    -- Each row carries: .bg .icon .lbl .nm .tm
    local defs  = CDT_SPELL_DEFS
    local nDefs = _getn(defs)

    for si = 1, nDefs do
        local def = defs[si]
        CDT_BLOCK_ROWS[si] = {}
        CDT_ROW_CACHE[si]  = {}

        for ri = 1, CDT_MAX_ROWS_PER_SPELL do
            local row = CreateFrame("Frame", "CDTRow_"..si.."_"..ri, CDT_BODY)
            row:SetWidth(CDT_W)
            row:SetHeight(CDT_ROW_H)
            row:SetPoint("TOPLEFT", CDT_BODY, "TOPLEFT", 0, 0)

            -- Class-tinted row background
            -- First row of a block is slightly brighter to visually mark the group start
            local shade
            if ri == 1 then
                shade = 0.20
            elseif _mod(ri, 2) == 0 then
                shade = 0.12
            else
                shade = 0.09
            end
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            bg:SetTexture(def.cr * shade, def.cg * shade, def.cb * shade, 0.95)
            row.bg = bg

            -- Thin class-coloured left stripe for group identity
            local stripe = row:CreateTexture(nil, "BORDER")
            stripe:SetWidth(2)
            stripe:SetHeight(CDT_ROW_H)
            stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            stripe:SetTexture(def.cr * 0.8, def.cg * 0.8, def.cb * 0.8, 0.9)

            -- Spell icon (shown only on first row of block)
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(CDT_ICON_SZ); icon:SetHeight(CDT_ICON_SZ)
            icon:SetPoint("LEFT", row, "LEFT", CDT_ICON_X + 2, 0)
            icon:SetTexture("Interface\\Icons\\" .. def.icon)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim border
            row.icon = icon

            -- Spell label (shown only on first row of block)
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", row, "LEFT", CDT_LBL_X + 2, 0)
            lbl:SetWidth(CDT_LBL_W)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(def.label)
            lbl:SetTextColor(
                0.55 + def.cr * 0.45,
                0.55 + def.cg * 0.45,
                0.55 + def.cb * 0.45
            )
            row.lbl = lbl

            -- Player name
            local nm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nm:SetPoint("LEFT", row, "LEFT", CDT_NM_X, 0)
            nm:SetWidth(CDT_NM_W)
            nm:SetJustifyH("LEFT")
            row.nm = nm

            -- Timer (right-anchored)
            local tm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tm:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            tm:SetWidth(CDT_TM_W)
            tm:SetJustifyH("RIGHT")
            row.tm = tm

            row:Hide()
            CDT_BLOCK_ROWS[si][ri] = row

            CDT_ROW_CACHE[si][ri] = {
                nm       = "",
                tm       = "",
                tr=-1, tg=-1, tb=-1,
                nnr=-1, nng=-1, nnb=-1,
                visible  = false,
                lblShown = nil,
                yOff     = nil,   -- last yOff passed to SetPoint; nil forces first paint
            }
        end
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
            if CDT_MODE_MO and not CDT_MOUSEOVER then
                CDT_SetBodyVisible(false)
            end
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
        end
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
    local cfgH = 156 + 8 + spellCount * 14 + 4
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

    MakeDivider(-85)

    local readyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readyLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -90)
    readyLbl:SetTextColor(0.8, 0.8, 1); readyLbl:SetText("Ready:")

    local readyOpts = CDT_READY_OPTS
    for idx = 1, _getn(readyOpts) do
        local mode = readyOpts[idx]
        local btn = CreateFrame("Button", "CDTReadyBtn"..idx, f)
        btn:SetWidth(56); btn:SetHeight(14)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 3 + (idx-1)*62, -103)
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
    descOn:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -121)
    descOn:SetTextColor(0.45, 0.45, 0.55); descOn:SetWidth(198)
    descOn:SetJustifyH("LEFT"); descOn:SetText("on: keep row with READY text")

    local descOff = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descOff:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -131)
    descOff:SetTextColor(0.45, 0.45, 0.55); descOff:SetWidth(198)
    descOff:SetJustifyH("LEFT"); descOff:SetText("off: remove row 10s after READY")

    MakeDivider(-143)

    local spellsLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellsLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -148)
    spellsLbl:SetTextColor(0.8, 0.8, 1); spellsLbl:SetText("Track spells:")

    CDT_CFG_SPELL_CHKS = {}
    for i = 1, spellCount do
        local def  = CDT_SPELL_DEFS[i]
        local yOff = -148 - 4 - i * 14

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
        end)

        CDT_CFG_SPELL_CHKS[i] = { box=box, lbl=lbl, key=def.key }
    end

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
end

-- ── Events ────────────────────────────────────────────────────────────────────

local ev = CreateFrame("Frame", "CDTEventFrame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_CASTEVENT")

ev:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        CDT_InitDB()
        if not CDT_READY then CDT_Build() end
        DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CoolDownTracker]|r ready - /cdt for help")
        CDT_UpdateVisibility()
        return
    end
    if arg3 == "CAST" then
        local spellId = tonumber(arg4)
        if not CDT_IDS[spellId] then return end

        local casterGuid = arg1
        local targetGuid = arg2
        local name       = nil
        local targetName = nil
        local raidUnits  = CDT_RAID_UNITS

        for i = 1, 40 do
            local unit    = raidUnits[i]
            local _, guid = UnitExists(unit)
            if guid then
                if not name and casterGuid == guid then
                    name = UnitName(unit)
                end
                if not targetName and targetGuid and targetGuid ~= ""
                   and targetGuid == guid then
                    targetName = UnitName(unit)
                end
            end
            -- Early exit once both resolved
            if name and (targetName or not targetGuid or targetGuid == "") then break end
        end

        if not name then return end

        -- Soulstone target might be the player themselves
        if not targetName and targetGuid and targetGuid ~= "" then
            local _, pguid = UnitExists("player")
            if pguid == targetGuid then
                targetName = UnitName("player")
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
        end
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
        CDT_AddEntry("Uther",     1022,  nil)
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
