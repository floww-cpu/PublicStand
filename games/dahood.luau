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

-- MainEvent reference
local MainEvent = ReplicatedStorage:WaitForChild("MainEvent", 5)

-- AutoPredic value (prediction multiplier)
local AutoPredic = 0.155

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
print("[Da Hood Config] Commands: knock <player>, stomp <player>")
print("[Da Hood Config] Prediction: 0.155 (AutoPredic)")
