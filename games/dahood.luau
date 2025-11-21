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
    local HISTORY_WINDOW = 0.6
    local MAX_HISTORY = 30
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
        local currentCFrame = targetHRP.CFrame
        
        history[#history + 1] = {
            position = targetHRP.Position,
            velocity = targetHRP.AssemblyLinearVelocity,
            angularVelocity = targetHRP.AssemblyAngularVelocity,
            cframe = currentCFrame,
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

    local function detectJumping(history)
        if not history or #history < 4 then
            return false, 0
        end

        local recent = history[#history]
        local older = history[#history - 3]
        
        local verticalVelocity = recent.velocity.Y
        local verticalChange = recent.position.Y - older.position
        local timeDiff = recent.time - older.time
        
        if verticalVelocity > 8 or verticalChange > 5 then
            return true, verticalVelocity
        end
        
        return false, verticalVelocity
    end

    local function getTurningRate(history)
        if not history or #history < 3 then
            return 0
        end

        local totalAngleChange = 0
        for i = 2, #history do
            local prevLook = (history[i-1].cframe.LookVector * Vector3.new(1, 0, 1)).Unit
            local currLook = (history[i].cframe.LookVector * Vector3.new(1, 0, 1)).Unit

            if prevLook.Magnitude > 0 and currLook.Magnitude > 0 then
                local dotProduct = math.clamp(prevLook:Dot(currLook), -1, 1)
                local angleChange = math.acos(dotProduct)
                totalAngleChange += angleChange
            end
        end

        local duration = history[#history].time - history[1].time
        return duration > 0 and (totalAngleChange / duration) or 0
    end

    local function detectCircularMotion(history)
        if not history or #history < 6 then
            return false, 0
        end

        local positions = {}
        for i = 1, #history do
            positions[i] = history[i].position
        end

        local first = positions[1]
        local last = positions[#positions]
        local distanceFromStart = (last - first).Magnitude

        local maxDist = 0
        for i = 2, #positions - 1 do
            local dist = (positions[i] - first).Magnitude
            maxDist = math.max(maxDist, dist)
        end

        local totalDistance = 0
        for i = 2, #history do
            totalDistance += (history[i].position - history[i-1].position).Magnitude
        end

        local circularity = distanceFromStart > 0 and (totalDistance / distanceFromStart) or 0
        local isCircular = circularity > 2.5 and maxDist > 2 and distanceFromStart < maxDist * 0.4

        return isCircular, circularity
    end

    local function predictJumpArc(history, travelTime)
        if not history or #history < 2 then
            return Vector3.new()
        end

        local latest = history[#history]
        local initialPos = latest.position
        local initialVelocity = latest.velocity
        
        local gravity = 196.2
        local predictedY = initialPos.Y + (initialVelocity.Y * travelTime) - (0.5 * gravity * travelTime * travelTime)
        
        return Vector3.new(0, predictedY - initialPos.Y, 0)
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
        local isJumping, verticalVelocity = detectJumping(history)
        local turningRate = getTurningRate(history)
        local isCircular, circularity = detectCircularMotion(history)

        local effectiveSpeed = instantaneousSpeed
        if averageSpeed then
            effectiveSpeed = (effectiveSpeed * 0.4) + (averageSpeed * 0.6)
        end

        if burstSpeed and burstSpeed > effectiveSpeed then
            effectiveSpeed = (effectiveSpeed * 0.25) + (burstSpeed * 0.75)
        end

        local targetPlayer = Players:GetPlayerFromCharacter(targetHRP.Parent)
        local ping = targetPlayer and targetPlayer:GetNetworkPing() or 0.17

        local travelTime = 0.25 + (ping * 1.5)

        if turningRate > 1.5 then
            travelTime = travelTime * 0.85
        end

        if isCircular then
            travelTime = travelTime * 1.35
        end

        if isJumping then
            travelTime = travelTime * 1.2
        end

        if history and #history >= 4 then
            local newest = history[#history]
            local windowStart = history[#history - 3]
            local elapsed = math.max(newest.time - windowStart.time, 1e-3)
            local displacement = (newest.position - windowStart.position).Magnitude
            local windowSpeed = displacement / elapsed

            if windowSpeed > effectiveSpeed then
                travelTime = travelTime + math.min((windowSpeed - effectiveSpeed) * 0.008, 0.25)
            end
        end

        local desiredDistance = effectiveSpeed * travelTime

        if effectiveSpeed > 25 then
            desiredDistance = desiredDistance + math.min((effectiveSpeed - 25) * 0.9, 24)
        elseif effectiveSpeed > 15 then
            desiredDistance = desiredDistance + math.min((effectiveSpeed - 15) * 0.55, 12)
        end

        if isJumping then
            desiredDistance = desiredDistance * 1.15
        end

        if isCircular then
            desiredDistance = desiredDistance * 1.3
        end

        if turningRate > 2.0 then
            desiredDistance = desiredDistance * 0.9
        end
        
        -- Add flat distance boost for better prediction
        desiredDistance = desiredDistance + 3

        local maxDistance = 55
        desiredDistance = math.max(0, math.min(maxDistance, desiredDistance))

        local jumpOffset = Vector3.new()
        if isJumping then
            jumpOffset = predictJumpArc(history, travelTime)
        end

        local currentDistance = (predictedPos - targetHRP.Position).Magnitude
        if desiredDistance > currentDistance then
            local normalizedDirection = moveDirection / directionMagnitude
            predictedPos = targetHRP.Position + (normalizedDirection * desiredDistance) + jumpOffset
        else
            predictedPos = predictedPos + jumpOffset
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
            task.wait(0.06)
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
        -- Keep retrying with timeout to avoid prolonged lag
        local commandStartTime = tick()
        local maxCommandTime = 5
        while not success and not isKnockedOut(target) and Stand.Attacking and (tick() - commandStartTime < maxCommandTime) do
            success = chargedPunch(target)
            if not success and not isKnockedOut(target) and Stand.Attacking then
                -- Pause between attempts
                for i = 1, 10 do
                    if not Stand.Attacking then break end
                    task.wait(0.1)
                end
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

-- Register the stomp command
API.Create("stomp", function(args)
    if #args < 1 then
        return
    end
    
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or findPlayer(playerName)
    
    if not target then
        return
    end
    
    -- Save original state
    local wasAttacking = Stand.Attacking
    local wasFollowing = Stand.Following
    local originalTarget = API.currentFollowTarget
    
    -- Check if target is already knocked out
    if not isKnockedOut(target) then
        -- Knock them first
        Stand.Attacking = true
        Stand.Following = false
        API.currentFollowTarget = nil
        
        local success = false
        local knockStartTime = tick()
        local maxKnockTime = 10
        
        while not success and not isKnockedOut(target) and Stand.Attacking and (tick() - knockStartTime < maxKnockTime) do
            success = chargedPunch(target)
            if not success and not isKnockedOut(target) and Stand.Attacking then
                task.wait(0.2)
            end
        end
        
        if not isKnockedOut(target) then
            -- Failed to knock out, restore state and exit
            Stand.Attacking = wasAttacking
            Stand.Following = wasFollowing
            API.currentFollowTarget = originalTarget
            return
        end
    end
    
    -- Target is now knocked out, proceed with stomp
    Stand.Attacking = false
    Stand.Following = false
    API.currentFollowTarget = nil
    
    local stompSuccess = pcall(function()
        local targetCharacter = target and target.Character
        if not targetCharacter then return end
        
        local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")
        if not targetHRP then return end
        
        local hrp = getLocalHRP()
        if not hrp then return end
        
        -- Teleport directly on top of the knocked out target
        local targetPos = targetHRP.Position
        hrp.CFrame = CFrame.new(targetPos.X, targetPos.Y + 3, targetPos.Z)
        
        task.wait(0.1)
        
        -- Press E using VirtualInputManager
        local VirtualInputManager = game:GetService("VirtualInputManager")
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        
        task.wait(0.2)
    end)
    
    if stompSuccess then
        API.sendChat("Stomped " .. target.Name)
    end
    
    -- Restore original state
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
