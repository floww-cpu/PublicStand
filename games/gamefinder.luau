getgenv().SocietyStandAPI = getgenv().SocietyStandAPI or {}
local gameId = game.GameId

local scripts = {
    [10449761463] = "https://xehh0.github.io/games/thestrongestb.luau", -- the strongest battlegrounds
    [3808081382] = "https://xehh0.github.io/games/thestrongestb.luau", -- the strongest battlegrounds
    [2788229376] = "https://xehh0.github.io/games/dahood.luau", -- game with anticheat bypass
}


if scripts[gameId] then
    print("Game config found for game ID: " .. gameId)
    local url = scripts[gameId]
    
    task.spawn(function()
        local success, result = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        
        if success then
            print("extension loaded successfully!")
        else
            warn("Failed to load extension: " .. tostring(result))
        end
    end)
else
    warn("❌ No custom game config found for game ID: " .. gameId)
end

return
