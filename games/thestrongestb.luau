local requiredFields = {"Stand", "Create", "Stop", "sendChat", "getPlayer", "ownerPlayer", "currentFollowTarget"}
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

local function hrpOf(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function myHRP() return hrpOf(LocalPlayer.Character) end

local function isSlotOnCooldown(slotNumber)
    local hotbar = LocalPlayer.PlayerGui:FindFirstChild("Hotbar")
    if not hotbar then return false end
    
    local backpack = hotbar:FindFirstChild("Backpack")
    if not backpack then return false end
    
    local hotbarSlots = backpack:FindFirstChild("Hotbar")
    if not hotbarSlots then return false end
    
    local slot = hotbarSlots:FindFirstChild(tostring(slotNumber))
    if not slot then return false end
    
    local base = slot:FindFirstChild("Base")
    if not base then return false end
    
    local cooldown = base:FindFirstChild("Cooldown")
    if cooldown then
        return true 
    end
    
    return false 
end

local slotToToolName = {}

local VIM = game:GetService("VirtualInputManager")

local function doM1()
    if not Stand.Attack then return false end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:UnequipTools() end)
    end

    VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) 
    task.wait(0.05)
    VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    return true
end


local function getToolByName(name)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return nil end
    return bp:FindFirstChild(name) or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(name))
end

local function getAvailableSlots()
    local availableSlots = {}
    for slotNumber = 1, 4 do
        if not isSlotOnCooldown(slotNumber) then
            table.insert(availableSlots, slotNumber)
        end
    end
    return availableSlots
end

local function equip(tool)
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and tool and tool.Parent ~= LocalPlayer.Character then
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.1)
    end
end

local function tryFireTool(tool, toolName)
    if not Stand.Attack or not tool then return false end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    pcall(function() hum:EquipTool(tool) end)
    task.wait(0.05)
    if not Stand.Attack then return false end

    local ok = false
    if tool.Activate then ok = pcall(function() tool:Activate() end) or ok end
    for _, d in ipairs(tool:GetDescendants()) do
        if not Stand.Attack then break end
        if d:IsA("RemoteEvent") then
            ok = pcall(function() d:FireServer() end) or ok
        elseif d:IsA("RemoteFunction") then
            ok = pcall(function() d:InvokeServer() end) or ok
        end
        if ok then break end
    end

    task.wait(0.05)
    pcall(function() hum:UnequipTools() end)
    return ok
end

local function clearAttackState()
    if Stand.AttackConn then Stand.AttackConn:Disconnect() Stand.AttackConn = nil end
    if Stand.AttackDeathConn then Stand.AttackDeathConn:Disconnect() Stand.AttackDeathConn = nil end
    Stand.Attack = false
    Stand.Attacking = false
    
    -- Return to following the owner after attack is cleared
    if API then
        API.currentFollowTarget = API.ownerPlayer
        API.Stand.Following = true
        API.Stop()
        API.Summon()
    end
end

local MoveCooldowns = {0, 0, 0, 0}

local function resetMimicCooldowns()
    for i = 1, 4 do
        MoveCooldowns[i] = 0
    end
end

local function markMoveCooldown(slotIndex, duration)
    MoveCooldowns[slotIndex] = os.clock() + duration
end

local function isMoveOnCooldown(slotIndex)
    return (MoveCooldowns[slotIndex] or 0) > os.clock()
end

local MimicEnabled = false
local MimicTarget = nil
local MimicConnections = {}
local MimicCharacterConnections = {}

local function disconnectConnections(list)
    for _, conn in ipairs(list) do
        if conn then
            conn:Disconnect()
        end
    end
end

local function clearMimicCharacterConnections()
    disconnectConnections(MimicCharacterConnections)
    MimicCharacterConnections = {}
end

local function clearMimicState()
    MimicEnabled = false
    MimicTarget = nil
    disconnectConnections(MimicConnections)
    MimicConnections = {}
    clearMimicCharacterConnections()
    resetMimicCooldowns()
    
    -- Reset API flags when mimic state is cleared
    if API then
        API.MimicEnabled = false
        API.currentFollowTarget = API.ownerPlayer  -- Return to following owner
    end
end

local Movesets = {
    [1] = { name = "TheStrongestHero", character = "Bald", tools = {"Normal Punch", "Consecutive Punches", "Shove", "Uppercut"} },
    [2] = { name = "HeroHunter", character = "Hunter", tools = {"Flowing Water","Lethal Whirlwind Stream","Hunter's Grasp","Prey's Peril"} },
    [3] = { name = "DestructiveCyborg", character = "Cyborg", tools = {"Machine Gun Blows","Ignition Burst","Blitz Shot","Jet Dive"} },
    [4] = { name = "DeadlyNinja", character = "Ninja", tools = {"Flash Strike","Whirlwind Kick","Scatter","Explosive Shuriken"} },
    [5] = { name = "BrutalDemon", character = "Batter", tools = {"Homerun","Beatdown","Grand Slam","Foul Ball"} },
    [6] = { name = "BladeMaster", character = "Blade", tools = {"Quick Slice","Atmos Cleave","Pinpoint Cut","Split Second Counter"} },
    [7] = { name = "WildPsychic", character = "Esper", tools = {"Crushing Pull","Windstorm Fury","Stone Coffin","Expulsive Push"} },
    [8] = { name = "MartialArtist", character = "Purple", tools = {"Bullet Barrage","Vanishing Kick","Whirlwind Drop","Head First"} },
}

