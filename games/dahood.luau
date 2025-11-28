local globalEnv = getgenv()
local SocietyStandConfig = globalEnv.SocietyStandConfig or {}
local DahoodConfig = SocietyStandConfig.Dahood or {}
local DahoodMainConfig = DahoodConfig.Main or {}
local SocietyStandConfig = globalEnv.SocietyStandConfig
SocietyStandConfig.Dahood = type(SocietyStandConfig.Dahood) == "table" and SocietyStandConfig.Dahood or {}
SocietyStandConfig.Dahood.Main = type(SocietyStandConfig.Dahood.Main) == "table" and SocietyStandConfig.Dahood.Main or {}
SocietyStandConfig.Dahood.Main.AntiStomp = (SocietyStandConfig.Dahood.Main.AntiStomp == nil) and true or SocietyStandConfig.Dahood.Main.AntiStomp
SocietyStandConfig.Dahood.Main.Automask = (SocietyStandConfig.Dahood.Main.Automask == nil) and false or SocietyStandConfig.Dahood.Main.Automask

local requiredFields = {"Stand", "Create", "Stop", "sendChat", "getPlayer", "ownerPlayer", "Notify", "ForceChat"}
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

if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

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
end

local bypassSuccess, bypassError = pcall(installCheckerBypass)
if not bypassSuccess and bypassError then
    warn("[Da Hood Config] Failed to install CHECKER_1 bypass:", bypassError)
end

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

print("[Da Hood Config] Anticheat protection Enabled")

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

local ownerRevengeConnections = {}
local trackedOwnerForRevenge = nil

local function attachRevengeTracker(character)
    if not character then return end
    lastKiller = nil
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

local function bindRevengeTrackerToOwner(player)
    for _, conn in ipairs(ownerRevengeConnections) do
        conn:Disconnect()
    end
    ownerRevengeConnections = {}
    trackedOwnerForRevenge = player
    if not player then return end

    local function onCharacterAdded(character)
        attachRevengeTracker(character)
    end

    if player.Character then
        attachRevengeTracker(player.Character)
    end

    table.insert(ownerRevengeConnections, player.CharacterAdded:Connect(onCharacterAdded))
end

bindRevengeTrackerToOwner(API.ownerPlayer)

