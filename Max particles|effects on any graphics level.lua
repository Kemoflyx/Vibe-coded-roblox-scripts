local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Lighting   = game:GetService("Lighting")

-- We ONLY cache particles now. Beams and Lights don't need to be checked every frame.
local ParticleCache = setmetatable({}, { __mode = "k" })

if getgenv().GraphicsPatcher then
    for _, v in pairs(getgenv().GraphicsPatcher.Conns) do 
        v:Disconnect() 
    end
end

getgenv().GraphicsPatcher = { Conns = {} }
local Conns = getgenv().GraphicsPatcher.Conns

local function patch(obj)
    if obj:IsA("ParticleEmitter") then
        if ParticleCache[obj] then return end
        
        local originalRate = obj.Rate
        if originalRate > 0 then
            local parent = obj.Parent
            local isPart = parent and parent:IsA("BasePart")
            local isAttachment = parent and parent:IsA("Attachment")
            
            -- Pre-calculate everything we can so Heartbeat doesn't have to
            ParticleCache[obj] = { 
                rate = originalRate, 
                acc = 0,
                parent = parent,
                hasPos = isPart or isAttachment,
                isPart = isPart
            }
            obj.Rate = 0
        end
        
    elseif obj:IsA("Beam") then
        -- math.max(10) might actually ADD lag if the map maker used lower segments. 
        -- Leaving it as you wrote it, but keep that in mind.
        obj.Segments = math.max(obj.Segments, 10)
        
    elseif obj:IsA("Light") then
        -- WARNING: If you want better FPS, set this to FALSE. True will tank performance.
        obj.Shadows = false 
    end
end

local function safeScan(root)
    local descendants = root:GetDescendants()
    -- Removed pcall. It's too slow and unnecessary for scanning Workspace/Lighting.
    for i = 1, #descendants do
        patch(descendants[i])
        -- Increased batch size from 200 to 1000 since we removed the slow pcall
        if i % 1000 == 0 then task.wait() end 
    end
end

-- Register connections
table.insert(Conns, Workspace.DescendantAdded:Connect(patch))
table.insert(Conns, Lighting.DescendantAdded:Connect(patch))

task.spawn(safeScan, Workspace)
task.spawn(safeScan, Lighting)

table.insert(Conns, RunService.Heartbeat:Connect(function(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local camPos = cam.CFrame.Position
    dt = math.min(dt, 0.1)

    -- Luau allows safe removal of keys during iteration, so we don't need the deadKeys table!
    for emitter, data in pairs(ParticleCache) do
        local parent = emitter.Parent
        
        if not parent then
            ParticleCache[emitter] = nil
            continue
        end
        
        if not emitter.Enabled then continue end
        
        -- Calculate position based on whether it's a Part or an Attachment
        if data.hasPos then
            local pos = data.isPart and parent.Position or parent.WorldPosition
            if (pos - camPos).Magnitude > 150 then 
                -- Optional: reset accumulator so particles don't "burst" when you walk into range
                data.acc = 0 
                continue 
            end
        end

        data.acc += dt
        local interval = 1 / data.rate
        
        if data.acc >= interval then
            local count = math.floor(data.acc / interval)
            data.acc -= (count * interval)
            emitter:Emit(count)
        end
    end
end))