local MovesList = {
    {"Normal Punch", 10468665991, 20, 1, "Normal Punch"},
    {"Consecutive Punches", 10466974800, 15, 2, "Consecutive Punches"},
    {"Shove", 10471336737, 10, 3, "Shove"},
    {"Uppercut", 12510170988, 20, 4, "Uppercut"},
    {"Table Flip", 11365563255, 20, 2, "Table Flip"},
    {"Serious Punch", 12983333733, 20, 3, "Serious Punch"},
    {"Omni Directional Punch", 13927612951, 20, 4, "Omni Directional Punch"},
    {"Lethal Whirlwind Stream", 12296882427, 20, 2, "Lethal Whirlwind Stream"},
    {"Flowing Water", 12272894215, 17.5, 1, "Flowing Water"},
    {"Hunters Grasp", 12307656616, 15, 3, "Hunter's Grasp"},
    {"Preys Peril", 12351854556, 17, 4, "Prey's Peril"},
    {"Water Stream Cutting Fist", 12460977270, 8.450704225352114, 1, "Water Stream Cutting Fist"},
    {"The Final Hunt", 12463072679, 101, 2, "The Final Hunt"},
    {"Rock Splitting Fist", 14057231976, 14.084507042253522, 3, "Rock Splitting Fist"},
    {"Crushed Rock", 13630786846, 9.577464788732394, 4, "Crushed Rock"},
    {"Machine Gun Blows", 12534735382, 15, 1, "Machine Gun Blows"},
    {"Machine Gun Blows", 12971270638, 15, 1, "Machine Gun Blows"},
    {"Ignition Burst", 12502664044, 17.5, 2, "Ignition Burst"},
    {"Blitz Shot", 12618271998, 25, 3, "Blitz Shot"},
    {"Jet Dive", 12684390285, 17.5, 4, "Jet Dive"},
    {"Thunder Kick", 14721837245, 15, 1, "Thunder Kick"},
    {"Speedblitz Dropkick", 12832505612, 20, 2, "Speedblitz Dropkick"},
    {"Flamewave Cannon", 13083332742, 25, 3, "Flamewave Cannon"},
    {"Incinerate", 13146710762, 101, 4, "Incinerate"},
    {"Flash Strike", 13309500827, 17.5, 1, "Flash Strike"},
    {"Whirlwind Kick", 13294790250, 20, 2, "Whirlwind Kick"},
    {"Scatter", 13362587853, 21.25, 3, "Scatter"},
    {"Explosive Shuriken", 13501296372, 17.5, 4, "Explosive Shuriken"},
    {"Twinblade Rush", 13632347366, 20, 1, "Twinblade Rush"},
    {"Straight On", 13643152947, 17, 2, "Straight On"},
    {"Carnage", 13723174078, 25, 3, "Carnage"},
    {"Fourfold Flashstrike", 13881335713, 25, 4, "Fourfold Flashstrike"},
    {"Homerun", 14004235777, 17.5, 1, "Homerun"},
    {"Beatdown", 14046756619, 23, 2, "Beatdown"},
    {"Grand Slam", 14299135500, 20, 3, "Grand Slam"},
    {"Foul Ball", 14351441234, 23, 4, "Foul Ball"},
    {"Savage Tornado", 14719290328, 17, 1, "Savage Tornado"},
    {"Brutal Beatdown", 14701242661, 30, 2, "Brutal Beatdown"},
    {"Strength Difference", 14900168720, 20, 3, "Strength Difference"},
    {"Death Blow", 15128849047, 101, 4, "Death Blow"},
    {"Quick Slice", 15290930205, 20, 1, "Quick Slice"},
    {"Atmos Cleave", 15145462680, 22, 2, "Atmos Cleave"},
    {"Pinpoint Cut", 15295895753, 17, 3, "Pinpoint Cut"},
    {"Split Second Counter", 15311685628, 17.5, 4, "Split Second Counter"},
    {"Sunset", 15520132233, 15, 1, "Sunset"},
    {"Solar Cleave", 15676072469, 15, 2, "Solar Cleave"},
    {"Sunrise", 16062410809, 20, 3, "Sunrise"},
    {"Atomic Slash", 16082123712, 101, 4, "Atomic Slash"},
    {"Crushing Pull", 16139108718, 21, 1, "Crushing Pull"},
    {"Windstorm Fury", 16515850153, 20, 2, "Windstorm Fury"},
    {"Stone Coffin", 16431491215, 25, 3, "Stone Coffin"},
    {"Expulsive Push", 16597322398, 19, 4, "Expulsive Push"},
    {"Cosmic Strike", 16737255386, 30, 1, "Cosmic Strike"},
    {"Psychic Ricochet", 17464644182, 15, 2, "Psychic Ricochet"},
    {"Terrible Tornado", 17275150809, 101, 3, "Terrible Tornado"},
    {"Sky Snatcher", 17860467628, 17, 4, "Sky Snatcher"},
    {"Bullet Barrage", 17799224866, 20, 1, "Bullet Barrage"},
    {"Vanishing Kick", 17838006839, 23, 2, "Vanishing Kick"},
    {"Whirlwind Drop", 17857788598, 15, 3, "Whirlwind Drop"},
    {"Head First", 18179181663, 20, 4, "Head First"},
}

local MovesBySlot = {
    [1] = {},
    [2] = {},
    [3] = {},
    [4] = {}
}
local MovesByAnimationId = {}

for _, move in ipairs(MovesList) do
    local slot = move[4]
    MovesBySlot[slot] = MovesBySlot[slot] or {}
    table.insert(MovesBySlot[slot], move)

    local animationIdStr = tostring(move[2])
    MovesByAnimationId[animationIdStr] = MovesByAnimationId[animationIdStr] or {}
    table.insert(MovesByAnimationId[animationIdStr], move)
end

local function getAnimationIdString(animationTrack)
    if not animationTrack then return nil end
    local success, animationId = pcall(function()
        return tostring(animationTrack.Animation.AnimationId):match("%d+")
    end)
    if success and animationId then
        return animationId
    end
    return nil
end

local function detectToolsAndClass()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    local detectedTools = {}
    local detectedClass = nil

    if bp then
        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") then
                table.insert(detectedTools, tool.Name)
            end
        end
    end

    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                table.insert(detectedTools, tool.Name)
            end
        end
    end

    local uniqueTools = {}
    local seen = {}
    for _, tName in ipairs(detectedTools) do
        if not seen[tName] then
            table.insert(uniqueTools, tName)
            seen[tName] = true
        end
        if #uniqueTools >= 4 then break end
    end

    for _, data in pairs(Movesets) do
        for _, tName in ipairs(data.tools) do
            for _, dt in ipairs(uniqueTools) do
                if dt == tName then
                    detectedClass = data.character
                    break
                end
            end
            if detectedClass then break end
        end
        if detectedClass then break end
    end

    if not detectedClass then
        detectedClass = char and char.Name or "Unknown"
    end

    for i = 1, 4 do
        slotToToolName[i] = uniqueTools[i]
    end

    print("[Auto-detect] Class:", detectedClass)
    print("[Auto-detect] Tools:", table.concat(uniqueTools, ", "))
end

detectToolsAndClass()


