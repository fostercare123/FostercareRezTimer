-- =========================================================================
-- Addon: FostercareRezTimer
-- Author: Fostercare
-- Version: 1.1
-- Description: Tracks enemy respawn waves in Battlegrounds
-- =========================================================================

-- Startup Confirmation
message("FostercareRezTimer: Loaded! Type /frt for commands.")

-- 1. Configuration & Constants
local Config = {
    Font       = "Fonts\\FRIZQT__.TTF",
    FontSize   = 18,
    TitleColor = "|cffFFFFFF", -- White (Labels)
    TimerColor = "|cffFFFFFF", -- White (Numbers)
    WarnColor  = "|cffEE0000", -- Red (< 5s remaining)
}

local deadEnemies = {}   -- Stores timestamps of enemy deaths
local lastUpdate  = 0    -- Throttle for OnUpdate script

-- 2. UI Frame Initialization
local f = CreateFrame("Frame", "FostercareRezFrame", UIParent)

f:SetWidth(150)
f:SetHeight(50)
f:SetPoint("CENTER", 0, 0)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:Hide() -- Default to hidden; shown only in active BGs

-- Frame Styling (Backdrop & Border)
f:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground", 
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", 
    tile     = true, tileSize = 16, edgeSize = 12, 
    insets   = { left = 3, right = 3, top = 3, bottom = 3 }
})
f:SetBackdropColor(0, 0, 0, 0.75)
f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

-- Text Display
f.text = f:CreateFontString(nil, "OVERLAY")
f.text:SetFont(Config.Font, Config.FontSize, "OUTLINE")
f.text:SetPoint("CENTER", 0, 0)

-- 3. Drag & Save Logic
f:SetScript("OnDragStart", function()
    -- Global 'this' is required for 1.12 compatibility
    if FostercareRezDB and not FostercareRezDB.locked then 
        this:StartMoving() 
    end
end)

f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    -- Save position to SavedVariables
    if FostercareRezDB then
        local point, _, relPoint, x, y = this:GetPoint()
        FostercareRezDB.point = point
        FostercareRezDB.relPoint = relPoint
        FostercareRezDB.x = x
        FostercareRezDB.y = y
    end
end)

-- 4. Helper Functions
local function InitDB()
    if not FostercareRezDB then 
        FostercareRezDB = { 
            point    = "CENTER", 
            relPoint = "CENTER", 
            x        = 0, 
            y        = 0, 
            locked   = false, 
            nextRez  = GetTime() + 30 
        } 
    end
end

local function CheckZone()
    local zone = GetZoneText()
    -- Optimize Performance: Only run the addon inside Battlegrounds
    if zone == "Warsong Gulch" or zone == "Arathi Basin" or zone == "Alterac Valley" then
        f:Show()
    else
        f:Hide()
    end
end

-- 5. Event Handling
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

-- Events for Auto-Sync
f:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
f:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF")

f:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        InitDB()
        this:ClearAllPoints()
        this:SetPoint(FostercareRezDB.point, UIParent, FostercareRezDB.relPoint, FostercareRezDB.x, FostercareRezDB.y)
        
        if FostercareRezDB.locked then 
            this:EnableMouse(false) 
        end
        
        CheckZone()
        DEFAULT_CHAT_FRAME:AddMessage("|cffBF3EFFFostercareRezTimer|r Hybrid Sync Ready!")

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        CheckZone()

    -- Track Enemy Deaths (Visual Counter)
    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        if this:IsVisible() then 
            table.insert(deadEnemies, GetTime()) 
        end

    -- Sync Method A: Combat Log Detection (While Alive)
    -- Detects "Spirit Guide casts Spirit Heal" from any nearby Spirit Healer
    elseif (event == "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF" or event == "CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF") then
        if string.find(arg1, "casts Spirit Heal") then
            FostercareRezDB.nextRez = GetTime() + 30.5
        end
    end
end)

-- 6. Commands (/frt)
SLASH_FOSTERCAREREZ1 = "/frt"
SlashCmdList["FOSTERCAREREZ"] = function(msg)
    InitDB()
    
    if msg == "lock" then
        FostercareRezDB.locked = not FostercareRezDB.locked
        f:EnableMouse(not FostercareRezDB.locked)
        
        local status = FostercareRezDB.locked and "LOCKED" or "UNLOCKED"
        DEFAULT_CHAT_FRAME:AddMessage("|cffBF3EFFFostercare:|r Window " .. status)
        
    elseif msg == "show" then
        f:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cffBF3EFFFostercare:|r Frame Shown")
        
    elseif msg == "hide" then
        f:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("|cffBF3EFFFostercare:|r Frame Hidden")
        
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffBF3EFFFostercare:|r Commands: /frt lock | /frt show | /frt hide")
    end
end

-- 7. Core Update Loop
f:SetScript("OnUpdate", function()
    -- Throttle updates to 0.1s to save CPU
    if (GetTime() - lastUpdate) < 0.1 then return end
    lastUpdate = GetTime()
    
    if not FostercareRezDB then return end
    local now = GetTime()

    -- Sync Method B: API Detection (While Dead)
    -- GetAreaSpiritHealerTime() returns the exact server timer when the player is dead.
    -- I use this to calibrate the loop with 100% accuracy.
    local realSpiritTime = GetAreaSpiritHealerTime()
    if realSpiritTime > 0 then
        FostercareRezDB.nextRez = now + realSpiritTime
    end
    
    -- Loop Maintenance (30.5s Cycle)
    if not FostercareRezDB.nextRez or now > FostercareRezDB.nextRez then
        FostercareRezDB.nextRez = now + 30.5
    end
    
    -- Cleanup Old Deaths (>32s)
    local count = 0
    local i = 1
    while i <= table.getn(deadEnemies) do
        if (now - deadEnemies[i]) > 32 then
            table.remove(deadEnemies, i)
        else
            count = count + 1
            i = i + 1
        end
    end
    
    -- Visual Updates
    local timeLeft = FostercareRezDB.nextRez - now
    local displayColor = (timeLeft < 5) and Config.WarnColor or Config.TimerColor
    
    f.text:SetText(string.format(
        "%sGY Timer: %s%.1f\n%sRessing: %s%d",
        Config.TitleColor, displayColor, timeLeft,
        Config.TitleColor, Config.TimerColor, count
    ))
end)
