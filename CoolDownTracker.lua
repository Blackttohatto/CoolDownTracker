-- CoolDownTracker (rewritten)
-- Summary-only cooldown tracker with independent PullCheck frame.

local _GetTime = GetTime
local _floor = math.floor
local _mod = math.mod
local _getn = table.getn
local _sub = string.sub

local CDT_Clear

local CDT_HDR_H = 16
local CDT_PAD = 1
local CDT_COL_W = 32
local CDT_ICON_SZ = 28
local CDT_SLOT_H = 52
local CDT_GAP_X = 1
local CDT_GAP_Y = 4

local PC_HDR_H = 14
local PC_ROW_H = 14
local PC_RANGE = 40
local CDT_UPDATE_INTERVAL = 5.0
local PC_UPDATE_INTERVAL = 3.0

CDT_SPELL_DEFS = {
    { key="cshout",             label="C.Shout",           cd=600,  icon="ability_bullrush",                cr=0.78, cg=0.61, cb=0.43 },
    { key="croar",              label="C.Roar",            cd=600,  icon="ability_druid_challangingroar",  cr=1.0,  cg=0.49, cb=0.04 },
    { key="disarm",             label="Disarm",            cd=60,   icon="ability_warrior_disarm",         cr=0.78, cg=0.61, cb=0.43 },
    { key="loh",                label="Lay on Hands*",     cd=3600, icon="spell_holy_layonhands",          cr=0.96, cg=0.55, cb=0.73 },
    { key="divineintervention", label="Div.Intervention",  cd=3600, icon="spell_nature_timestop",          cr=0.96, cg=0.55, cb=0.73 },
    { key="fearward",           label="Fear Ward",         cd=30,   icon="spell_holy_excorcism",            cr=1.0,  cg=1.0,  cb=1.0  },
    { key="spiritlink",         label="Spirit Link",       cd=180,  icon="spell_shaman_spiritlink",         cr=0.0,  cg=0.44, cb=0.87 },
    { key="innervate",          label="Innervate",         cd=360,  icon="spell_nature_lightning",          cr=1.0,  cg=0.49, cb=0.04 },
    { key="tranquility",        label="Tranquility*",      cd=1800, icon="spell_nature_tranquility",        cr=1.0,  cg=0.49, cb=0.04 },
    { key="reincarn",           label="Reincarnation*",    cd=3600, icon="spell_nature_reincarnation",      cr=0.0,  cg=0.44, cb=0.87 },
    { key="soulstone",          label="Soulstone",         cd=1800, icon="inv_misc_orb_04",                cr=0.58, cg=0.51, cb=0.79 },
    { key="rebirth",            label="Rebirth*",          cd=1800, icon="spell_nature_reincarnation",      cr=1.0,  cg=0.49, cb=0.04 },
}

local keyDefs = {}
for i = 1, _getn(CDT_SPELL_DEFS) do keyDefs[CDT_SPELL_DEFS[i].key] = CDT_SPELL_DEFS[i] end

CDT_IDS = {
    [1161]=keyDefs.cshout, [5209]=keyDefs.croar, [676]=keyDefs.disarm,
    [29166]=keyDefs.innervate, [20484]=keyDefs.rebirth, [20739]=keyDefs.rebirth,
    [20742]=keyDefs.rebirth, [20747]=keyDefs.rebirth, [20748]=keyDefs.rebirth,
    [633]=keyDefs.loh, [2800]=keyDefs.loh, [10310]=keyDefs.loh, [20234]=keyDefs.loh, [20235]=keyDefs.loh,
    [19752]=keyDefs.divineintervention, [6346]=keyDefs.fearward,
    [693]=keyDefs.soulstone, [20752]=keyDefs.soulstone, [20755]=keyDefs.soulstone, [20756]=keyDefs.soulstone, [20757]=keyDefs.soulstone,
    [20608]=keyDefs.reincarn, [51363]=keyDefs.spiritlink,
    [740]=keyDefs.tranquility, [8918]=keyDefs.tranquility, [9862]=keyDefs.tranquility, [9863]=keyDefs.tranquility,
}
keyDefs = nil