local function switchMode(num)
    local data = Movesets[num]
    if not data then
        warn("Invalid mode:", num)
        return
    end

    local args = {{Goal = "Change Character", Character = data.character}}
    local char = LocalPlayer.Character
    local comm = char and char:FindFirstChild("Communicate")
    if comm and comm:IsA("RemoteEvent") then
        comm:FireServer(unpack(args))
    else
        Instance.new("RemoteEvent", nil):FireServer(unpack(args))
    end

    for i, toolName in ipairs(data.tools) do
        slotToToolName[i] = toolName
    end

    print("[Mode Switch] Now:", data.name, "(", data.character, ")")
    return data
end

API.Create("switch", function(args)
    local modeNum = tonumber(args[1])
    if not modeNum then
        API.sendChat("Invalid mode number. Usage: switch <1-8>")
        return
    end
    local data = switchMode(modeNum)
    if data then
        API.sendChat(("Switched mode to %s (%s)"):format(data.name, data.character))
    end
end)

API.Create("attack", function(args)
    if Stand.Attack then
        clearAttackState()
        
        -- Reset to following the owner
        API.Stand.Following = true
        API.currentFollowTarget = API.ownerPlayer
        API.Stop()
        API.sendChat("Stopped attacking.")
        return
    end

    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    if not target then
        local lowerName = playerName:lower()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and (player.Name:lower():find(lowerName,1,true) or 
                (player.DisplayName and player.DisplayName:lower():find(lowerName,1,true))) then
                target = player
                break
            end
        end
    end

    if not target or not target.Character then
        API.sendChat("Target not found.")
        return
    end

    local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
    local targetHRP = hrpOf(target.Character)
    if not humanoid or not targetHRP then
        API.sendChat("Target invalid (no Humanoid/HRP).")
        return
    end

    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character.HumanoidRootPart.Anchored = false
    end

    Stand.Summoned = true
    Stand.Following = true
    Stand.Attack = true
    Stand.Attacking = true  
    API.Summon()
    
    -- Set the follow target to the attack target
    API.currentFollowTarget = target

    Stand.AttackDeathConn = humanoid.Died:Connect(function()
        clearAttackState()
        API.sendChat("Target eliminated. Returning to owner.")
    end)

    Stand.AttackConn = RunService.Heartbeat:Connect(function()
        if not Stand.Attack or not (target.Character and targetHRP.Parent) then return end
        if API.currentFollowTarget ~= target then API.currentFollowTarget = target end

        local availableSlots = getAvailableSlots()
        local usedTool = false

        if #availableSlots > 0 then
            for _, slotNumber in ipairs(availableSlots) do
                if not Stand.Attack then break end
                local tool = getToolByName(slotToToolName[slotNumber])
                if tool then
                    Stand.Attacking = true
                    tryFireTool(tool, slotToToolName[slotNumber])
                    usedTool = true
                    task.wait(0.5)
                end
            end
        end

        if not usedTool then
            for i = 1, 3 do
                if not Stand.Attack then break end
                doM1()
                task.wait(0.1)
            end
        end
    end)




    API.sendChat("Attacking " .. target.Name .. "!")
end)

API.Create("unattack", function()
    clearAttackState()
    clearAutoAttackState()
    clearAssistState()
    clearMimicState()
    
    -- Reset to following the owner
    API.Stand.Following = true
    API.currentFollowTarget = API.ownerPlayer
    API.Stop()
    API.Summon()
    API.sendChat("Stopped attacking and returned to following owner.")
end)

API.Create("auto", function(args)
    clearAutoAttackState()
    
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    if not target then
        local lowerName = playerName:lower()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and (player.Name:lower():find(lowerName,1,true) or 
                (player.DisplayName and player.DisplayName:lower():find(lowerName,1,true))) then
                target = player
                break
            end
        end
    end

    if not target or not target.Character then
        API.sendChat("Target not found.")
        return
    end

    AutoAttackEnabled = true
    AutoAttackTarget = target
    Stand.Summoned = true
    Stand.Following = true
    Stand.Attack = true
    Stand.Attacking = true
    API.Summon()
    
    API.currentFollowTarget = target
    
    -- Handle respawn
    AutoAttackRespawnConn = target.CharacterAdded:Connect(function(newCharacter)
        if AutoAttackEnabled and AutoAttackTarget == target then
            task.wait(1) -- Give time for character to load
            startAutoAttackLoop()
        end
    end)

    startAutoAttackLoop()
    API.sendChat("Auto attacking " .. target.Name .. "! Use 'auto' again to stop.")
end)


API.Create("assist", function()
    if AssistEnabled then
        clearAssistState()
        API.sendChat("Assist stopped.")
        return
    end
    
    if not API.ownerPlayer or not API.ownerPlayer.Character then
        API.sendChat("Owner not available for assist.")
        return
    end
    
    AssistEnabled = true
    Stand.Attacking = false
    Stand.Summoned = true
    API.currentFollowTarget = API.ownerPlayer
    
    setupAssistForOwner()
    
    table.insert(AssistConnections, RunService.Heartbeat:Connect(function()
        if not AssistEnabled then return end
        
        if not API.ownerPlayer or not API.ownerPlayer.Character then
            clearAssistState()
            return
        end
        
        local ownerHRP = API.ownerPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not ownerHRP then return end
        
        local now = os.clock()
        
        if AssistCurrentTarget then
            if not AssistCurrentTarget.Parent then
                clearAssistAttack()
            else
                local humanoid = AssistCurrentTarget.Character and AssistCurrentTarget.Character:FindFirstChildOfClass("Humanoid")
                if not humanoid or humanoid.Health <= 0 then
                    clearAssistAttack()
                end
            end
        end
        
        local nextThreat
        
        if (now - AssistLastOwnerAttackTime) < ASSIST_THREAT_WINDOW then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player ~= API.ownerPlayer and not isWhitelisted(player) and player.Character then
                    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                    local playerHRP = player.Character:FindFirstChild("HumanoidRootPart")
                    if humanoid and humanoid.Health > 0 and playerHRP then
                        if distanceToPlayer(player) <= ASSIST_ATTACK_RANGE then
                            if player ~= AssistCurrentTarget then
                                nextThreat = player
                                break
                            end
                        end
                    end
                end
            end
        end
        
        if nextThreat then
            startAssistAttack(nextThreat)
        end
        
        if not AssistCurrentTarget and not Stand.Attack then
            API.currentFollowTarget = API.ownerPlayer
        end
    end))
    
    API.sendChat("Assist activated! Will attack nearby enemies when you use abilities.")
end)

API.Create("unassist", function()
    clearAssistState()
    API.sendChat("Assist deactivated.")
end)


