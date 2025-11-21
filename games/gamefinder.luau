getgenv().SocietyStandAPI = getgenv().SocietyStandAPI or {}
local gameId = game.GameId

local scripts = {
    [1008451066] = "https://raw.githubusercontent.com/floww-cpu/PublicStand/refs/heads/main/games/dahood.luau", -- dahood
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
