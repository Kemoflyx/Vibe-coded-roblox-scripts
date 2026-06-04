local scriptCode = [[
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local UserSettings = UserSettings():GetService("UserGameSettings")
    local min = math.min

    local LocalPlayer = Players.LocalPlayer

    -- CONFIGURATION
    local MAX_DISTANCE = 100
    local CULL_UPDATE_RATE = 1

    -- We keep the weak table. Lua's Garbage Collector will automatically 
    -- remove destroyed particles from this list.
    local OriginalRates = setmetatable({}, { __mode = "k" })
    local CulledStates = setmetatable({}, { __mode = "k" }) -- Tracks if a particle is currently hidden

    local scaleMap = {0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.85, 0.92, 0.96, 1.0}

    local lastScale = -1
    local currentScale = 1.0

    local function applyRate(emitter, originalRate)
        -- If it's culled by distance, kill it immediately
        if CulledStates[emitter] then
            if emitter.Rate ~= 0 then emitter.Rate = 0 end
            return
        end

        -- Otherwise, apply the quality scale logic
        local r = min(originalRate * 10, originalRate / currentScale)
        if emitter.Rate ~= r then emitter.Rate = r end
    end

    local function updateParticles()
        local qLevel = UserSettings.SavedQualityLevel.Value
        currentScale = scaleMap[qLevel ~= 0 and qLevel or 10] or 1.0
        
        if currentScale == lastScale then return end
        lastScale = currentScale
        
        for emitter, originalRate in pairs(OriginalRates) do
            if emitter.Parent then
                applyRate(emitter, originalRate)
            end
        end
    end

    local function register(obj)
        if obj:IsA("ParticleEmitter") and not OriginalRates[obj] then
            local rate = obj.Rate
            OriginalRates[obj] = rate
            CulledStates[obj] = false -- Assume visible on spawn until loop checks
            applyRate(obj, rate)
        end
    end

    -- Performance loop for distance checking
    task.spawn(function()
        while task.wait(CULL_UPDATE_RATE) do
            local camera = Workspace.CurrentCamera
            local character = LocalPlayer.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")

            local camPos = camera and camera.CFrame.Position
            local charPos = rootPart and rootPart.Position

            -- If both don't exist yet, skip this tick
            if not camPos and not charPos then continue end

            for emitter, originalRate in pairs(OriginalRates) do
                local parent = emitter.Parent
                if not parent then continue end

                -- Emitters only render in BaseParts or Attachments. Grab the right position.
                local emitterPos
                if parent:IsA("BasePart") then
                    emitterPos = parent.Position
                elseif parent:IsA("Attachment") then
                    emitterPos = parent.WorldPosition
                else
                    continue
                end

                -- Get distances (fallback to math.huge if char/cam are temporarily missing)
                local distCam = camPos and (emitterPos - camPos).Magnitude or math.huge
                local distChar = charPos and (emitterPos - charPos).Magnitude or math.huge

                -- Condition: Beyond MAX_DISTANCE from BOTH Camera AND Character
                local isTooFar = (distCam > MAX_DISTANCE) and (distChar > MAX_DISTANCE)

                -- Only trigger property updates if the state actually changed
                if isTooFar ~= CulledStates[emitter] then
                    CulledStates[emitter] = isTooFar
                    applyRate(emitter, originalRate)
                end
            end
        end
    end)

    -- Still needed to catch newly spawned particles
    Workspace.DescendantAdded:Connect(register)

    -- ipairs is faster for arrays than pairs
    for _, v in ipairs(Workspace:GetDescendants()) do 
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