local VIM = game:GetService("VirtualInputManager")

local recentlyUsedTrashcans = {}
local TRASHCAN_MEMORY_TIME = 35 

local function leftClick()
    VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) 
    task.wait(0.1)
    VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0) 
end

local function getClosestTrashcan()
     local trashFolder = workspace:FindFirstChild("Trash")
     if not trashFolder then
         local mapFolder = workspace:FindFirstChild("Map")
         if mapFolder then
             trashFolder = mapFolder:FindFirstChild("Trash")
         end
     end
     if not trashFolder then return nil end

     local myPos = myHRP() and myHRP().Position
     if not myPos then return nil end

     local closest, dist = nil, math.huge
     for _, obj in ipairs(trashFolder:GetChildren()) do
         if obj.Name == "Trashcan" and obj:IsDescendantOf(workspace) then
             if not recentlyUsedTrashcans[obj] then
                 local primaryPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                 if primaryPart then
                     local d = (primaryPart.Position - myPos).Magnitude
                     if d < dist then
                         closest, dist = obj, d
                     end
                 end
             end
         end
     end
     return closest
 end

local function trashcanStillExists(trashcan)
    return trashcan and trashcan:IsDescendantOf(workspace) and trashcan.Name == "Trashcan"
end

local function markTrashcanUsed(trashcan)
    if trashcan then
        recentlyUsedTrashcans[trashcan] = true
        delay(TRASHCAN_MEMORY_TIME, function()
            recentlyUsedTrashcans[trashcan] = nil
        end)
    end
end

local function trashAttack(target)
     if not target or not target.Character then
         API.sendChat("Target not found!")
         return
     end

     local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
     if not targetHRP then
         return
     end

     local trashcan = getClosestTrashcan()
     if not trashcan then
         API.sendChat("No available trashcans found! They respawn every 35 seconds.")
         return
     end

     local trashcanPart = trashcan.PrimaryPart or trashcan:FindFirstChildWhichIsA("BasePart")
     if not trashcanPart then
         return
     end

     local wasAttacking = Stand.Attacking
     local wasFollowing = Stand.Following
     local wasSummoned = Stand.Summoned
     local wasManualControl = Stand.ManualControl
     local originalTarget = API.currentFollowTarget

     Stand.Attacking = false
     Stand.Following = false
     Stand.Summoned = true
     Stand.ManualControl = true
     API.currentFollowTarget = nil
     Stand.TrashAttacking = true

     if not trashcanStillExists(trashcan) then
         API.sendChat("Trashcan disappeared before we could reach it!")
         Stand.TrashAttacking = false
         Stand.ManualControl = wasManualControl
         return
     end

     markTrashcanUsed(trashcan)

     local myHRP = myHRP()
           local char = LocalPlayer.Character
           local humanoid = char and char:FindFirstChildOfClass("Humanoid")
           if myHRP then
               local trashcanPos = trashcanPart.Position
               local direction = (trashcanPos - myHRP.Position).Unit
               local approachPos = trashcanPos - direction * 2

               -- Teleport to approach position for instant pickup
               myHRP.CFrame = CFrame.new(approachPos, Vector3.new(trashcanPos.X, approachPos.Y, trashcanPos.Z))
           end
     task.wait(0.3)

     if not trashcanStillExists(trashcan) then
         API.sendChat("Trashcan disappeared before we could pick it up!")
         local newTrashcan = getClosestTrashcan()
         if newTrashcan then
             trashcan = newTrashcan
             trashcanPart = trashcan.PrimaryPart or trashcan:FindFirstChildWhichIsA("BasePart")
             myHRP = myHRP()
             humanoid = char and char:FindFirstChildOfClass("Humanoid")
             if trashcanPart and myHRP then
                               local trashcanPos = trashcanPart.Position
                               local direction = (trashcanPos - myHRP.Position).Unit
                               local approachPos = trashcanPos - direction * 2

                               -- Teleport to approach position for instant pickup
                               myHRP.CFrame = CFrame.new(approachPos, Vector3.new(trashcanPos.X, approachPos.Y, trashcanPos.Z))
                               task.wait(0.3)
                               markTrashcanUsed(trashcan)
             else
                 Stand.TrashAttacking = false
                 Stand.ManualControl = wasManualControl
                 return
             end
         else
             API.sendChat("No trashcans available right now.")
             Stand.TrashAttacking = false
             Stand.ManualControl = wasManualControl
             return
         end
     end

     leftClick()
     task.wait(1.5)

     -- Verify trashcan was picked up by checking if character has it
     local char = LocalPlayer.Character
     local humanoid = char and char:FindFirstChildOfClass("Humanoid")
     local hasTrashcan = false
     if char then
         for _, child in ipairs(char:GetChildren()) do
             if child:IsA("Tool") and child.Name:lower():find("trash") then
                 hasTrashcan = true
                 break
             end
         end
     end
     
     if not hasTrashcan then
         API.sendChat("Failed to pick up trashcan!")
         Stand.TrashAttacking = false
         Stand.ManualControl = wasManualControl
         return
     end

     myHRP = myHRP()
           if myHRP and targetHRP then
               local targetPos = targetHRP.Position
               local direction = (targetPos - myHRP.Position).Unit
               local throwPos = targetPos - direction * 8

               -- Teleport to throw position for instant attack
               myHRP.CFrame = CFrame.new(throwPos, Vector3.new(targetPos.X, throwPos.Y, targetPos.Z))
           end
     task.wait(0.3)

     leftClick()
     task.wait(1.5)

     Stand.Attacking = wasAttacking
     Stand.Following = wasFollowing
     Stand.Summoned = wasSummoned
     Stand.ManualControl = wasManualControl
     API.currentFollowTarget = originalTarget
     Stand.TrashAttacking = false

     if wasAttacking then
         Stand.Attacking = true
     end
end

API.Create("trashcan", function(args)
    if Stand.TrashAttacking then
        API.sendChat("Already performing trash attack!")
        return
    end
    
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    
    if not target then
        API.sendChat("Target not found.")
        return
    end
    

    trashAttack(target)
    
end)

