local requiredFields = {"Stand", "Create", "Stop", "sendChat", "getPlayer", "ownerPlayer", "getPredictedPosition", "Notify"}
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
local LocalPlayer = Players.LocalPlayer
local Stand = API.Stand

-- Function to safely get LocalPlayer (handles reconnection scenarios)
local function getLocalPlayer()
    return Players.LocalPlayer
end

-- Ensure LocalPlayer is available before proceeding
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- Detected functions that trigger anticheat - these must be completely avoided
-- bodygyro and bodyvelocity: Used for physics manipulation (fling, knock, bring, etc.)
-- updatemousepos: Used for mouse position detection/manipulation
local DETECTED_FUNCTIONS = {
    bodygyro = true,
    bodyvelocity = true,
    updatemousepos = true
}

-- Mark the API with information about which commands use detected functions
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

local function wrapAPIMethod(methodName, wrapperBuilder)
    local tag = "_DaHoodWrapped_" .. methodName

    local function tryWrap()
        local original = API[methodName]
        if type(original) ~= "function" then
            return false
        end

        if API[tag] then
            return true
        end

        API[tag] = true
        API[methodName] = wrapperBuilder(original)
        return true
    end

    if not tryWrap() then
        task.spawn(function()
            while not tryWrap() do
                task.wait()
            end
        end)
    end
end

wrapAPIMethod("Stop", function(originalStop)
    return function(...)
        Stand.Attacking = false
        Stand.Following = false
        API.currentFollowTarget = nil
        return originalStop(...)
    end
end)

wrapAPIMethod("Summon", function(originalSummon)
    return function(...)
        if Stand.Attacking then
            Stand.Attacking = false
            Stand.Following = false
            API.currentFollowTarget = nil
        end
        return originalSummon(...)
    end
end)