PC_HEAL_IDS = {
    [2061]=true,[9472]=true,[9473]=true,[9474]=true,[10915]=true,[10916]=true,[10917]=true,[25233]=true,[25235]=true,
    [1064]=true,[10622]=true,[10623]=true,[25422]=true,
    [774]=true,[1058]=true,[1430]=true,[2090]=true,[2091]=true,[3627]=true,[8910]=true,[9839]=true,[9840]=true,[25299]=true,
    [8936]=true,[8938]=true,[8939]=true,[8940]=true,[8941]=true,[9750]=true,[9856]=true,[9857]=true,[9858]=true,
    [5185]=true,[5186]=true,[5187]=true,[5188]=true,[5189]=true,[6778]=true,[8903]=true,[9758]=true,[9888]=true,[9889]=true,[25297]=true,
    [28562]=true,[28563]=true,
    [19750]=true,[19939]=true,[19940]=true,[19941]=true,[19942]=true,[19943]=true,[25514]=true,
    [635]=true,[639]=true,[647]=true,[1026]=true,[1042]=true,[3472]=true,[10328]=true,[10329]=true,[25292]=true,[27135]=true,
}

CDT_DB = CDT_DB or nil
CDT_FRAME = nil
CDT_BODY = nil
CDT_CFG = nil
CDT_CLEAR_CONFIRM = nil
CDT_SLOTS = {}
CDT_BY_KEY = {}
CDT_GUID_TO_NAME = {}
CDT_CFG_SPELL_BTNS = {}
CDT_ENABLED_DEFS = {}
CDT_ENABLED_DEFS_DIRTY = true

PC_FRAME = nil
PC_HEADER_TXT = nil
PC_HEALERS = {}
PC_DETECT_COUNTS = {}
PC_NAME_TO_UNIT = {}
PC_IN_COMBAT = false

CDT_RAID_UNITS = {}
for i = 1, 40 do CDT_RAID_UNITS[i] = "raid" .. i end

for i = 1, _getn(CDT_SPELL_DEFS) do
    CDT_BY_KEY[CDT_SPELL_DEFS[i].key] = {}
end

local function CDT_Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffaabbff[CDT]|r " .. msg)
end

local function CDT_InitDB()
    if not CDT_DB then CDT_DB = {} end
    if CDT_DB.x == nil then CDT_DB.x = 0 end
    if CDT_DB.y == nil then CDT_DB.y = 220 end
    if CDT_DB.shown == nil then CDT_DB.shown = true end
    if CDT_DB.cols == nil then CDT_DB.cols = 6 end
    if CDT_DB.rows == nil then CDT_DB.rows = 2 end
    if CDT_DB.spells == nil then CDT_DB.spells = {} end
    if CDT_DB.pullShown == nil then CDT_DB.pullShown = true end
    if CDT_DB.pcX == nil then CDT_DB.pcX = 260 end
    if CDT_DB.pcY == nil then CDT_DB.pcY = 220 end
    if CDT_DB.manaThresh == nil then CDT_DB.manaThresh = 50 end

    for i = 1, _getn(CDT_SPELL_DEFS) do
        local key = CDT_SPELL_DEFS[i].key
        if CDT_DB.spells[key] == nil then CDT_DB.spells[key] = true end
    end
    CDT_ENABLED_DEFS_DIRTY = true
end

local function CDT_BuildIndexes()
    for k in pairs(CDT_GUID_TO_NAME) do CDT_GUID_TO_NAME[k] = nil end
    for k in pairs(PC_NAME_TO_UNIT) do PC_NAME_TO_UNIT[k] = nil end

    local n = GetNumRaidMembers()
    if n and n > 0 then
        for i = 1, n do
            local unit = CDT_RAID_UNITS[i]
            local exists, guid = UnitExists(unit)
            if exists and guid then
                local name = UnitName(unit)
                if name then
                    CDT_GUID_TO_NAME[guid] = name
                    PC_NAME_TO_UNIT[name] = unit
                end
            end
        end
    end

    local pExists, pGuid = UnitExists("player")
    if pExists and pGuid then
        local pName = UnitName("player")
        if pName then
            CDT_GUID_TO_NAME[pGuid] = pName
            PC_NAME_TO_UNIT[pName] = "player"
        end
    end
end

local function Sec(rem)
    local m = _floor(rem / 60)
    local s = _floor(_mod(rem, 60))
    if s < 10 then return m .. ":0" .. s end
    return m .. ":" .. s