local function mimicFireTool(tool, toolName)
     if not tool then return false end
     local previousAttack, previousAttacking = Stand.Attack, Stand.Attacking
     local previousManualControl = Stand.ManualControl
     
     Stand.MimicPhase = "up"
     Stand.Attack = true
     Stand.Attacking = true
     Stand.ManualControl = true
     
     task.wait(1)
     
     Stand.MimicPhase = "firing"
     local success = tryFireTool(tool, toolName)
     
     task.wait(2)
     
     Stand.MimicPhase = nil
     Stand.Attack = previousAttack
     Stand.Attacking = previousAttacking
     Stand.ManualControl = previousManualControl
     
     return success
 end

local function mimicFireSlot(slotIndex)
    local slotMoves = MovesBySlot[slotIndex]
    if not slotMoves then return end
    for _, move in ipairs(slotMoves) do
        local tool = getToolByName(move[5])
        if tool and mimicFireTool(tool, move[5]) then
            break
        end
    end
end

local function setupMimicForCharacter(character)
    if not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 3)
    if not humanoid then
        return false
    end

    clearMimicCharacterConnections()
    resetMimicCooldowns()

    table.insert(MimicCharacterConnections, humanoid.AnimationPlayed:Connect(function(animationTrack)
        local animIdStr = getAnimationIdString(animationTrack)
        if not animIdStr then
            return
        end

        local matchingMoves = MovesByAnimationId[animIdStr]
        if not matchingMoves then
            return
        end

        for _, move in ipairs(matchingMoves) do
            markMoveCooldown(move[4], move[3])
        end
    end))

    for _, move in ipairs(MovesList) do
        local attributeName = "Holding" .. string.gsub(move[1], " ", "")
        local signal = character:GetAttributeChangedSignal(attributeName):Connect(function()
            if not MimicEnabled or not MimicTarget then
                return
            end
            if MimicTarget.Character ~= character then
                return
            end

            local isHolding = character:GetAttribute(attributeName)
            if isHolding and isMoveOnCooldown(move[4]) then
                mimicFireSlot(move[4])
            end
        end)
        table.insert(MimicCharacterConnections, signal)
    end

    return true
end

API.Create("mimic", function(args)
    if MimicEnabled then
        clearMimicState()
        API.sendChat("Mimic stopped.")
        return
    end

    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)

    if not target then
        API.sendChat("Target not found.")
        return
    end

    if not target.Character then
        API.sendChat("Target character not found.")
        return
    end

    MimicTarget = target
    MimicEnabled = true
    API.MimicEnabled = true  -- Expose to API for positioning logic
    API.currentFollowTarget = target  -- Set follow target to the person being mimicked

    Stand.Summoned = true
    API.Summon()

    if not setupMimicForCharacter(target.Character) then
        clearMimicState()
        API.sendChat("Failed to attach mimic to " .. target.Name .. ".")
        return
    end

    table.insert(MimicConnections, target.CharacterAdded:Connect(function(newCharacter)
        if not MimicEnabled or MimicTarget ~= target then
            return
        end

        task.spawn(function()
            if MimicEnabled and MimicTarget == target then
                setupMimicForCharacter(newCharacter)
            end
        end)
    end))

    table.insert(MimicConnections, target:GetPropertyChangedSignal("Parent"):Connect(function()
        if target.Parent == nil and MimicEnabled then
            clearMimicState()
            API.sendChat("Mimic stopped - target left the game.")
        end
    end))

    API.sendChat("Mimicking " .. target.Name .. "! Use mimic again to stop.")
end)

local GuardWhitelist = {}

-- Auto attack variables
local AutoAttackEnabled = false
local AutoAttackTarget = nil
local AutoAttackConn = nil
local AutoAttackRespawnConn = nil

-- Assist variables
local AssistEnabled = false
local AssistConnections = {}
local AssistOwnerConnections = {}
local AssistLastOwnerAttackTime = 0
local AssistCurrentTarget = nil
local AssistAttackConn = nil
local ASSIST_ATTACK_RANGE = 7
local ASSIST_THREAT_WINDOW = 2

local function clearAssistAttack()
     if AssistAttackConn then
         AssistAttackConn:Disconnect()
         AssistAttackConn = nil
     end
     AssistCurrentTarget = nil
     Stand.Attack = false
     Stand.Attacking = false
end

local function startAssistAttack(target)
     if AssistCurrentTarget == target and AssistAttackConn then
         return
     end
     
     clearAssistAttack()
     
     if not target or not target.Character then return end
     
     local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
     local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
     if not targetHRP or not humanoid then return end
     
     AssistCurrentTarget = target
     Stand.Attack = true
     Stand.Attacking = true
     
     API.currentFollowTarget = target
     if API.Commands and API.Commands["frame"] then
         pcall(function() API.Commands["frame"]({target.Name}) end)
     end
     
     AssistAttackConn = RunService.Heartbeat:Connect(function()
         if not Stand.Attack or not AssistCurrentTarget or not AssistCurrentTarget.Character then
             clearAssistAttack()
             return
         end
         
         local tHRP = AssistCurrentTarget.Character:FindFirstChild("HumanoidRootPart")
         if not tHRP then
             clearAssistAttack()
             return
         end
         
         if API.currentFollowTarget ~= AssistCurrentTarget then
             API.currentFollowTarget = AssistCurrentTarget
         end
         
         local availableSlots = getAvailableSlots()
         local usedTool = false
         
         if #availableSlots > 0 then
             for _, slotNumber in ipairs(availableSlots) do
                 if not Stand.Attack then break end
                 local tool = getToolByName(slotToToolName[slotNumber])
                 if tool then
                     Stand.Attacking = true
                     tryFireTool(tool, slotToToolName[slotNumber])
                     usedTool = true
                     task.wait(0.5)
                 end
             end
         end
         
         if not usedTool then
             for i = 1, 3 do
                 if not Stand.Attack then break end
                 doM1()
                 task.wait(0.1)
             end
         end
     end)
end

