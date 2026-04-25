local UserSettings = UserSettings():GetService("UserGameSettings")

-- Using a weak table ensures that when an emitter is destroyed, 
-- it gets garbage collected automatically without memory leaks.
shared.OriginalRates = shared.OriginalRates or setmetatable({}, { __mode = "k" })
local OriginalRates = shared.OriginalRates

local robloxScaleMap = {
    [1] = 0.1, [2] = 0.2, [3] = 0.3, [4] = 0.45, [5] = 0.6,
    [6] = 0.75, [7] = 0.85, [8] = 0.92, [9] = 0.96, [10] = 1.0
}

local currentScale = 1.0

-- Calculates the rate for a specific emitter
local function applyRate(emitter, originalRate)
    local targetRate = originalRate / currentScale
    local finalRate = math.min(originalRate * 10, targetRate)
    
    if emitter.Rate ~= finalRate then
        emitter.Rate = finalRate
    end
end

-- Updates our scale multiplier
local function updateScale()
    local qLevel = UserSettings.SavedQualityLevel.Value
    if qLevel == 0 then qLevel = 10 end -- Handle "Automatic" setting
    currentScale = robloxScaleMap[qLevel] or 1.0
end

-- Pushes the new rate to all cached emitters
local function updateAllEmitters()
    for emitter, originalRate in pairs(OriginalRates) do
        applyRate(emitter, originalRate)
    end
end

-- Registers a new emitter and instantly scales it
local function register(obj)
    if obj:IsA("ParticleEmitter") and not OriginalRates[obj] then
        OriginalRates[obj] = obj.Rate 
        applyRate(obj, obj.Rate)
    end
end

-- 1. Initial setup calculation
updateScale()

-- 2. ONLY run the math when the player changes their graphics slider
UserSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
    updateScale()
    updateAllEmitters()
end)

-- 3. Hook onto new descendants and scan existing ones
workspace.DescendantAdded:Connect(register)

-- Use ipairs instead of pairs for GetDescendants() as it's slightly faster for arrays
for _, v in ipairs(workspace:GetDescendants()) do 
    register(v) 
end
