local requiredFields = {"Stand", "Create", "Stop", "sendChat", "getPlayer", "ownerPlayer", "Notify"}
local function isAPIReady()
    local api = getgenv().SocietyStandAPI
    if not api then return false end
    for _, field in ipairs(requiredFields) do
        if api[field] == nil then
            return false
        end
    end
    return true
end

repeat task.wait() until isAPIReady()
local API = getgenv().SocietyStandAPI

if not API or not API.Stand then
    warn("SocietyStandAPI not properly initialized")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Stand = API.Stand

-- Ensure LocalPlayer is available
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- Install CHECKER_1 anticheat bypass
local function installCheckerBypass()
    if getgenv().SocietyStandDaHoodCheckerBypass then
        return
    end

    local hookMeta = hookmetamethod
    local getNamecallMethod = getnamecallmethod
    local checkCaller = checkcaller

    if type(hookMeta) ~= "function" or type(getNamecallMethod) ~= "function" or type(checkCaller) ~= "function" then
        return
    end

    local ok, mainEvent = pcall(function()
        return ReplicatedStorage:WaitForChild("MainEvent", 5)
    end)

    if not ok or not mainEvent then
        return
    end

    local oldNamecall
    oldNamecall = hookMeta(game, "__namecall", function(self, ...)
        local method = getNamecallMethod()
        if not checkCaller() and self == mainEvent and method == "FireServer" then
            local args = {...}
            if args[1] == "CHECKER_1" or args[1] == "TeleportDetect" or args[1] == "CHECKER" then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end)

    getgenv().SocietyStandDaHoodCheckerBypass = true
    print("[Da Hood Config] CHECKER_1 anticheat bypass active")
end

local bypassSuccess, bypassError = pcall(installCheckerBypass)
if not bypassSuccess and bypassError then
    warn("[Da Hood Config] Failed to install CHECKER_1 bypass:", bypassError)
end

-- Disable detected commands that use BodyVelocity/BodyGyro
local DETECTED_FUNCTIONS = {
    bodygyro = true,
    bodyvelocity = true,
    updatemousepos = true
}

API.DetectedFunctionsInfo = API.DetectedFunctionsInfo or {}
API.DetectedFunctionsInfo.detectedFunctions = API.DetectedFunctionsInfo.detectedFunctions or {}
API.DetectedFunctionsInfo.disabledCommands = API.DetectedFunctionsInfo.disabledCommands or {}

for funcName, flagged in pairs(DETECTED_FUNCTIONS) do
    API.DetectedFunctionsInfo.detectedFunctions[funcName] = flagged
end

local disableCommand = API.DisableCommand or API.disableCommand
local disableReason = "Uses BodyVelocity/BodyGyro (detected function)"

local function disableDetectedCommand(commandName)
    if disableCommand then
        disableCommand(commandName, disableReason)
    else
        API.DetectedFunctionsInfo.disabledCommands[commandName] = disableReason
        if API.RemoveCommand then
            API.RemoveCommand(commandName)
        elseif API.Commands and API.Commands[commandName] then
            API.Commands[commandName] = nil
        end
        warn("[Anticheat Protection] Command '" .. commandName .. "' disabled: " .. disableReason)
    end
end

for _, cmdName in ipairs({"fling", "punch", "slam", "roof", "lift"}) do
    disableDetectedCommand(cmdName)
end

print("[Da Hood Config] Anticheat protection: Disabled commands that use BodyVelocity/BodyGyro")

-- Track who kills/stomps the owner for revenge
local function markKillerFromBodyEffects(bodyEffects, reason)
    if not bodyEffects then return end
    local creatorValue = bodyEffects:FindFirstChild("Creator")
    if creatorValue and creatorValue.Value and creatorValue.Value:IsA("Player") then
        lastKiller = creatorValue.Value
        print(string.format("[Revenge Tracker] Marked %s via %s", lastKiller.Name, reason or "Creator"))
        return
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local theirAttacking = Attacking(player)
            if theirAttacking and theirAttacking.Value == true then
                lastKiller = player
                print(string.format("[Revenge Tracker] Marked %s via %s fallback", player.Name, reason or "attack"))
                break
            end
        end
    end
end

local function detectStomper(character)
    if not character then return nil end
    local upperTorso = character:FindFirstChild("UpperTorso")
    if not upperTorso then return nil end
    
    local upperTorsoPos = upperTorso.Position
    local closestPlayer = nil
    local bestScore = math.huge
    
    local HORIZONTAL_THRESHOLD = 4
    local VERTICAL_MIN = 0.5
    local VERTICAL_MAX = 6
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local theirRoot = getRoot(player)
            if theirRoot then
                local offset = theirRoot.Position - upperTorsoPos
                local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
                local verticalDistance = offset.Y
                if horizontalDistance <= HORIZONTAL_THRESHOLD and verticalDistance >= VERTICAL_MIN and verticalDistance <= VERTICAL_MAX then
                    local score = horizontalDistance + math.abs(verticalDistance - VERTICAL_MIN)
                    if score < bestScore then
                        bestScore = score
                        closestPlayer = player
                    end
                end
            end
        end
    end
    
    return closestPlayer
end

local function attachRevengeTracker(character)
    if not character then return end
    task.spawn(function()
        local bodyEffects = character:WaitForChild("BodyEffects", 10)
        if not bodyEffects then return end
        
        local function onCreator(valueObj)
            if not valueObj then return end
            valueObj:GetPropertyChangedSignal("Value"):Connect(function()
                if valueObj.Value and valueObj.Value:IsA("Player") then
                    lastKiller = valueObj.Value
                    print("[Revenge Tracker] Creator set to " .. lastKiller.Name)
                end
            end)
        end
        
        local function onBoolean(valueObj, label)
            if not valueObj then return end
            valueObj:GetPropertyChangedSignal("Value"):Connect(function()
                if valueObj.Value == true then
                    if label == "Dead" then
                        local stomper = detectStomper(character)
                        if stomper then
                            lastKiller = stomper
                            print(string.format("[Revenge Tracker] Detected stomper: %s (standing on UpperTorso)", stomper.Name))
                            return
                        end
                    end
                    markKillerFromBodyEffects(bodyEffects, label)
                end
            end)
        end
        
        local function connectWhenAvailable(name, callback)
            local existing = bodyEffects:FindFirstChild(name)
            if existing then
                callback(existing)
            end
            bodyEffects.ChildAdded:Connect(function(child)
                if child.Name == name then
                    callback(child)
                end
            end)
        end
        
        connectWhenAvailable("Creator", onCreator)
        connectWhenAvailable("K.O", function(value)
            onBoolean(value, "K.O")
        end)
        connectWhenAvailable("Dead", function(value)
            onBoolean(value, "Dead")
        end)
    end)