local function startAutoAttackLoop()
    if not AutoAttackTarget or not AutoAttackEnabled then return end
    
    AutoAttackConn = RunService.Heartbeat:Connect(function()
        if not AutoAttackEnabled or not AutoAttackTarget or not AutoAttackTarget.Character then
            return
        end
        
        local humanoid = AutoAttackTarget.Character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return -- Wait for respawn
        end
        
        local targetHRP = hrpOf(AutoAttackTarget.Character)
        if not targetHRP then
            return
        end
        
        if API.currentFollowTarget ~= AutoAttackTarget then
            API.currentFollowTarget = AutoAttackTarget
        end

        local availableSlots = getAvailableSlots()
        local usedTool = false

        if #availableSlots > 0 then
            for _, slotNumber in ipairs(availableSlots) do
                if not AutoAttackEnabled then break end
                local tool = getToolByName(slotToToolName[slotNumber])
                if tool then
                    Stand.Attacking = true
                    tryFireTool(tool, slotToToolName[slotNumber])
                    usedTool = true
                    task.wait(0.5)
                end
            end
        end

        if not usedTool then
            for i = 1, 3 do
                if not AutoAttackEnabled then break end
                doM1()
                task.wait(0.1)
            end
        end
    end)
    
    -- Handle respawn
    AutoAttackRespawnConn = AutoAttackTarget.CharacterAdded:Connect(function(newCharacter)
        if AutoAttackEnabled and AutoAttackTarget == target then
            task.wait(1) -- Give time for character to load
            startAutoAttackLoop()
        end
    end)
end

local function clearAssistState()
    AssistEnabled = false
    
    for _, conn in ipairs(AssistConnections) do
        if conn then conn:Disconnect() end
    end
    AssistConnections = {}
    
    for _, conn in ipairs(AssistOwnerConnections) do
        if conn then conn:Disconnect() end
    end
    AssistOwnerConnections = {}
    
    AssistLastOwnerAttackTime = 0
    
    if API.ownerPlayer then
        API.currentFollowTarget = API.ownerPlayer
        if API.Commands and API.Commands["frame"] then
            pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
        end
    end
end

local function setupAssistForOwner()
     if not API.ownerPlayer or not API.ownerPlayer.Character then return end

     local humanoid = API.ownerPlayer.Character:FindFirstChildOfClass("Humanoid")
     if not humanoid then return end

     local conn = humanoid.AnimationPlayed:Connect(function(animationTrack)
         if not AssistEnabled or not API.ownerPlayer.Character then return end

         local animIdStr = getAnimationIdString(animationTrack)
         if animIdStr then
             local matchingMoves = MovesByAnimationId[animIdStr]
             if matchingMoves and #matchingMoves > 0 then
                 AssistLastOwnerAttackTime = os.clock()
             end
         end
     end)

     table.insert(AssistOwnerConnections, conn)

     -- Monitor for M1 attacks (M1ing accessory appears in workspace.Live.[player])
     local m1CheckConn = RunService.Heartbeat:Connect(function()
         if not AssistEnabled or not API.ownerPlayer or not API.ownerPlayer.Character then
             if m1CheckConn then m1CheckConn:Disconnect() end
             return
         end

         local live = workspace:FindFirstChild("Live")
         if live then
             local playerFolder = live:FindFirstChild(API.ownerPlayer.Name)
             if playerFolder and playerFolder:FindFirstChild("M1ing") then
                 AssistLastOwnerAttackTime = os.clock()
             end
         end
     end)

     table.insert(AssistOwnerConnections, m1CheckConn)
end

local function distanceToPlayer(player)
    if not player or not player.Character or not API.ownerPlayer or not API.ownerPlayer.Character then
        return math.huge
    end
    local playerHRP = player.Character:FindFirstChild("HumanoidRootPart")
    local ownerHRP = API.ownerPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not playerHRP or not ownerHRP then
        return math.huge
    end
    return (playerHRP.Position - ownerHRP.Position).Magnitude
end

local function clearAutoAttackState()
    if AutoAttackConn then
        AutoAttackConn:Disconnect()
        AutoAttackConn = nil
    end
    if AutoAttackRespawnConn then
        AutoAttackRespawnConn:Disconnect()
        AutoAttackRespawnConn = nil
    end
    AutoAttackEnabled = false
    AutoAttackTarget = nil
    
    -- Return to following the owner
    if API then
        API.currentFollowTarget = API.ownerPlayer
        API.Stand.Following = true
        API.Stop()
        API.Summon()
    end
end

local function isWhitelisted(player)
    return GuardWhitelist[player.UserId] == true
end

API.Create("whitelist", function(args)
    local subCmd = args[1] and args[1]:lower()
    local playerName = table.concat(args, " ", 2)

    if subCmd == "add" then
        local p = API.getPlayer(playerName)
        if not p then
            API.sendChat("Player not found.")
            return
        end
        GuardWhitelist[p.UserId] = true
        API.sendChat(("Whitelisted %s"):format(p.Name))
    elseif subCmd == "remove" then
        local p = API.getPlayer(playerName)
        if not p then
            API.sendChat("Player not found.")
            return
        end
        GuardWhitelist[p.UserId] = nil
        API.sendChat(("Removed %s from whitelist"):format(p.Name))
    elseif subCmd == "list" then
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if GuardWhitelist[p.UserId] then
                table.insert(names, p.Name)
            end
        end
        if #names == 0 then
            API.sendChat("Whitelist is empty.")
        else
            API.sendChat("Whitelisted: " .. table.concat(names, ", "))
        end
    else
        API.sendChat("Usage: whitelist <add/remove/list> <player>")
    end
end)


local GUARD_RANGE = 20       
local DISENGAGE_RANGE = 28   
local ATTEMPT_EVERY = 0.3    
local RETURN_DELAY = 1    

local guardConn
local guardThreat 
local lastSwing = 0

local function clearGuardState()
    if guardConn then guardConn:Disconnect() guardConn = nil end
    guardThreat = nil
    Stand.Guarding = false
    Stand.Attacking = false
    if API.ownerPlayer then
        API.currentFollowTarget = API.ownerPlayer
        if API.Commands and API.Commands["frame"] then
            pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
        end
    end
end

local function validHRP(p)
    return p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

local function isAlive(p)
    local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function distanceBetween(hrpA, hrpB)
    if not hrpA or not hrpB then return math.huge end
    local ok, dist = pcall(function()
        return (hrpA.Position - hrpB.Position).Magnitude
    end)
    return ok and dist or math.huge
end

local function performGuardSwing()
    local prevAttack = Stand.Attack
    Stand.Attack = true

    local availableSlots = getAvailableSlots()
    local swung = false

    if #availableSlots > 0 then
        for _, slotNumber in ipairs(availableSlots) do
            local toolName = slotToToolName[slotNumber]
            local tool = getToolByName(toolName)
            if tool then
                swung = tryFireTool(tool, toolName) or swung
                task.wait(0.05)
                if swung then break end
            end
        end
    end

    if not swung then
        for i = 1, 2 do
            if doM1() then break end
            task.wait(0.05)
        end
    end

    Stand.Attack = prevAttack
end