end

local function Short6(txt)
    if not txt then return "" end
    return _sub(txt, 1, 6)
end

local function CDT_AddEntry(casterName, spellId, targetName)
    local def = CDT_IDS[spellId]
    if not def then return end

    local list = CDT_BY_KEY[def.key]
    local now = _GetTime()
    local display = casterName
    if def.key == "soulstone" and targetName then
        display = casterName .. "(" .. targetName .. ")"
    end

    for i = 1, _getn(list) do
        local e = list[i]
        if e.name == casterName then
            e.displayName = display
            e.expireAt = now + def.cd
            e.ready = false
            return
        end
    end

    list[_getn(list) + 1] = {
        name = casterName,
        displayName = display,
        expireAt = now + def.cd,
        cd = def.cd,
        ready = false,
    }
end

local function CDT_SortAndUpdate(now)
    for i = 1, _getn(CDT_SPELL_DEFS) do
        local def = CDT_SPELL_DEFS[i]
        local list = CDT_BY_KEY[def.key]
        for j = 1, _getn(list) do
            local e = list[j]
            if (not e.ready) and now >= e.expireAt then e.ready = true end
        end

        table.sort(list, function(a, b)
            if a.ready ~= b.ready then return a.ready end
            return a.expireAt < b.expireAt
        end)
    end
end

local function CDT_RebuildEnabledDefs()
    for i = _getn(CDT_ENABLED_DEFS), 1, -1 do CDT_ENABLED_DEFS[i] = nil end
    for i = 1, _getn(CDT_SPELL_DEFS) do
        local def = CDT_SPELL_DEFS[i]
        if CDT_DB.spells[def.key] ~= false then
            CDT_ENABLED_DEFS[_getn(CDT_ENABLED_DEFS) + 1] = def
        end
    end
    CDT_ENABLED_DEFS_DIRTY = false
end

local function CDT_EnabledDefs()
    if CDT_ENABLED_DEFS_DIRTY then CDT_RebuildEnabledDefs() end
    return CDT_ENABLED_DEFS
end

local function CDT_SetMainPoint(frame, x, y)
    local uiScale = UIParent:GetScale()
    local sw = GetScreenWidth() * uiScale
    local sh = GetScreenHeight() * uiScale
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sw / 2 + x, sh / 2 + y)
end

local function CDT_ReadPoint(frame)
    local uiScale = UIParent:GetScale()
    local sw = GetScreenWidth() * uiScale
    local sh = GetScreenHeight() * uiScale
    local scale = frame:GetEffectiveScale()
    return frame:GetLeft() * scale - sw / 2, frame:GetTop() * scale - sh / 2
end

