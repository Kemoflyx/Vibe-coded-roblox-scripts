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

-- Global Settings
getgenv().CF = getgenv().CF or {
    Enabled = true,
    Target = "Head",
    Sens = 0.4,
    Keybind = Enum.KeyCode.Z
}
local CF = getgenv().CF

-- Backup Logic
local OriginalUpdate = nil
local CameraController = nil

local function Disconnect(conn)
    if conn then pcall(function() conn:Disconnect() end) end
end

if getgenv().CF_Connections then
    for _, c in ipairs(getgenv().CF_Connections) do Disconnect(c) end
end
getgenv().CF_Connections = {}

local function trackConn(c)
    table.insert(getgenv().CF_Connections, c)
    return c
end

-- Camera Hijack/Restore
local function ToggleCameraLobotomy(enable)
    local PlayerScripts = LP:FindFirstChild("PlayerScripts")
    local PlayerModule = PlayerScripts and PlayerScripts:FindFirstChild("PlayerModule")
    if not PlayerModule then return end
    
    local success, module = pcall(require, PlayerModule)
    if success then
        local CameraModule = module:GetCameras()
        if CameraModule and CameraModule.activeCameraController then
            CameraController = CameraModule.activeCameraController
            if not OriginalUpdate then OriginalUpdate = CameraController.Update end
            
            if enable then
                CameraController.Update = function() return Cam.CFrame, Cam.Focus end
            else
                if OriginalUpdate then CameraController.Update = OriginalUpdate end
            end
        end
    end
end

if CF.Enabled then ToggleCameraLobotomy(true) end

-- Input State
local RotX, RotY, Zoom = 0, 0, 12
local radX, radY = 0, 0
local RMBHeld = false

trackConn(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CF.Keybind then
        CF.Enabled = not CF.Enabled
        ToggleCameraLobotomy(CF.Enabled)
        if getgenv().UpdateCFUI then getgenv().UpdateCFUI() end
    end
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

-- Cache & Collision
local Cache = { Subject = nil, TargetMode = nil, Hum = nil, Part = nil, Offset = 0 }
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getIgnoredInstances()
    local ignored = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(ignored, player.Character) end
    end
    return ignored
end

local function updateCache()
    local subject = Cam.CameraSubject
    local char = (subject and subject:IsA("Humanoid") and subject.Parent) or (subject and subject:IsA("BasePart") and subject.Parent) or LP.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local part = (CF.Target == "Head" and char:FindFirstChild("Head")) or (CF.Target == "Torso" and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))) or hrp
    
    Cache.Offset = (CF.Target == "Head") and 0 or 1.5
    if hrp and hum and part then
        Cache.Hum, Cache.Part, Cache.TargetMode, Cache.Subject = hum, part, CF.Target, subject
    end
end

if getgenv().RigidConn then Disconnect(getgenv().RigidConn) end
getgenv().RigidConn = RunService.PreRender:Connect(function()
    if not CF.Enabled then return end
    if Cache.Subject ~= Cam.CameraSubject or Cache.TargetMode ~= CF.Target then updateCache() end
    if not Cache.Part then return end
    if Cache.Hum.CameraOffset ~= V3_zero then Cache.Hum.CameraOffset = V3_zero end

    local targetPos = Cache.Part.Position + V3_new(0, Cache.Offset, 0)
    if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        targetPos = targetPos + (CF_angles(0, radX, 0) * V3_new(1.75, 0, 0))
    end

    local rotation = CF_fromEuler(radY, radX, 0)
    RayParams.FilterDescendantsInstances = getIgnoredInstances()
    
    local hit = workspace:Raycast(targetPos, rotation * V3_new(0, 0, Zoom), RayParams)
    local finalZoom = Zoom
    if hit and hit.Instance.CanCollide and hit.Instance.Transparency < 0.9 then
        finalZoom = math_max(hit.Distance - 0.3, 0.5)
    end

    Cam.Focus = CF_new(targetPos)
    Cam.CFrame = CF_new(targetPos) * rotation * CF_new(0, 0, finalZoom)
end)

--------------------------------------------------------------------------------
-- GUI Code (Draggable again)
--------------------------------------------------------------------------------
if getgenv().CF_Gui then pcall(function() getgenv().CF_Gui:Destroy() end) end
local Gui = Instance.new("ScreenGui", gethui() and gethui() or game:GetService("CoreGui"))
getgenv().CF_Gui = Gui

local F = Instance.new("Frame", Gui)
F.Size, F.Position = UDim2.new(0, 150, 0, 130), UDim2.new(0, 10, 0.5, -55)
F.BackgroundColor3, F.Active, F.Draggable = Color3.new(0, 0, 0), true, true -- Active/Draggable enabled
Instance.new("UIStroke", F).Color = Color3.new(0.3, 0.3, 0.3)

-- Dragging Logic
local dragging, dragInput, dragStart, startPos
trackConn(F.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = F.Position
    end
end))
trackConn(UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        F.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end))
trackConn(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end))

local buttons = {}
getgenv().UpdateCFUI = function()
    buttons.Head.TextColor3 = CF.Target == "Head" and Color3.new(1,1,1) or Color3.new(0.3,0.3,0.3)
    buttons.Torso.TextColor3 = CF.Target == "Torso" and Color3.new(1,1,1) or Color3.new(0.3,0.3,0.3)
    buttons.HRP.TextColor3 = CF.Target == "HumanoidRootPart" and Color3.new(1,1,1) or Color3.new(0.3,0.3,0.3)
    buttons.Toggle.Text = CF.Enabled and "STATUS: RIGID" or "STATUS: OFF"
    buttons.Toggle.TextColor3 = CF.Enabled and Color3.new(0,1,0) or Color3.new(1,0,0)
    buttons.Bind.Text = "BIND: " .. CF.Keybind.Name
end

local function mk(id, txt, pos, target)
    local b = Instance.new("TextButton", F)
    b.Size, b.Position, b.Text = UDim2.new(1, -16, 0, 18), pos, txt
    b.BackgroundColor3, b.Font, b.TextSize = Color3.new(0.05, 0.05, 0.05), Enum.Font.Code, 10
    b.TextColor3, b.BorderSizePixel = Color3.new(0.6, 0.6, 0.6), 0
    b.MouseButton1Click:Connect(function()
        if id == "Bind" then
            b.Text = "..."
            local l; l = UserInputService.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.Keyboard then
                    CF.Keybind = i.KeyCode
                    l:Disconnect()
                    getgenv().UpdateCFUI()
                end
            end)
        elseif target then CF.Target = target 
        else CF.Enabled = not CF.Enabled; ToggleCameraLobotomy(CF.Enabled) end
        getgenv().UpdateCFUI()
    end)
    buttons[id] = b
end

mk("Head", "FOLLOW: HEAD", UDim2.new(0, 8, 0, 8), "Head")
mk("Torso", "FOLLOW: TORSO", UDim2.new(0, 8, 0, 28), "Torso")
mk("HRP", "FOLLOW: HRP", UDim2.new(0, 8, 0, 48), "HumanoidRootPart")
mk("Toggle", "STATUS: RIGID", UDim2.new(0, 8, 0, 75))
mk("Bind", "BIND: Z", UDim2.new(0, 8, 0, 95))
getgenv().UpdateCFUI()