local function reframeOwnerDelayed()
    task.delay(RETURN_DELAY, function()
        if Stand.Guarding and not guardThreat then
            API.currentFollowTarget = API.ownerPlayer
            if API.Commands and API.Commands["frame"] then
                pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
            end
        end
    end)
end

API.Create("guard", function()
    if Stand.Guarding then
        API.sendChat("Already guarding.")
        return
    end

    if not API.ownerPlayer or not validHRP(API.ownerPlayer) then
        API.sendChat("Owner not available to guard.")
        return
    end

    Stand.Guarding = true
    Stand.Summoned = true
    Stand.Following = true
    guardThreat = nil

    API.currentFollowTarget = API.ownerPlayer
    if API.Commands and API.Commands["frame"] then
        pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
    end

    guardConn = RunService.Heartbeat:Connect(function()
        if not Stand.Guarding then return end

        local ownerHRP = validHRP(API.ownerPlayer) and API.ownerPlayer.Character.HumanoidRootPart
        if not ownerHRP then return end

        if guardThreat then
            if (not isAlive(guardThreat)) or (not validHRP(guardThreat)) then
                guardThreat = nil
                Stand.Attacking = false
                reframeOwnerDelayed()
            else
                local dist = distanceBetween(ownerHRP, guardThreat.Character.HumanoidRootPart)
                if dist > DISENGAGE_RANGE then
                    guardThreat = nil
                    Stand.Attacking = false
                    reframeOwnerDelayed()
                end
            end
        end

        if not guardThreat then
            local closest, closestDist = nil, GUARD_RANGE
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p ~= API.ownerPlayer and not isWhitelisted(p) and isAlive(p) and validHRP(p) then
                    local d = distanceBetween(ownerHRP, p.Character.HumanoidRootPart)
                    if d < closestDist then
                        closest, closestDist = p, d
                    end
                end
            end
            if closest then
                guardThreat = closest
                Stand.Attacking = true
                API.currentFollowTarget = closest
                if API.Commands and API.Commands["frame"] then
                    pcall(function() API.Commands["frame"]({closest.Name}) end)
                end
            end
        end

        if guardThreat and Stand.Attacking then
            local now = os.clock()
            if now - lastSwing >= ATTEMPT_EVERY then
                lastSwing = now
                performGuardSwing()
            end
        end
    end)

    API.sendChat(("Guarding owner."))
end)

API.Create("unguard", function()
    clearGuardState()
    API.sendChat("Stopped guarding.")
end)

local SentryEnabled = false
local SentryConnections = {}
local SentryPlayerConnections = {}
local SentryLastAttackTime = {}
local SentryCurrentTarget = nil
local SentryAttackConn = nil
local SENTRY_ATTACK_RANGE = 7
local SENTRY_THREAT_WINDOW = 2

local function clearSentryAttack()
    if SentryAttackConn then
        SentryAttackConn:Disconnect()
        SentryAttackConn = nil
    end
    SentryCurrentTarget = nil
    Stand.Attack = false
    Stand.Attacking = false
end

local function clearSentryState()
    SentryEnabled = false
    clearSentryAttack()
    
    for _, conn in ipairs(SentryConnections) do
        if conn then conn:Disconnect() end
    end
    SentryConnections = {}
    
    for _, conns in pairs(SentryPlayerConnections) do
        for _, conn in ipairs(conns) do
            if conn then conn:Disconnect() end
        end
    end
    SentryPlayerConnections = {}
    SentryLastAttackTime = {}
    
    if API.ownerPlayer then
        API.currentFollowTarget = API.ownerPlayer
        if API.Commands and API.Commands["frame"] then
            pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
        end
    end
end

local function setupSentryForPlayer(player)
     if not player or not player.Character then return end

     local userId = player.UserId
     if not SentryPlayerConnections[userId] then
         SentryPlayerConnections[userId] = {}
     end

     if not SentryLastAttackTime[userId] then
         SentryLastAttackTime[userId] = 0
     end

     local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
     if not humanoid then return end

     local conn = humanoid.AnimationPlayed:Connect(function(animationTrack)
         if not SentryEnabled or not player.Character then return end

         local animIdStr = getAnimationIdString(animationTrack)
         if animIdStr then
             local matchingMoves = MovesByAnimationId[animIdStr]
             if matchingMoves and #matchingMoves > 0 then
                 SentryLastAttackTime[userId] = os.clock()
             end
         end
     end)

     table.insert(SentryPlayerConnections[userId], conn)

     -- Monitor for M1 attacks (M1ing accessory appears in workspace.Live.[player])
     local m1CheckConn = RunService.Heartbeat:Connect(function()
         if not SentryEnabled or not player or not player.Character then
             if m1CheckConn then m1CheckConn:Disconnect() end
             return
         end

         local live = workspace:FindFirstChild("Live")
         if live then
             local playerFolder = live:FindFirstChild(player.Name)
             if playerFolder and playerFolder:FindFirstChild("M1ing") then
                 SentryLastAttackTime[userId] = os.clock()
             end
         end
     end)

     table.insert(SentryPlayerConnections[userId], m1CheckConn)
end

local function distanceTo(player)
    if not player or not player.Character or not API.ownerPlayer or not API.ownerPlayer.Character then
        return math.huge
    end
    local playerHRP = player.Character:FindFirstChild("HumanoidRootPart")
    local ownerHRP = API.ownerPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not playerHRP or not ownerHRP then
        return math.huge
    end
    return (playerHRP.Position - ownerHRP.Position).Magnitude
end

local function removeSentryPlayer(userId)
    SentryLastAttackTime[userId] = nil
    local userConnections = SentryPlayerConnections[userId]
    if userConnections then
        for _, conn in ipairs(userConnections) do
            if conn then conn:Disconnect() end
        end
    end
    SentryPlayerConnections[userId] = nil
end