wrapAPIMethod("getPredictedPosition", function(originalPredict)
    local HISTORY_WINDOW = 0.45
    local MAX_HISTORY = 20
    local motionHistory = setmetatable({}, {__mode = "k"})

    local function updateHistory(targetHRP)
        if not targetHRP then
            return nil
        end

        local history = motionHistory[targetHRP]
        if not history then
            history = {}
            motionHistory[targetHRP] = history
        end

        local now = tick()
        history[#history + 1] = {
            position = targetHRP.Position,
            velocity = targetHRP.AssemblyLinearVelocity,
            time = now
        }

        while #history > MAX_HISTORY do
            table.remove(history, 1)
        end

        while #history > 0 and (now - history[1].time) > HISTORY_WINDOW do
            table.remove(history, 1)
        end

        return history
    end

    local function getAverageSpeed(history)
        if not history or #history < 2 then
            return nil
        end

        local totalDistance = 0
        for i = 2, #history do
            totalDistance += (history[i].position - history[i-1].position).Magnitude
        end

        local duration = history[#history].time - history[1].time
        if duration <= 0 then
            return nil
        end

        return totalDistance / duration
    end

    local function getBurstSpeed(history)
        if not history or #history < 3 then
            return nil
        end

        local last = history[#history]
        local prev = history[#history - 1]
        local prev2 = history[#history - 2]

        local dt1 = math.max(prev.time - prev2.time, 1e-3)
        local dt2 = math.max(last.time - prev.time, 1e-3)

        local speed1 = (prev.position - prev2.position).Magnitude / dt1
        local speed2 = (last.position - prev.position).Magnitude / dt2

        return math.max(speed1, speed2)
    end

    return function(targetHRP, commandType)
        local predictionType = commandType == "knock" and "punch" or commandType
        local predictedPos, moveDirection = originalPredict(targetHRP, predictionType)

        if not targetHRP then
            return predictedPos, moveDirection
        end

        local history = updateHistory(targetHRP)

        if commandType ~= "knock" then
            return predictedPos, moveDirection
        end

        if not predictedPos or not moveDirection then
            return predictedPos, moveDirection
        end

        local directionMagnitude = moveDirection.Magnitude
        if directionMagnitude == 0 then
            return predictedPos, moveDirection
        end

        local velocity = targetHRP.AssemblyLinearVelocity
        local instantaneousSpeed = velocity.Magnitude
        local averageSpeed = getAverageSpeed(history)
        local burstSpeed = getBurstSpeed(history)

        local effectiveSpeed = instantaneousSpeed
        if averageSpeed then
            effectiveSpeed = (effectiveSpeed * 0.5) + (averageSpeed * 0.5)
        end

        if burstSpeed and burstSpeed > effectiveSpeed then
            effectiveSpeed = (effectiveSpeed * 0.35) + (burstSpeed * 0.65)
        end

        local targetPlayer = Players:GetPlayerFromCharacter(targetHRP.Parent)
        local ping = targetPlayer and targetPlayer:GetNetworkPing() or 0.17

        local travelTime = 0.2 + (ping * 1.35)

        if history and #history >= 4 then
            local newest = history[#history]
            local windowStart = history[#history - 3]
            local elapsed = math.max(newest.time - windowStart.time, 1e-3)
            local displacement = (newest.position - windowStart.position).Magnitude
            local windowSpeed = displacement / elapsed

            if windowSpeed > effectiveSpeed then
                travelTime = travelTime + math.min((windowSpeed - effectiveSpeed) * 0.007, 0.18)
            end
        end

        local desiredDistance = effectiveSpeed * travelTime

        if effectiveSpeed > 20 then
            desiredDistance = desiredDistance + math.min((effectiveSpeed - 20) * 0.5, 12)
        end

        local maxDistance = 32
        desiredDistance = math.max(0, math.min(maxDistance, desiredDistance))

        local currentDistance = (predictedPos - targetHRP.Position).Magnitude
        if desiredDistance > currentDistance then
            local normalizedDirection = moveDirection / directionMagnitude
            predictedPos = targetHRP.Position + (normalizedDirection * desiredDistance)
        end

        return predictedPos, moveDirection
    end
end)

-- Helper functions
local function getLocalCharacter()
    local success, result = pcall(function()
        local player = getLocalPlayer()
        if not player then return nil end
        local character = player.Character
        return character
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

-- Combat helper functions for Da Hood
local function getPredictedPosition(targetHRP, commandType)
    return API.getPredictedPosition(targetHRP, commandType)
end

local function findPlayer(name)
    local target = API.getPlayer(name)
    if target then return target end
    
    if name == "" or name == "me" then
        return API.ownerPlayer or getLocalPlayer()
    end
    
    local lowerName = name:lower()
    local localPlayer = getLocalPlayer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and 
           (player.Name:lower():find(lowerName, 1, true) or 
           (player.DisplayName and player.DisplayName:lower():find(lowerName, 1, true))) then
            return player
        end
    end
    
    return nil
end

local function isKnockedOut(player)
    if not player then
        return false
    end
    
    local success, character = pcall(function()
        return player.Character
    end)
    if not success or not character then
        return false
    end
    
    local success2, result = pcall(function()
        local bodyEffects = character:FindFirstChild("BodyEffects")
        if bodyEffects then
            local ko = bodyEffects:FindFirstChild("K.O")
            if ko and ko.Value then
                return true
            end
        end
        return false
    end)
    
    return success2 and result or false
end

local function equipCombatTool()
    local success, result = pcall(function()
        local player = getLocalPlayer()
        if not player then return nil end
        
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then return nil end
        
        local combatTool = backpack:FindFirstChild("Combat")
        if not combatTool then return nil end

        local humanoid = getLocalHumanoid()
        if not humanoid then return nil end

        humanoid:EquipTool(combatTool)
        task.wait(0.1)
        return combatTool
    end)
    
    return success and result or nil
end

local function unequipTools()
    pcall(function()
        local humanoid = getLocalHumanoid()
        if humanoid then
            humanoid:UnequipTools()
        end
    end)
end

local function quickPunches(targetPlayer)
    if not targetPlayer then return false end
    
    local combatTool = equipCombatTool()
    if not combatTool then
        return false
    end
    
    if API.Commands and API.Commands["frame"] then
        API.Commands["frame"]({targetPlayer.Name})
    else
        API.currentFollowTarget = targetPlayer
    end
    
    local maxPunches = 50
    local punches = 0
    
    while punches < maxPunches and Stand.Attacking and not isKnockedOut(targetPlayer) do
        punches = punches + 1
        
        local success, shouldBreak = pcall(function()
            local targetCharacter = targetPlayer and targetPlayer.Character
            if not targetCharacter then return true end
            
            local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return true end
            
            local predictedPos, moveDirection = getPredictedPosition(targetHRP, "knock")
            
            local hrp = getLocalHRP()
            if predictedPos and hrp then
                hrp.CFrame = CFrame.new(predictedPos + (moveDirection * 6), predictedPos)
            end

            combatTool:Activate()
            task.wait(0.06)
            combatTool:Deactivate()
            
            return false
        end)
        
        if not success or shouldBreak then
            break
        end
        
        task.wait(0.1)
    end
    
    unequipTools()
    return isKnockedOut(targetPlayer)
end

local FALLBACK_POSITIONS = {
    Vector3.new(-880, 116, -969),
    Vector3.new(-888, 116, -885),
    Vector3.new(-927, 116, -850),
    Vector3.new(-975, 120, -891),
    Vector3.new(-990, 120, -991)
}

local function chargedPunch(targetPlayer)
    if not targetPlayer then return false end
    
    local combatTool = equipCombatTool()
    if not combatTool then
        return false
    end
    
    local chargeTime = 1.5
    local startTime = tick()
    local positionIndex = 1
    
    pcall(function() combatTool:Activate() end)
    
    local wasAttacking = Stand.Attacking
    local wasFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    while tick() - startTime < chargeTime do
        if isKnockedOut(targetPlayer) then
            pcall(function() combatTool:Deactivate() end)
            unequipTools()
            Stand.Attacking = wasAttacking
            Stand.Following = wasFollowing
            API.currentFollowTarget = originalTarget
            return true
        end
        
        pcall(function()
            local hrp = getLocalHRP()
            if hrp then
                hrp.CFrame = CFrame.new(FALLBACK_POSITIONS[positionIndex])
                positionIndex = (positionIndex % #FALLBACK_POSITIONS) + 1
            end
        end)
        
        task.wait(0.001)
    end
    
    local success, targetHRP = pcall(function()
        local targetCharacter = targetPlayer and targetPlayer.Character
        if not targetCharacter then return nil end
        return targetCharacter:FindFirstChild("HumanoidRootPart")
    end)
    
    if not success or not targetHRP then
        pcall(function() combatTool:Deactivate() end)
        unequipTools()
        Stand.Attacking = wasAttacking
        Stand.Following = wasFollowing
        API.currentFollowTarget = originalTarget
        return false
    end
    
    if API.Commands and API.Commands["frame"] then
        API.Commands["frame"]({targetPlayer.Name})
    else
        API.currentFollowTarget = targetPlayer
    end
    
    Stand.Following = true
    Stand.Attacking = true
    
    pcall(function()
        local predictedPos, moveDirection = getPredictedPosition(targetHRP, "knock")
        
        local hrp = getLocalHRP()
        if predictedPos and hrp then
            hrp.CFrame = CFrame.new(predictedPos + (moveDirection * 6), predictedPos)
        end
    end)
    
    pcall(function() combatTool:Deactivate() end)
    
    local maxAttempts = 25
    local attempts = 0
    local knockSuccess = false
    
    while not isKnockedOut(targetPlayer) and attempts < maxAttempts do
        attempts = attempts + 1
        
        local loopSuccess = pcall(function()
            local loopCharacter = targetPlayer and targetPlayer.Character
            if not loopCharacter then return end
            
            local loopHRP = loopCharacter:FindFirstChild("HumanoidRootPart")
            if not loopHRP then return end
            
            local newPredictedPos, newMoveDirection = getPredictedPosition(loopHRP, "knock")
            local hrp = getLocalHRP()
            if newPredictedPos and hrp then
                hrp.CFrame = CFrame.new(newPredictedPos + (newMoveDirection * 6), newPredictedPos)
            end
            
            combatTool:Activate()
            task.wait(0.03)
            combatTool:Deactivate()
        end)
        
        if not loopSuccess then
            break
        end
        
        task.wait(0.08)
        
        if isKnockedOut(targetPlayer) then
            knockSuccess = true
            break
        end
    end
    
    unequipTools()
    
    Stand.Attacking = wasAttacking
    Stand.Following = wasFollowing
    API.currentFollowTarget = originalTarget
    
    return knockSuccess
end

-- Register the knock command (safe - uses CFrame positioning, no detected functions)
API.Create("knock", function(args)
    if #args < 1 then
        return
    end
    
    local playerName = table.concat(args, " ")
    local mode = "heavy"
    
    if args[#args] == "light" or args[#args] == "heavy" then
        mode = table.remove(args)
        playerName = table.concat(args, " ")
    end
    
    local target = (playerName == "" and API.ownerPlayer) or findPlayer(playerName)
    
    if not target then
        return
    end
    
    if isKnockedOut(target) then
        return
    end
    
    local wasAttacking = Stand.Attacking
    local wasFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    Stand.Attacking = true
    Stand.Following = false
    API.currentFollowTarget = nil
    
    local success = false
    
    if mode == "light" then
        success = quickPunches(target)
    else
        local attempts = 0
        local maxAttempts = 2
        
        while not success and attempts < maxAttempts and not isKnockedOut(target) do
            attempts = attempts + 1
            success = chargedPunch(target)
            if not success and attempts < maxAttempts then
                task.wait(0.5)
            end
        end
    end
    
    if success then
        API.sendChat("Knocked out " .. target.Name)
    end
    
    -- Restore original state regardless of success
    Stand.Attacking = wasAttacking
    Stand.Following = wasFollowing
    API.currentFollowTarget = originalTarget
end)

API.Notify({
    Title = "GAME CONFIG",
    Description = (game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Game") .. " Loaded",
    Duration = 20
})

local disabledList = {}
for cmd, _ in pairs(API.DetectedFunctionsInfo.disabledCommands) do
    table.insert(disabledList, cmd)
end
if #disabledList > 0 then
    print("[Da Hood Config] Disabled commands:", table.concat(disabledList, ", "))
    API.Notify({
        Title = "ANTICHEAT PROTECTION",
        Description = "Disabled commands: " .. table.concat(disabledList, ", ") .. "\nThese use detected functions that trigger anticheat",
        Duration = 15
    })
end

-- Initialize fall protection AFTER everything else is set up and character is loaded
task.spawn(function()
    -- Wait for character to be fully loaded
    local character = getLocalCharacter()
    while not character do
        task.wait(0.5)
        character = getLocalCharacter()
    end
    
    -- Wait for HumanoidRootPart to exist
    local hrp = getLocalHRP()
    while not hrp do
        task.wait(0.5)
        hrp = getLocalHRP()
    end
    
    -- Additional delay to let player settle after initial spawn/teleport
    task.wait(2)
    
    local FALLEN_PARTS_HEIGHT = workspace.FallenPartsDestroyHeight or -500
    local BASE_FALL_THRESHOLD = (FALLEN_PARTS_HEIGHT + 20)
    local FALL_THRESHOLD = math.min(math.max(BASE_FALL_THRESHOLD, -50), -5)
    local SAFE_UPDATE_Y = FALL_THRESHOLD + 5
    local FALL_RECOVERY_Y = FALL_THRESHOLD - 5
    local lastSafeCFrame = nil
    
    -- Initialize lastSafeCFrame with current position
    pcall(function()
        local initialHRP = getLocalHRP()
        if initialHRP and initialHRP.Position.Y > SAFE_UPDATE_Y then
            lastSafeCFrame = initialHRP.CFrame
        end
    end)
    
    -- Set up respawn handler
    local function onCharacterAdded(newCharacter)
        lastSafeCFrame = nil
        if not newCharacter then return end
        task.wait(2)
        
        pcall(function()
            local newHRP = newCharacter:WaitForChild("HumanoidRootPart", 10)
            if newHRP and newHRP.Position.Y > SAFE_UPDATE_Y then
                lastSafeCFrame = newHRP.CFrame
            end
        end)
    end
    
    local player = getLocalPlayer()
    if player then
        player.CharacterAdded:Connect(onCharacterAdded)
        
        -- Add CharacterRemoving handler to clean up when player dies
        player.CharacterRemoving:Connect(function()
            lastSafeCFrame = nil
        end)
    end
    
    -- Start fall protection loop
    RunService.Heartbeat:Connect(function()
        local success, err = pcall(function()
            local hrp = getLocalHRP()
            if not hrp then return end

            local currentY = hrp.Position.Y
            if currentY > SAFE_UPDATE_Y then
                lastSafeCFrame = hrp.CFrame
                return
            end

            if lastSafeCFrame and currentY < FALL_RECOVERY_Y then
                hrp.CFrame = lastSafeCFrame * CFrame.new(0, 2, 0)
            end
        end)
        if not success then
            -- Silently handle errors to prevent spam when player dies
        end
    end)
    
    print("[Da Hood Config] Fall protection initialized")
end)
