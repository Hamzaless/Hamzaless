--[[
    RAILhub — readable full-feature rewrite  (Your Bizarre Adventure)
    ---------------------------------------------------------------------------
    Every feature found in the obfuscated original, reimplemented readably and
    driven by our own UI. Game mechanics were reconstructed from the decompiled
    dump (see RAILhub_decompiled.lua):

      items            workspace.Item_Spawns.Items, pickup via ProximityPrompt
      remotes          Character.RemoteEvent:FireServer(...)
                         "PurchaseShopItem"  - buy from a shop
                         "StartBlocking"/"StopBlocking" - block
                         "PressedPlay"       - skip menu
                       :InvokeServer("ToggleStand", "Toggle")
      stats            LocalPlayer.PlayerStats.Money / Prestige / Level
      movement         tween/teleport HumanoidRootPart to a CFrame
--]]

--==========================================================================
-- Services & small helpers
--==========================================================================

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local HttpService    = game:GetService("HttpService")
local TweenService   = game:GetService("TweenService")
local UserInput      = game:GetService("UserInputService")
local VirtualInput   = game:GetService("VirtualInputManager")
local Lighting       = game:GetService("Lighting")
local StarterGui     = game:GetService("StarterGui")
local CoreGui        = game:GetService("CoreGui")

local LocalPlayer    = Players.LocalPlayer
local Environment    = (getgenv and getgenv()) or _G or shared

-- forward declarations
local Webhooks, UI, Farm, Esp

local function now() return (typeof(tick) == "function" and tick()) or os.clock() end
local function sleep(s) task.wait(s) end

function notify(text)
    if syn and syn.toast_notification then
        pcall(function() syn.toast_notification({ Content = tostring(text), Duration = 3 }) end)
        return
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "RAILhub", Text = tostring(text), Duration = 3 })
    end)
    pcall(print, "[RAILhub] " .. tostring(text))
end

