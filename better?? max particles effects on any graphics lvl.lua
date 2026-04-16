-- ========================================
-- SETTINGS: Adjust these values anytime!
-- ========================================
_G.ParticleLevel = 10     -- Graphics quality (1-10 recommended, but higher values work too)
_G.MaxDistance   = 100    -- Distance in studs - particles beyond this won't render

-- ========================================
-- OPTIMIZED PARTICLE PATCHER
-- ========================================
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Lighting   = game:GetService("Lighting")

-- Persistent cache across script re-runs
shared.ParticleRegistry = shared.ParticleRegistry or setmetatable({}, { __mode = "k" })
local Registry = shared.ParticleRegistry

-- Clean up previous instance
if getgenv().ParticlePatcher then
    for _, conn in pairs(getgenv().ParticlePatcher.Conns) do 
        conn:Disconnect() 
    end
end

getgenv().ParticlePatcher = { Conns = {} }
local Conns = getgenv().ParticlePatcher.Conns

-- ========================================
-- PATCHING LOGIC
-- ========================================
local function patch(obj)
    if obj:IsA("ParticleEmitter") then
        -- Only register if not already cached
        if Registry[obj] then return end
        
        local originalRate = obj.Rate
        if originalRate > 0 then
            local parent = obj.Parent
            local isPart = parent and parent:IsA("BasePart")
            local isAttachment = parent and parent:IsA("Attachment")
            
            -- Store original data for this particle
            Registry[obj] = { 
                rate = originalRate,      -- Original emission rate
                acc = 0,                  -- Accumulator for manual emission
                parent = parent,          -- Cached parent reference
                hasPos = isPart or isAttachment,
                isPart = isPart
            }
            
            -- Set rate to 0 - we'll handle emission manually
            obj.Rate = 0
        end
        
    elseif obj:IsA("Beam") then
        -- Increase segments for smoother beams (only if current is lower)
        obj.Segments = math.max(obj.Segments, 10)
        
    elseif obj:IsA("Light") then
        -- Disable shadows for massive FPS boost
        obj.Shadows = false 
    end
end

-- ========================================
-- SCANNING FUNCTION
-- ========================================
local function safeScan(root)
    local descendants = root:GetDescendants()
    for i = 1, #descendants do
        patch(descendants[i])
        -- Yield every 1000 objects to prevent lag spikes
        if i % 1000 == 0 then task.wait() end 
    end
end

-- ========================================
-- SETUP CONNECTIONS
-- ========================================
-- Monitor new descendants in Workspace and Lighting
table.insert(Conns, Workspace.DescendantAdded:Connect(patch))
table.insert(Conns, Lighting.DescendantAdded:Connect(patch))

-- Initial scan of existing objects
task.spawn(safeScan, Workspace)
task.spawn(safeScan, Lighting)

-- ========================================
-- MAIN UPDATE LOOP
-- ========================================
table.insert(Conns, RunService.Heartbeat:Connect(function(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local camPos = cam.CFrame.Position
    local maxDist = _G.MaxDistance or 150
    
    -- Get character position for dual-distance check
    local player = game.Players.LocalPlayer
    local character = player and player.Character
    local charPos = character and character:FindFirstChild("HumanoidRootPart")
    charPos = charPos and charPos.Position or nil
    
    -- Clamp deltaTime to prevent huge jumps (e.g., when game freezes)
    dt = math.min(dt, 0.1)
    
    -- Calculate rate multiplier from ParticleLevel
    -- Level 10 = 1x (full quality), Level 1 = 0.1x (10% quality)
    -- Values above 10 are allowed and will increase beyond original rate
    local multiplier = math.max((_G.ParticleLevel or 10) / 10, 0.01)
    
    -- Iterate through all registered particles
    for emitter, data in pairs(Registry) do
        local parent = emitter.Parent
        
        -- Clean up destroyed particles
        if not parent then
            Registry[emitter] = nil
            continue
        end
        
        -- Skip disabled particles
        if not emitter.Enabled then 
            data.acc = 0  -- Reset accumulator
            continue 
        end
        
        -- Distance culling: render if within MaxDistance of EITHER camera OR character
        if data.hasPos then
            local pos = data.isPart and parent.Position or parent.WorldPosition
            local distToCamera = (pos - camPos).Magnitude
            local distToChar = charPos and (pos - charPos).Magnitude or math.huge
            
            -- Skip if too far from BOTH camera and character
            if distToCamera > maxDist and distToChar > maxDist then 
                data.acc = 0  -- Reset so particles don't burst when back in range
                continue 
            end
        end
        
        -- Apply quality multiplier to base rate
        local effectiveRate = data.rate * multiplier
        
        -- Accumulate time
        data.acc = data.acc + dt
        
        -- Calculate emission interval
        local interval = 1 / effectiveRate
        
        -- Emit particles when accumulated time exceeds interval
        if data.acc >= interval then
            local count = math.floor(data.acc / interval)
            data.acc = data.acc - (count * interval)
            emitter:Emit(count)
        end
    end
end))

print("[ParticlePatcher] Initialized with Quality=" .. (_G.ParticleLevel or 10) .. ", MaxDistance=" .. (_G.MaxDistance or 150) .. " studs")