local function CDT_EnsureSlots(capacity)
    for i = _getn(CDT_SLOTS) + 1, capacity do
        local slot = CreateFrame("Frame", nil, CDT_BODY)
        slot:SetWidth(CDT_COL_W)
        slot:SetHeight(CDT_SLOT_H)
        slot:EnableMouse(true)

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(CDT_ICON_SZ)
        icon:SetHeight(CDT_ICON_SZ)
        icon:SetPoint("TOP", slot, "TOP", 0, 0)
        slot.icon = icon

        slot.text = {}
        for r = 1, 2 do
            local fs = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetWidth(CDT_COL_W)
            fs:SetJustifyH("CENTER")
            fs:SetPoint("TOP", slot, "TOP", 0, -(CDT_ICON_SZ + 2 + (r - 1) * 11))
            slot.text[r] = fs
        end

        slot:SetScript("OnEnter", function()
            if not slot.def then return end
            local now = _GetTime()
            local list = CDT_BY_KEY[slot.def.key]

            GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(slot.def.label)

            if _getn(list) == 0 then
                GameTooltip:AddLine("No tracked players", 0.7, 0.7, 0.7)
            else
                for j = 1, _getn(list) do
                    local e = list[j]
                    if e.ready or now >= e.expireAt then
                        GameTooltip:AddLine(e.displayName .. " - READY", 0.25, 1, 0.25)
                    else
                        GameTooltip:AddLine(e.displayName .. " - " .. Sec(e.expireAt - now), 1, 0.82, 0.45)
                    end
                end
            end

            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        CDT_SLOTS[i] = slot
    end
end

local function CDT_ResizeAndLayout()
    local cols = tonumber(CDT_DB.cols) or 6
    local rows = tonumber(CDT_DB.rows) or 2
    if cols < 1 then cols = 1 elseif cols > 12 then cols = 12 end
    if rows < 1 then rows = 1 elseif rows > 12 then rows = 12 end
    CDT_DB.cols = cols
    CDT_DB.rows = rows

    local bodyW = CDT_PAD * 2 + cols * CDT_COL_W + (cols - 1) * CDT_GAP_X
    local bodyH = CDT_PAD * 2 + rows * CDT_SLOT_H + (rows - 1) * CDT_GAP_Y
    CDT_FRAME:SetWidth(bodyW)
    CDT_FRAME:SetHeight(CDT_HDR_H + bodyH)
    CDT_BODY:SetWidth(bodyW)
    CDT_BODY:SetHeight(bodyH)
end

local function CDT_Redraw()
    if not CDT_FRAME or not CDT_DB.shown then return end
    local now = _GetTime()
    CDT_SortAndUpdate(now)

    local defs = CDT_EnabledDefs()
    local cap = (CDT_DB.cols or 6) * (CDT_DB.rows or 2)
    CDT_EnsureSlots(cap)

    for i = 1, cap do
        local slot = CDT_SLOTS[i]
        local def = defs[i]
        if def then
            local list = CDT_BY_KEY[def.key]
            local ready = {}
            local soonest = nil
            local soonestName = ""
            slot.def = def

            for j = 1, _getn(list) do
                local e = list[j]
                if e.ready then ready[_getn(ready) + 1] = Short6(e.displayName)
                elseif (not soonest) or e.expireAt < soonest then
                    soonest = e.expireAt
                    soonestName = Short6(e.displayName)
                end
            end

            slot.icon:SetTexture("Interface\\Icons\\" .. def.icon)
            slot:Show()

            local col = _mod(i - 1, CDT_DB.cols)
            local row = _floor((i - 1) / CDT_DB.cols)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", CDT_BODY, "TOPLEFT", CDT_PAD + col * (CDT_COL_W + CDT_GAP_X), -(CDT_PAD + row * (CDT_SLOT_H + CDT_GAP_Y)))

            if _getn(ready) > 0 then
                slot.text[1]:SetText(ready[1] or "")
                slot.text[2]:SetText(ready[2] or "")
                slot.text[1]:SetTextColor(0.2, 1, 0.2)
                slot.text[2]:SetTextColor(0.2, 1, 0.2)
            elseif soonest then
                local rem = soonest - now
                if rem < 0 then rem = 0 end
                slot.text[1]:SetText(soonestName)
                slot.text[2]:SetText(Sec(rem))
                slot.text[1]:SetTextColor(1, 0.85, 0.55)
                slot.text[2]:SetTextColor(1, 0.35, 0.2)
            else
                slot.text[1]:SetText("---")
                slot.text[2]:SetText("--")
                slot.text[1]:SetTextColor(0.5, 0.5, 0.5)
                slot.text[2]:SetTextColor(0.45, 0.45, 0.45)
            end
        else
            slot.def = nil
            slot:Hide()
        end
    end
end

local function PC_Poll()
    if not CDT_DB.pullShown or not PC_FRAME then return end
    local n = GetNumRaidMembers()
    if not n or n == 0 then
        PC_HEADER_TXT:SetText("H:0/0  M:0/0  P:0/0")
        return
    end

    local px, py, pz = UnitPosition("player")
    local range2 = PC_RANGE * PC_RANGE
    local manaThresh = (CDT_DB.manaThresh or 50) / 100

    local hTot, hIn, mIn, pIn = 0, 0, 0, 0
    for i = 1, n do
        local unit = CDT_RAID_UNITS[i]
        if UnitExists(unit) then
            local name = UnitName(unit)
            local inRange = false
            if px then
                local ux, uy, uz = UnitPosition(unit)
                if ux then
                    local dx, dy, dz = ux - px, uy - py, uz - pz
                    if dx * dx + dy * dy + dz * dz <= range2 then inRange = true end
                end
            end
            if inRange then pIn = pIn + 1 end

            if name and PC_HEALERS[name] then
                hTot = hTot + 1
                if inRange then
                    hIn = hIn + 1
                    local mana, manaMax = UnitMana(unit), UnitManaMax(unit)
                    if manaMax and manaMax > 0 and (mana / manaMax) >= manaThresh then mIn = mIn + 1 end
                end
            end
        end
    end

    PC_HEADER_TXT:SetText("H:" .. hIn .. "/" .. hTot .. "  M:" .. mIn .. "/" .. hIn .. "  P:" .. pIn .. "/" .. n)
end

local function PC_OnCombatStart()
    PC_IN_COMBAT = true
    for k in pairs(PC_DETECT_COUNTS) do PC_DETECT_COUNTS[k] = nil end
end

local function PC_OnCombatEnd()
    PC_IN_COMBAT = false
    for name, count in pairs(PC_DETECT_COUNTS) do
        if count >= 3 then PC_HEALERS[name] = true end
    end
    PC_Poll()
end

local function CDT_BuildConfig()
    local spellCount = _getn(CDT_SPELL_DEFS)
    local f = CreateFrame("Frame", "CDTConfigFrame", UIParent)
    f:SetWidth(220)
    f:SetHeight(120 + spellCount * 14)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0.05, 0.05, 0.1, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("CDT Layout")

    local function MakeInput(label, y, value)
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
        l:SetText(label)

        local eb = CreateFrame("EditBox", nil, f)
        eb:SetWidth(40)
        eb:SetHeight(16)
        eb:SetPoint("LEFT", l, "RIGHT", 8, 0)
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetText(tostring(value))

        local left = eb:CreateTexture(nil, "BACKGROUND")
        left:SetWidth(8); left:SetHeight(16); left:SetPoint("LEFT", eb, "LEFT", 0, 0)
        left:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        left:SetTexCoord(0.79, 0.97, 0.14, 0.27)
        local mid = eb:CreateTexture(nil, "BACKGROUND")
        mid:SetHeight(16); mid:SetPoint("LEFT", left, "RIGHT", 0, 0); mid:SetPoint("RIGHT", eb, "RIGHT", -8, 0)
        mid:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        mid:SetVertexColor(0, 0, 0)
        local right = eb:CreateTexture(nil, "BACKGROUND")
        right:SetWidth(8); right:SetHeight(16); right:SetPoint("RIGHT", eb, "RIGHT", 0, 0)
        right:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        right:SetTexCoord(0.04, 0.22, 0.14, 0.27)

        return eb
    end

    local colsEB = MakeInput("Columns", -34, CDT_DB.cols)
    local rowsEB = MakeInput("Rows", -56, CDT_DB.rows)
    local manaEB = MakeInput("Pull mana %", -78, CDT_DB.manaThresh)

    local spellTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -98)
    spellTitle:SetText("Tracked spells")

    for i = 1, spellCount do
        local def = CDT_SPELL_DEFS[i]
        local y = -98 - i * 14
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
        lbl:SetWidth(128)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(def.label)

        local btn = CreateFrame("Button", nil, f)
        btn:SetWidth(34); btn:SetHeight(12)
        btn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(btn)
        btn.txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.txt:SetAllPoints(btn)
        btn.key = def.key
        btn:SetScript("OnClick", function()
            CDT_DB.spells[btn.key] = not CDT_DB.spells[btn.key]
            CDT_ENABLED_DEFS_DIRTY = true
            if CDT_DB.spells[btn.key] then
                btn.bg:SetTexture(0.12, 0.35, 0.12, 0.95)
                btn.txt:SetText("on")
                btn.txt:SetTextColor(0.35, 1, 0.35)
            else
                btn.bg:SetTexture(0.3, 0.12, 0.12, 0.95)
                btn.txt:SetText("off")
                btn.txt:SetTextColor(1, 0.45, 0.45)
            end
            CDT_Redraw()
        end)
        CDT_CFG_SPELL_BTNS[i] = btn
    end

    local apply = CreateFrame("Button", nil, f)
    apply:SetWidth(60); apply:SetHeight(16)
    apply:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    local abg = apply:CreateTexture(nil, "BACKGROUND")
    abg:SetAllPoints(apply); abg:SetTexture(0.12, 0.3, 0.12, 0.95)
    local at = apply:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    at:SetAllPoints(apply); at:SetText("Apply")
    apply:SetScript("OnClick", function()
        CDT_DB.cols = tonumber(colsEB:GetText()) or CDT_DB.cols
        CDT_DB.rows = tonumber(rowsEB:GetText()) or CDT_DB.rows
        CDT_DB.manaThresh = tonumber(manaEB:GetText()) or CDT_DB.manaThresh
        CDT_ResizeAndLayout()
        CDT_Redraw()
        PC_Poll()
    end)

    local close = CreateFrame("Button", nil, f)
    close:SetWidth(60); close:SetHeight(16)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    local cbg = close:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints(close); cbg:SetTexture(0.3, 0.12, 0.12, 0.95)
    local ct = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ct:SetAllPoints(close); ct:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnShow", function()
        colsEB:SetText(tostring(CDT_DB.cols))
        rowsEB:SetText(tostring(CDT_DB.rows))
        manaEB:SetText(tostring(CDT_DB.manaThresh))
        for i = 1, _getn(CDT_CFG_SPELL_BTNS) do
            local btn = CDT_CFG_SPELL_BTNS[i]
            if CDT_DB.spells[btn.key] then
                btn.bg:SetTexture(0.12, 0.35, 0.12, 0.95)
                btn.txt:SetText("on")
                btn.txt:SetTextColor(0.35, 1, 0.35)
            else
                btn.bg:SetTexture(0.3, 0.12, 0.12, 0.95)
                btn.txt:SetText("off")
                btn.txt:SetTextColor(1, 0.45, 0.45)
            end
        end
    end)

    CDT_CFG = f