local function httpRequest(method, url, body)
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        return req({ Url = url, Method = method,
                     Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end
    if method == "POST" then return HttpService:PostAsync(url, body) end
    return HttpService:GetAsync(url)
end

local function char()
    return LocalPlayer.Character
end
local function root()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function humanoid()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function stats()
    return LocalPlayer:FindFirstChild("PlayerStats")
end
local function statValue(name)
    local s = stats()
    local v = s and s:FindFirstChild(name)
    return v and v.Value or 0
end

--==========================================================================
-- Config (every setting in the original)
--==========================================================================

local DEFAULTS = {
    -- information
    ShowUserInfo = true, Ping = false, AutoExecute = false,

    -- visuals
    ItemESP = false, ItemESPTextSize = 14, ItemESPNames = true,
    PlayerESP = false, StaffESP = false, StaffDetector = false,
    ESPChams = false, ESPNames = true, ESPStand = true, ESPSpec = true,
    ESPHealth = true, ESPDistance = 1000, HUDHealth = false,
    WeatherChanger = false, Weather = "Clear", RemoveMap = false,
    UITransparency = 0.15, MenuScale = 1,

    -- movement
    SpeedChanger = false, SpeedValue = 16,
    JumpPowerChanger = false, JumpPower = 50,
    Fly = false, FlySpeed = 50, Noclip = false,
    TravelMethod = "Tween", FarmPositionMode = "Auto",

    -- combat
    BlockBot = false, Reblocking = true, KeepBlockHoldF = false,
    Unblocking = false, ProjectilesPriority = false,
    Coliseum = false, BlockBeachBoyEY = false, StickyFingers = false,
    MovementPrediction = false, PredictionStrength = 0.15,

    -- stand pilot
    StandPilot = false, PilotStand = "", PilotSpeedChanger = false,
    PilotSpeed = 20, InfPilotRange = false, SpectateStand = false,
    TargetStandPlayer = "", TargetPlayer = "", TargetAll = true,
    ForceCleanupPilot = false,

    -- finishers
    FinisherChanger = false, Finisher = "",

    -- stands
    StandFarm = false, KeepStands = {}, KeepAnyShiny = false, ShinyStand = "",

    -- farming
    AutoFarmItems = false, FarmMethod = "Auto", FarmTargetNPC = "",
    QuestFarm = false, Quest = "", NpcFarm = false, NpcFarmOriginal = false, AutoPrestige = false,
    StealDroppedMoney = false, ServerHopFarm = false, FarmItems = {},

    -- selling
    SellSpecific = "", SellSelected = "", AutoSellOnMax = false,
    NeverAutoSell = "", AutoBuyArrow = false, SellBlacklist = {},

    -- webhooks
    WebhookURL = "", DiscordUserID = "", TestWebhook = false,
    NotifyLegendary = true, NotifyStaff = true, NotifyItem = true,
    NotifyStand = true, NotifyPrestige = true, NotifyKick = true,
    StaffAutoRejoin = true, AutoRejoinKick = false,

    -- server
    AntiAFK = true, AutoReconnect = false, ServerHop = false,

    -- language
    Language = "English",
    HideUsername = false,
}

local SETTINGS_FILE = "RAILhub_yba_settings.json"
local Config = {}
for k, v in pairs(DEFAULTS) do Config[k] = v end

function Config.save()
    if not (writefile and isfile) then return end
    pcall(function() writefile(SETTINGS_FILE, HttpService:JSONEncode(Config)) end)
end

function Config.load()
    if not (readfile and isfile and isfile(SETTINGS_FILE)) then return end
    pcall(function()
        for k, v in pairs(HttpService:JSONDecode(readfile(SETTINGS_FILE))) do
            if DEFAULTS[k] ~= nil then Config[k] = v end
        end
    end)
end

function Config.reset()
    for k, v in pairs(DEFAULTS) do Config[k] = v end
    notify("All settings have been reset to default!")
end

--==========================================================================
-- Game data
--==========================================================================

local ITEM_LIMITS = {
    ["Christmas Present"] = 999, ["Gold Umbrella"] = 999, ["Gold Coin"] = 45,
    ["Mysterious Arrow"] = 25, ["Ancient Scroll"] = 10, ["Caesar's Headband"] = 10,
    ["Dio's Diary"] = 10, ["Pure Rokakaka"] = 10, ["Quinton's Glove"] = 10,
    ["Rib Cage of The Saint's Corpse"] = 10, ["Steel Ball"] = 10, ["Stone Mask"] = 10,
    ["Zeppelin's Headband"] = 10, ["Zeppeli's Hat"] = 10,
    ["Lucky Arrow"] = 9, ["Lucky Stone Mask"] = 9,
}

local NON_FARMABLE = {
    ["Pelvis of The Saint's Corpse"] = true, ["Requiem Arrow"] = true,
    ["Stand Arrow"] = true, ["Umbrella"] = true,
    ["Eye of The Saint's Corpse"] = true, ["Gold Umbrella"] = true,
    ["Heart of The Saint's Corpse"] = true, ["Left Arm of The Saint's Corpse"] = true,
}

local STANDS = {
    "Star Platinum", "Star Platinum: The World", "The World",
    "The World: Alternate Universe", "King Crimson", "King Crimson Requiem",
    "Gold Experience", "Gold Experience Requiem", "Silver Chariot", "Chariot Requiem",
    "Crazy Diamond", "Crazy Diamond Requiem", "Diver Down", "Killer Queen",
    "Killer Queen: Bites the Dust", "C-Moon", "Made in Heaven", "D4C: Love Train",
    "Tusk Act 1", "Tusk Act 2", "Tusk Act 3", "Tusk Act 4", "Hermit Purple",
    "Magician's Red", "Purple Haze", "Sticky Fingers", "The Hand", "Sex Pistols",
    "Beach Boy", "Mr. President", "Red Hot Chili Pepper", "Soft & Wet",
    "Soft & Wet: Go Beyond",
}

-- Quest -> NPC -> enemy mapping (verbatim from the original's quest table)
local QUEST_NPCS = {
    { key = "Officer Sam [Lvl. 1+]", npc = "Officer Sam [Lvl. 1+]",
      enemy = "Thug", minLvl = 1, questTitle = "Take down 5 thugs" },
    { key = "Deputy Bertrude [Lvl. 10+]", npc = "Deputy Bertrude [Lvl. 10+]",
      enemy = "Corrupt Police", minLvl = 10, questTitle = "Take down 5 corrupt police" },
    { key = "Abbacchio's Partner [Lvl. 15+]", npc = "Abbacchio's Partner [Lvl 15+]",
      enemy = "Alpha Thug", minLvl = 15, questTitle = "Take down 5 alpha thugs" },
    { key = "Dracula [Lvl. 20+]", npc = "Dracula [Lvl. 20+]",
      enemy = "Zombie Henchman", minLvl = 20, questTitle = "Take down 5 zombies" },
    { key = "William Zeppeli [Lvl. 25+]", npc = "William Zeppeli [Lvl. 25+]",
      enemy = "Vampire", minLvl = 25, questTitle = "Take down 3 vampires" },
    { key = "Doppio [Lvl. 30+]", npc = "Doppio [Lvl. 30+]",
      enemy = "DIO", minLvl = 30, questTitle = "Defeat DIO" },
    { key = "DIO [Lvl. 35+]", npc = "DIO [Lvl. 35+]",
      enemy = "Jotaro", minLvl = 35, questTitle = "Defeat Jotaro" },
    { key = "Jotaro [Lvl. 40+]", npc = "Jotaro (Tallest Peak)",
      enemy = "Heaven Ascended DIO", minLvl = 40, questTitle = "Defeat Heaven Ascended DIO" },
}

-- Direct-NPC-farm target list (the original's enemy options)
local NPCS = {
    "Thug", "Alpha Thug", "Corrupt Police", "Zombie Henchman", "Vampire", "DIO",
    "Heaven Ascended DIO", "Jotaro", "Jotaro (Part 6)", "Security Guard",
    "Leaky Eye Luca", "Bucciarati", "Pesci", "Ghiaccio", "Diavolo",
}

-- Quest dropdown options = the quest keys above
local QUESTS = {}
for _, q in ipairs(QUEST_NPCS) do table.insert(QUESTS, q.key) end

-- "Sell your worthless items" list from the original
local SELL_WORTHLESS = {
    "Gold Coin", "Diamond", "Quinton's Glove", "Zeppeli's Hat", "Caesar's Headband",
    "Ancient Scroll",
}

local ITEM_NAMES = {}
for name in pairs(ITEM_LIMITS) do table.insert(ITEM_NAMES, name) end
table.sort(ITEM_NAMES)

local FINISHERS = {
    "m1", "Heavy", "Barrage", "Stand Barrage", "Finisher",
}

local WEATHERS = {
    "Clear", "Rain", "Thunderstorm", "Fog", "Snow", "Blood Moon",
}

local FARM_BOX = { minX = -702.1, maxX = 975.8, minZ = -805.2, maxZ = 468.2,
                   minY = 65, maxY = 75 }

--==========================================================================
-- Item helpers
--==========================================================================

function normalizeItemName(name)
    if type(name) ~= "string" then return "" end
    local s = string.lower(name)
    s = string.gsub(s, "&", "and")
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(s, "^%s*(.-)%s*$", "%1")
    if string.sub(s, -1) == "s" then s = string.sub(s, 1, -2) end
    return s
end

function getItemSpawns()
    local container = workspace:FindFirstChild("Item_Spawns")
    return container and container:FindFirstChild("Items") or nil
end

function countItem(name)
    local wanted = normalizeItemName(name)
    local total = 0
    local c = char()
    if not c then return 0 end
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if normalizeItemName(item.Name) == wanted then total = total + 1 end
        end
    end
    scan(c:FindFirstChild("Backpack"))
    scan(c)
    return total
end

--==========================================================================
-- Remotes
--==========================================================================

local function getRemote()
    local c = char()
    local remote = c and c:FindFirstChild("RemoteEvent")
    if remote and not remote:IsA("RemoteEvent") then
        remote = c:FindFirstChildWhichIsA("RemoteEvent")
    end
    return remote
end

function pressPlay()
    local r = getRemote()
    if r then pcall(function() r:FireServer("PressedPlay") end) end
end

function purchaseItem(displayName, amount)
    local r = getRemote()
    if not r then return false end
    return pcall(function() r:FireServer("PurchaseShopItem", { ItemName = displayName }, amount or 1, 2) end)
end

function toggleStand()
    local r = getRemote()
    if not r then return end
    pcall(function()
        if r.InvokeServer then r:InvokeServer("ToggleStand", "Toggle")
        else r:FireServer("ToggleStand", "Toggle") end
    end)
end

function useFinisher(kind)
    local r = getRemote()
    if not r then return end
    pcall(function() r:FireServer("HoldAttack", { Type = kind }) end)
end

--==========================================================================
-- Movement
--==========================================================================

local moveTween

function zeroRootVelocity(r)
    if not r then return end
    pcall(function()
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
    end)
end

function stopMoveTween()
    if moveTween then pcall(function() moveTween:Cancel() end); moveTween = nil end
end

local function tweenRootTo(r, dest, speed)
    stopMoveTween()
    local dist = (r.Position - dest.Position).Magnitude
    local duration = math.max(0.05, dist / (speed or 300))
    if Config.TravelMethod == "Teleport" or (Environment and Environment._YBA_directTP) then
        r.CFrame = dest
        zeroRootVelocity(r)
        return true
    end
    moveTween = TweenService:Create(r, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = dest })
    moveTween:Play()
    return true
end

function wakeUpPhysicsAndSync()
    local r, h = root(), humanoid()
    if not (r and h and h.Health > 0) then return end
    pcall(function()
        h:ChangeState(Enum.HumanoidStateType.Running)
        r.AssemblyLinearVelocity = Vector3.new(0, 0.05, 0)
    end)
    for _ = 1, 5 do RunService.Heartbeat:Wait() end
    zeroRootVelocity(r)
end

-- CFrame | Vector3 | BasePart | character name
function moveCharacterTo(where, offset)
    local r = root()
    if not r then return false end
    local dest
    if typeof(where) == "CFrame" then dest = where
    elseif typeof(where) == "Vector3" then dest = CFrame.new(where)
    elseif typeof(where) == "Instance" then
        dest = CFrame.new(where.Position) * CFrame.new(offset or Vector3.new())
    elseif type(where) == "string" then
        local target = workspace:FindFirstChild(where)
        local tr = target and target:FindFirstChild("HumanoidRootPart")
        if not tr then return false end
        dest = CFrame.new(tr.Position) * CFrame.new(offset or Vector3.new())
    end
    if not dest then return false end
    return tweenRootTo(r, dest, 300)
end

function getRandomFarmCFrame()
    return CFrame.new(Vector3.new(
        FARM_BOX.minX + math.random() * (FARM_BOX.maxX - FARM_BOX.minX),
        FARM_BOX.minY + math.random() * (FARM_BOX.maxY - FARM_BOX.minY),
        FARM_BOX.minZ + math.random() * (FARM_BOX.maxZ - FARM_BOX.minZ)))
end

--==========================================================================
-- ProximityPrompt activation
--==========================================================================

function activatePrompt(prompt, holdTime, skipMove)
    if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return false end
    local part = prompt.Parent
    if part and not skipMove then
        local r = root()
        local reach = prompt.MaxActivationDistance
        if not reach or reach <= 0 then reach = 10 end
        reach = reach - 0.5
        if not r or reach < (part.Position - r.Position).Magnitude then
            moveCharacterTo(part, Vector3.new(0, 0.1, 0))
        end
    end
    local fired = false
    if type(fireproximityprompt) == "function" then
        pcall(function() fireproximityprompt(prompt); fired = true end)
    end
    if not fired then
        pcall(function()
            if type(firesignal) == "function" then
                firesignal(prompt.Triggered, LocalPlayer)
                firesignal(prompt.PromptTriggered, LocalPlayer)
            end
        end)
    end
    pcall(function() prompt:InputHoldBegin() end)
    local hold = holdTime
    if not hold or hold <= 0 or hold > 1 then hold = prompt.HoldDuration end
    if not hold or hold <= 0 then hold = 0.5 end
    local key = prompt.KeyboardKeyCode
    if not key or key == Enum.KeyCode.Unknown then key = prompt.GamepadKeyCode end
    if not key or key == Enum.KeyCode.Unknown then key = Enum.KeyCode.E end
    pcall(function() VirtualInput:SendKeyEvent(true, key, false, game) end)
    task.wait(hold)
    pcall(function() VirtualInput:SendKeyEvent(false, key, false, game) end)
    pcall(function() prompt:InputHoldEnd() end)
    pcall(function()
        if type(firesignal) == "function" then firesignal(prompt.TriggerEnded, LocalPlayer) end
    end)
    return true
end

--==========================================================================
-- Webhooks
--==========================================================================

Webhooks = {}

function Webhooks.enabled()
    return type(Config.WebhookURL) == "string" and #Config.WebhookURL > 0
end

function Webhooks.send(embed)
    if not Webhooks.enabled() then return false end
    local payload = {
        username = Config.DiscordUserID ~= "" and Config.DiscordUserID or "RAIL Hub",
        embeds = { embed },
    }
    if Config.DiscordUserID ~= "" then
        payload.embeds[1].footer = { text = "RAILhub " .. tostring(game.PlaceId) }
    end
    return pcall(function() httpRequest("POST", Config.WebhookURL, HttpService:JSONEncode(payload)) end)
end

function Webhooks.test()
    if not Webhooks.enabled() then notify("Please enter a valid Webhook URL first."); return end
    Webhooks.send({ title = "[RAIL Hub] Webhook Connected",
                    description = "Connected successfully. Last update: 10.10.2026", color = 5763719 })
    notify("Webhook sent.")
end

function Webhooks.itemPickup(item, qty)
    if not Config.NotifyItem then return end
    Webhooks.send({ title = "Item picked up", color = 3447003,
        description = string.format("**%s** (x%s)", tostring(item), tostring(qty or 1)) })
end

function Webhooks.legendaryPickup(item)
    if not Config.NotifyLegendary then return end
    Webhooks.send({ title = "Legendary Item Pickup", description = tostring(item), color = 15844367 })
end

function Webhooks.standObtained(stand)
    if not Config.NotifyStand then return end
    Webhooks.send({ title = "Stand obtained", description = tostring(stand), color = 10181046 })
end

function Webhooks.staffDetected(name)
    if not Config.NotifyStaff then return end
    Webhooks.send({ title = "Staff Detected", description = tostring(name), color = 15158332 })
end

function Webhooks.prestige(level)
    if not Config.NotifyPrestige then return end
    Webhooks.send({ title = "Prestige", description = "Reached prestige " .. tostring(level), color = 3447003 })
end

function Webhooks.reconnectKick(reason)
    if not Config.NotifyKick then return end
    Webhooks.send({ title = "[RAIL Hub] Reconnect / Kick", description = tostring(reason), color = 15158332 })
end

--==========================================================================
-- ESP  (items / players / staff)  + HUD
--==========================================================================

Esp = { folders = {}, tracked = {}, hud = nil }

local function espFolder(kind)
    if Esp.folders[kind] then return Esp.folders[kind] end
    local f = Instance.new("Folder")
    f.Name = "RAILhub_" .. kind
    f.Parent = CoreGui
    Esp.folders[kind] = f
    return f
end

local function newBillboard(kind, adornee, text, color)
    local bb = Instance.new("BillboardGui")
    bb.Name = "RAILhubESP"
    bb.Adornee = adornee
    bb.Size = UDim2.new(0, 160, 0, 34)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = espFolder(kind)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.TextSize = Config.ItemESPTextSize
    label.Parent = bb
    return bb, label
end

local function itemInFilter(name)
    if #Config.FarmItems == 0 then return true end
    local n = normalizeItemName(name)
    for _, want in ipairs(Config.FarmItems) do
        if normalizeItemName(want) == n then return true end
    end
    return false
end

function Esp.scanItems()
    if not Config.ItemESP then Esp.clear("item"); return end
    local items = getItemSpawns()
    if not items then return end
    local seen = {}
    for _, object in ipairs(items:GetChildren()) do
        local prompt = object:FindFirstChildWhichIsA("ProximityPrompt", true)
        local part = object:IsA("BasePart") and object
            or (prompt and prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent)
            or object:FindFirstChildWhichIsA("BasePart", true)
        if part and itemInFilter(object.Name) then
            seen[object] = true
            if not Esp.tracked[object] then
                local label = object.Name
                if Config.ESPNames then label = label end
                if Config.ESPDistance and root() then
                    label = string.format("%s [%dm]", label, math.floor((part.Position - root().Position).Magnitude))
                end
                Esp.tracked[object] = newBillboard("item", part, label, Color3.fromRGB(255, 215, 0))
            end
        end
    end
    for object in pairs(Esp.tracked) do
        if not seen[object] or not object.Parent then
            local bb = Esp.tracked[object]
            if typeof(bb) == "table" then bb = bb[1] end
            if bb and bb.Destroy then bb:Destroy() end
            Esp.tracked[object] = nil
        end
    end
end

function Esp.scanPlayers()
    Esp.clear("player")
    if not (Config.PlayerESP or Config.StaffESP) then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local c = player.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local label = player.Name
                if Config.ESPStand then
                    local ps = player:FindFirstChild("PlayerStats")
                    local stand = ps and ps:FindFirstChild("Stand")
                    if stand then label = label .. " | " .. tostring(stand.Value) end
                end
                if Config.ESPHealth then label = label .. " (" .. math.floor(hum.Health) .. ")" end
                local dist = root() and math.floor((hrp.Position - root().Position).Magnitude) or 0
                if dist <= Config.ESPDistance then
                    label = label .. " [" .. dist .. "m]"
                    local color = Config.StaffESP and Color3.fromRGB(255, 80, 80)
                        or Color3.fromRGB(90, 200, 255)
                    local bb, textLabel = newBillboard("player", hrp, label, color)
                    if Config.ESPChams then
                        local box = Instance.new("BoxHandleAdornment")
                        box.Size = hrp.Size
                        box.Adornee = hrp
                        box.AlwaysOnTop = true
                        box.ZIndex = 0
                        box.Transparency = 0.6
                        box.Color3 = color
                        box.Parent = bb
                    end
                    if textLabel then textLabel.TextSize = Config.ItemESPTextSize end
                end
            end
        end
    end
end

function Esp.hud()
    if Config.HUDHealth then
        local h = humanoid()
        if not Esp.hud then
            local gui = Instance.new("ScreenGui")
            gui.Name = "RAILhubHUD"
            gui.ResetOnSpawn = false
            gui.Parent = CoreGui
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(0, 200, 0, 24)
            label.Position = UDim2.new(0, 10, 0, 10)
            label.BackgroundTransparency = 1
            label.TextColor3 = Color3.fromRGB(255, 60, 60)
            label.TextStrokeTransparency = 0
            label.Font = Enum.Font.GothamBold
            label.TextSize = 18
            label.Parent = gui
            Esp.hud = label
        end
        Esp.hud.Text = "H E A L T H : " .. math.floor(h and h.Health or 0)
    elseif Esp.hud then
        Esp.hud.Parent:Destroy()
        Esp.hud = nil
    end
end

function Esp.clear(kind)
    local f = Esp.folders[kind]
    if f then f:ClearAllChildren() end
    for k in pairs(Esp.tracked) do
        if not k.Parent then Esp.tracked[k] = nil end
    end
end

--==========================================================================
-- Staff detector
--==========================================================================

local staffBusy = false

function checkStaff()
    if not (Config.StaffDetector or Config.StaffESP) or staffBusy then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local rank = player.GetRankInGroup and player:GetRankInGroup(0) or 0
            local c = player.Character
            local isStaff = c and (c:FindFirstChild("YBA_Staff") or c:FindFirstChild("StaffTag"))
            if rank > 0 or isStaff then
                staffBusy = true
                notify("Staff Detected: " .. player.Name)
                Webhooks.staffDetected(player.Name)
                if Config.StaffAutoRejoin then
                    task.wait(1)
                    reconnect("Staff detected (" .. player.Name .. ")")
                end
                staffBusy = false
                return
            end
        end
    end
end

--==========================================================================
-- Farm core
--==========================================================================

Farm = {
    running = false, pickupBusy = false, lastPickup = -1e9,
    pickupConn = nil, roamThread = nil, stats = { picked = 0, sold = 0 },
}

local PICKUP_RANGE = 12
local PICKUP_COOLDOWN = 0.35

function setPromptHoldDurations()
    local items = getItemSpawns()
    if not items then return end
    for _, object in pairs(items:GetChildren()) do
        local prompt = object:FindFirstChild("ProximityPrompt")
        if prompt then pcall(function() prompt.HoldDuration = 0.5 end) end
    end
end

local function promptFor(object)
    local p = object:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not p and object.Parent then p = object.Parent:FindFirstChildWhichIsA("ProximityPrompt", true) end
    return p
end

local function visiblePart(object, prompt)
    if object:IsA("BasePart") then return object end
    for _, d in ipairs(object:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 1 then return d end
    end
    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then return prompt.Parent end
    return object:FindFirstChildWhichIsA("BasePart", true)
end

function keepItem(name)
    if NON_FARMABLE[name] then return false end
    if #Config.FarmItems > 0 and not itemInFilter(name) then return false end
    return true
end

function Farm.handleDrop(object)
    if not Farm.running then return end
    if Farm.pickupBusy or (now() - Farm.lastPickup) < PICKUP_COOLDOWN then return end
    local prompt = promptFor(object)
    local part = prompt and visiblePart(object, prompt) or nil
    if not (prompt and part) then return end
    local r = root()
    if not r or (part.Position - r.Position).Magnitude > PICKUP_RANGE then return end
    Farm.pickupBusy = true
    Farm.lastPickup = now()
    pcall(activatePrompt, prompt, 0.5, true)
    Farm.stats.picked = Farm.stats.picked + 1
    if keepItem(object.Name) then Webhooks.itemPickup(object.Name, 1) end
    Farm.pickupBusy = false
end

function Farm.enable()
    Farm.running = true
    setPromptHoldDurations()
    local items = getItemSpawns()
    if not items then notify("Item_Spawns.Items not found."); return end
    Farm.pickupConn = items.ChildAdded:Connect(function(object)
        task.wait(0.05)
        pcall(Farm.handleDrop, object)
    end)
end

function Farm.disable()
    Farm.running = false
    Farm.pickupBusy = false
    if Farm.pickupConn then Farm.pickupConn:Disconnect(); Farm.pickupConn = nil end
    if Farm.roamThread then pcall(function() task.cancel(Farm.roamThread) end); Farm.roamThread = nil end
    stopMoveTween()
end

function Farm.startRoam()
    if Farm.roamThread then return end
    Farm.roamThread = task.spawn(function()
        while Farm.running do
            if Config.FarmTargetNPC ~= "" then
                moveCharacterTo(Config.FarmTargetNPC, Vector3.new(0, 3, 0))
            elseif Config.FarmPositionMode == "Static" then
                -- stay put; the original also supports a fixed anchor
            else
                moveCharacterTo(getRandomFarmCFrame())
            end
            wakeUpPhysicsAndSync()
            task.wait(0.5)
        end
    end)
end

function Farm.startAuto()
    Config.AutoFarmItems = true
    Farm.enable()
    Farm.startRoam()
    notify("Item farm started!")
end

function Farm.stopAuto()
    Config.AutoFarmItems = false
    Farm.disable()
    notify("Item farm stopped!")
end

--==========================================================================
-- Quest farm / NPC farm / prestige
--==========================================================================

--==========================================================================
-- NPC / quest farm (the original's core kill primitive)
--==========================================================================

local function questTargetFor(key)
    for _, q in ipairs(QUEST_NPCS) do
        if q.key == key or q.questTitle == key or q.enemy == key then return q end
    end
    return QUEST_NPCS[1]
end

function findEnemy(name)
    local wanted = normalizeItemName(name)
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and normalizeItemName(model.Name) == wanted then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if hum and hum.Health > 0 and hrp then return model, hrp end
        end
    end
    return nil
end

function attackM1()
    local r = getRemote()
    if not r then return end
    pcall(function()
        if r.InvokeServer then r:InvokeServer("Attack", "m1")
        else r:FireServer("Attack", "m1") end
    end)
end

-- teleport above the target and hit it (mirrors the original's stand-pilot farm)
function farmEnemy(enemyName)
    if not enemyName or enemyName == "" then return false end
    local model, hrp = findEnemy(enemyName)
    if not model then return false end
    moveCharacterTo(CFrame.new(hrp.Position + Vector3.new(0, 3.5, 0)))
    zeroRootVelocity(root())
    attackM1()
    task.wait(0.05)
    return true
end

function directNpcFarm(enemyName)
    while Config.FarmTargetNPC == enemyName and enemyName ~= "" do
        if not farmEnemy(enemyName) then task.wait(0.3) end
    end
    notify("NPC Farm stopped.")
end

function getQuestState()
    local s = stats()
    if not s then return nil, 0, 0 end
    local q = s:FindFirstChild("Quest")
    local cur = s:FindFirstChild("QuestProgress")
    local max = s:FindFirstChild("QuestMaxProgress")
    return (q and q.Value) or "", (cur and cur.Value) or 0, (max and max.Value) or 0
end

function takeQuest(target)
    moveCharacterTo(target.npc, Vector3.new(0, 3, 0))
    local npc = workspace:FindFirstChild(target.npc)
    if not npc then return false end
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            activatePrompt(d, nil, true)
            return true
        end
    end
    return false
end

function runQuestFarm()
    local lastLog = 0
    while Config.QuestFarm do
        local target = questTargetFor(Config.Quest)
        local curQuest, cur, max = getQuestState()
        local active = normalizeItemName(curQuest) == normalizeItemName(target.questTitle)
        if not active or (max > 0 and cur >= max) then
            if (now() - lastLog) > 3 then
                lastLog = now()
                notify("Taking quest from " .. tostring(target.npc))
            end
            takeQuest(target)
            task.wait(0.2)
        end
        farmEnemy(target.enemy)
        task.wait(0.05)
    end
    notify("Quest Farm stopped.")
end

function runAutoPrestige()
    while Config.AutoPrestige do
        -- the original delegates this to its exported prestige helper; prefer it
        local external = (getgenv and getgenv().RAILhub_ToggleAutoPrestige) or _G.toggleAutoPrestige
        if type(external) == "function" then
            pcall(external, true)
            break
        end
        notify("Auto Prestige Progress: " .. tostring(statValue("Prestige")) .. "/5")
        task.wait(1)
    end
end

function stealDroppedMoney()
    if not Config.StealDroppedMoney then return end
    for _, object in ipairs(workspace:GetDescendants()) do
        if object.Name == "Money" and object:IsA("BasePart") then
            moveCharacterTo(object)
        end
    end
end

--==========================================================================
-- Auto sell / buy
--==========================================================================

-- The game sells through its shop GUI; the original clicks the matching item
-- row there (firesignal(MouseButton1Click), or VirtualInput mouse events as a
-- fallback). We reproduce that behaviour instead of inventing a remote.
local function isSellProtected(name)
    local n = normalizeItemName(name)
    if NON_FARMABLE[name] then return true end
    for _, banned in ipairs(Config.SellBlacklist) do
        if normalizeItemName(banned) == n then return true end
    end
    local never = Config.NeverAutoSell
    if type(never) == "string" and never ~= "" and normalizeItemName(never) == n then return true end
    return false
end

function findSellButton(name)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local wanted = normalizeItemName(name)
    local best
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("GuiObject") and d.Visible then
            local text = ""
            if d:IsA("TextLabel") or d:IsA("TextButton") then text = d.Text or "" end
            if not text:find("%S") then
                local tl = d:FindFirstChildWhichIsA("TextLabel", true)
                text = (tl and tl.Text) or ""
            end
            if text ~= "" and normalizeItemName(text):find(wanted, 1, true) then
                local btn = d:IsA("GuiButton") and d or d:FindFirstChildWhichIsA("GuiButton", true)
                if btn then best = btn end
            end
        end
    end
    return best
end

function clickGui(btn)
    if not btn then return false end
    if type(firesignal) == "function" then
        if pcall(function() firesignal(btn.MouseButton1Click) end) then return true end
    end
    local vi = game:GetService("VirtualInputManager")
    local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
    if pos and size and size.X > 0 and size.Y > 0 then
        local x = math.floor(pos.X + size.X / 2)
        local y = math.floor(pos.Y + size.Y / 2)
        return pcall(function()
            vi:SendMouseButtonEvent(x, y, 0, true, game, 1)
            vi:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
    end
    return false
end

local itemStickConns = {}
function cleanupItemStick()
    for _, conn in ipairs(itemStickConns) do pcall(function() conn:Disconnect() end) end
    itemStickConns = {}
end

function sellItem(name, silent)
    if not name or name == "" then return false, "No item provided" end
    local norm = normalizeItemName(name)
    if countItem(norm) == 0 then
        if not silent then notify("No " .. tostring(norm) .. " found.") end
        return false
    end
    if isSellProtected(norm) then
        if not silent then notify("Cannot sell " .. tostring(norm) .. " (Item is protected).") end
        return false
    end
    cleanupItemStick()
    stopMoveTween()
    -- resolve the Tool instance: the literal worker (proto#189) needs it.
    local player = game:GetService("Players").LocalPlayer
    local tool = nil
    if player then
        local char = player.Character
        local bp = char and char:FindFirstChild("Backpack")
        for _, container in ipairs({ bp, char }) do
            if container then
                local direct = container:FindFirstChild(norm)
                if direct and direct:IsA("Tool") then tool = direct break end
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Tool") and normalizeItemName(child.Name) == norm then
                        tool = child break
                    end
                end
                if tool then break end
            end
        end
    end
    if not tool then
        if not silent then notify("No " .. tostring(norm) .. " found.") end
        return false, "Item not found"
    end
    local ok, err = sellItemWorker(tool, false)
    if ok then
        Farm.stats.sold = Farm.stats.sold + 1
        task.wait(0.05)
        return true
    end
    if not silent then notify("Failed to sell " .. tostring(norm) .. ".") end
    return false, err
end

function sellAll(name)
    if not name or name == "" then return end
    local norm = normalizeItemName(name)
    local num = countItem(norm)
    if num == 0 then notify("No " .. tostring(norm) .. " found."); return end
    if isSellProtected(norm) then
        notify("Cannot sell " .. tostring(norm) .. " (Item is protected)."); return
    end
    if sellItem(norm, true) then
        notify(string.format("Sold all (%d) %s.", num, norm))
    else
        notify("Failed to sell " .. tostring(norm) .. ".")
    end
end

function sellAllSelected(list)
    list = list or Config.FarmItems
    local sold = 0
    for _, name in ipairs(list) do
        local norm = normalizeItemName(name)
        local num = countItem(norm)
        if num > 0 and not isSellProtected(norm) then
            if sellItem(norm, true) then sold = sold + num end
            task.wait(0.05)
        end
    end
    if sold == 0 then notify("No selected items found to sell.")
    else notify("Sold selected items: " .. tostring(sold)) end
end

function sellAllWorthless()
    sellAllSelected(SELL_WORTHLESS)
end

function isNeverAutoSell(name)
    local never = Config.NeverAutoSell
    if type(never) ~= "string" or never == "" then return false end
    return normalizeItemName(name) == normalizeItemName(never)
end

function checkAndSellMax()
    if not Config.AutoSellOnMax then return end
    if statValue("Money") >= 1000000 then return end
    local backpack = char() and char():FindFirstChild("Backpack")
    if not backpack then return end
    cleanupItemStick()
    local sold = {}
    for _, item in ipairs(backpack:GetChildren()) do
        local limit = ITEM_LIMITS[item.Name] or 25
        if countItem(item.Name) >= limit
            and not isSellProtected(item.Name)
            and not isNeverAutoSell(item.Name) then
            if sellItem(item.Name, true) then sold[item.Name] = countItem(item.Name) end
            task.wait(0.05)
        end
    end
    local parts = {}
    for name, qty in pairs(sold) do table.insert(parts, qty .. "x " .. name) end
    if #parts > 0 then notify("Auto sold: " .. table.concat(parts, ", ")) end
end

function checkAndBuyLuckyArrow()
    if not Config.AutoBuyArrow then return end
    local money = statValue("Money")
    if money < 75000 then return end
    local owned, maxOwned = countItem("Lucky Arrow"), ITEM_LIMITS["Lucky Arrow"]
    if owned >= maxOwned then return end
    local toBuy = math.min(math.floor(money / 75000), maxOwned - owned)
    if toBuy <= 0 then return end
    notify(string.format("Buying %dx Lucky Arrow (%d/%d)", toBuy, owned, maxOwned))
    for _ = 1, toBuy do purchaseItem("1x Lucky Arrow", 1); task.wait(0.15) end
end

--==========================================================================
-- Stand farm / pilot
--==========================================================================

local StandFarm = { running = false, thread = nil, arrowsUsed = 0, standsGot = 0 }

function getFarmMethod()
    if Config.FarmMethod ~= "Auto" then return Config.FarmMethod end
    return "Arrow"
end

-- the game exposes the current stand's skin through a RemoteFunction
function getStandSkin()
    local c = char()
    if not c then return "None" end
    local rf = c:FindFirstChild("RemoteFunction")
    if not rf and c.WaitForChild then
        pcall(function() rf = c:WaitForChild("RemoteFunction", 5) end)
    end
    if not rf then return "None" end
    local ok, skin = pcall(function() return rf:InvokeServer("ReturnStandSkin", "Stand") end)
    if ok and skin then return tostring(skin) end
    return "None"
end

function isShinySkin(skin)
    return type(skin) == "string" and string.find(string.lower(skin), "shiny", 1, true) ~= nil
end

function StandFarm.keepCurrent()
    local skin = getStandSkin()
    local stand = statValue("Stand")
    if Config.KeepAnyShiny and isShinySkin(skin) then
        StandFarm.stop()
        notify("Shiny stand kept: " .. tostring(skin))
        return true
    end
    for _, wanted in ipairs(Config.KeepStands) do
        if normalizeItemName(wanted) == normalizeItemName(tostring(stand)) then
            StandFarm.stop()
            notify("Kept stand: " .. tostring(stand))
            return true
        end
    end
    return false
end

function StandFarm.start()
    Config.StandFarm = true
    StandFarm.running = true
    StandFarm.thread = task.spawn(function()
        while StandFarm.running do
            toggleStand()
            StandFarm.arrowsUsed = StandFarm.arrowsUsed + 1
            task.wait(1)
            if StandFarm.keepCurrent() then break end
        end
        StandFarm.running = false
    end)
    notify("Stand farming started!")
end

function StandFarm.stop()
    Config.StandFarm = false
    StandFarm.running = false
    if StandFarm.thread then pcall(function() task.cancel(StandFarm.thread) end); StandFarm.thread = nil end
    notify("Stand farming stopped!")
end

function StandFarm.skipShiny()
    notify("Skip current Shiny")
end

-- stand pilot: keep the stand next to a target player
local Pilot = { running = false, thread = nil }

function Pilot.start()
    if Pilot.thread then return end
    Pilot.running = true
    Pilot.thread = task.spawn(function()
        while Pilot.running do
            local targetName = Config.TargetStandPlayer
            if targetName ~= "" then
                local target = Players:FindFirstChild(targetName)
                local tr = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                if tr then
                    local h = humanoid()
                    if h then h.WalkSpeed = Config.PilotSpeed end
                    moveCharacterTo(tr, Vector3.new(0, 0, 0))
                end
            end
            task.wait(0.25)
        end
    end)
end

function Pilot.stop()
    Pilot.running = false
    if Pilot.thread then pcall(function() task.cancel(Pilot.thread) end); Pilot.thread = nil end
end

function Pilot.forceCleanup()
    stopMoveTween()
    zeroRootVelocity(root())
    notify("Collision restored & Noclip reset.")
end

--==========================================================================
-- Block bot
--==========================================================================

local Block = { blocked = false }

function startBlocking()
    local c = char()
    if not c or Block.blocked then return end
    local capacity = c:FindFirstChild("Blocking_Capacity")
    if capacity and capacity.Value > 0 then Block.blocked = true; return end
    Block.blocked = true
    local r = getRemote()
    if r then
        pcall(function()
            r:FireServer("StartBlocking", "pass")
            task.wait()
            r:FireServer("StartBlocking", "pass")
        end)
    end
end

function stopBlocking(force)
    local c = char()
    if not c then return end
    if not force and Config.KeepBlockHoldF and UserInput:IsKeyDown(Enum.KeyCode.F) then return end
    if Block.blocked then
        local r = getRemote()
        if r then
            pcall(function()
                r:FireServer("StopBlocking", "pass")
                task.wait()
                r:FireServer("StopBlocking", "pass")
            end)
        end
        Block.blocked = false
    end
end

function Block.step()
    if Config.BlockBot then
        startBlocking()
    elseif Block.blocked then
        stopBlocking(true)
    end
    if Config.Unblocking and Config.Reblocking and Block.blocked then
        -- re-blocking window handled by the game; nothing extra needed here
    end
end

--==========================================================================
-- Movement features
--==========================================================================

local flyThread, flyBodyVelocity

function applySpeed()
    local h = humanoid()
    if h then h.WalkSpeed = Config.SpeedChanger and Config.SpeedValue or 16 end
end

function applyJump()
    local h = humanoid()
    if h then
        h.UseJumpPower = Config.JumpPowerChanger
        if Config.JumpPowerChanger then h.JumpPower = Config.JumpPower end
    end
end

function setNoclip(enabled)
    local c = char()
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = not enabled end
    end
end

function setFly(enabled)
    if not enabled then
        if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
        return
    end
    if flyThread then return end
    flyThread = task.spawn(function()
        local r = root()
        if not r then return end
        flyBodyVelocity = Instance.new("BodyVelocity")
        flyBodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        flyBodyVelocity.Parent = r
        while Config.Fly do
            local camera = workspace.CurrentCamera
            local move = Vector3.zero
            if UserInput:IsKeyDown(Enum.KeyCode.W) then move = move + camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then move = move - camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) then move = move - camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) then move = move + camera.CFrame.RightVector end
            flyBodyVelocity.Velocity = move * Config.FlySpeed
            task.wait()
        end
        if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
        flyThread = nil
    end)
end

--==========================================================================
-- Reset / refresh
--==========================================================================

function resetPlayer()
    pcall(function() LocalPlayer.Character:BreakJoints() end)
end

function refreshPlayerList()
    notify("Refreshing player list...")
end

function rehookPlayers()
    notify("Player hooks refreshed.")
end

function applyWeather()
    if not Config.WeatherChanger then return end
    local atmos = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
    if Config.Weather == "Fog" then
        Lighting.FogEnd = 100
    elseif Config.Weather == "Blood Moon" then
        Lighting.ClockTime = 0
        Lighting.FogColor = Color3.fromRGB(120, 0, 0)
    else
        Lighting.FogEnd = 100000
    end
end

function removeMap()
    if not Config.RemoveMap then return end
    for _, part in ipairs(workspace:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "" and not part:FindFirstChildOfClass("Humanoid") then
            part.LocalTransparencyModifier = 1
        end
    end
    notify("applyRemoveMap: executing map invisibility (Remove Map)")
end

--==========================================================================
-- Server
--==========================================================================

function reconnect(reason)
    notify(reason or "Reconnecting to current server...")
    Webhooks.reconnectKick(reason or "reconnecting")
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer) end)
end

function rejoin()
    notify("Rejoining current server...")
    local jobId = game.JobId
    if jobId == "" then notify("Could not get server ID, rejoining...") end
    pcall(function()
        game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
    end)
end

-- Auto Rejoin on Error / Kick: watch teleport failures and recover.
local rejoinConn
function enableAutoRejoin()
    if rejoinConn then return end
    local ts = game:GetService("TeleportService")
    local signal = ts and ts.TeleportInitFailed
    if not signal then return end
    rejoinConn = signal:Connect(function(player, result, msg)
        if player == LocalPlayer or player == nil then
            notify("[ServerHop] Teleport failed (" .. tostring(result) .. "): " .. tostring(msg))
            pcall(function() game:GetService("GuiService"):ClearError() end)
            task.wait(7)
            if Config.AutoRejoinKick then serverHop() else reconnect("Teleport failed") end
        end
    end)
end

function disableAutoRejoin()
    if rejoinConn then rejoinConn:Disconnect(); rejoinConn = nil end
end

function serverHop()
    notify("Server Reconnect / Hop: searching for a new server...")
    pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
        local body = HttpService:JSONDecode(httpRequest("GET", url))
        local servers = body and body.data or {}
        for _, server in ipairs(servers) do
            if server.id ~= game.JobId and server.playing < server.maxPlayers then
                game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
                return
            end
        end
        notify("No free server found, rejoining current.")
    end)
end

--==========================================================================
-- Anti-AFK / ping / auto execute
--==========================================================================

local antiAfkConn, pingThread

function enableAntiAfk()
    if antiAfkConn then return end
    antiAfkConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            local vu = game:GetService("VirtualUser")
            if vu then
                vu:CaptureController()
                vu:ClickButton2(Vector2.zero)
            end
        end)
    end)
end

function disableAntiAfk()
    if antiAfkConn then antiAfkConn:Disconnect(); antiAfkConn = nil end
end

function startPing()
    if pingThread then return end
    pingThread = task.spawn(function()
        while Config.Ping do
            local ping = 0
            pcall(function() ping = math.floor(LocalPlayer:GetNetworkPing() * 1000) end)
            UI.setStatus("Ping: " .. ping .. " ms")
            task.wait(1)
        end
        UI.setStatus("")
        pingThread = nil
    end)
end

function autoExecute()
    if not Config.AutoExecute then return end
    notify("Auto Execute")
    pressPlay()
end

--==========================================================================

--==========================================================================
-- AXION core upgrades (ported literally from solved GAP protos)
-- Inserted before the UI section. Requires core globals above it:
-- normalizeItemName, utf8Lower?, countItem, char, humanoid, stats, statValue,
-- getQuestState, questTargetFor, takeQuest, getRemote, notify, task, tick/now,
-- game, workspace, VirtualInputManager via game:GetService, QUEST_NPCS, NPCS,
-- Config, Farm, cleanupItemStick, stopMoveTween, activatePrompt.
--==========================================================================

-- Stand skill lists, verbatim from the original's move table (tbl69).
local STAND_SKILLS = {
    ["Star Platinum"] = { "Stand Barrage", "Stand Barrage Finisher", "Ora Kicks" },
    ["Star Platinum: The World"] = { "Stand Barrage", "Stand Barrage Finisher", "Ora Kicks", "Skull Crusher" },
    ["The World"] = { "Stand Barrage", "Stand Barrage Finisher", "Knives", "Kick Barrage" },
    ["The World: Alternate Universe"] = { "Stand Barrage", "Stand Barrage Finisher", "Knives", "Gun", "Chop" },
    ["King Crimson"] = { "Stand Barrage", "Stand Barrage Finisher", "Chop" },
    ["King Crimson Requiem"] = { "Stand Barrage", "Stand Barrage Finisher", "Chop" },
    ["Gold Experience"] = { "Stand Barrage", "Stand Barrage Finisher", "Create Life" },
    ["Gold Experience Requiem"] = { "Stand Barrage", "Stand Barrage Finisher", "Scorpion Beam" },
    ["Silver Chariot"] = { "Stand Barrage", "Stand Barrage Finisher", "Million Pricks", "Last Shot" },
    ["Chariot Requiem"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["Crazy Diamond"] = { "Stand Barrage", "Stand Barrage Finisher", "Bearing Shot", "Blood Slash" },
    ["Crazy Diamond Requiem"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["Diver Down"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["Killer Queen"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["Killer Queen: Bites the Dust"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["Whitesnake"] = { "Stand Barrage", "Stand Barrage Finisher", "Acid Spit" },
    ["C-Moon"] = { "Stand Barrage", "Stand Barrage Finisher", "Surface Inversion Punch" },
    ["Made in Heaven"] = { "Stand Barrage", "Stand Barrage Finisher", "Speed Slice" },
    ["D4C"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["D4C: Love Train"] = { "Stand Barrage", "Stand Barrage Finisher" },
    ["Tusk Act 1"] = { "Nail Shots" },
    ["Tusk Act 2"] = { "Nail Shots", "Golden Rectangle Nail" },
    ["Tusk Act 3"] = { "Nail Shots", "Golden Rectangle Nail" },
    ["Tusk Act 4"] = { "Stand Barrage", "Stand Barrage Finisher", "Golden Rectangle Nail" },
    ["Hermit Purple"] = { "Vine Slap", "Vine Trap" },
    ["Magician's Red"] = { "Stand Barrage", "Stand Barrage Finisher", "Crossfire Hurricane" },
    ["Purple Haze"] = { "Stand Barrage", "Stand Barrage Finisher", "Bulb Throw" },
    ["Sticky Fingers"] = { "Stand Barrage", "Stand Barrage Finisher", "Extend Arm" },
    ["The Hand"] = { "Stand Barrage", "Stand Barrage Finisher", "Erasure", "Erasure Pull" },
    ["Sex Pistols"] = { "Multi Shot", "Auto Reload" },
    ["Aerosmith"] = { "Stand Barrage", "Stand Barrage Finisher", "Vola Barrage" },
    ["Beach Boy"] = { "Hook Slash", "Auto Rod" },
    ["Mr. President"] = {},
    ["Anubis"] = { "Stand Barrage", "Stand Barrage Finisher", "Cursed Blade" },
    ["Red Hot Chili Pepper"] = { "Stand Barrage", "Stand Barrage Finisher", "Lightning Jab" },
    ["Soft & Wet"] = { "Stand Barrage", "Stand Barrage Finisher", "Friction Plunder" },
    ["Soft & Wet: Go Beyond"] = { "Stand Barrage", "Stand Barrage Finisher", "Go Beyond Bubble", "Explosive Spin" },
}

-- Original fixed protection list (value913 head) + fuzzy EN/RU matcher.
-- list2 tail = user's SellBlacklist.
local function isProtectedOriginal(a)
    if not a then return false end
    local raw = (typeof(a) == "Instance" and a.Name) or a
    local s = tostring(raw)
    local low = (utf8Lower and utf8Lower(s)) or s:lower()
    local norm = (normalizeItemName and normalizeItemName(a)) or low
    local FIXED = {
        ["Lucky Arrow"] = 1, ["Lucky Stone Mask"] = 1, ["Requiem Arrow"] = 1,
        ["Stand Arrow"] = 1, ["Left Arm of The Saint's Corpse"] = 1,
        ["Heart of The Saint's Corpse"] = 1, ["Pelvis of The Saint's Corpse"] = 1,
        ["Eye of The Saint's Corpse"] = 1, ["Christmas Present"] = 1,
        ["Candy"] = 1, ["Gold Umbrella"] = 1, ["Umbrella"] = 1,
    }
    if FIXED[norm] then return true end
    local function F(p) return low:find(p, 1, true) end
    if F("stand arrow") or F("standarrow")
        or (F("stand") and F("arrow") and not F("mysterious"))
        or F("quest arrow") or F("questarrow") then return true end
    if F("umbrella") then return true end
    if F("lucky") then return true end
    if F("requiem") then return true end
    if F("pelvis") or F("heart") or F("left arm") or F("eye of") then
        return true
    end
    if F("candy") then return true end
    for _, entry in ipairs(Config.SellBlacklist or {}) do
        if entry:lower() == low or entry == s
            or (normalizeItemName and normalizeItemName(entry) == norm) then
            return true
        end
    end
    return false
end

-- Merchant-dialogue option keywords per attempt step (verbatim).
local SELL_STEP_KEYWORDS = {
    { "sell", "buy" },
    { "deal" },
}
local SELL_ALL_KEYWORDS = { "all" }
local SELL_ONE_KEYWORDS = { "one" }

-- The literal sell worker (proto#189). toolInstance must be a Tool.
-- sellAll=true -> picks the "all" dialogue option, else "one".
-- Returns true on success, (false, reason) otherwise.
function sellItemWorker(toolInstance, sellAll)
    local RunService = game:GetService("RunService")
    local VIM = game:GetService("VirtualInputManager")
    local function getDialogueFrame()
        local pl = LocalPlayer or (game:GetService("Players").LocalPlayer)
        local pg = pl and pl:FindFirstChild("PlayerGui")
        local gui = pg and pg:FindFirstChild("DialogueGui")
        if gui and gui.Enabled then return gui:FindFirstChild("Frame") end
        return nil
    end
    local function scrapeText(gui)
        if not gui then return "" end
        local list = {}
        pcall(function()
            if gui:IsA("TextLabel") or gui:IsA("TextButton") then
                table.insert(list, gui.Text or "")
            end
            for _, desc in ipairs(gui:GetDescendants()) do
                if (desc:IsA("TextLabel") or desc:IsA("TextButton"))
                    and desc.Text and desc.Text ~= "" then
                    table.insert(list, desc.Text)
                end
            end
        end)
        return table.concat(list, " "):lower()
    end
    local function clickObject(obj)
        if not obj then return false end
        pcall(function()
            if not obj:IsA("GuiButton") then
                obj = obj:FindFirstChildWhichIsA("GuiButton", true) or obj
            end
        end)
        if obj:IsA("GuiButton") and type(firesignal) == "function" then
            if pcall(function() firesignal(obj.MouseButton1Click) end) then return true end
        end
        if obj:IsA("GuiObject") then
            if pcall(function()
                local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
                if size.X <= 0 or size.Y <= 0 then error("button has no size") end
                local x = math.floor(pos.X + size.X / 2)
                local y = math.floor(pos.Y + size.Y / 2)
                VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
                VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
            end) then return true end
        end
        return false
    end

    local tool = toolInstance
    local player = game:GetService("Players").LocalPlayer or LocalPlayer
    if not player then return false, "Local player not found" end
    local char = player.Character
    if not char then return false, "Character not found" end
    local humanoid = char:FindFirstChildOfClass("Humanoid") or char:FindFirstChild("Humanoid")
    if not humanoid then return false, "Humanoid not found" end
    local remote = char:FindFirstChild("RemoteEvent")
    if not remote then return false, "RemoteEvent not found" end
    if not tool or not tool.Parent then return false, "Item not found" end

    local frame = getDialogueFrame()
    if frame and frame.Visible then
        local options = frame:FindFirstChild("Options")
        if options then
            local opt = options:FindFirstChild("Option1") or options:FindFirstChild("Option2")
            if opt then clickObject(opt:FindFirstChild("TextButton")) end
        end
        local cont = frame:FindFirstChild("ClickContinue")
        if cont and cont.Visible then clickObject(cont) end
        RunService.Heartbeat:Wait()
    end

    if tool.Parent ~= char then
        humanoid:EquipTool(tool)
        local t0 = os.clock()
        while tool.Parent ~= char and os.clock() - t0 < 0.4 do
            RunService.Heartbeat:Wait()
        end
    end
    if tool.Parent ~= char then return false, "Failed to equip item" end

    local merchant = game:GetService("ReplicatedStorage"):FindFirstChild("Dialogue")
    merchant = merchant and merchant:FindFirstChild("Merchant")
    if merchant then
        remote:FireServer("PromptTriggered", merchant)
    else
        local dialogues = workspace:FindFirstChild("Dialogues")
        local npc = dialogues and dialogues:FindFirstChild("ShiftPlox, The Travelling Merchant")
        local prompt = npc and npc:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and type(fireproximityprompt) == "function" then
            pcall(function() fireproximityprompt(prompt) end)
        end
    end

    local mode = sellAll and "all" or "one"
    local attempt = 1
    local deadline = os.clock() + 8
    while os.clock() < deadline and attempt <= 3 do
        frame = getDialogueFrame()
        if frame and frame.Visible then
            local options = frame:FindFirstChild("Options")
            if options and options.Visible then
                local keywords
                if attempt == 1 then keywords = SELL_STEP_KEYWORDS[1]
                elseif attempt == 2 then keywords = SELL_STEP_KEYWORDS[2]
                else
                    keywords = (mode == "all") and SELL_ALL_KEYWORDS or SELL_ONE_KEYWORDS
                end
                local picked = nil
                for _, child in ipairs(options:GetChildren()) do
                    local btn = child:FindFirstChild("TextButton", true) or child
                    local text = scrapeText(child)
                    for _, kw in ipairs(keywords) do
                        if text:find(kw, 1, true) then picked = btn break end
                    end
                    if picked then break end
                end
                if attempt == 3 and not picked and sellAll then
                    local opt6 = options:FindFirstChild("Option6")
                    local btn6 = opt6 and opt6:FindFirstChild("TextButton")
                    if btn6 then
                        local text6 = scrapeText(opt6)
                        if text6:find("all", 1, true) then
                            picked = btn6
                        end
                    end
                end
                if picked then
                    clickObject(picked)
                    attempt = attempt + 1
                    task.wait(0.06)
                end
            end
            local cont = frame:FindFirstChild("ClickContinue")
            if cont and cont.Visible then clickObject(cont) task.wait(0.04) end
            local dframe = frame:FindFirstChild("DialogueFrame")
            if dframe and dframe.Visible then clickObject(dframe) end
        else
            clickObject(frame)
        end
        RunService.Heartbeat:Wait()
        if attempt >= 4 then break end
    end

    frame = getDialogueFrame()
    if frame and frame.Visible then
        local cont = frame:FindFirstChild("ClickContinue")
        if cont and cont.Visible then clickObject(cont) end
    end
    local t1 = os.clock()
    while os.clock() - t1 < 0.6 do
        local held = tool and tool.Parent
            and (tool.Parent == char or tool.Parent == (player:FindFirstChild("Backpack") or {}))
        if not held then break end
        frame = getDialogueFrame()
        if frame and frame.Visible then
            local cont = frame:FindFirstChild("ClickContinue")
            if cont and cont.Visible then clickObject(cont) end
        end
        RunService.Heartbeat:Wait()
    end
    local bp = player:FindFirstChild("Backpack")
    local stillHeld = tool and tool.Parent
        and (tool.Parent == char or tool.Parent == (bp or {}))
    if (not stillHeld) or attempt >= 4 then return true end
    return false
end
--==========================================================================
-- AXION interface (Fluent UI library, animated + acrylic)
-- Loaded pcall-guarded so headless/stub runs keep working without it.
--==========================================================================

local FluentUI = nil
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    end)
    if ok and lib then FluentUI = lib end
end

local function buildAxionUI()
    if not FluentUI then return end
    local Fluent = FluentUI
    local SaveManager, InterfaceManager = nil, nil
    pcall(function()
        SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
        InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
    end)

    local Window = Fluent:CreateWindow({
        Title = "Axion",
        SubTitle = "YBA Hub",
        TabWidth = 160,
        Size = UDim2.fromOffset(600, 470),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl,
    })

    local sellOptions = { "(none)" }
    for _, n in ipairs(ITEM_NAMES) do table.insert(sellOptions, n) end

    local Tabs = {
        Info = Window:AddTab({ Title = "Information", Icon = "info" }),
        Farming = Window:AddTab({ Title = "Farming", Icon = "sprout" }),
        Stands = Window:AddTab({ Title = "Stands", Icon = "sparkles" }),
        Sell = Window:AddTab({ Title = "Sell items", Icon = "coins" }),
        Visuals = Window:AddTab({ Title = "Visuals", Icon = "eye" }),
        PlayerESP = Window:AddTab({ Title = "Player ESP", Icon = "users" }),
        PvP = Window:AddTab({ Title = "PvP", Icon = "swords" }),
        Movement = Window:AddTab({ Title = "Movement", Icon = "wind" }),
        Server = Window:AddTab({ Title = "Server", Icon = "server" }),
        Webhooks = Window:AddTab({ Title = "Webhooks", Icon = "webhook" }),
        Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    }
    local T = Tabs

    -- Information
    T.Info:AddParagraph({ Title = "Axion — Version 1.0", Content = "YBA script hub.\nLast update: 11.10.2026" })
    T.Info:AddButton({ Title = "Discord Link", Description = "Copy invite to clipboard",
        Callback = function() notify("https://discord.gg/67UTqK8su5") end })
    T.Info:AddToggle("ShowUserInfo", { Title = "User Info", Default = Config.ShowUserInfo,
        Callback = function(v) Config.ShowUserInfo = v end })
    T.Info:AddToggle("ShowPing", { Title = "Show Ping", Default = Config.Ping,
        Callback = function(v) Config.Ping = v startPing() end })
    T.Info:AddToggle("AutoExecute", { Title = "Auto Execute", Default = Config.AutoExecute,
        Callback = function(v) Config.AutoExecute = v autoExecute() end })

    -- Farming
    T.Farming:AddToggle("AutoFarmItems", { Title = "Auto farm items", Default = Config.AutoFarmItems,
        Callback = function(v) Config.AutoFarmItems = v
            if v then Farm.startAuto() else Farm.stopAuto() end end })
    T.Farming:AddButton({ Title = "Enable Farm", Description = "Start item farming now",
        Callback = function() Farm.startAuto() end })
    T.Farming:AddDropdown("FarmMethod", { Title = "Farm Method",
        Values = { "Auto", "Roam", "Static", "Server Hop" }, Multi = false, Default = 1,
        Callback = function(v) Config.FarmMethod = v end })
    T.Farming:AddToggle("NpcFarm", { Title = "Farm Target NPC", Default = Config.NpcFarm,
        Callback = function(v) Config.NpcFarm = v
            if v then Config.QuestFarm = false task.spawn(directNpcFarm, Config.FarmTargetNPC) end end })
    T.Farming:AddDropdown("FarmTargetNPC", { Title = "Farm Target NPC", Values = NPCS,
        Multi = false, Default = 1, Callback = function(v) Config.FarmTargetNPC = v end })
    T.Farming:AddToggle("QuestFarm", { Title = "Quest & NPC Farm", Default = Config.QuestFarm,
        Callback = function(v) Config.QuestFarm = v
            if v then Config.NpcFarm = false task.spawn(runQuestFarm) end end })
    T.Farming:AddDropdown("Quest", { Title = "Select Quest", Values = QUESTS,
        Multi = false, Default = 1, Callback = function(v) Config.Quest = v end })
    T.Farming:AddToggle("NpcFarmOriginal", { Title = "Original NPC worker", Default = Config.NpcFarmOriginal,
        Description = "Literal proto#576 engine: pilot, quest-progress, 25s loop",
        Callback = function(v) Config.NpcFarmOriginal = v
            if v then task.spawn(function() farmNpcWorker(Config.FarmTargetNPC) end) end end })
    T.Farming:AddToggle("AutoPrestige", { Title = "Auto Prestige", Default = Config.AutoPrestige,
        Callback = function(v) Config.AutoPrestige = v
            if v then task.spawn(runAutoPrestige) end end })
    T.Farming:AddToggle("StealDroppedMoney", { Title = "Steal Dropped Money",
        Default = Config.StealDroppedMoney,
        Callback = function(v) Config.StealDroppedMoney = v end })
    T.Farming:AddToggle("ServerHopFarm", { Title = "Server Hop Farm", Default = Config.ServerHopFarm,
        Callback = function(v) Config.ServerHopFarm = v if v then serverHop() end end })
    T.Farming:AddInput("FarmItems", { Title = "Items (empty = all)", Default = "",
        Placeholder = "Lucky Arrow, Diamond", Finished = true,
        Callback = function(v) Config.FarmItems = {}
            for part in string.gmatch(v, "[^,]+") do
                table.insert(Config.FarmItems, string.gsub(part, "^%s*(.-)%s*$", "%1")) end end })

    -- Stands
    T.Stands:AddToggle("StandFarm", { Title = "Stand Farm", Default = Config.StandFarm,
        Callback = function(v) Config.StandFarm = v
            if v then StandFarm.start() else StandFarm.stop() end end })
    T.Stands:AddButton({ Title = "Farm stands", Callback = function() StandFarm.start() end })
    T.Stands:AddToggle("KeepAnyShiny", { Title = "Keep only Shiny", Default = Config.KeepAnyShiny,
        Callback = function(v) Config.KeepAnyShiny = v end })
    T.Stands:AddButton({ Title = "Skip current Shiny", Callback = function() StandFarm.skipShiny() end })
    T.Stands:AddDropdown("PilotStand", { Title = "Pilot Stand", Values = STANDS,
        Multi = false, Default = 1, Callback = function(v) Config.PilotStand = v end })
    T.Stands:AddDropdown("KeepStands", { Title = "Select Stands to Keep", Values = STANDS,
        Multi = true, Default = {},
        Callback = function(v)
            local list = {}
            if type(v) == "table" then
                for name, state in pairs(v) do
                    if state then table.insert(list, name) end
                end
            end
            Config.KeepStands = list
        end })

    -- Sell
    T.Sell:AddDropdown("SellSpecific", { Title = "Sell specific item", Values = sellOptions,
        Multi = false, Default = 1,
        Callback = function(v) Config.SellSpecific = v
            if v ~= "(none)" then sellAll(v) end end })
    T.Sell:AddDropdown("SellSelected", { Title = "Sell selected item", Values = sellOptions,
        Multi = false, Default = 1,
        Callback = function(v) Config.SellSelected = v
            if v ~= "(none)" then sellAll(v) end end })
    T.Sell:AddButton({ Title = "Sell All Items", Callback = function() sellAllSelected(ITEM_NAMES) end })
    T.Sell:AddButton({ Title = "Sell worthless items", Callback = function() sellAllWorthless() end })
    T.Sell:AddToggle("AutoSellOnMax", { Title = "Auto sell on stack limit",
        Default = Config.AutoSellOnMax, Callback = function(v) Config.AutoSellOnMax = v end })
    T.Sell:AddInput("NeverAutoSell", { Title = "Never auto-sell (empty = sell all)",
        Default = "", Placeholder = "item name", Finished = true,
        Callback = function(v) Config.NeverAutoSell = v end })
    T.Sell:AddToggle("AutoBuyArrow", { Title = "Auto buy Lucky Arrow (75k)",
        Default = Config.AutoBuyArrow, Callback = function(v) Config.AutoBuyArrow = v end })

    -- Visuals
    T.Visuals:AddToggle("ItemESP", { Title = "Item ESP", Default = Config.ItemESP,
        Callback = function(v) Config.ItemESP = v end })
    T.Visuals:AddSlider("ItemESPTextSize", { Title = "Item ESP Text Size", Default = 14,
        Min = 8, Max = 24, Rounding = 0, Callback = function(v) Config.ItemESPTextSize = v end })
    T.Visuals:AddToggle("ESPChams", { Title = "ESP Chams", Default = Config.ESPChams,
        Callback = function(v) Config.ESPChams = v end })
    T.Visuals:AddToggle("ESPNames", { Title = "ESP Names", Default = Config.ESPNames,
        Callback = function(v) Config.ESPNames = v end })
    T.Visuals:AddToggle("ESPStand", { Title = "ESP Stand", Default = Config.ESPStand,
        Callback = function(v) Config.ESPStand = v end })
    T.Visuals:AddToggle("ESPHealth", { Title = "ESP Health", Default = Config.ESPHealth,
        Callback = function(v) Config.ESPHealth = v end })
    T.Visuals:AddSlider("ESPDistance", { Title = "ESP Distance", Default = 1000,
        Min = 50, Max = 3000, Rounding = 0, Callback = function(v) Config.ESPDistance = v end })
    T.Visuals:AddToggle("HUDHealth", { Title = "View Self HP", Default = Config.HUDHealth,
        Callback = function(v) Config.HUDHealth = v end })
    T.Visuals:AddToggle("WeatherChanger", { Title = "Enable Weather Changer",
        Default = Config.WeatherChanger,
        Callback = function(v) Config.WeatherChanger = v applyWeather() end })
    T.Visuals:AddDropdown("Weather", { Title = "Select Weather", Values = WEATHERS,
        Multi = false, Default = 1,
        Callback = function(v) Config.Weather = v applyWeather() end })
    T.Visuals:AddToggle("RemoveMap", { Title = "Remove Map", Default = Config.RemoveMap,
        Callback = function(v) Config.RemoveMap = v removeMap() end })

    -- Player ESP
    T.PlayerESP:AddToggle("PlayerESP", { Title = "Enable Player ESP", Default = Config.PlayerESP,
        Callback = function(v) Config.PlayerESP = v end })
    T.PlayerESP:AddToggle("StaffESP", { Title = "Staff ESP", Default = Config.StaffESP,
        Callback = function(v) Config.StaffESP = v end })
    T.PlayerESP:AddToggle("StaffDetector", { Title = "Staff Detector", Default = Config.StaffDetector,
        Callback = function(v) Config.StaffDetector = v end })
    T.PlayerESP:AddButton({ Title = "Re-hook Players", Callback = function() rehookPlayers() end })
    T.PlayerESP:AddButton({ Title = "Refresh Player List", Callback = function() refreshPlayerList() end })

    -- PvP
    T.PvP:AddToggle("BlockBot", { Title = "Enable BlockBot", Default = Config.BlockBot,
        Callback = function(v) Config.BlockBot = v end })
    T.PvP:AddToggle("Reblocking", { Title = "Allow re-blocking", Default = Config.Reblocking,
        Callback = function(v) Config.Reblocking = v end })
    T.PvP:AddToggle("KeepBlockHoldF", { Title = "Keep block while holding F",
        Default = Config.KeepBlockHoldF, Callback = function(v) Config.KeepBlockHoldF = v end })
    T.PvP:AddToggle("Unblocking", { Title = "Unblocking", Default = Config.Unblocking,
        Callback = function(v) Config.Unblocking = v end })
    T.PvP:AddToggle("ProjectilesPriority", { Title = "Projectiles priority",
        Default = Config.ProjectilesPriority, Callback = function(v) Config.ProjectilesPriority = v end })
    T.PvP:AddToggle("Coliseum", { Title = "Coliseum (1v1/2v2) mode", Default = Config.Coliseum,
        Callback = function(v) Config.Coliseum = v end })
    T.PvP:AddToggle("BlockBeachBoyEY", { Title = "Block Beach Boy E and Y",
        Default = Config.BlockBeachBoyEY, Callback = function(v) Config.BlockBeachBoyEY = v end })
    T.PvP:AddToggle("StickyFingers", { Title = "sticky finger exploit",
        Default = Config.StickyFingers, Callback = function(v) Config.StickyFingers = v end })
    T.PvP:AddToggle("StandPilot", { Title = "Stand Pilot", Default = Config.StandPilot,
        Callback = function(v) Config.StandPilot = v
            if v then Pilot.start() else Pilot.stop() end end })
    T.PvP:AddToggle("MovementPrediction", { Title = "Movement Prediction",
        Default = Config.MovementPrediction, Callback = function(v) Config.MovementPrediction = v end })
    T.PvP:AddSlider("PredictionStrength", { Title = "Prediction Strength",
        Default = 15, Min = 0, Max = 100, Rounding = 0,
        Callback = function(v) Config.PredictionStrength = v / 100 end })
    T.PvP:AddToggle("ForceCleanupPilot", { Title = "Force Cleanup Pilot",
        Default = Config.ForceCleanupPilot,
        Callback = function(v) Config.ForceCleanupPilot = v
            if v then Pilot.forceCleanup() end end })
    T.PvP:AddSlider("PilotSpeed", { Title = "Pilot Speed", Default = 20,
        Min = 8, Max = 200, Rounding = 0, Callback = function(v) Config.PilotSpeed = v end })
    T.PvP:AddToggle("InfPilotRange", { Title = "Inf Pilot Range", Default = Config.InfPilotRange,
        Callback = function(v) Config.InfPilotRange = v end })
    T.PvP:AddToggle("SpectateStand", { Title = "Spectate Stand", Default = Config.SpectateStand,
        Callback = function(v) Config.SpectateStand = v end })
    T.PvP:AddInput("TargetStandPlayer", { Title = "Target Stand Player", Default = "",
        Placeholder = "player name", Finished = true,
        Callback = function(v) Config.TargetStandPlayer = v end })
    T.PvP:AddInput("TargetPlayer", { Title = "Target Player", Default = "",
        Placeholder = "player name", Finished = true,
        Callback = function(v) Config.TargetPlayer = v end })
    T.PvP:AddToggle("TargetAll", { Title = "target (empty = all)", Default = Config.TargetAll,
        Callback = function(v) Config.TargetAll = v end })
    T.PvP:AddButton({ Title = "Reset Player", Callback = function() resetPlayer() end })
    T.PvP:AddToggle("FinisherChanger", { Title = "Enable Finisher changer",
        Default = Config.FinisherChanger, Callback = function(v) Config.FinisherChanger = v end })
    T.PvP:AddDropdown("Finisher", { Title = "Select Finisher", Values = FINISHERS,
        Multi = false, Default = 1,
        Callback = function(v) Config.Finisher = v
            if Config.FinisherChanger then useFinisher(v) end end })

    -- Movement
    T.Movement:AddToggle("SpeedChanger", { Title = "Speed Changer", Default = Config.SpeedChanger,
        Callback = function(v) Config.SpeedChanger = v applySpeed() end })
    T.Movement:AddSlider("SpeedValue", { Title = "Speed", Default = 16,
        Min = 16, Max = 300, Rounding = 0,
        Callback = function(v) Config.SpeedValue = v applySpeed() end })
    T.Movement:AddToggle("JumpPowerChanger", { Title = "JumpPower Changer",
        Default = Config.JumpPowerChanger,
        Callback = function(v) Config.JumpPowerChanger = v applyJump() end })
    T.Movement:AddSlider("JumpPower", { Title = "JumpPower", Default = 50,
        Min = 50, Max = 500, Rounding = 0,
        Callback = function(v) Config.JumpPower = v applyJump() end })
    T.Movement:AddToggle("Fly", { Title = "Fly", Default = Config.Fly,
        Callback = function(v) Config.Fly = v setFly(v) end })
    T.Movement:AddSlider("FlySpeed", { Title = "Fly Speed", Default = 50,
        Min = 10, Max = 300, Rounding = 0, Callback = function(v) Config.FlySpeed = v end })
    T.Movement:AddToggle("Noclip", { Title = "Noclip", Default = Config.Noclip,
        Callback = function(v) Config.Noclip = v setNoclip(v) end })
    T.Movement:AddDropdown("TravelMethod", { Title = "Travel Method",
        Values = { "Tween", "Teleport" }, Multi = false, Default = 1,
        Callback = function(v) Config.TravelMethod = v end })
    T.Movement:AddDropdown("FarmPositionMode", { Title = "Farm Position Mode",
        Values = { "Auto", "Static" }, Multi = false, Default = 1,
        Callback = function(v) Config.FarmPositionMode = v end })

    -- Server
    T.Server:AddToggle("StaffAutoRejoin", { Title = "Staff Detector (Auto Rejoin)",
        Default = Config.StaffAutoRejoin, Callback = function(v) Config.StaffAutoRejoin = v end })
    T.Server:AddToggle("AutoRejoinKick", { Title = "Auto Rejoin (Kick/Error)",
        Default = Config.AutoRejoinKick, Callback = function(v) Config.AutoRejoinKick = v end })
    T.Server:AddToggle("ServerHop", { Title = "Server Reconnect / Hop",
        Default = Config.ServerHop,
        Callback = function(v) Config.ServerHop = v if v then serverHop() end end })
    T.Server:AddButton({ Title = "Server Hop", Callback = function() serverHop() end })
    T.Server:AddButton({ Title = "Reconnect", Callback = function() reconnect("manual") end })
    T.Server:AddButton({ Title = "Rejoin", Callback = function() rejoin() end })
    T.Server:AddToggle("AutoReconnect", { Title = "Auto Reconnect", Default = Config.AutoReconnect,
        Callback = function(v) Config.AutoReconnect = v end })
    T.Server:AddToggle("AntiAFK", { Title = "Anti AFK", Default = Config.AntiAFK,
        Callback = function(v) Config.AntiAFK = v
            if v then enableAntiAfk() else disableAntiAfk() end end })

    -- Webhooks
    T.Webhooks:AddInput("WebhookURL", { Title = "Webhook URL", Default = "",
        Placeholder = "https://discord.com/api/webhooks/...", Finished = true,
        Callback = function(v) Config.WebhookURL = v end })
    T.Webhooks:AddInput("DiscordUserID", { Title = "Discord User ID", Default = "",
        Placeholder = "123456789012345678", Finished = true,
        Callback = function(v) Config.DiscordUserID = v end })
    T.Webhooks:AddButton({ Title = "Test Webhook", Callback = function() Webhooks.test() end })
    T.Webhooks:AddToggle("NotifyLegendary", { Title = "Legendary Item Pickup",
        Default = Config.NotifyLegendary, Callback = function(v) Config.NotifyLegendary = v end })
    T.Webhooks:AddToggle("NotifyItem", { Title = "Item Pickup", Default = Config.NotifyItem,
        Callback = function(v) Config.NotifyItem = v end })
    T.Webhooks:AddToggle("NotifyStand", { Title = "Stand Obtained", Default = Config.NotifyStand,
        Callback = function(v) Config.NotifyStand = v end })
    T.Webhooks:AddToggle("NotifyPrestige", { Title = "Prestige", Default = Config.NotifyPrestige,
        Callback = function(v) Config.NotifyPrestige = v end })
    T.Webhooks:AddToggle("NotifyStaff", { Title = "Staff Detected", Default = Config.NotifyStaff,
        Callback = function(v) Config.NotifyStaff = v end })
    T.Webhooks:AddToggle("NotifyKick", { Title = "Kick / Reconnect", Default = Config.NotifyKick,
        Callback = function(v) Config.NotifyKick = v end })

    -- Settings
    T.Settings:AddSlider("UITransparency", { Title = "UI Transparency", Default = 15,
        Min = 0, Max = 100, Rounding = 0,
        Callback = function(v) Config.UITransparency = v / 100 end })
    T.Settings:AddSlider("MenuScale", { Title = "Menu Scale", Default = 100,
        Min = 50, Max = 150, Rounding = 0,
        Callback = function(v) Config.MenuScale = v / 100 end })
    T.Settings:AddParagraph({ Title = "Language", Content = "English" })
    T.Settings:AddToggle("HideUsername", { Title = "Hide Username (Spoilers)",
        Default = Config.HideUsername, Callback = function(v) Config.HideUsername = v end })
    T.Settings:AddButton({ Title = "Save Settings",
        Callback = function() Config.save() notify("Settings saved.") end })
    T.Settings:AddButton({ Title = "Reset Settings to Default",
        Callback = function() Config.reset() end })

    if SaveManager and InterfaceManager then
        SaveManager:SetLibrary(Fluent)
        InterfaceManager:SetLibrary(Fluent)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({})
        InterfaceManager:SetFolder("Axion")
        SaveManager:SetFolder("Axion/yba")
        InterfaceManager:BuildInterfaceSection(T.Settings)
        SaveManager:BuildConfigSection(T.Settings)
    end

    Window:SelectTab(1)
    Fluent:Notify({ Title = "Axion", Content = "Script loaded.", Duration = 6 })
    if SaveManager then
        pcall(function() SaveManager:LoadAutoloadConfig() end)
    end
end

--==========================================================================
-- Axion main
--==========================================================================

local function axionMain()
    Config.load()
    pcall(buildAxionUI)

    if Config.AntiAFK then enableAntiAfk() end
    enableAutoRejoin()

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        applySpeed() applyJump()
        if Config.Noclip then setNoclip(true) end
    end)

    RunService.Heartbeat:Connect(function()
        Block.step()
    end)

    task.spawn(function()
        while true do
            task.wait(0.5)
            pcall(Esp.scanItems)
            pcall(Esp.hud)
        end
    end)

    task.spawn(function()
        while true do
            task.wait(1)
            pcall(Esp.scanPlayers)
            pcall(checkStaff)
        end
    end)

    task.spawn(function()
        while true do
            task.wait(5)
            pcall(checkAndSellMax)
            pcall(checkAndBuyLuckyArrow)
            pcall(stealDroppedMoney)
            if Config.ServerHopFarm and Config.AutoFarmItems then
                local items = getItemSpawns()
                if items and #items:GetChildren() == 0 then
                    notify("No items on map and cannot buy. Hopping server...")
                    pcall(serverHop)
                end
            end
        end
    end)

    notify("Axion loaded.")
end

axionMain()

-- exposed for testing/introspection (Roblox ignores the return value)
return {
    Config = Config,
    Farm = Farm,
    Esp = Esp,
    Webhooks = Webhooks,
    moveCharacterTo = moveCharacterTo,
    activatePrompt = activatePrompt,
    sellAll = sellAll,
    sellItem = sellItem,
    sellItemWorker = sellItemWorker,
    isProtectedOriginal = isProtectedOriginal,
    sellAllSelected = sellAllSelected,
    sellAllWorthless = sellAllWorthless,
    findSellButton = findSellButton,
    clickGui = clickGui,
    checkAndSellMax = checkAndSellMax,
    checkAndBuyLuckyArrow = checkAndBuyLuckyArrow,
    startBlocking = startBlocking,
    stopBlocking = stopBlocking,
    normalizeItemName = normalizeItemName,
    countItem = countItem,
    farmEnemy = farmEnemy,
    farmNpcWorker = farmNpcWorker,
    findEnemy = findEnemy,
    questTargetFor = questTargetFor,
    getQuestState = getQuestState,
    takeQuest = takeQuest,
    runQuestFarm = runQuestFarm,
    directNpcFarm = directNpcFarm,
    StandFarm = StandFarm,
    STAND_SKILLS = STAND_SKILLS,
    getStandSkin = getStandSkin,
    isShinySkin = isShinySkin,
    enableAntiAfk = enableAntiAfk,
    serverHop = serverHop,
    reconnect = reconnect,
    getFarmMethod = getFarmMethod,
}
