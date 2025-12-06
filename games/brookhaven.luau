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

local BringingTarget = false

local function unequipCart()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:UnequipTools() end)
    end
end

local function clearExistingCart()
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        local cart = backpack:FindFirstChild("ShoppingCart")
        if cart then
            cart:Destroy()
        end
    end
    
    local character = LocalPlayer.Character
    if character then
        local cart = character:FindFirstChild("ShoppingCart")
        if cart then
            cart:Destroy()
        end
    end
end

local function clickGuiButton(guiPath)
    local success, result = pcall(function()
        local element = guiPath()
        if element then
            local pos = element.AbsolutePosition
            local size = element.AbsoluteSize
            local x = pos.X + size.X / 2
            local y = pos.Y + size.Y * 0.75
            
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
            task.wait(0.1)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
            return true
        end
        return false
    end)

    return success and result == true
end

local function hasShoppingCart()
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack and backpack:FindFirstChild("ShoppingCart") then
        return true
    end
    
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("ShoppingCart") then
        return true
    end
    
    return false
end

local function equipCart()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not PlayerGui then
        return false
    end

    -- Check if cart is already equipped
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("ShoppingCart") then
        return true
    end
    
    -- Clear any existing cart first
    clearExistingCart()
    task.wait(0.1)
    
    -- State 1: Check if cart is already in backpack
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack and backpack:FindFirstChild("ShoppingCart") then
        local cart = backpack:FindFirstChild("ShoppingCart")
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum:EquipTool(cart) end)
            task.wait(0.2)
            return character and character:FindFirstChild("ShoppingCart") ~= nil
        end
    end
    
    -- State 2: Check if menu is already open and has cart available
    local cartInMenu = false
    pcall(function()
        local catalog = PlayerGui:FindFirstChild("NoResetGUIHandler")
            :WaitForChild("MainToolMenuFilter", 1)
            :WaitForChild("Catalog", 1)
            :WaitForChild("Container", 1)
            :WaitForChild("ScrollingFrame", 1)
            :WaitForChild("ShoppingCart", 1)
        cartInMenu = catalog ~= nil
    end)
    
    -- State 3: If menu is closed, open it first
    if not cartInMenu then
        local button1Success = clickGuiButton(function()
            return PlayerGui:WaitForChild("MainGUIHandler", 2)
                :WaitForChild("MainButtons", 2)
                :WaitForChild("Buttons", 2)
                :WaitForChild("BackPack", 2)
        end)
        
        if not button1Success then
            return false
        end
        
        task.wait(0.5)
    end
    
    -- State 4: Click ShoppingCart button in catalog (whether menu was open or just opened)
    local button2Success = clickGuiButton(function()
        return PlayerGui:WaitForChild("NoResetGUIHandler", 2)
            :WaitForChild("MainToolMenuFilter", 2)
            :WaitForChild("Catalog", 2)
            :WaitForChild("Container", 2)
            :WaitForChild("ScrollingFrame", 2)
            :WaitForChild("ShoppingCart", 2)
    end)
    
    if not button2Success then
        return false
    end

    task.wait(0.3)
    
    -- Wait for cart to appear in backpack
    for _ = 1, 20 do
        if hasShoppingCart() then
            break
        end
        task.wait(0.1)
    end
    
    -- Now equip the cart from backpack
    local cart = nil
    if backpack then
        cart = backpack:FindFirstChild("ShoppingCart")
    end
    
    if not cart then
        return false
    end
    
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:EquipTool(cart) end)
        task.wait(0.2)
    end
    
    -- Verify cart is now equipped
    return character and character:FindFirstChild("ShoppingCart") ~= nil
end

local function fastTeleport(targetCFrame)
    local myChar = LocalPlayer.Character
    local myCharHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    
    if not myCharHRP then
        return false
    end
    
    -- Create a manual control connection to maintain position
    local manualConn
    local startTime = tick()
    local startCFrame = myCharHRP.CFrame
    local duration = 0.8 -- Duration for smooth transition
    
    manualConn = RunService.Heartbeat:Connect(function(deltaTime)
        if not myChar or not myChar:IsDescendantOf(workspace) then
            if manualConn then manualConn:Disconnect() end
            return
        end
        
        local currentHRP = myChar:FindFirstChild("HumanoidRootPart")
        if currentHRP then
            local elapsed = tick() - startTime
            
            if elapsed >= duration then
                -- Final position
                currentHRP.CFrame = targetCFrame
                if manualConn then manualConn:Disconnect() end
            else
                -- Smooth interpolation
                local alpha = elapsed / duration
                -- Use ease-in-out for smooth acceleration/deceleration
                alpha = alpha * alpha * (3.0 - 2.0 * alpha)
                currentHRP.CFrame = startCFrame:Lerp(targetCFrame, alpha)
            end
        end
    end)
    
    -- Set initial position
    myCharHRP.CFrame = targetCFrame
    
    return true
end