local function startSentryAttack(target)
    if SentryCurrentTarget == target and SentryAttackConn then
        return
    end
    
    clearSentryAttack()
    
    if not target or not target.Character then return end
    
    local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
    local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
    if not targetHRP or not humanoid then return end
    
    SentryCurrentTarget = target
    Stand.Attack = true
    Stand.Attacking = true
    
    API.currentFollowTarget = target
    if API.Commands and API.Commands["frame"] then
        pcall(function() API.Commands["frame"]({target.Name}) end)
    end
    
    SentryAttackConn = RunService.Heartbeat:Connect(function()
        if not Stand.Attack or not SentryCurrentTarget or not SentryCurrentTarget.Character then
            clearSentryAttack()
            return
        end
        
        local tHRP = SentryCurrentTarget.Character:FindFirstChild("HumanoidRootPart")
        if not tHRP then
            clearSentryAttack()
            return
        end
        
        if API.currentFollowTarget ~= SentryCurrentTarget then
            API.currentFollowTarget = SentryCurrentTarget
        end
        
        local availableSlots = getAvailableSlots()
        local usedTool = false
        
        if #availableSlots > 0 then
            for _, slotNumber in ipairs(availableSlots) do
                if not Stand.Attack then break end
                local tool = getToolByName(slotToToolName[slotNumber])
                if tool then
                    Stand.Attacking = true
                    tryFireTool(tool, slotToToolName[slotNumber])
                    usedTool = true
                    task.wait(0.5)
                end
            end
        end
        
        if not usedTool then
            for i = 1, 3 do
                if not Stand.Attack then break end
                doM1()
                task.wait(0.1)
            end
        end
    end)
end

API.Create("sentry", function()
    if SentryEnabled then
        clearSentryState()
        API.sendChat("Sentry stopped.")
        return
    end
    
    if not API.ownerPlayer or not API.ownerPlayer.Character then
        API.sendChat("Owner not available for sentry.")
        return
    end
    
    SentryEnabled = true
    Stand.Attacking = false
    Stand.Summoned = true
    API.currentFollowTarget = API.ownerPlayer
    if API.Commands and API.Commands["frame"] then
        pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player ~= API.ownerPlayer and not isWhitelisted(player) and player.Character then
            setupSentryForPlayer(player)
        end
    end
    
    table.insert(SentryConnections, RunService.Heartbeat:Connect(function()
        if not SentryEnabled then return end
        
        if not API.ownerPlayer or not API.ownerPlayer.Character then
            clearSentryState()
            return
        end
        
        local ownerHRP = API.ownerPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not ownerHRP then return end
        
        local now = os.clock()
        
        if SentryCurrentTarget then
            if not SentryCurrentTarget.Parent then
                clearSentryAttack()
            else
                local humanoid = SentryCurrentTarget.Character and SentryCurrentTarget.Character:FindFirstChildOfClass("Humanoid")
                if not humanoid or humanoid.Health <= 0 then
                    clearSentryAttack()
                end
            end
        end
        
        local nextThreat
        local latestThreatTime = -math.huge
        local currentTargetThreatTime = -math.huge
        
        for userId, lastAttackTime in pairs(SentryLastAttackTime) do
            local player = Players:GetPlayerByUserId(userId)
            if player and player ~= LocalPlayer and player ~= API.ownerPlayer and not isWhitelisted(player) and player.Character then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                local playerHRP = player.Character:FindFirstChild("HumanoidRootPart")
                
                if humanoid and humanoid.Health > 0 and playerHRP then
                    if (now - lastAttackTime) < SENTRY_THREAT_WINDOW * 2 and distanceTo(player) <= SENTRY_ATTACK_RANGE then
                        if player == SentryCurrentTarget then
                            currentTargetThreatTime = lastAttackTime
                        elseif lastAttackTime > latestThreatTime then
                            latestThreatTime = lastAttackTime
                            nextThreat = player
                        end
                    end
                end
            else
                removeSentryPlayer(userId)
            end
        end
        
        if nextThreat and latestThreatTime > currentTargetThreatTime then
            startSentryAttack(nextThreat)
        elseif not SentryCurrentTarget and nextThreat then
            startSentryAttack(nextThreat)
        end
        
        if not SentryCurrentTarget and not Stand.Attack then
            API.currentFollowTarget = API.ownerPlayer
            if API.Commands and API.Commands["frame"] then
                pcall(function() API.Commands["frame"]({API.ownerPlayer.Name}) end)
            end
        end
    end))
    
    table.insert(SentryConnections, Players.PlayerAdded:Connect(function(player)
        if SentryEnabled and player ~= LocalPlayer and player ~= API.ownerPlayer and not isWhitelisted(player) then
            task.wait(0.5)
            if player.Character then
                setupSentryForPlayer(player)
            end
        end
    end))
    
    API.sendChat("Sentry activated! Will protect owner from nearby attackers.")
end)

API.Create("unsentry", function()
    clearSentryState()
    API.sendChat("Sentry deactivated.")
end)

local AutoRoastEnabled = false

local roastMessages = {
    "Uninstall the game, %s. You're a lost cause.",
    "%s, your existence is a critical miss.",
    "I've seen more skill from a screen door, %s.",
    "%s, you're the reason your team has a report button.",
    "Go apologize to your parents for those genes, %s.",
    "Is your strategy to bore me to death, %s? It might work.",
    "%s, you fight like a dairy farmer.",
    "I'd call you a noob, %s, but that would be an insult to noobs everywhere.",
    "%s, your gameplay is a cry for help.",
    "Do everyone a favor and unplug your router, %s.",
    "%s, you're so bad you made me win by accident.",
    "I'd rather lick a subway pole than play with %s again.",
    "%s, your birth certificate is an apology letter from the condom factory.",
    "Even a bot would demand a better player, %s.",
    "%s, your IQ is lower than your ping.",
    "The only thing you're carrying, %s, is a disease.",
    "%s, you have the reaction time of a sedated sloth.",
    "Did you buy your account, %s? Or was it a gift from a blind man?",
    "%s, you're about as useful as a chocolate teapot.",
    "Go back to the tutorial and try not to fail it this time, %s."
}

local function getRandomRoast(targetName)
    local msg = roastMessages[math.random(1, #roastMessages)]
    return msg:format(targetName)
end

API.Create("autoroast", function()
    AutoRoastEnabled = not AutoRoastEnabled
    API.sendChat("AutoRoast " .. (AutoRoastEnabled and "enabled" or "disabled"))
end)

local function hookRoastOnDeath(target)
    if not target or not target.Character then return end
    local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    humanoid.Died:Connect(function()
        if AutoRoastEnabled and Stand.Attacking and API.currentFollowTarget == target then
            API.sendChat(getRandomRoast(target.Name))
        end
    end)
end

local oldAttack = API.Commands["attack"]
API.Commands["attack"] = function(args)
    oldAttack(args)
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    if target then
        hookRoastOnDeath(target)
    end
end


API.Notify({
    Title = "GAME CONFIG",
    Description = (game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Game") .. " Loaded",
    Duration = 20
})