end

local function CDT_BuildMain()
    CDT_FRAME = CreateFrame("Frame", "CDTMainFrame", UIParent)
    CDT_FRAME:SetMovable(true)
    CDT_FRAME:EnableMouse(true)
    CDT_FRAME:RegisterForDrag("LeftButton")
    CDT_FRAME:SetScript("OnDragStart", function() CDT_FRAME:StartMoving() end)
    CDT_FRAME:SetScript("OnDragStop", function()
        CDT_FRAME:StopMovingOrSizing()
        CDT_DB.x, CDT_DB.y = CDT_ReadPoint(CDT_FRAME)
    end)

    local bg = CDT_FRAME:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(CDT_FRAME)
    bg:SetTexture(0.02, 0.02, 0.05, 0.9)

    local hdr = CreateFrame("Frame", nil, CDT_FRAME)
    hdr:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", CDT_FRAME, "TOPRIGHT", 0, 0)
    hdr:SetHeight(CDT_HDR_H)

    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(hdr)
    hbg:SetTexture(0.1, 0.1, 0.3, 0.95)

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", hdr, "LEFT", 5, 0)
    title:SetText("|cffaabbff[CDT]|r CoolDownTracker")

    local clr = CreateFrame("Button", nil, hdr)
    clr:SetWidth(28); clr:SetHeight(12)
    clr:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -32, -2)
    local clbg = clr:CreateTexture(nil, "BACKGROUND")
    clbg:SetAllPoints(clr); clbg:SetTexture(0.35, 0.1, 0.1, 0.95)
    local clt = clr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clt:SetAllPoints(clr); clt:SetText("CLR")

    local cfg = CreateFrame("Button", nil, hdr)
    cfg:SetWidth(28); cfg:SetHeight(12)
    cfg:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -2, -2)
    local cbg = cfg:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints(cfg); cbg:SetTexture(0.2, 0.2, 0.45, 0.95)
    local cfs = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cfs:SetAllPoints(cfg); cfs:SetText("CFG")
    cfg:SetScript("OnClick", function()
        if CDT_CFG:IsVisible() then CDT_CFG:Hide() else CDT_CFG:Show() end
    end)

    CDT_CLEAR_CONFIRM = CreateFrame("Frame", "CDTClearConfirm", UIParent)
    CDT_CLEAR_CONFIRM:SetWidth(130)
    CDT_CLEAR_CONFIRM:SetHeight(44)
    CDT_CLEAR_CONFIRM:SetFrameStrata("DIALOG")
    CDT_CLEAR_CONFIRM:Hide()

    local cfb = CDT_CLEAR_CONFIRM:CreateTexture(nil, "BACKGROUND")
    cfb:SetAllPoints(CDT_CLEAR_CONFIRM)
    cfb:SetTexture(0.08, 0.04, 0.04, 0.97)

    local cfl = CDT_CLEAR_CONFIRM:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cfl:SetPoint("TOP", CDT_CLEAR_CONFIRM, "TOP", 0, -7)
    cfl:SetText("Clear all data?")

    local yes = CreateFrame("Button", nil, CDT_CLEAR_CONFIRM)
    yes:SetWidth(40); yes:SetHeight(14)
    yes:SetPoint("BOTTOMLEFT", CDT_CLEAR_CONFIRM, "BOTTOMLEFT", 8, 6)
    local yb = yes:CreateTexture(nil, "BACKGROUND")
    yb:SetAllPoints(yes); yb:SetTexture(0.1, 0.4, 0.1, 0.95)
    local yt = yes:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yt:SetAllPoints(yes); yt:SetText("Yes")
    yes:SetScript("OnClick", function()
        CDT_Clear()
        CDT_CLEAR_CONFIRM:Hide()
    end)

    local no = CreateFrame("Button", nil, CDT_CLEAR_CONFIRM)
    no:SetWidth(40); no:SetHeight(14)
    no:SetPoint("BOTTOMRIGHT", CDT_CLEAR_CONFIRM, "BOTTOMRIGHT", -8, 6)
    local nb = no:CreateTexture(nil, "BACKGROUND")
    nb:SetAllPoints(no); nb:SetTexture(0.3, 0.1, 0.1, 0.95)
    local nt = no:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nt:SetAllPoints(no); nt:SetText("No")
    no:SetScript("OnClick", function() CDT_CLEAR_CONFIRM:Hide() end)

    clr:SetScript("OnClick", function()
        if CDT_CLEAR_CONFIRM:IsVisible() then
            CDT_CLEAR_CONFIRM:Hide()
        else
            CDT_CLEAR_CONFIRM:ClearAllPoints()
            CDT_CLEAR_CONFIRM:SetPoint("TOP", CDT_FRAME, "BOTTOM", 0, -2)
            CDT_CLEAR_CONFIRM:Show()
        end
    end)

    CDT_BODY = CreateFrame("Frame", nil, CDT_FRAME)
    CDT_BODY:SetPoint("TOPLEFT", CDT_FRAME, "TOPLEFT", 0, -CDT_HDR_H)
    local bbg = CDT_BODY:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints(CDT_BODY)
    bbg:SetTexture(0.04, 0.04, 0.08, 0.92)

    CDT_SetMainPoint(CDT_FRAME, CDT_DB.x, CDT_DB.y)
    CDT_ResizeAndLayout()
    if CDT_DB.shown then CDT_FRAME:Show() else CDT_FRAME:Hide() end

    CDT_BuildConfig()