end

if LocalPlayer.Character then
    attachRevengeTracker(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(attachRevengeTracker)

-- Helper functions
local function getLocalPlayer()
    return Players.LocalPlayer
end

local function getLocalCharacter()
    local success, result = pcall(function()
        local player = getLocalPlayer()
        if not player then return nil end
        return player.Character
    end)
    return success and result or nil
end

local function getLocalHumanoid()
    local character = getLocalCharacter()
    if not character then return nil end
    
    local success, result = pcall(function()
        return character:FindFirstChildOfClass("Humanoid")
    end)
    return success and result or nil
end

local function getLocalHRP()
    local character = getLocalCharacter()
    if not character then return nil end
    
    local success, result = pcall(function()
        return character:FindFirstChild("HumanoidRootPart")
    end)
    return success and result or nil
end

local function getVehiclesFolder()
    return Workspace:FindFirstChild("Vehicles")
end

local function getRoot(player)
    if not player or not player.Character then return nil end
    local success, result = pcall(function()
        return player.Character:FindFirstChild("HumanoidRootPart")
    end)
    return success and result or nil
end

local function getHumanoid(player)
    if not player or not player.Character then return nil end
    local success, result = pcall(function()
        return player.Character:FindFirstChildOfClass("Humanoid")
    end)
    return success and result or nil
end

local function getTorso(player)
    if not player or not player.Character then return nil end
    local success, result = pcall(function()
        return player.Character:FindFirstChild("UpperTorso")
    end)
    return success and result or nil
end

local function KO(player)
    if not player or not player.Character then return nil end
    local success, result = pcall(function()
        if player.Character:FindFirstChild("BodyEffects") and 
           player.Character.BodyEffects:FindFirstChild("K.O") then
            return player.Character.BodyEffects["K.O"]
        end
        return nil
    end)
    return success and result or nil
end

local function isDead(player)
    if not player or not player.Character then return false end
    local success, result = pcall(function()
        if player.Character:FindFirstChild("BodyEffects") and 
           player.Character.BodyEffects:FindFirstChild("Dead") then
            return player.Character.BodyEffects.Dead.Value == true
        end
        return false
    end)
    return success and result or false
end

local function hasReduceWalk(player)
    if not player or not player.Character then return false end
    local success, result = pcall(function()
        return player.Character:FindFirstChild("BodyEffects") and 
               player.Character.BodyEffects:FindFirstChild("Movement") and
               player.Character.BodyEffects.Movement:FindFirstChild("ReduceWalk") ~= nil
    end)
    return success and result or false
end

local function isInVehicle(player)
    if not player then return false end
    local success, result = pcall(function()
        local vehiclesFolder = getVehiclesFolder()
        if not vehiclesFolder then return false end
        return vehiclesFolder:FindFirstChild(player.Name) ~= nil
    end)
    return success and result or false
end

local function Attacking(player)
    if not player or not player.Character then return nil end
    local success, result = pcall(function()
        if player.Character:FindFirstChild("BodyEffects") and 
           player.Character.BodyEffects:FindFirstChild("Attacking") then
            return player.Character.BodyEffects.Attacking
        end
        return nil
    end)
    return success and result or nil
end

local function Equip(itemName)
    local success = pcall(function()
        if not LocalPlayer.Character:FindFirstChild(itemName) then
            if LocalPlayer.Backpack:FindFirstChild(itemName) then
                LocalPlayer.Backpack:FindFirstChild(itemName).Parent = LocalPlayer.Character
            end
        end
    end)
    return success
end

local function Hit()
    local success = pcall(function()
        local tool = LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
        if tool then
            tool:Activate()
        end
    end)
    return success
end

local GUN_NAME = "[LMG]"
local LMG_SHOP_ITEM = "[LMG] - $4098"
local LMG_AMMO_ITEM = "200 [LMG Ammo] - $328"
local ShopFolder

local function getShopFolder()
    if ShopFolder and ShopFolder.Parent then
        return ShopFolder
    end
    local ignored = Workspace:FindFirstChild("Ignored")
    if not ignored then
        return nil
    end
    ShopFolder = ignored:FindFirstChild("Shop")
    return ShopFolder
end

local function hasTool(toolName)
    local character = getLocalCharacter()
    if character and character:FindFirstChild(toolName) then
        return true
    end
    local backpack = LocalPlayer and LocalPlayer:FindFirstChild("Backpack")
    if backpack and backpack:FindFirstChild(toolName) then
        return true
    end
    return false
end

local function getTool(toolName)
    local character = getLocalCharacter()
    if character and character:FindFirstChild(toolName) then
        return character:FindFirstChild(toolName)
    end
    local backpack = LocalPlayer and LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        return backpack:FindFirstChild(toolName)
    end
    return nil
end

local function ensureToolEquipped(toolName)
    local character = getLocalCharacter()
    if not character then return nil end
    local tool = character:FindFirstChild(toolName)
    if tool then
        return tool
    end
    local backpack = LocalPlayer and LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        tool = backpack:FindFirstChild(toolName)
        if tool then
            tool.Parent = character
            task.wait()
            return tool
        end
    end
    return nil
end

local function getClickDetectorFunc()
    if typeof(fireclickdetector) == "function" then
        return fireclickdetector
    end
    local env = (typeof(getgenv) == "function") and getgenv()
    if env and typeof(env.fireclickdetector) == "function" then
        return env.fireclickdetector
    end
    return nil
end

local function buyShopItem(shopItemName, expectedToolName, attempts)
    local shopFolder = getShopFolder()
    if not shopFolder then
        return false, "Shop folder missing"
    end
    local shopItem = shopFolder:FindFirstChild(shopItemName)
    if not shopItem then
        return false, "Shop item '" .. shopItemName .. "' not found"
    end
    local head = shopItem:FindFirstChild("Head")
    local detector = shopItem:FindFirstChild("ClickDetector")
    if not head or not detector then
        return false, "Shop item incomplete"
    end
    local hrp = getLocalHRP()
    if not hrp then
        return false, "HumanoidRootPart missing"
    end
    local originalCFrame
    pcall(function()
        originalCFrame = hrp.CFrame
        hrp.CFrame = head.CFrame * CFrame.new(0, 3, 0)
    end)
    task.wait(0.15)
    local clickFunction = getClickDetectorFunc()
    if not clickFunction then
        pcall(function()
            if originalCFrame then
                hrp.CFrame = originalCFrame
            end
        end)
        return false, "fireclickdetector unavailable"
    end
    local success = false
    local attemptsCount = attempts or 5
    for _ = 1, attemptsCount do
        pcall(function()
            clickFunction(detector)
        end)
        task.wait(0.2)
        if not expectedToolName or hasTool(expectedToolName) then
            success = true
            break
        end
    end
    pcall(function()
        if originalCFrame then
            hrp.CFrame = originalCFrame
        end
    end)
    return success, success and "Purchased" or "Purchase failed"
end

local function buyLMG(ammoPurchases)
    local hasGun = hasTool(GUN_NAME)
    if not hasGun then
        local success, message = buyShopItem(LMG_SHOP_ITEM, GUN_NAME, 8)
        if not success then
            return false, message
        end
    end
    local purchases = ammoPurchases or 6
    for _ = 1, purchases do
        buyShopItem(LMG_AMMO_ITEM, nil, 1)
    end
    return true, hasGun and "ammo_only" or "full_purchase"
end

-- MainEvent reference
local MainEvent = ReplicatedStorage:WaitForChild("MainEvent", 5)

local ZERO_VECTOR = Vector3.new(0, 0, 0)

-- Revenge tracking
local lastKiller = nil

-- Holster/unequip all tools
local function unequipAllTools()
    pcall(function()
        local humanoid = getLocalHumanoid()
        if humanoid then
            humanoid:UnequipTools()
        end
    end)
end

local function shootTargetWithGun(target, gun)
    if not target or not gun or not MainEvent then
        return false
    end
    local handle = gun:FindFirstChild("Handle")
    local head = target.Character and target.Character:FindFirstChild("Head")
    if not handle or not head then
        return false
    end
    pcall(function()
        MainEvent:FireServer("ShootGun", handle, handle.Position, head.Position, head, ZERO_VECTOR)
    end)
    return true
end

local function reloadGunIfNeeded(gun)
    if not gun or not MainEvent then return end
    local ammo = gun:FindFirstChild("Ammo")
    if ammo and ammo.Value <= 0 then
        MainEvent:FireServer("Reload", gun)
    end
end

local function gunKnockTarget(target, options)
    options = options or {}
    local timeout = options.timeout or 30
    local gunName = options.gunName or GUN_NAME
    local targetKO = KO(target)
    if not targetKO then
        return false, "invalid target"
    end
    local startTime = tick()
    while target.Character and not isDead(target) and targetKO.Value == false do
        if tick() - startTime > timeout then
            return false, "timeout"
        end
        local gun = ensureToolEquipped(gunName)
        if not gun then
            return false, "missing weapon"
        end
        local shotSuccess = shootTargetWithGun(target, gun)
        if not shotSuccess then
            return false, "failed to shoot"
        end
        reloadGunIfNeeded(gun)
        RunService.Heartbeat:Wait()
    end
    return targetKO.Value == true, targetKO.Value and "Target knocked" or "Target lost"
end

local function stompTarget(target)
    local targetTorso = getTorso(target)
    local myHRP = getLocalHRP()
    if not targetTorso or not myHRP or not MainEvent then
        return false
    end
    local success = pcall(function()
        myHRP.CFrame = CFrame.new(targetTorso.Position + Vector3.new(0, 5, 0))
        task.wait(0.1)
        MainEvent:FireServer("Stomp")
    end)
    return success
end

local function resolveTargetFromArgs(args)
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    if target then
        return target, playerName
    end
    local lowerName = playerName:lower()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and 
           (player.Name:lower():find(lowerName, 1, true) or 
           (player.DisplayName and player.DisplayName:lower():find(lowerName, 1, true))) then
            return player, playerName
        end
    end
    return nil, playerName
end

-- AutoPredic value (prediction multiplier)
local AutoPredic = 0.155

-- Strafe defaults for gun commands
local STRAFE_DEFAULTS = {
    height = 8,
    radius = 10,
    rotationSpeed = (2 * math.pi) / 0.7,
    mode = "Sky"
}

local function startGunStrafe(target, config)
    config = config or {}
    local mode = config.mode or STRAFE_DEFAULTS.mode
    local height = config.height or STRAFE_DEFAULTS.height
    local radius = math.max(config.radius or STRAFE_DEFAULTS.radius, 4)
    local rotationSpeed = config.rotationSpeed or STRAFE_DEFAULTS.rotationSpeed
    local angle = 0
    local connection

    connection = RunService.Heartbeat:Connect(function(dt)
        local myHRP = getLocalHRP()
        local targetRoot = getRoot(target)
        local targetHumanoid = getHumanoid(target)

        if not myHRP or not targetRoot or not targetHumanoid or not target or not target.Character then
            return
        end

        angle = (angle + rotationSpeed * dt) % (math.pi * 2)

        local predictedPosition = targetRoot.Position
        local success, prediction = pcall(function()
            return targetHumanoid.MoveDirection * AutoPredic * targetHumanoid.WalkSpeed
        end)
        if success and prediction then
            predictedPosition += prediction
        end

        local offsetY
        if mode == "Under" then
            if targetHumanoid.FloorMaterial == Enum.Material.Air then
                offsetY = -height - 8
            else
                offsetY = -height - 2
            end
        else
            offsetY = height
        end

        local orbitCenter = predictedPosition + Vector3.new(0, offsetY, 0)
        local orbitCFrame = CFrame.new(orbitCenter) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, radius)

        pcall(function()
            myHRP.CFrame = orbitCFrame
            local humanoid = getLocalHumanoid()
            if humanoid then
                for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
                    local animationId = track.Animation and track.Animation.AnimationId or ""
                    if animationId:find("3541114300") or animationId:find("3084858603") or animationId:find("13850634687") then
                        track:Stop()
                    end
                end
            end
        end)
    end)

    return function()
        if connection then
            connection:Disconnect()
            connection = nil
        end
    end
