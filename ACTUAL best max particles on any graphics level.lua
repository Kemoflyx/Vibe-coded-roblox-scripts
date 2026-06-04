local scriptCode = [[
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local UserSettings = UserSettings():GetService("UserGameSettings")

    local LocalPlayer = Players.LocalPlayer

    -- CONFIGURATION
    local MAX_DISTANCE = 100
    local CULL_UPDATE_RATE = 0.5 -- Faster updates, but safer now because of time-slicing
    local MAX_CHECKS_PER_FRAME = 200 -- Prevents lag spikes by spreading the math out

    local scaleMap = {0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.85, 0.92, 0.96, 1.0}
    local currentScale = 1.0

    local CulledStates = setmetatable({}, { __mode = "k" })

    local function applyRate(emitter)
        local originalRate = emitter:GetAttribute("TrueOriginalRate")
        if not originalRate then return end

        if CulledStates[emitter] then
            if emitter.Rate ~= 0 then 
                emitter:SetAttribute("IgnoreNextChange", true)
                emitter.Rate = 0 
            end
            return
        end

        local r = math.min(originalRate * 10, originalRate / currentScale)
        
        if math.abs(emitter.Rate - r) > 0.01 then
            emitter:SetAttribute("IgnoreNextChange", true)
            emitter.Rate = r
        end
    end

    local function updateParticles()
        local qLevel = UserSettings.SavedQualityLevel.Value
        currentScale = (qLevel > 0 and qLevel <= 10 and scaleMap[qLevel]) or 1.0
        
        for emitter in pairs(CulledStates) do
            applyRate(emitter)
        end
    end

    local function register(obj)
        -- FAST FAIL: Direct ClassName check is slightly faster than :IsA()
        if obj.ClassName ~= "ParticleEmitter" then return end

        if not obj:GetAttribute("TrueOriginalRate") then
            obj:SetAttribute("TrueOriginalRate", obj.Rate)
        end
        
        CulledStates[obj] = false

        obj:GetPropertyChangedSignal("Rate"):Connect(function()
            if obj:GetAttribute("IgnoreNextChange") then
                obj:SetAttribute("IgnoreNextChange", false)
                return
            end
            obj:SetAttribute("TrueOriginalRate", obj.Rate)
            applyRate(obj)
        end)

        -- Explicitly clear memory the exact moment it's destroyed
        obj.Destroying:Connect(function()
            CulledStates[obj] = nil
        end)

        applyRate(obj)
    end

    -- Highly Optimized Culling Loop
    task.spawn(function()
        while task.wait(CULL_UPDATE_RATE) do
            local camera = Workspace.CurrentCamera
            local character = LocalPlayer.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")

            local camPos = camera and camera.CFrame.Position
            local charPos = rootPart and rootPart.Position

            if not camPos and not charPos then continue end

            local checksThisFrame = 0

            for emitter, isCulled in pairs(CulledStates) do
                -- 1. Time Slicing: Yield to the next frame if we are doing too much math at once
                checksThisFrame = checksThisFrame + 1
                if checksThisFrame >= MAX_CHECKS_PER_FRAME then
                    task.wait() 
                    checksThisFrame = 0
                    
                    -- Re-fetch positions since a frame has passed
                    camPos = camera and camera.CFrame.Position
                    charPos = rootPart and rootPart.Position
                    if not camPos and not charPos then break end
                end

                local parent = emitter.Parent
                if not parent then
                    CulledStates[emitter] = nil
                    continue
                end

                local emitterPos
                if parent:IsA("BasePart") then
                    emitterPos = parent.Position
                elseif parent:IsA("Attachment") then
                    emitterPos = parent.WorldPosition
                else
                    continue
                end
                
                local distCam = camPos and (emitterPos - camPos).Magnitude or math.huge
                local distChar = charPos and (emitterPos - charPos).Magnitude or math.huge

                local isTooFar = (distCam > MAX_DISTANCE) and (distChar > MAX_DISTANCE)

                if isTooFar ~= isCulled then
                    CulledStates[emitter] = isTooFar
                    applyRate(emitter)
                end
            end
        end
    end)

    Workspace.DescendantAdded:Connect(register)

    -- Yielded Initialization to prevent freezing when you execute the script
    task.spawn(function()
        local descendants = Workspace:GetDescendants()
        for i, v in ipairs(descendants) do 
            register(v)
            -- Yield for a frame every 500 instances so the game doesn't stutter on load
            if i % 500 == 0 then task.wait() end 
        end
    end)

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