end

local function PC_BuildFrame()
    PC_FRAME = CreateFrame("Frame", "CDTPullCheckFrame", UIParent)
    PC_FRAME:SetWidth(170)
    PC_FRAME:SetHeight(PC_HDR_H + PC_ROW_H)
    PC_FRAME:SetMovable(true)
    PC_FRAME:EnableMouse(true)
    PC_FRAME:RegisterForDrag("LeftButton")
    PC_FRAME:SetScript("OnDragStart", function() PC_FRAME:StartMoving() end)
    PC_FRAME:SetScript("OnDragStop", function()
        PC_FRAME:StopMovingOrSizing()
        CDT_DB.pcX, CDT_DB.pcY = CDT_ReadPoint(PC_FRAME)
    end)

    local bg = PC_FRAME:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(PC_FRAME)
    bg:SetTexture(0.03, 0.07, 0.03, 0.9)

    local hdr = CreateFrame("Frame", nil, PC_FRAME)
    hdr:SetPoint("TOPLEFT", PC_FRAME, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", PC_FRAME, "TOPRIGHT", 0, 0)
    hdr:SetHeight(PC_HDR_H)

    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(hdr)
    hbg:SetTexture(0.08, 0.14, 0.08, 0.95)

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    title:SetText("PullCheck")
    title:SetTextColor(0.6, 0.9, 0.6)

    PC_HEADER_TXT = PC_FRAME:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PC_HEADER_TXT:SetPoint("TOPLEFT", PC_FRAME, "TOPLEFT", 4, -(PC_HDR_H + 1))
    PC_HEADER_TXT:SetWidth(160)
    PC_HEADER_TXT:SetJustifyH("LEFT")
    PC_HEADER_TXT:SetText("H:0/0  M:0/0  P:0/0")

    CDT_SetMainPoint(PC_FRAME, CDT_DB.pcX, CDT_DB.pcY)
    if CDT_DB.pullShown then PC_FRAME:Show() else PC_FRAME:Hide() end
end

local ticker = CreateFrame("Frame", "CDTTickerFrame")
local cdtAcc = 0
local pcAcc = 0

ticker:SetScript("OnUpdate", function()
    cdtAcc = cdtAcc + arg1
    pcAcc = pcAcc + arg1

    if CDT_DB and CDT_DB.shown and cdtAcc >= CDT_UPDATE_INTERVAL then
        cdtAcc = 0
        CDT_Redraw()
    end

    if CDT_DB and CDT_DB.pullShown and pcAcc >= PC_UPDATE_INTERVAL then
        pcAcc = 0
        PC_Poll()
    end
end)

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
        CDT_BuildIndexes()
        if not CDT_FRAME then CDT_BuildMain() end
        if not PC_FRAME then PC_BuildFrame() end
        CDT_Redraw()
        PC_Poll()
        CDT_Print("loaded. /cdt for commands")
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        CDT_BuildIndexes()
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

    if event == "UNIT_CASTEVENT" and arg3 == "CAST" then
        local spellId = tonumber(arg4)
        local name = CDT_GUID_TO_NAME[arg1]

        if spellId and name and CDT_IDS[spellId] then
            local targetName = nil
            if arg2 and arg2 ~= "" then targetName = CDT_GUID_TO_NAME[arg2] end
            CDT_AddEntry(name, spellId, targetName)
            CDT_Redraw()
        end

        if spellId and name and PC_IN_COMBAT and PC_HEAL_IDS[spellId] then
            PC_DETECT_COUNTS[name] = (PC_DETECT_COUNTS[name] or 0) + 1
        end
    end
end)

