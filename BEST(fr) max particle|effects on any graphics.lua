local scriptCode = [[
    local UserSettings = UserSettings():GetService("UserGameSettings")
    local min = math.min

    -- We keep the weak table. Lua's Garbage Collector will automatically 
    -- remove destroyed particles from this list.
    local OriginalRates = setmetatable({}, { __mode = "k" })

    local scaleMap = {0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.85, 0.92, 0.96, 1.0}

    local lastScale = -1
    local currentScale = 1.0

    local function applyRate(emitter, originalRate)
        local r = min(originalRate * 10, originalRate / currentScale)
        if emitter.Rate ~= r then emitter.Rate = r end
    end

    local function updateParticles()
        local qLevel = UserSettings.SavedQualityLevel.Value
        currentScale = scaleMap[qLevel ~= 0 and qLevel or 10] or 1.0
        
        if currentScale == lastScale then return end
        lastScale = currentScale
        
        for emitter, originalRate in pairs(OriginalRates) do
            -- Safety check to ensure the particle still exists in the world
            if emitter.Parent then
                applyRate(emitter, originalRate)
            end
        end
    end

    local function register(obj)
        if obj:IsA("ParticleEmitter") and not OriginalRates[obj] then
            local rate = obj.Rate
            OriginalRates[obj] = rate
            applyRate(obj, rate)
        end
    end

    -- Still needed to catch newly spawned particles, but much lighter without DescendantRemoving
    workspace.DescendantAdded:Connect(register)

    -- ipairs is faster for arrays than pairs
    for _, v in ipairs(workspace:GetDescendants()) do 
        register(v) 
    end

    UserSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(updateParticles)
    updateParticles()
]]

-- 1. Queue it for future teleports/rejoins
local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport) or queueonteleport
if qot then
    qot(scriptCode)
end

-- 2. Run it immediately for the current session
local executorLoad = loadstring or load
if executorLoad then
    executorLoad(scriptCode)()
end
