local RunService = game:GetService("RunService")

local originalRates = {}
local accumulators  = {}

local function patchParticle(obj)
    if not obj:IsA("ParticleEmitter") then return end
    if originalRates[obj] then return end

    local rate = obj.Rate
    if rate <= 0 then return end

    originalRates[obj] = rate
    accumulators[obj]  = 0

    pcall(function() obj.Rate      = 0                        end)
    pcall(function() obj.Brightness = math.max(obj.Brightness, 1) end)
    pcall(function() obj.TimeScale  = 1                       end)
end

local function patchBeam(obj)
    if not obj:IsA("Beam") then return end
    pcall(function() obj.Segments = math.max(obj.Segments, 10) end)
end

local function patchLight(obj)
    if not (obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight")) then return end
    pcall(function() obj.Shadows = true end)
end

local function patch(obj)
    patchParticle(obj)
    patchBeam(obj)
    patchLight(obj)
end

for _, obj in ipairs(game.Workspace:GetDescendants()) do patch(obj) end
for _, obj in ipairs(game:GetService("Lighting"):GetDescendants()) do patch(obj) end

game.DescendantAdded:Connect(function(obj) task.defer(patch, obj) end)

game.DescendantRemoving:Connect(function(obj)
    originalRates[obj] = nil
    accumulators[obj]  = nil
end)

RunService.Heartbeat:Connect(function(dt)
    local safe_dt = math.min(dt, 0.1)

    for emitter, rate in pairs(originalRates) do
        if not emitter.Parent then
            originalRates[emitter] = nil
            accumulators[emitter]  = nil
            continue
        end

        if not emitter.Enabled then
            accumulators[emitter] = 0
            continue
        end

        local acc      = accumulators[emitter] + safe_dt
        local interval = 1 / rate

        if acc >= interval then
            local count = math.floor(acc / interval)
            acc = acc - (count * interval)
            pcall(function() emitter:Emit(count) end)
        end

        accumulators[emitter] = acc
    end
end)