function CDT_Clear()
    for i = 1, _getn(CDT_SPELL_DEFS) do
        local list = CDT_BY_KEY[CDT_SPELL_DEFS[i].key]
        for j = _getn(list), 1, -1 do list[j] = nil end
    end
    CDT_Redraw()
end

SLASH_CDTRACKER1 = "/cdt"
SLASH_CDTRACKER2 = "/cooldowntracker"
SlashCmdList["CDTRACKER"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "" or msg == "toggle" then
        CDT_DB.shown = not CDT_DB.shown
        if CDT_DB.shown then CDT_FRAME:Show() else CDT_FRAME:Hide() end
        return
    elseif msg == "cfg" or msg == "config" then
        if CDT_CFG:IsVisible() then CDT_CFG:Hide() else CDT_CFG:Show() end
        return
    elseif msg == "clear" then
        CDT_Clear()
        CDT_Print("entries cleared")
        return
    elseif msg == "pc" or msg == "pull" then
        CDT_DB.pullShown = not CDT_DB.pullShown
        if CDT_DB.pullShown then PC_FRAME:Show() else PC_FRAME:Hide() end
        return
    elseif msg == "reset" then
        CDT_DB.x, CDT_DB.y = 0, 220
        CDT_DB.pcX, CDT_DB.pcY = 260, 220
        CDT_SetMainPoint(CDT_FRAME, CDT_DB.x, CDT_DB.y)
        CDT_SetMainPoint(PC_FRAME, CDT_DB.pcX, CDT_DB.pcY)
        return
    elseif msg == "test" then
        CDT_AddEntry("Thrall", 1161)
        CDT_AddEntry("Uther", 633)
        CDT_AddEntry("Malfurion", 20484)
        CDT_AddEntry("Anduin", 6346)
        CDT_Redraw()
        return
    end

    CDT_Print("commands: /cdt, /cdt cfg, /cdt clear, /cdt pc, /cdt reset, /cdt test")
end
