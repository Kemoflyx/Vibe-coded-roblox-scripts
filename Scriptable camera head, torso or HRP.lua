-- Localize Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Localize Math & Constructors
local CF_new, CF_angles = CFrame.new, CFrame.Angles
local CF_fromEuler = CFrame.fromEulerAnglesYXZ
local V3_new, V3_zero = Vector3.new, Vector3.zero
local math_rad, math_clamp, math_max = math.rad, math.clamp, math.max

-- Localize Player Variables
local LP = Players.LocalPlayer
local Cam = workspace.CurrentCamera

-- Cleanup Logic
local function Disconnect(conn)
    if conn then
        local success, err = pcall(function() conn:Disconnect() end)
    end
end

if getgenv().CF_Connections then
    for _, c in ipairs(getgenv().CF_Connections) do Disconnect(c) end
end
getgenv().CF_Connections = {}

if getgenv().RigidConn then Disconnect(getgenv().RigidConn); getgenv().RigidConn = nil end
if getgenv().CF_Gui then pcall(function() getgenv().CF_Gui:Destroy() end); getgenv().CF_Gui = nil end

-- Settings
getgenv().CF = getgenv().CF or {
    Enabled = true,
    Target = "Head",
    Sens = 0.4
}
local CF = getgenv().CF

local function trackConn(c)
    table.insert(getgenv().CF_Connections, c)
    return c
end

-- Camera Logic
local function LobotomizeCamera()
    local PlayerScripts = LP:FindFirstChild("PlayerScripts")
    if not PlayerScripts then return end
    
    local PlayerModule = PlayerScripts:FindFirstChild("PlayerModule")
    if not PlayerModule then return end
    
    local success, module = pcall(require, PlayerModule)
    if success then
        local CameraModule = module:GetCameras()
        if CameraModule and CameraModule.activeCameraController then
            CameraModule.activeCameraController.Update = function()
                return Cam.CFrame, Cam.Focus
            end
        end
    end
end

LobotomizeCamera()

-- Input State
local RotX, RotY, Zoom = 0, 0, 12
local radX, radY = 0, 0
local RMBHeld = false

trackConn(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        RMBHeld = true
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    end
end))

trackConn(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        RMBHeld = false
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end
end))

trackConn(UserInputService.InputChanged:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        local behavior = UserInputService.MouseBehavior
        if RMBHeld or behavior == Enum.MouseBehavior.LockCenter then
            RotX = RotX - input.Delta.X * CF.Sens
            RotY = math_clamp(RotY - input.Delta.Y * CF.Sens, -80, 80)
            radX, radY = math_rad(RotX), math_rad(RotY)
        end
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        Zoom = math_clamp(Zoom - input.Position.Z * 3, 4, 100)
    end
end))

-- Caching & Rendering
local Cache = { Char = nil, TargetMode = nil, HRP = nil, Hum = nil, Part = nil, Offset = 0 }
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateCache()
    local char = LP.Character
    if not char or not char:IsDescendantOf(workspace) then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local part
    
    if CF.Target == "Head" then
        part = char:FindFirstChild("Head")
        Cache.Offset = 0
    elseif CF.Target == "Torso" then
        part = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        Cache.Offset = 1.5
    else
        part = hrp
        Cache.Offset = 1.5
    end

    if hrp and hum and part then
        Cache.Char, Cache.HRP, Cache.Hum, Cache.Part = char, hrp, hum, part
        Cache.TargetMode = CF.Target
        RayParams.FilterDescendantsInstances = {char}
        LobotomizeCamera()
    end
end

getgenv().RigidConn = RunService.PreRender:Connect(function()
    if not CF.Enabled then return end
    
    -- Check if cache is valid
    if Cache.Char ~= LP.Character or Cache.TargetMode ~= CF.Target then
        updateCache()
    end

    local part = Cache.Part
    if not part then return end

    -- Minimal work inside loop
    if Cache.Hum.CameraOffset ~= V3_zero then
        Cache.Hum.CameraOffset = V3_zero
    end

    local pos = part.Position
    local targetPos = V3_new(pos.X, pos.Y + Cache.Offset, pos.Z)

    -- Handle Shift Lock Offset
    if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        targetPos = targetPos + (CF_angles(0, radX, 0) * V3_new(1.75, 0, 0))
    end

    -- Rotation calculation
    local rotation = CF_fromEuler(radY, radX, 0)
    local rawOffset = rotation * V3_new(0, 0, Zoom)

    -- Collision
    local hit = workspace:Raycast(targetPos, rawOffset, RayParams)
    local curZoom = hit and math_max(hit.Distance - 0.3, 0.5) or Zoom

    -- Apply
    Cam.Focus = CF_new(targetPos)
    Cam.CFrame = CF_new(targetPos) * rotation * CF_new(0, 0, curZoom)
end)

--------------------------------------------------------------------------------
-- GUI Code (Maintained functionality, streamlined structure)
--------------------------------------------------------------------------------
local Gui = Instance.new("ScreenGui", gethui() and gethui() or game:GetService("CoreGui"))
getgenv().CF_Gui = Gui

local F = Instance.new("Frame", Gui)
F.Size, F.Position = UDim2.new(0, 150, 0, 130), UDim2.new(0, 10, 0.5, -55)
F.BackgroundColor3, F.Active = Color3.new(0, 0, 0), true
Instance.new("UIStroke", F).Color = Color3.new(0.3, 0.3, 0.3)

-- Simple Dragging
local dragStart, startPos, dragging = nil, nil, false
trackConn(F.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; startPos = F.Position
    end
end))
trackConn(UserInputService.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = i.Position - dragStart
        F.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end))
trackConn(UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end))

local buttons = {}
local function updateUI()
    buttons.Head.TextColor3 = CF.Target == "Head" and Color3.new(1,1,1) or Color3.new(0.3,0.3,0.3)
    buttons.Torso.TextColor3 = CF.Target == "Torso" and Color3.new(1,1,1) or Color3.new(0.3,0.3,0.3)
    buttons.HRP.TextColor3 = CF.Target == "HumanoidRootPart" and Color3.new(1,1,1) or Color3.new(0.3,0.3,0.3)
    buttons.Toggle.Text = CF.Enabled and "STATUS: RIGID" or "STATUS: OFF"
    buttons.Toggle.TextColor3 = CF.Enabled and Color3.new(0,1,0) or Color3.new(1,0,0)
end

local function mk(id, txt, pos, target)
    local b = Instance.new("TextButton", F)
    b.Size, b.Position, b.Text = UDim2.new(1, -16, 0, 20), pos, txt
    b.BackgroundColor3, b.Font, b.TextSize = Color3.new(0.05, 0.05, 0.05), Enum.Font.Code, 10
    b.TextColor3, b.BorderSizePixel = Color3.new(0.6, 0.6, 0.6), 0
    b.MouseButton1Click:Connect(function()
        if target then CF.Target = target else CF.Enabled = not CF.Enabled end
        updateUI()
    end)
    buttons[id] = b
end

mk("Head", "FOLLOW: HEAD", UDim2.new(0, 8, 0, 8), "Head")
mk("Torso", "FOLLOW: TORSO", UDim2.new(0, 8, 0, 33), "Torso")
mk("HRP", "FOLLOW: HRP", UDim2.new(0, 8, 0, 58), "HumanoidRootPart")
mk("Toggle", "STATUS: RIGID", UDim2.new(0, 8, 0, 83))
updateUI()