local function bringTarget(target)
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    
    local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then
        API.sendChat("Target has no HumanoidRootPart!")
        return
    end
    
    local ownerHRP = hrpOf(API.ownerPlayer.Character)
    if not ownerHRP then
        API.sendChat("Owner has no HumanoidRootPart!")
        return
    end
    
    -- Save state
    local wasAttacking = Stand.Attacking
    local wasFollowing = Stand.Following
    local wasSummoned = Stand.Summoned
    local wasManualControl = Stand.ManualControl
    local originalTarget = API.currentFollowTarget
    
    BringingTarget = true
    Stand.Following = false
    Stand.ManualControl = true
    
    -- Fast teleport behind target first (without cart)
    local targetPos = targetHRP.Position
    local targetLookVector = targetHRP.CFrame.LookVector
    local behindPos = targetPos - targetLookVector * 3
    
    if not fastTeleport(CFrame.new(behindPos, targetPos)) then
        API.sendChat("Failed to teleport!")
        -- Restore state
        BringingTarget = false
        Stand.Following = wasFollowing
        Stand.ManualControl = wasManualControl
        return
    end
    
    task.wait(1.0) -- Wait for smooth teleport to complete
    
    -- Now equip the cart at the target location
    if not equipCart() then
        API.sendChat("Failed to equip cart!")
        -- Restore state
        BringingTarget = false
        Stand.Following = wasFollowing
        Stand.ManualControl = wasManualControl
        return
    end
    
    task.wait(1.2)
    
    -- Check if target is now seated
    local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
    if targetHumanoid and targetHumanoid.Sit then
        API.sendChat("Target captured! Bringing to owner...")
        
        -- Fast teleport back to owner
        local ownerPos = ownerHRP.Position
        local ownerLookVector = ownerHRP.CFrame.LookVector
        local returnPos = ownerPos + ownerLookVector * 5
        
        if not fastTeleport(CFrame.new(returnPos, ownerPos)) then
            API.sendChat("Failed to teleport back!")
        else
            task.wait(1.0)
            API.sendChat("Target delivered!")
        end
    else
        API.sendChat("Failed to capture target in cart.")
    end
    
    -- Unequip the cart
    unequipCart()
    task.wait(0.3)
    
    -- Restore state
    BringingTarget = false
    Stand.Attacking = wasAttacking
    Stand.Following = wasFollowing
    Stand.Summoned = wasSummoned
    Stand.ManualControl = wasManualControl
    API.currentFollowTarget = originalTarget
end

local function gotoTarget(target)
    if not target or not target.Character then
        API.sendChat("Target not found!")
        return
    end
    
    local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then
        API.sendChat("Target has no HumanoidRootPart!")
        return
    end
    
    -- Save state
    local wasAttacking = Stand.Attacking
    local wasFollowing = Stand.Following
    local wasSummoned = Stand.Summoned
    local wasManualControl = Stand.ManualControl
    local originalTarget = API.currentFollowTarget
    
    BringingTarget = true
    Stand.Following = false
    Stand.ManualControl = true
    
    -- Equip the cart first (this makes owner sit)
    if not equipCart() then
        API.sendChat("Failed to equip cart!")
        -- Restore state
        BringingTarget = false
        Stand.Following = wasFollowing
        Stand.ManualControl = wasManualControl
        return
    end
    
    task.wait(1.0)
    
    -- Fast teleport to target
    local targetPos = targetHRP.Position
    local targetLookVector = targetHRP.CFrame.LookVector
    local nearPos = targetPos + targetLookVector * 5
    
    if not fastTeleport(CFrame.new(nearPos, targetPos)) then
        API.sendChat("Failed to teleport!")
    else
        task.wait(1.0)
        API.sendChat("Teleported to target!")
    end
    
    -- Unequip the cart
    unequipCart()
    task.wait(0.3)
    
    -- Restore state
    BringingTarget = false
    Stand.Attacking = wasAttacking
    Stand.Following = wasFollowing
    Stand.Summoned = wasSummoned
    Stand.ManualControl = wasManualControl
    API.currentFollowTarget = originalTarget
end

API.Create("bring", function(args)
    if BringingTarget then
        API.sendChat("Already bringing someone!")
        return
    end
    
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    
    if not target then
        API.sendChat("Target not found.")
        return
    end
    
    if target == API.ownerPlayer then
        API.sendChat("Cannot bring yourself!")
        return
    end
    
    task.spawn(function()
        bringTarget(target)
    end)
end)

API.Create("goto", function(args)
    if BringingTarget then
        API.sendChat("Already teleporting!")
        return
    end
    
    local playerName = table.concat(args, " ")
    local target = (playerName == "" and API.ownerPlayer) or API.getPlayer(playerName)
    
    if not target then
        API.sendChat("Target not found.")
        return
    end
    
    if target == API.ownerPlayer then
        API.sendChat("Cannot goto yourself!")
        return
    end
    
    task.spawn(function()
        gotoTarget(target)
    end)
end)

API.Notify({
    Title = "GAME CONFIG",
    Description = (game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Game") .. " Loaded",
    Duration = 20
})
