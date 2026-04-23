local UserSettings = UserSettings():GetService("UserGameSettings")
local min = math.min

shared.OriginalRates = shared.OriginalRates or setmetatable({}, { __mode = "k" })
local OriginalRates = shared.OriginalRates

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
        applyRate(emitter, originalRate)
    end
end

local function register(obj)
    if obj:IsA("ParticleEmitter") and not OriginalRates[obj] then
        local rate = obj.Rate
        OriginalRates[obj] = rate
        applyRate(obj, rate)
    end
end

local function unregister(obj)
    if OriginalRates[obj] then
        OriginalRates[obj] = nil
    end
end

workspace.DescendantAdded:Connect(register)
workspace.DescendantRemoving:Connect(unregister)
for _, v in pairs(workspace:GetDescendants()) do register(v) end
UserSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(updateParticles)
updateParticles()
