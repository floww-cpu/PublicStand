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

local function clickGuiButton(guiPath)
    local success, err = pcall(function()
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
    return success and not err
end

local function equipCart()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not PlayerGui then
        return false
    end
    
    -- Click BackPack button
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
    
    -- Click ShoppingCart button
    local button2Success = clickGuiButton(function()
        return PlayerGui:WaitForChild("NoResetGUIHandler", 2)
            :WaitForChild("MainToolMenuFilter", 2)
            :WaitForChild("Catalog", 2)
            :WaitForChild("Container", 2)
            :WaitForChild("ScrollingFrame", 2)
            :WaitForChild("ShoppingCart", 2)
    end)
    
    return button2Success
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
    
    -- Equip the cart
    if not equipCart() then
        API.sendChat("Failed to equip cart!")
        -- Restore state
        BringingTarget = false
        Stand.Following = wasFollowing
        Stand.ManualControl = wasManualControl
        return
    end
    
    task.wait(1)
    
    -- Teleport behind target
    local myChar = LocalPlayer.Character
    local myCharHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    
    if myCharHRP and targetHRP then
        local targetPos = targetHRP.Position
        local targetLookVector = targetHRP.CFrame.LookVector
        local behindPos = targetPos - targetLookVector * 3
        
        myCharHRP.CFrame = CFrame.new(behindPos, targetPos)
        task.wait(0.5)
        
        -- Equip cart again to make them sit
        equipCart()
        task.wait(1.5)
        
        -- Check if target is now seated
        local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid and targetHumanoid.Sit then
            API.sendChat("Target captured! Bringing to owner...")
            
            -- Teleport back to owner
            if myCharHRP and ownerHRP then
                local ownerPos = ownerHRP.Position
                local ownerLookVector = ownerHRP.CFrame.LookVector
                local returnPos = ownerPos + ownerLookVector * 5
                
                myCharHRP.CFrame = CFrame.new(returnPos, ownerPos)
                task.wait(0.5)
                
                API.sendChat("Target delivered!")
            end
        else
            API.sendChat("Failed to capture target in cart.")
        end
    end
    
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

API.Notify({
    Title = "GAME CONFIG",
    Description = (game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Game") .. " Loaded",
    Duration = 20
})