end

-- TargetMelee function from stando.luau
local function TargetMelee(target)
    if not target or isDead(target) then return end
    
    local q = getRoot(target)
    local e = getHumanoid(target)
    local t = getLocalHRP()
    
    if not q or not e or not t then return end
    
    pcall(function()
        -- Stop all animations
        local humanoid = getLocalHumanoid()
        if humanoid then
            for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
                track:Stop()
            end
        end
        
        -- Position the stand
        if isInVehicle(target) then
            -- Vehicle handling
            local vehiclesFolder = getVehiclesFolder()
            local vehicle = vehiclesFolder and vehiclesFolder:FindFirstChild(target.Name)
            if vehicle then
                local vehicleVelocity = Vector3.new(0, 0, 0)
                pcall(function()
                    if vehicle:IsA("Model") then
                        local primaryPart = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart")
                        if primaryPart then
                            vehicleVelocity = primaryPart.AssemblyLinearVelocity or primaryPart.Velocity or Vector3.new(0, 0, 0)
                        end
                    elseif vehicle:IsA("BasePart") then
                        vehicleVelocity = vehicle.AssemblyLinearVelocity or vehicle.Velocity or Vector3.new(0, 0, 0)
                    end
                end)
                
                t.CFrame = CFrame.new(q.Position + vehicleVelocity * 0.4)
            end
        elseif hasReduceWalk(LocalPlayer) then
            -- ReduceWalk active - use MoveDirection prediction
            if e.FloorMaterial == Enum.Material.Air then
                -- Target is jumping/falling
                t.CFrame = CFrame.new(q.Position + Vector3.new(0, -6.8, 0) + e.MoveDirection * AutoPredic * e.WalkSpeed) * CFrame.Angles(math.pi * 0.5, 0, 0)
            else
                -- Target on ground
                t.CFrame = CFrame.new(q.Position + Vector3.new(0, 0, 0) + e.MoveDirection * AutoPredic * e.WalkSpeed)
            end
        else
            -- Normal prediction using velocity
            if e.FloorMaterial == Enum.Material.Air then
                t.CFrame = CFrame.new(q.Position.X + q.Velocity.X * AutoPredic, q.Position.Y + q.Velocity.Y * 0, q.Position.Z + q.Velocity.Z * AutoPredic) * CFrame.new(0, -6.8, 0) * CFrame.Angles(math.pi * 0.5, 0, 0)
            else
                t.CFrame = CFrame.new(q.Position.X + q.Velocity.X * AutoPredic, q.Position.Y + 0, q.Position.Z + q.Velocity.Z * AutoPredic)
            end
        end
        
        -- Set camera subject
        Workspace.Camera.CameraSubject = e
    end)