Players.PlayerAdded:Connect(function(player)
    if API.ownerPlayer and player == API.ownerPlayer then
        bindRevengeTrackerToOwner(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if player == lastKiller then
        lastKiller = nil
    end
end)

RunService.Heartbeat:Connect(function()
    if API.ownerPlayer ~= trackedOwnerForRevenge then
        bindRevengeTrackerToOwner(API.ownerPlayer)
    end
end)

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

local function hasAnyTool(toolNames)
    if type(toolNames) == "table" then
        for _, name in ipairs(toolNames) do
            if hasTool(name) then
                return true
            end
        end
        return false
    elseif type(toolNames) == "string" then
        return hasTool(toolNames)
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
        if not expectedToolName or hasAnyTool(expectedToolName) then
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
    local ammoBought = 0
    for _ = 1, purchases do
        local success, message = buyShopItem(LMG_AMMO_ITEM, nil, 1)
        if success then
            ammoBought = ammoBought + 1
        else
            if message and message:find("incomplete") then
                break
            end
        end
        task.wait(0.1)
    end
    return true, hasGun and ("ammo_only_" .. ammoBought) or ("full_purchase_" .. ammoBought)
end

local MainEvent = ReplicatedStorage:WaitForChild("MainEvent", 5)

local ZERO_VECTOR = Vector3.new(0, 0, 0)

local lastKiller = nil

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

local AutoPredic = 0.155

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
    
    local myHRP = getLocalHRP()
    local targetRoot = getRoot(target)
    local targetHumanoid = getHumanoid(target)
    if myHRP and targetRoot and targetHumanoid then
        pcall(function()
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
    end

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

local function TargetMelee(target)
    if not target or isDead(target) then return end
    
    local q = getRoot(target)
    local e = getHumanoid(target)
    local t = getLocalHRP()
    
    if not q or not e or not t then return end
    
    pcall(function()
        local humanoid = getLocalHumanoid()
        if humanoid then
            for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
                track:Stop()
            end
        end
        
        if isInVehicle(target) then
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
            if e.FloorMaterial == Enum.Material.Air then
                t.CFrame = CFrame.new(q.Position + Vector3.new(0, -6.8, 0) + e.MoveDirection * AutoPredic * e.WalkSpeed) * CFrame.Angles(math.pi * 0.5, 0, 0)
            else
                t.CFrame = CFrame.new(q.Position + Vector3.new(0, 0, 0) + e.MoveDirection * AutoPredic * e.WalkSpeed)
            end
        else
            if e.FloorMaterial == Enum.Material.Air then
                t.CFrame = CFrame.new(q.Position.X + q.Velocity.X * AutoPredic, q.Position.Y + q.Velocity.Y * 0, q.Position.Z + q.Velocity.Z * AutoPredic) * CFrame.new(0, -6.8, 0) * CFrame.Angles(math.pi * 0.5, 0, 0)
            else
                t.CFrame = CFrame.new(q.Position.X + q.Velocity.X * AutoPredic, q.Position.Y + 0, q.Position.Z + q.Velocity.Z * AutoPredic)
            end
        end
        
        Workspace.Camera.CameraSubject = e
    end)
end

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
    
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    if not LocalPlayer.Character:FindFirstChild("Combat") then
        if LocalPlayer.Backpack:FindFirstChild("Combat") then
            LocalPlayer.Backpack:FindFirstChild("Combat").Parent = LocalPlayer.Character
        end
    end
    
    API.sendChat("Knocking " .. target.Name .. "...")
    
    local knockStartTime = tick()
    local timeout = 30
    
    task.spawn(function()
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
        
        local localHumanoid = getLocalHumanoid()
        if localHumanoid then
            Workspace.Camera.CameraSubject = localHumanoid
        end
        
        Stand.Following = originalFollowing
        API.currentFollowTarget = originalTarget
        
        if targetKO.Value == true then
            API.sendChat(target.Name .. " has been knocked out!")
        end
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

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
    
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
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
        
        if targetKO.Value == true and not isDead(target) then
            performStomp()
            task.wait(0.5)
            
            if isDead(target) then
                API.sendChat(target.Name .. " has been stomped!")
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
    end)
end)

API.Create("revenge", function(args)
    stopAutokill("Revenge command activated - stopping AutoKill")
    stopGautokill("Revenge command activated - stopping GAutoKill")

    local owner = API.ownerPlayer
    if (not lastKiller or lastKiller.Parent ~= Players) and owner and owner.Character then
        local stomper = detectStomper(owner.Character)
        if stomper then
            lastKiller = stomper
            print(string.format("[Revenge Command] Using stomper %s as revenge target", stomper.Name))
        end
    end

    if not lastKiller or lastKiller.Parent ~= Players then
        API.sendChat("No revenge target found (nobody has killed/stomped the owner yet)")
        return
    end
    
    local target = lastKiller
    if not target.Character then
        API.sendChat("Revenge target has no character!")
        return
    end
    
    local targetKO = KO(target)
    if not targetKO then
        API.sendChat("Revenge target invalid!")
        return
    end
    
    API.sendChat("Taking revenge on " .. target.Name .. "!")
    
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    task.spawn(function()
        local standCharacter = getLocalCharacter()
        if not standCharacter then
            API.sendChat("Stand character missing - cannot execute revenge")
            return
        end
        
        if targetKO.Value == false then
            if not standCharacter:FindFirstChild("Combat") then
                local backpack = LocalPlayer:FindFirstChild("Backpack")
                if backpack and backpack:FindFirstChild("Combat") then
                    backpack:FindFirstChild("Combat").Parent = standCharacter
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
                    API.sendChat("Revenge knock timeout!")
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
        
        if targetKO.Value == true and not isDead(target) then
            local targetTorso = getTorso(target)
            local myHRP = getLocalHRP()
            
            if targetTorso and myHRP then
                pcall(function()
                    myHRP.CFrame = CFrame.new(targetTorso.Position + Vector3.new(0, 5, 0))
                    task.wait(0.1)
                    if MainEvent then
                        MainEvent:FireServer("Stomp")
                    end
                end)
            end
            
            task.wait(0.5)
            
            if isDead(target) then
                API.sendChat("Revenge complete! " .. target.Name .. " has been eliminated!")
            else
                API.sendChat("Revenge stomped " .. target.Name)
            end
        else
            API.sendChat("Revenge failed to knock " .. target.Name)
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
        
        unequipAllTools()
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

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
        
        unequipAllTools()
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

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

API.Create("gbring", function(args)
    local target, playerName = resolveTargetFromArgs(args)
    if not target or not target.Character then
        API.ForceChat("Target not found!")
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
        
    task.spawn(function()
        local stopStrafe = nil
        
        if targetKO.Value == false then
            stopStrafe = startGunStrafe(target, {mode = "Sky", height = 8, radius = 10})
            
            local startTime = tick()
            local timeout = 30
            
            while target.Character and not isDead(target) and targetKO.Value == false do
                if tick() - startTime > timeout then
                    print("Gun knock timeout!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    unequipAllTools()
                    return
                end
                
                local gun = ensureToolEquipped(GUN_NAME)
                if not gun then
                    print("Lost weapon!")
                    if stopStrafe then stopStrafe() end
                    Stand.Following = originalFollowing
                    API.currentFollowTarget = originalTarget
                    return
                end
                
                local shotSuccess = shootTargetWithGun(target, gun)
                if not shotSuccess then
                    print("Failed to shoot!")
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
        
        unequipAllTools()
        
        if API.Summon then
            task.wait(0.5)
            API.Summon()
        end
    end)
end)

API.Create("revenge", function(args)
    if not lastKiller or not lastKiller.Character then
        API.sendChat("No one to get revenge on!")
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
    
    local hasGun = hasTool(GUN_NAME)
    
    if hasGun then
        
        local tool = ensureToolEquipped(GUN_NAME)
        if not tool then
            print("Failed to equip gun!")
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
                        print("Lost weapon!")
                        if stopStrafe then stopStrafe() end
                        Stand.Following = originalFollowing
                        API.currentFollowTarget = originalTarget
                        return
                    end
                    
                    local shotSuccess = shootTargetWithGun(lastKiller, gun)
                    if not shotSuccess then
                        print("Failed to shoot!")
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
                    
                else

                end
            end
            
            local localHumanoid = getLocalHumanoid()
            if localHumanoid then
                Workspace.Camera.CameraSubject = localHumanoid
            end
            
            Stand.Following = originalFollowing
            API.currentFollowTarget = originalTarget
            
            unequipAllTools()
            
            lastKiller = nil
            
            if API.Summon then
                task.wait(0.5)
                API.Summon()
            end
        end)
    else        
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

                else

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

API.Create("drop", function(args)
    if not MainEvent then
        API.sendChat("MainEvent not found!")
        return
    end
    
    MainEvent:FireServer("Grabbing")
    API.sendChat("Dropped!")
end)

API.Create("wallet", function(args)
    local character = getLocalCharacter()
    local backpack = LocalPlayer and LocalPlayer:FindFirstChild("Backpack")
    if not character or not backpack then
        API.sendChat("Cannot equip wallet - missing character/backpack!")
        return
    end
    
    local walletTool = backpack:FindFirstChild("Wallet")
    if walletTool then
        walletTool.Parent = character

    else
        API.sendChat("Wallet not found in backpack!")
    end
end)

local function dropTenK()
    if not MainEvent then
        API.sendChat("MainEvent not found!")
        return false
    end
    
    MainEvent:FireServer("DropMoney", "10000")
    return true
end

API.Create("dropcash", function(args)
    dropTenK()
end)

API.Create("dcash", function(args)
    dropTenK()
end)

local MASK_TOOL_NAME = "[Mask]"
local MASK_ITEM_NAME = "[Surgeon Mask] - $27"

local function getMaskTool()
    local character = getLocalCharacter()
    if character then
        local tool = character:FindFirstChild(MASK_TOOL_NAME)
        if tool then
            return tool
        end
    end

    local backpack = LocalPlayer and LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        local tool = backpack:FindFirstChild(MASK_TOOL_NAME)
        if tool then
            return tool
        end
    end

    return nil
end

local function ensureMaskToolAvailable()
    local existing = getMaskTool()
    if existing then
        return existing
    end

    local shopFolder = getShopFolder()
    if not shopFolder then
        return nil, "Shop folder missing"
    end
    
    local shopItem = shopFolder:FindFirstChild(MASK_ITEM_NAME)
    if not shopItem then
        return nil, "Shop item not found"
    end
    
    local head = shopItem:FindFirstChild("Head")
    local detector = shopItem:FindFirstChild("ClickDetector")
    if not head or not detector then
        return nil, "Shop item incomplete"
    end
    
    local hrp = getLocalHRP()
    local humanoid = getLocalHumanoid()
    if not hrp or not humanoid then
        return nil, "HumanoidRootPart or Humanoid missing"
    end
    
    local clickFunction = getClickDetectorFunc()
    if not clickFunction then
        return nil, "fireclickdetector unavailable"
    end
    
    local originalFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    Stand.Following = false
    Stand.ManualControl = true
    API.currentFollowTarget = nil
    
    local originalCFrame = hrp.CFrame
    local originalCameraSubject = Workspace.CurrentCamera.CameraSubject
    
    pcall(function()
        hrp.CFrame = head.CFrame * CFrame.new(0, 3, 0)
    end)
    
    task.wait(0.1)
    
    local startTime = tick()
    local timeout = 15 
    local success = false
    
    repeat
        task.wait()
        pcall(function()
            local character = getLocalCharacter()
            if character then
                for _, part in pairs(character:GetDescendants()) do
                    if part:IsA("BasePart") or part:IsA("MeshPart") or part:IsA("Part") then
                        if part.CanCollide == true then
                            part.CanCollide = false
                        end
                        part.Velocity = Vector3.new(0, 0, 0)
                    end
                end
            end
            
            pcall(function()
                Workspace.CurrentCamera.CameraSubject = head
            end)
            
            hrp.CFrame = head.CFrame * CFrame.new(0, -5, 0)
            
            clickFunction(detector)
        end)
        
        if getMaskTool() then
            success = true
            break
        end
        
        if (tick() - startTime) >= timeout then
            break
        end
    until getMaskTool()
    
    pcall(function()
        if originalCameraSubject then
            Workspace.CurrentCamera.CameraSubject = originalCameraSubject
        elseif humanoid then
            Workspace.CurrentCamera.CameraSubject = humanoid
        end
    end)
    
    pcall(function()
        hrp.CFrame = originalCFrame
    end)
    
    Stand.Following = originalFollowing
    Stand.ManualControl = false
    API.currentFollowTarget = originalTarget
    
    local finalTool = getMaskTool()
    if finalTool then
        return finalTool
    else
        return nil, "Purchase timeout - mask not received"
    end
end

local function equipMaskTool(maskTool, character, humanoid)
    if not maskTool or not character or not humanoid then
        return false
    end

    humanoid:UnequipTools()
    task.wait(0.05)

    if maskTool.Parent ~= character then
        maskTool.Parent = character
        task.wait(0.1)
    end

    local equippedMask = character:FindFirstChild(MASK_TOOL_NAME) or maskTool
    if equippedMask and equippedMask:IsA("Tool") then
        pcall(function()
            equippedMask:Activate()
        end)
        task.wait(0.1)
        humanoid:UnequipTools()
        return true
    end

    return false
end

API.Create("mask", function(args)
    
    local maskTool, errorMsg = ensureMaskToolAvailable()
    if not maskTool then
        API.sendChat("Failed to buy mask" .. (errorMsg and ": " .. errorMsg or "!"))
        return
    end
    
    local character = getLocalCharacter()
    local humanoid = getLocalHumanoid()
    if not character or not humanoid then
        API.sendChat("Character/Humanoid missing!")
        return
    end
    
    local equipped = equipMaskTool(maskTool, character, humanoid)
    if equipped then

    else
        API.sendChat("Failed to equip mask!")
    end
end)

local amaskActive = false
local amaskConnection = nil
local amaskBuying = false

API.Create("amask", function(args)
    if amaskActive then
        amaskActive = false
        if amaskConnection then
            amaskConnection:Disconnect()
            amaskConnection = nil
        end
        API.sendChat("AMask deactivated")
        return
    end
    
    amaskActive = true
    
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
            
            local maskTool, errorMsg = ensureMaskToolAvailable()
            if not maskTool then
                if errorMsg then
                    warn("[AMask] Failed to buy mask: " .. tostring(errorMsg))
                end
                amaskBuying = false
                return
            end
            
            if equipMaskTool(maskTool, character, humanoid) then

            end
            
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
    
    API.sendChat("AMask activated")
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
    
    for _, obj in pairs(Workspace:GetDescendants()) do
        pcall(function()
            destroyChair(obj)
        end)
    end
    
    Workspace.DescendantAdded:Connect(function(obj)
        task.wait(0.1)
        pcall(function()
            destroyChair(obj)
        end)
    end)
end)

local autokillState = {
    active = false,
    connection = nil,
    target = nil,
    originalFollowing = nil,
    originalTarget = nil,
    lastStomp = 0
}

local gautokillState = {
    active = false,
    connection = nil,
    target = nil,
    originalFollowing = nil,
    originalTarget = nil,
    stopStrafe = nil,
    lastStomp = 0,
    holdConnection = nil,
    lastKnownPosition = nil,
    holdAnchor = nil,
    buyingGun = false,
    restockingAmmo = false,
    needsAmmo = false,
    awaitingRespawn = false,
    shootFailureCount = 0
}

local function stopGautokillHold()
    if gautokillState.holdConnection then
        gautokillState.holdConnection:Disconnect()
        gautokillState.holdConnection = nil
    end
    gautokillState.holdAnchor = nil
end

local function ensureGautokillHold(anchorPosition)
    if anchorPosition then
        gautokillState.lastKnownPosition = anchorPosition
        gautokillState.holdAnchor = anchorPosition
    elseif not gautokillState.holdAnchor then
        gautokillState.holdAnchor = gautokillState.lastKnownPosition
    end

    if gautokillState.holdConnection or not gautokillState.holdAnchor then
        return
    end

    local orbitAngle = math.random() * math.pi * 2
    local driftAngle = math.random() * math.pi * 2
    gautokillState.holdConnection = RunService.Heartbeat:Connect(function(dt)
        if not gautokillState.active or not gautokillState.awaitingRespawn then
            stopGautokillHold()
            return
        end

        local myHRP = getLocalHRP()
        local anchor = gautokillState.holdAnchor or gautokillState.lastKnownPosition
        if not myHRP or not anchor then
            return
        end

        orbitAngle = (orbitAngle + ((2 * math.pi) / 0.18) * dt) % (math.pi * 2)
        driftAngle = (driftAngle + ((2 * math.pi) / 5.5) * dt) % (math.pi * 2)

        local driftCenter = anchor + Vector3.new(math.cos(driftAngle) * 800, 0, math.sin(driftAngle) * 800)
        local orbitCenter = driftCenter + Vector3.new(0, 350, 0)
        local orbitCFrame = CFrame.new(orbitCenter) * CFrame.Angles(0, orbitAngle, 0) * CFrame.new(0, 0, 550)

        pcall(function()
            myHRP.CFrame = orbitCFrame
        end)
    end)
end

local function markGautokillNeedsAmmo()
    gautokillState.needsAmmo = true
end

local function requestGautokillGun()
    if gautokillState.buyingGun or not gautokillState.active then
        return false
    end
    if not getLocalHRP() then
        return false
    end

    gautokillState.buyingGun = true
    stopGautokillHold()
    if gautokillState.stopStrafe then
        pcall(function()
            gautokillState.stopStrafe()
        end)
        gautokillState.stopStrafe = nil
    end

    task.spawn(function()
        local success, message = buyLMG(8)
        if not success and message then
            warn("[GAutoKill] Failed to buy LMG: " .. tostring(message))
        end
        if success then
            markGautokillNeedsAmmo()
        end
        gautokillState.buyingGun = false
    end)

    return true
end

local function requestGautokillAmmo(bundles)
    if gautokillState.restockingAmmo or not gautokillState.active then
        return false
    end
    if not hasTool(GUN_NAME) or not getLocalHRP() then
        return false
    end

    gautokillState.restockingAmmo = true
    stopGautokillHold()
    if gautokillState.stopStrafe then
        pcall(function()
            gautokillState.stopStrafe()
        end)
        gautokillState.stopStrafe = nil
    end

    task.spawn(function()
        local purchaseCount = math.max(bundles or 2, 1)
        local successCount = 0
        for _ = 1, purchaseCount do
            local success, errMsg = buyShopItem(LMG_AMMO_ITEM, nil, 1)
            if success then
                successCount += 1
            else
                if errMsg then
                    warn("[GAutoKill] Ammo purchase failed: " .. tostring(errMsg))
                end
                if errMsg == "HumanoidRootPart missing" then
                    break
                end
            end
            task.wait(0.25)
        end
        if successCount > 0 then
            gautokillState.needsAmmo = false
        end
        gautokillState.restockingAmmo = false
    end)

    return true
end

local function restoreStandState(state)
    if state.originalFollowing ~= nil then
        Stand.Following = state.originalFollowing
        state.originalFollowing = nil
    end
    if state.originalTarget ~= nil then
        API.currentFollowTarget = state.originalTarget
        state.originalTarget = nil
    end
end

local function stopAutokill(reason)
    if autokillState.connection then
        autokillState.connection:Disconnect()
        autokillState.connection = nil
    end
    if not autokillState.active then
        autokillState.target = nil
        autokillState.lastStomp = 0
        return
    end
    autokillState.active = false
    autokillState.target = nil
    autokillState.lastStomp = 0
    restoreStandState(autokillState)
    local humanoid = getLocalHumanoid()
    if humanoid then
        Workspace.Camera.CameraSubject = humanoid
    end
    if reason then
        API.sendChat(reason)
        print("[AutoKill] Stopped: " .. reason)
    else
        print("[AutoKill] Stopped")
    end
end

local function stopGautokill(reason)
    if not gautokillState.active and not gautokillState.connection then
        return
    end
    
    gautokillState.active = false
    
    if gautokillState.connection then
        gautokillState.connection:Disconnect()
        gautokillState.connection = nil
    end
    if gautokillState.holdConnection then
        gautokillState.holdConnection:Disconnect()
        gautokillState.holdConnection = nil
    end
    if gautokillState.stopStrafe then
        pcall(function()
            gautokillState.stopStrafe()
        end)
        gautokillState.stopStrafe = nil
    end
    
    gautokillState.target = nil
    gautokillState.lastStomp = 0
    gautokillState.lastKnownPosition = nil
    gautokillState.holdAnchor = nil
    gautokillState.buyingGun = false
    gautokillState.restockingAmmo = false
    gautokillState.needsAmmo = false
    gautokillState.awaitingRespawn = false
    gautokillState.shootFailureCount = 0
    
    restoreStandState(gautokillState)
    unequipAllTools()
    local humanoid = getLocalHumanoid()
    if humanoid then
        Workspace.Camera.CameraSubject = humanoid
    end
    if reason then
        API.sendChat(reason)
        print("[GAutoKill] Stopped: " .. reason)
    else
        print("[GAutoKill] Stopped")
    end
end

local function startAutokillLoop(target)
    autokillState.originalFollowing = Stand.Following
    autokillState.originalTarget = API.currentFollowTarget
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    autokillState.target = target
    autokillState.active = true
    autokillState.lastStomp = 0

    autokillState.connection = RunService.Heartbeat:Connect(function()
        if not autokillState.active then
            return
        end

        local success, err = pcall(function()
            local trackedTarget = autokillState.target
            if not trackedTarget or trackedTarget.Parent ~= Players then
                stopAutokill("Target unavailable, AutoKill stopped.")
                return
            end

            local targetCharacter = trackedTarget.Character
            if not targetCharacter then
                return
            end

            local targetKO = KO(trackedTarget)
            if not targetKO then
                return
            end

            if targetKO.Value == false and not isDead(trackedTarget) then
                autokillState.lastStomp = 0
                local character = getLocalCharacter()
                if character and not character:FindFirstChild("Combat") then
                    local backpack = LocalPlayer:FindFirstChild("Backpack")
                    if backpack then
                        local combat = backpack:FindFirstChild("Combat")
                        if combat then
                            combat.Parent = character
                        end
                    end
                end
                if MainEvent then
                    MainEvent:FireServer("ChargeButton")
                end
                TargetMelee(trackedTarget)
            else
                local attackingValue = Attacking(LocalPlayer)
                if attackingValue and attackingValue.Value == true then
                    local myHRP = getLocalHRP()
                    local targetRoot = getRoot(trackedTarget)
                    if myHRP and targetRoot then
                        pcall(function()
                            myHRP.CFrame = targetRoot.CFrame * CFrame.new(0, 300, 0)
                        end)
                    end
                    return
                end

                if not isDead(trackedTarget) then
                    if tick() - autokillState.lastStomp > 0.75 then
                        if stompTarget(trackedTarget) then
                            autokillState.lastStomp = tick()
                        end
                    end
                end
            end
        end)

        if not success and autokillState.active then
            warn("[AutoKill] " .. tostring(err))
        end
    end)
end

local function startGautokillLoop(target)
    gautokillState.originalFollowing = Stand.Following
    gautokillState.originalTarget = API.currentFollowTarget
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    gautokillState.target = target
    gautokillState.active = true
    gautokillState.lastStomp = 0
    gautokillState.lastKnownPosition = nil
    gautokillState.holdAnchor = nil
    gautokillState.buyingGun = false
    gautokillState.restockingAmmo = false
    gautokillState.needsAmmo = true
    gautokillState.awaitingRespawn = false
    gautokillState.shootFailureCount = 0
    stopGautokillHold()

    gautokillState.connection = RunService.Heartbeat:Connect(function()
        if not gautokillState.active then
            return
        end

        local success, err = pcall(function()
            local trackedTarget = gautokillState.target
            if not trackedTarget or trackedTarget.Parent ~= Players then
                stopGautokill("Target unavailable, GAutoKill stopped.")
                return
            end

            local targetCharacter = trackedTarget.Character
            local targetKO = targetCharacter and KO(trackedTarget)
            if targetCharacter and targetKO then
                local targetRoot = getRoot(trackedTarget)
                if targetRoot then
                    gautokillState.lastKnownPosition = targetRoot.Position
                    if not gautokillState.awaitingRespawn then
                        gautokillState.holdAnchor = targetRoot.Position
                    end
                end
            end

            local localCharacter = getLocalCharacter()
            local humanoid = getLocalHumanoid()
            local hrp = getLocalHRP()
            local localDead = not localCharacter or not humanoid or not hrp or isDead(LocalPlayer)

            if localDead then
                markGautokillNeedsAmmo()
                if gautokillState.stopStrafe then
                    gautokillState.stopStrafe()
                    gautokillState.stopStrafe = nil
                end
                stopGautokillHold()
                return
            end

            if gautokillState.buyingGun or gautokillState.restockingAmmo then
                return
            end

            if not hasTool(GUN_NAME) then
                requestGautokillGun()
                return
            end

            local gun = ensureToolEquipped(GUN_NAME)
            if not gun then
                requestGautokillGun()
                return
            end

            if gautokillState.needsAmmo then
                requestGautokillAmmo(3)
                return
            end

            if not targetCharacter or not targetKO then
                gautokillState.awaitingRespawn = true
                ensureGautokillHold(gautokillState.lastKnownPosition or hrp.Position)
                return
            end

            if targetKO.Value == false and not isDead(trackedTarget) then
                gautokillState.awaitingRespawn = false
                gautokillState.lastStomp = 0
                stopGautokillHold()
                if not gautokillState.stopStrafe then
                    gautokillState.stopStrafe = startGunStrafe(trackedTarget, {mode = "Sky", height = 8, radius = 10})
                end

                local shotSuccess = shootTargetWithGun(trackedTarget, gun)
                if not shotSuccess then
                    gautokillState.shootFailureCount = gautokillState.shootFailureCount + 1
                    if gautokillState.shootFailureCount >= 5 then
                        markGautokillNeedsAmmo()
                        gautokillState.shootFailureCount = 0
                    end
                    return
                end

                gautokillState.shootFailureCount = 0
                reloadGunIfNeeded(gun)
            else
                gautokillState.shootFailureCount = 0
                if gautokillState.stopStrafe then
                    gautokillState.stopStrafe()
                    gautokillState.stopStrafe = nil
                end

                local attackingValue = Attacking(LocalPlayer)
                if attackingValue and attackingValue.Value == true then
                    local myHRP = getLocalHRP()
                    local targetRoot = getRoot(trackedTarget)
                    if myHRP and targetRoot then
                        pcall(function()
                            myHRP.CFrame = targetRoot.CFrame * CFrame.new(0, 300, 0)
                        end)
                    end
                    return
                end

                if not isDead(trackedTarget) then
                    stopGautokillHold()
                    if tick() - gautokillState.lastStomp > 0.75 then
                        if stompTarget(trackedTarget) then
                            gautokillState.lastStomp = tick()
                            markGautokillNeedsAmmo()
                        end
                    end
                else
                    gautokillState.awaitingRespawn = true
                    if gautokillState.needsAmmo then
                        requestGautokillAmmo(3)
                        return
                    end
                    ensureGautokillHold(gautokillState.lastKnownPosition or hrp.Position)
                end
            end
        end)

        if not success and gautokillState.active then
            warn("[GAutoKill] " .. tostring(err))
        end
    end)
end

local function autokillCommand(args)
    if autokillState.active then
        API.sendChat("AutoKill already running!")
        return
    end

    stopGautokill()

    local target = select(1, resolveTargetFromArgs(args))
    if not target then
        API.sendChat("Target not found!")
        return
    end

    startAutokillLoop(target)
    API.sendChat("AutoKill locked on " .. target.Name .. " (type 'summon' or 'stop' to cancel)")
end

API.Create("autokill", autokillCommand)
API.Create("auto", autokillCommand)

local function gautokillCommand(args)
    if gautokillState.active then
        API.sendChat("GAutoKill already running!")
        return
    end

    stopAutokill()

    local target = select(1, resolveTargetFromArgs(args))
    if not target then
        API.sendChat("Target not found!")
        return
    end

    startGautokillLoop(target)
    API.sendChat("GAutoKill locked on " .. target.Name .. " (type 'summon' or 'stop' to cancel)")
end

API.Create("gautokill", gautokillCommand)
API.Create("gauto", gautokillCommand)

local originalStopFunction = API.Stop
API.Stop = function(...)
    stopAutokill()
    stopGautokill()
    if originalStopFunction then
        return originalStopFunction(...)
    end
end

local originalSummonFunction = API.Summon
API.Summon = function(...)
    stopAutokill()
    stopGautokill()
    if originalSummonFunction then
        return originalSummonFunction(...)
    end
end

local function wrapBaseCommandWithAutoReset(commandName)
    if API.Commands and type(API.Commands[commandName]) == "function" then
        local original = API.Commands[commandName]
        API.Commands[commandName] = function(...)
            stopAutokill("Auto modes cancelled by '" .. commandName .. "'")
            stopGautokill("Auto modes cancelled by '" .. commandName .. "'")
            return original(...)
        end
    end
end

wrapBaseCommandWithAutoReset("summon")
wrapBaseCommandWithAutoReset("stop")
wrapBaseCommandWithAutoReset("vanish")



if DahoodMainConfig.Automask == true and not amaskActive then
    task.spawn(function()
        task.wait(2) 
        amaskActive = true
        print("[Da Hood Config] Auto-activating AMask (getgenv config: Automask = true)")
        
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
                
                local maskTool, errorMsg = ensureMaskToolAvailable()
                if not maskTool then
                    if errorMsg then
                        warn("[AMask] Failed to buy mask: " .. tostring(errorMsg))
                    end
                    amaskBuying = false
                    return
                end
                
                if equipMaskTool(maskTool, character, humanoid) then
                    print("[AMask] Auto-equipped mask")
                end
                
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
end

RunService.Stepped:Connect(function()
    if DahoodMainConfig.AntiStomp == true then
        pcall(function()
            local localDead = isDead(LocalPlayer)
            local localKO = KO(LocalPlayer)
            
            if localDead == false and localKO and localKO.Value == false and getLocalHumanoid() and getLocalHumanoid().Health <= 80 then
                if MainEvent then
                    game.Players.LocalPlayer.Character.Humanoid.Health = 0
                end
            end
        end)
    end
end)

API.Create("stando", function(args)
    API.ForceChat("This is not stando mwuah 😙")
end)

API.Create("skido", function(args)
    API.ForceChat("This is not skido mwuah 😙")
end)

API.Create("stand", function(args)
    local part1 = { 
        "dѕc", "ԁѕᴄ", "ɗşç", "đşċ"
    }

    local part2 = { 
        ".ɡɡ", ".ɢɢ", "․ɡɡ"
    }

    local part3 = { 
        "ѕосіеtу‑ѕtаnd",
        "şoçïëłÿ‑şţåñđ",
        "şoċïeţý‑šťañd",
    }

    local p1 = part1[math.random(#part1)]
    local p2 = part2[math.random(#part2)]
    local p3 = part3[math.random(#part3)]

    API.ForceChat(p1)
    wait(0.1)
    API.ForceChat(p2)
    wait(0.1)
    API.ForceChat(p3)

end)


API.Notify({
    Title = "GAME CONFIG",
    Description = (game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Game") .. " Loaded",
    Duration = 20
})