end

-- Knock command
API.Create("knock", function(args)
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    
    if not target then
        local lowerName = playerName:lower()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and 
               (player.Name:lower():find(lowerName, 1, true) or 
               (player.DisplayName and player.DisplayName:lower():find(lowerName, 1, true))) then
                target = player
                break
            end
        end
    end
    
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    
    if isDead(target) then
        API.sendChat("Target is already dead!")
        return
    end
    
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    
    if targetKO.Value == true then
        API.sendChat(target.Name .. " is already knocked out!")
        return
    end
    
    -- Save original state
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    -- Stop current actions
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    -- Equip combat
    if not LocalPlayer.Character:FindFirstChild("Combat") then
        if LocalPlayer.Backpack:FindFirstChild("Combat") then
            LocalPlayer.Backpack:FindFirstChild("Combat").Parent = LocalPlayer.Character
        end
    end
    
    API.sendChat("Knocking " .. target.Name .. "...")
    
    -- Knock loop
    local knockStartTime = tick()
    local timeout = 30 -- 30 second timeout
    
    task.spawn(function()
        repeat
            RunService.Stepped:Wait()
            
            if not target.Character or isDead(target) then
                break
            end
            
            if targetKO.Value == false then
                -- Continue attacking
                Equip("Combat")
                if MainEvent then
                    MainEvent:FireServer("ChargeButton")
                end
                TargetMelee(target)
            else
                -- Target is knocked out
                break
            end
            
            -- Check timeout
            if tick() - knockStartTime > timeout then
                API.sendChat("Knock timeout!")
                break
            end
            
        until targetKO.Value == true or not target.Character or isDead(target)
        
        -- Cleanup - wait for attacking animation to finish
        local attackingValue = Attacking(LocalPlayer)
        if attackingValue then
            local waitStart = tick()
            while attackingValue.Value == true and tick() - waitStart < 5 do
                task.wait(0.1)
            end
        end
        
        -- Reset camera
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        -- Restore original state
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
        
        if targetKO.Value == true then
            API.sendChat(target.Name .. " has been knocked out!")
        end
        
        -- Return to owner (summon)
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

-- Stomp command
API.Create("stomp", function(args)
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    
    if not target then
        local lowerName = playerName:lower()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and 
               (player.Name:lower():find(lowerName, 1, true) or 
               (player.DisplayName and player.DisplayName:lower():find(lowerName, 1, true))) then
                target = player
                break
            end
        end
    end
    
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    
    if isDead(target) then
        API.sendChat("Target is already dead!")
        return
    end
    
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    
    -- Save original state
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    -- Stop current actions
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    local function performStomp()
        local targetTorso = getTorso(target)
        local myHRP = getLocalHRP()
        
        if not targetTorso or not myHRP then return false end
        
        pcall(function()
            myHRP.CFrame = CFrame.new(targetTorso.Position + Vector3.new(0, 5, 0))
            task.wait(0.1)
            if MainEvent then
                MainEvent:FireServer("Stomp")
            end
        end)
        
        return true
    end
    
    API.sendChat("Stomping " .. target.Name .. "...")
    
    task.spawn(function()
        -- First knock them out if not already KO'd
        if targetKO.Value == false then
            -- Equip combat
            if not LocalPlayer.Character:FindFirstChild("Combat") then
                if LocalPlayer.Backpack:FindFirstChild("Combat") then
                    LocalPlayer.Backpack:FindFirstChild("Combat").Parent = LocalPlayer.Character
                end
            end
            
            -- Knock loop
            local knockStartTime = tick()
            local timeout = 30
            
            repeat
                RunService.Stepped:Wait()
                
                if not target.Character or isDead(target) then
                    break
                end
                
                if targetKO.Value == false then
                    Equip("Combat")
                    if MainEvent then
                        MainEvent:FireServer("ChargeButton")
                    end
                    TargetMelee(target)
                else
                    break
                end
                
                if tick() - knockStartTime > timeout then
                    API.sendChat("Knock timeout!")
                    break
                end
                
            until targetKO.Value == true or not target.Character or isDead(target)
            
            -- Wait for attacking animation to finish
            local attackingValue = Attacking(LocalPlayer)
            if attackingValue then
                local waitStart = tick()
                while attackingValue.Value == true and tick() - waitStart < 5 do
                    task.wait(0.1)
                end
            end
        end
        
        -- Now stomp
        if targetKO.Value == true and not isDead(target) then
            performStomp()
            task.wait(0.5)
            
            if isDead(target) then
                API.sendChat(target.Name .. " has been stomped!")
            else
                API.sendChat("Stomped " .. target.Name)
            end
        end
        
        -- Reset camera
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        -- Restore original state
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
    end)
end)

-- Gun command (buys LMG)
API.Create("gun", function(args)
    local alreadyOwned = hasTool(GUN_NAME)
    if alreadyOwned then
        API.sendChat("LMG detected, restocking ammo...")
    else
        API.sendChat("Buying LMG and ammo...")
    end
    Stand.Attacking = false
    Stand.Following = false
    task.spawn(function()
        local success, result = buyLMG(8)
        if success then
            if result == "ammo_only" then
                API.sendChat("LMG ammo restocked!")
            else
                API.sendChat("LMG purchased with ammo!")
            end
            local ownerRoot = getRoot(API.ownerPlayer)
            local myHRP = getLocalHRP()
            if ownerRoot and myHRP then
                pcall(function()
                    myHRP.CFrame = ownerRoot.CFrame * CFrame.new(0, 2, 3)
                end)
            end
            task.wait(0.3)
            Stand.Following = true
        else
            API.sendChat("Failed to buy LMG: " .. (result or "unknown error"))
        end
    end)
end)

-- GKnock command (gun knock using ShootGun)
API.Create("gknock", function(args)
    local target, playerName = resolveTargetFromArgs(args)
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    if isDead(target) then
        API.sendChat("Target is already dead!")
        return
    end
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    if targetKO.Value == true then
        API.sendChat(target.Name .. " is already knocked out!")
        return
    end
    local tool = ensureToolEquipped(GUN_NAME)
    if not tool then
        API.sendChat("No LMG found! Use 'gun' command first.")
        return
    end
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    API.sendChat("Gun knocking " .. target.Name .. "...")
    task.spawn(function()
        local stopStrafe = startGunStrafe(target, {mode = "Sky", height = 8, radius = 10})
        
        local startTime = tick()
        local timeout = 30
        
        while target.Character and not isDead(target) and targetKO.Value == false do
            if tick() - startTime > timeout then
                API.sendChat("Gun knock timeout!")
                break
            end
            
            local gun = ensureToolEquipped(GUN_NAME)
            if not gun then
                API.sendChat("Lost weapon!")
                break
            end
            
            local shotSuccess = shootTargetWithGun(target, gun)
            if not shotSuccess then
                API.sendChat("Failed to shoot!")
                break
            end
            
            reloadGunIfNeeded(gun)
            RunService.Heartbeat:Wait()
        end
        
        stopStrafe()
        
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
        
        if targetKO.Value == true then
            API.sendChat(target.Name .. " has been gun knocked out!")
        end
        
        -- Unequip gun after command
        unequipAllTools()
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

-- GStomp command (gun stomp using ShootGun)
API.Create("gstomp", function(args)
    local target, playerName = resolveTargetFromArgs(args)
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    if isDead(target) then
        API.sendChat("Target is already dead!")
        return
    end
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    local tool = ensureToolEquipped(GUN_NAME)
    if not tool then
        API.sendChat("No LMG found! Use 'gun' command first.")
        return
    end
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    API.sendChat("Gun stomping " .. target.Name .. "...")
    task.spawn(function()
        local stopStrafe = nil
        
        if targetKO.Value == false then
            stopStrafe = startGunStrafe(target, {mode = "Sky", height = 8, radius = 10})
            
            local startTime = tick()
            local timeout = 30
            
            while target.Character and not isDead(target) and targetKO.Value == false do
                if tick() - startTime > timeout then
                    API.sendChat("Gun knock timeout!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    return
                end
                
                local gun = ensureToolEquipped(GUN_NAME)
                if not gun then
                    API.sendChat("Lost weapon!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    return
                end
                
                local shotSuccess = shootTargetWithGun(target, gun)
                if not shotSuccess then
                    API.sendChat("Failed to shoot!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    return
                end
                
                reloadGunIfNeeded(gun)
                RunService.Heartbeat:Wait()
            end
            
            if stopStrafe then
                stopStrafe()
                stopStrafe = nil
            end
        end
        
        if targetKO.Value == true and not isDead(target) then
            stompTarget(target)
            task.wait(0.5)
            if isDead(target) then
                API.sendChat(target.Name .. " has been gun stomped!")
            else
                API.sendChat("Stomped " .. target.Name)
            end
        end
        
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
        
        -- Unequip gun after command
        unequipAllTools()
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

-- Bring command (grab and bring knocked target to owner)
API.Create("bring", function(args)
    local target, playerName = resolveTargetFromArgs(args)
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    if isDead(target) then
        API.sendChat("Target is already dead!")
        return
    end
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    API.sendChat("Bringing " .. target.Name .. "...")
    
    task.spawn(function()
        -- First knock them out if not already KO'd
        if targetKO.Value == false then
            if not LocalPlayer.Character:FindFirstChild("Combat") then
                if LocalPlayer.Backpack:FindFirstChild("Combat") then
                    LocalPlayer.Backpack:FindFirstChild("Combat").Parent = LocalPlayer.Character
                end
            end
            
            local knockStartTime = tick()
            local timeout = 30
            
            repeat
                RunService.Stepped:Wait()
                
                if not target.Character or isDead(target) then
                    break
                end
                
                if targetKO.Value == false then
                    Equip("Combat")
                    if MainEvent then
                        MainEvent:FireServer("ChargeButton")
                    end
                    TargetMelee(target)
                else
                    break
                end
                
                if tick() - knockStartTime > timeout then
                    API.sendChat("Knock timeout!")
                    break
                end
                
            until targetKO.Value == true or not target.Character or isDead(target)
            
            local attackingValue = Attacking(LocalPlayer)
            if attackingValue then
                local waitStart = tick()
                while attackingValue.Value == true and tick() - waitStart < 5 do
                    task.wait(0.1)
                end
            end
        end
        
        -- Now grab and bring them
        if targetKO.Value == true and not isDead(target) and API.ownerPlayer and API.ownerPlayer.Character then
            local targetTorso = getTorso(target)
            local myHRP = getLocalHRP()
            local ownerRoot = getRoot(API.ownerPlayer)
            
            if targetTorso and myHRP and ownerRoot then
                local bringAttempts = 0
                repeat
                    bringAttempts = bringAttempts + 1
                    
                    if not target.Character then
                        break
                    end
                    
                    local updatedTorso = getTorso(target)
                    if updatedTorso then
                        targetTorso = updatedTorso
                    end
                    
                    if targetTorso then
                        pcall(function()
                            myHRP.CFrame = CFrame.new(targetTorso.Position) * CFrame.new(0, 3, 0)
                        end)
                    end
                    
                    task.wait(0.2)
                    
                    if MainEvent then
                        MainEvent:FireServer("Grabbing")
                    end
                    
                    task.wait(0.3)
                    
                    pcall(function()
                        local updatedOwnerRoot = getRoot(API.ownerPlayer)
                        if updatedOwnerRoot then
                            ownerRoot = updatedOwnerRoot
                        end
                        if ownerRoot then
                            myHRP.CFrame = ownerRoot.CFrame * CFrame.new(0, 2, 3)
                        end
                    end)
                    
                    task.wait(0.2)
                    
                until (not target.Character) or target.Character:FindFirstChild("GRABBING_CONSTRAINT") or targetKO.Value == false or bringAttempts >= 5
                
                local finalTorso = getTorso(target) or targetTorso
                local finalOwnerRoot = getRoot(API.ownerPlayer) or ownerRoot
                if target.Character and finalTorso and finalOwnerRoot and (target.Character:FindFirstChild("GRABBING_CONSTRAINT") or (finalTorso.Position - finalOwnerRoot.Position).Magnitude < 15) then
                    API.sendChat(target.Name .. " has been brought!")
                else
                    API.sendChat("Failed to grab " .. target.Name)
                end
            end
        end
        
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

-- GBring command (gun bring)
API.Create("gbring", function(args)
    local target, playerName = resolveTargetFromArgs(args)
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    if isDead(target) then
        API.sendChat("Target is already dead!")
        return
    end
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    local tool = ensureToolEquipped(GUN_NAME)
    if not tool then
        API.sendChat("No LMG found! Use 'gun' command first.")
        return
    end
    
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    API.sendChat("Gun bringing " .. target.Name .. "...")
    
    task.spawn(function()
        local stopStrafe = nil
        
        -- Knock with gun if not already KO'd
        if targetKO.Value == false then
            stopStrafe = startGunStrafe(target, {mode = "Sky", height = 8, radius = 10})
            
            local startTime = tick()
            local timeout = 30
            
            while target.Character and not isDead(target) and targetKO.Value == false do
                if tick() - startTime > timeout then
                    API.sendChat("Gun knock timeout!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    unequipAllTools()
                    return
                end
                
                local gun = ensureToolEquipped(GUN_NAME)
                if not gun then
                    API.sendChat("Lost weapon!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    return
                end
                
                local shotSuccess = shootTargetWithGun(target, gun)
                if not shotSuccess then
                    API.sendChat("Failed to shoot!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    unequipAllTools()
                    return
                end
                
                reloadGunIfNeeded(gun)
                RunService.Heartbeat:Wait()
            end
            
            if stopStrafe then
                stopStrafe()
                stopStrafe = nil
            end
        end
        
        -- Now grab and bring them
        if targetKO.Value == true and not isDead(target) and API.ownerPlayer and API.ownerPlayer.Character then
            local targetTorso = getTorso(target)
            local myHRP = getLocalHRP()
            local ownerRoot = getRoot(API.ownerPlayer)
            
            if targetTorso and myHRP and ownerRoot then
                local bringAttempts = 0
                repeat
                    bringAttempts = bringAttempts + 1
                    
                    if not target.Character then
                        break
                    end
                    
                    local updatedTorso = getTorso(target)
                    if updatedTorso then
                        targetTorso = updatedTorso
                    end
                    
                    if targetTorso then
                        pcall(function()
                            myHRP.CFrame = CFrame.new(targetTorso.Position) * CFrame.new(0, 3, 0)
                        end)
                    end
                    
                    task.wait(0.2)
                    
                    if MainEvent then
                        MainEvent:FireServer("Grabbing")
                    end
                    
                    task.wait(0.3)
                    
                    pcall(function()
                        local updatedOwnerRoot = getRoot(API.ownerPlayer)
                        if updatedOwnerRoot then
                            ownerRoot = updatedOwnerRoot
                        end
                        if ownerRoot then
                            myHRP.CFrame = ownerRoot.CFrame * CFrame.new(0, 2, 3)
                        end
                    end)
                    
                    task.wait(0.2)
                    
                until (not target.Character) or target.Character:FindFirstChild("GRABBING_CONSTRAINT") or targetKO.Value == false or bringAttempts >= 5
                
                local finalTorso = getTorso(target) or targetTorso
                local finalOwnerRoot = getRoot(API.ownerPlayer) or ownerRoot
                if target.Character and finalTorso and finalOwnerRoot and (target.Character:FindFirstChild("GRABBING_CONSTRAINT") or (finalTorso.Position - finalOwnerRoot.Position).Magnitude < 15) then
                    API.sendChat(target.Name .. " has been gun brought!")
                else
                    API.sendChat("Failed to grab " .. target.Name)
                end
            end
        end
        
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
        
        -- Unequip gun after command
        unequipAllTools()
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

-- Revenge command (stomp the player who killed/stomped the owner)
API.Create("revenge", function(args)
    if not lastKiller or not lastKiller.Character then
        API.sendChat("No one to get revenge on! (No recent killer tracked)")
        return
    end
    
    if isDead(lastKiller) then
        API.sendChat(lastKiller.Name .. " is already dead!")
        lastKiller = nil
        return
    end
    
    local targetKO = KO(lastKiller)
    if not targetKO then
        API.sendChat("Target invalid!")
        return
    end
    
    -- Check if we have a gun
    local hasGun = hasTool(GUN_NAME)
    
    if hasGun then
        API.sendChat("Getting revenge on " .. lastKiller.Name .. " with gun...")
        
        local tool = ensureToolEquipped(GUN_NAME)
        if not tool then
            API.sendChat("Failed to equip gun!")
            return
        end
        
        local originalFollowing = Stand.Following
        local originalTarget = API.currentFollowTarget
        Stand.Attacking = false
        Stand.Following = false
        API.currentFollowTarget = nil
        
        task.spawn(function()
            local stopStrafe = nil
            
            if targetKO.Value == false then
                stopStrafe = startGunStrafe(lastKiller, {mode = "Sky", height = 8, radius = 10})
                
                local startTime = tick()
                local timeout = 30
                
                while lastKiller.Character and not isDead(lastKiller) and targetKO.Value == false do
                    if tick() - startTime > timeout then
                        API.sendChat("Gun knock timeout!")
                        if stopStrafe then stopStrafe() end
                        Stand.Following = originalFollowing
                        API.currentFollowTarget = originalTarget
                        unequipAllTools()
                        return
                    end
                    
                    local gun = ensureToolEquipped(GUN_NAME)
                    if not gun then
                        API.sendChat("Lost weapon!")
                        if stopStrafe then stopStrafe() end
                        Stand.Following = originalFollowing
                        API.currentFollowTarget = originalTarget
                        return
                    end
                    
                    local shotSuccess = shootTargetWithGun(lastKiller, gun)
                    if not shotSuccess then
                        API.sendChat("Failed to shoot!")
                        if stopStrafe then stopStrafe() end
                        Stand.Following = originalFollowing
                        API.currentFollowTarget = originalTarget
                        unequipAllTools()
                        return
                    end
                    
                    reloadGunIfNeeded(gun)
                    RunService.Heartbeat:Wait()
                end
                
                if stopStrafe then
                    stopStrafe()
                    stopStrafe = nil
                end
            end
            
            if targetKO.Value == true and not isDead(lastKiller) then
                stompTarget(lastKiller)
                task.wait(0.5)
                if isDead(lastKiller) then
                    API.sendChat("Revenge complete! " .. lastKiller.Name .. " has been eliminated!")
                else
                    API.sendChat("Stomped " .. lastKiller.Name)
                end
            end
            
            local localHumanoid = getLocalHumanoid()
            if localHumanoid then
                Workspace.Camera.CameraSubject = localHumanoid
            end
            
            Stand.Following = originalFollowing
            API.currentFollowTarget = originalTarget
            
            -- Unequip gun after command
            unequipAllTools()
            
            lastKiller = nil
            
            if API.Summon then
                task.wait(0.5)
                API.Summon()
            end
        end)
    else
        -- Use combat tool
        API.sendChat("Getting revenge on " .. lastKiller.Name .. " with combat...")
        
        local originalFollowing = Stand.Following
        local originalTarget = API.currentFollowTarget
        Stand.Attacking = false
        Stand.Following = false
        API.currentFollowTarget = nil
        
        task.spawn(function()
            if targetKO.Value == false then
                if not LocalPlayer.Character:FindFirstChild("Combat") then
                    if LocalPlayer.Backpack:FindFirstChild("Combat") then
                        LocalPlayer.Backpack:FindFirstChild("Combat").Parent = LocalPlayer.Character
                    end
                end
                
                local knockStartTime = tick()
                local timeout = 30
                
                repeat
                    RunService.Stepped:Wait()
                    
                    if not lastKiller.Character or isDead(lastKiller) then
                        break
                    end
                    
                    if targetKO.Value == false then
                        Equip("Combat")
                        if MainEvent then
                            MainEvent:FireServer("ChargeButton")
                        end
                        TargetMelee(lastKiller)
                    else
                        break
                    end
                    
                    if tick() - knockStartTime > timeout then
                        API.sendChat("Knock timeout!")
                        break
                    end
                    
                until targetKO.Value == true or not lastKiller.Character or isDead(lastKiller)
                
                local attackingValue = Attacking(LocalPlayer)
                if attackingValue then
                    local waitStart = tick()
                    while attackingValue.Value == true and tick() - waitStart < 5 do
                        task.wait(0.1)
                    end
                end
            end
            
            if targetKO.Value == true and not isDead(lastKiller) then
                stompTarget(lastKiller)
                task.wait(0.5)
                if isDead(lastKiller) then
                    API.sendChat("Revenge complete! " .. lastKiller.Name .. " has been eliminated!")
                else
                    API.sendChat("Stomped " .. lastKiller.Name)
                end
            end
            
            local localHumanoid = getLocalHumanoid()
            if localHumanoid then
                Workspace.Camera.CameraSubject = localHumanoid
            end
            
            Stand.Following = originalFollowing
            API.currentFollowTarget = originalTarget
            
            lastKiller = nil
            
            if API.Summon then
                task.wait(0.5)
                API.Summon()
            end
        end)
    end
end)

-- Mask command - puts on mask
API.Create("mask", function(args)
    local hrp = getLocalHRP()
    if not hrp then
        API.sendChat("HRP missing!")
        return
    end
    
    local character = getLocalCharacter()
    if not character then
        API.sendChat("Character missing!")
        return
    end
    
    local humanoid = getLocalHumanoid()
    if not humanoid then
        API.sendChat("Humanoid missing!")
        return
    end
    
    API.sendChat("Buying mask...")
    
    local maskItemName = "[Other Mask] - $66"
    local maskToolName = "[Mask]"
    
    local shopFolder = getShopFolder()
    if not shopFolder then
        API.sendChat("Shop folder missing!")
        return
    end
    
    local shopItem = shopFolder:FindFirstChild(maskItemName)
    if not shopItem then
        API.sendChat("Mask shop item not found!")
        return
    end
    
    local head = shopItem:FindFirstChild("Head")
    local detector = shopItem:FindFirstChild("ClickDetector")
    if not head or not detector then
        API.sendChat("Mask shop item incomplete!")
        return
    end
    
    humanoid:UnequipTools()
    task.wait(0.1)
    
    local originalCFrame = hrp.CFrame
    pcall(function()
        hrp.CFrame = head.CFrame * CFrame.new(0, 3, 0)
    end)
    
    task.wait(0.15)
    
    local clickFunction = getClickDetectorFunc()
    if not clickFunction then
        pcall(function()
            hrp.CFrame = originalCFrame
        end)
        API.sendChat("fireclickdetector unavailable!")
        return
    end
    
    local success = false
    for _ = 1, 5 do
        pcall(function()
            clickFunction(detector)
        end)
        task.wait(0.2)
        if LocalPlayer.Backpack:FindFirstChild(maskToolName) then
            success = true
            break
        end
    end
    
    if success then
        task.wait(0.1)
        local maskTool = LocalPlayer.Backpack:FindFirstChild(maskToolName)
        if maskTool then
            maskTool.Parent = character
            task.wait(0.1)
            local equippedMask = character:FindFirstChild(maskToolName)
            if equippedMask then
                equippedMask:Activate()
                task.wait(0.1)
                humanoid:UnequipTools()
                API.sendChat("Mask equipped!")
            end
        end
    else
        API.sendChat("Failed to buy mask!")
    end
    
    pcall(function()
        hrp.CFrame = originalCFrame
    end)
end)

-- AMask command - automatically puts on mask when no mask is equipped
local amaskActive = false
local amaskConnection = nil
local amaskBuying = false

API.Create("amask", function(args)
    if amaskActive then
        API.sendChat("AMask already active!")
        return
    end
    
    amaskActive = true
    API.sendChat("AMask activated - will auto-equip mask when missing")
    
    local function checkAndEquipMask()
        if not amaskActive or amaskBuying then return end
        amaskBuying = true
        
        task.spawn(function()
            local character = getLocalCharacter()
            if not character then
                amaskBuying = false
                return
            end
            
            local bodyEffects = character:FindFirstChild("BodyEffects")
            if not bodyEffects then
                amaskBuying = false
                return
            end
            
            local mask = bodyEffects:FindFirstChild("Mask")
            if mask and mask.Value ~= nil then
                amaskBuying = false
                return
            end
            
            local humanoid = getLocalHumanoid()
            if not humanoid then
                amaskBuying = false
                return
            end
            
            local hrp = getLocalHRP()
            if not hrp then
                amaskBuying = false
                return
            end
            
            local maskToolName = "[Mask]"
            local maskItemName = "[Other Mask] - $66"
            
            local shopFolder = getShopFolder()
            if not shopFolder then
                amaskBuying = false
                return
            end
            
            local shopItem = shopFolder:FindFirstChild(maskItemName)
            if not shopItem then
                amaskBuying = false
                return
            end
            
            local head = shopItem:FindFirstChild("Head")
            local detector = shopItem:FindFirstChild("ClickDetector")
            if not head or not detector then
                amaskBuying = false
                return
            end
            
            local originalCFrame = hrp.CFrame
            humanoid:UnequipTools()
            task.wait(0.1)
            
            pcall(function()
                hrp.CFrame = head.CFrame * CFrame.new(0, 3, 0)
            end)
            
            task.wait(0.15)
            
            local clickFunction = getClickDetectorFunc()
            if not clickFunction then
                pcall(function()
                    hrp.CFrame = originalCFrame
                end)
                amaskBuying = false
                return
            end
            
            for _ = 1, 5 do
                pcall(function()
                    clickFunction(detector)
                end)
                task.wait(0.2)
                if LocalPlayer.Backpack:FindFirstChild(maskToolName) then
                    break
                end
            end
            
            task.wait(0.1)
            local maskTool = LocalPlayer.Backpack:FindFirstChild(maskToolName)
            if maskTool then
                maskTool.Parent = character
                task.wait(0.1)
                local equippedMask = character:FindFirstChild(maskToolName)
                if equippedMask then
                    equippedMask:Activate()
                    task.wait(0.1)
                    humanoid:UnequipTools()
                    print("[AMask] Auto-equipped mask")
                end
            end
            
            pcall(function()
                hrp.CFrame = originalCFrame
            end)
            
            amaskBuying = false
        end)
    end
    
    amaskConnection = RunService.Heartbeat:Connect(function()
        if not amaskActive or amaskBuying then return end
        
        local character = getLocalCharacter()
        if not character then return end
        
        local bodyEffects = character:FindFirstChild("BodyEffects")
        if not bodyEffects then return end
        
        local mask = bodyEffects:FindFirstChild("Mask")
        if not mask or mask.Value == nil then
            pcall(checkAndEquipMask)
        end
    end)
end)

API.Create("unamask", function(args)
    if not amaskActive then
        API.sendChat("AMask not active!")
        return
    end
    
    amaskActive = false
    if amaskConnection then
        amaskConnection:Disconnect()
        amaskConnection = nil
    end
    API.sendChat("AMask deactivated")
end)

-- Chair destroyer (from memory - prevents stand from sitting)
task.spawn(function()
    task.wait(2)
    
    local function isInsideVehicle(seat)
        local parent = seat.Parent
        while parent and parent ~= Workspace do
            if parent.Name == "Vehicles" and parent.Parent == Workspace then
                return true
            end
            parent = parent.Parent
        end
        return false
    end
    
    local function destroyChair(obj)
        if obj:IsA("Seat") or obj:IsA("VehicleSeat") then
            if not isInsideVehicle(obj) then
                obj:Destroy()
            end
        elseif obj.Name:lower():find("chair") or obj.Name:lower():find("seat") then
            if not isInsideVehicle(obj) then
                obj:Destroy()
            end
        end
    end
    
    -- Destroy existing chairs
    for _, obj in pairs(Workspace:GetDescendants()) do
        pcall(function()
            destroyChair(obj)
        end)
    end
    
    -- Monitor for new chairs
    Workspace.DescendantAdded:Connect(function(obj)
        task.wait(0.1)
        pcall(function()
            destroyChair(obj)
        end)
    end)
end)

print("[Da Hood Config] Loaded successfully!")
print("[Da Hood Config] Commands: knock, stomp, gun, gknock, gstomp, bring, gbring, revenge, mask, amask, unamask")
print("[Da Hood Config] Prediction: 0.155 (AutoPredic from stando script)")
print("[Da Hood Config] Revenge tracking active - will remember who kills/stomps the owner")
