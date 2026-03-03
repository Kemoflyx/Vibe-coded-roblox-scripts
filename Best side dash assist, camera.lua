-- Replicated Side-Arch Dash (Camera Independent, Orientation Independent)
local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")
local player     = Players.LocalPlayer
local camera     = workspace.CurrentCamera

-- ── Tunable values ────────────────────────────────────────────────────────────
local COOLDOWN          = 2      -- normal side dash cooldown (seconds)
local COOLDOWN_W        = 7      -- W front dash cooldown (seconds)
local MAX_RANGE         = 30     -- normal side dash max target range (studs)
local MAX_RANGE_W       = 35     -- W front dash max target range (studs)
local DASH_SPEED        = 115    -- normal side arch movement speed
local DASH_SPEED_W      = 100    -- W held front dash movement speed
local STEPS             = 20     -- arc resolution (higher = smoother curve)
local CAM_LOCK_DURATION = 0.55   -- how long camera stares at target (seconds)
local CAM_RIGHT_OFFSET  = 1.5    -- aim point shifted to your right (studs)
local CAM_AIM_HEIGHT    = 0.3    -- aim height: fraction of HipHeight above feet (0=feet, 1=hip, 2=head)
local FACING_LINGER     = 1      -- how long character keeps facing target after dash (seconds)
local ARCH_WIDTH_MIN    = 6      -- minimum side dash arc width (studs)
local ARCH_WIDTH_MAX    = 14     -- maximum side dash arc width at full range (studs)
local ARCH_OVERSHOOT    = 4      -- how far past target the arc endpoint extends (studs)
local W_SIDE_OFFSET     = 4.5    -- W dash lateral offset from target (studs)
local W_FORWARD_OFFSET  = 1      -- W dash forward offset past target (studs)
-- ─────────────────────────────────────────────────────────────────────────────

local onCooldown  = false
local onCooldownW = false

if _G.__dashCleanup then _G.__dashCleanup() end
local cleanupTasks = {}
local activeConns  = {}
local function onCleanup(fn) table.insert(cleanupTasks, fn) end
local function trackActive(c) table.insert(activeConns, c) return c end
_G.__dashCleanup = function()
	for _, fn in ipairs(cleanupTasks) do pcall(fn) end
	cleanupTasks = {}
	for _, c in ipairs(activeConns) do pcall(function() c:Disconnect() end) end
	activeConns = {}
	_G.__dashCleanup = nil
end

local targetCache = {}
local playerConns = {}
local diedConns   = {}

local function addModel(model)
	if model == player.Character then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hrp and hum then
		targetCache[model] = { Root = hrp, Humanoid = hum }
		local dc = hum.Died:Connect(function() targetCache[model] = nil end)
		table.insert(diedConns, dc)
	end
end

local function removeModel(model) targetCache[model] = nil end

local function trackPlayer(p)
	if p == player then return end
	if playerConns[p] then
		for _, c in ipairs(playerConns[p]) do pcall(function() c:Disconnect() end) end
	end
	playerConns[p] = {}
	if p.Character then addModel(p.Character) end
	table.insert(playerConns[p], p.CharacterAdded:Connect(function(c)
		task.wait(0.5)
		addModel(c)
	end))
	table.insert(playerConns[p], p.CharacterRemoving:Connect(function(c)
		removeModel(c)
	end))
end

for _, model in ipairs(workspace:GetDescendants()) do
	if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
		addModel(model)
	end
end
for _, p in ipairs(Players:GetPlayers()) do trackPlayer(p) end

local c1 = Players.PlayerAdded:Connect(trackPlayer)
local c2 = Players.PlayerRemoving:Connect(function(p)
	if p.Character then removeModel(p.Character) end
	if playerConns[p] then
		for _, c in ipairs(playerConns[p]) do pcall(function() c:Disconnect() end) end
		playerConns[p] = nil
	end
end)
local c3 = workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then
		task.wait(0.1)
		local model = d.Parent
		if model and model:IsA("Model") and model:FindFirstChild("HumanoidRootPart") then
			addModel(model)
		end
	end
end)
local c4 = workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Model") and targetCache[d] then removeModel(d) end
end)
onCleanup(function() c1:Disconnect() end)
onCleanup(function() c2:Disconnect() end)
onCleanup(function() c3:Disconnect() end)
onCleanup(function() c4:Disconnect() end)
onCleanup(function()
	for _, conns in pairs(playerConns) do
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	end
	playerConns = {}
	for _, c in ipairs(diedConns) do pcall(function() c:Disconnect() end) end
	diedConns = {}
end)

local function getCharacter() return player.Character or player.CharacterAdded:Wait() end

local function quadBezier(p0, p1, p2, t)
	return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

local function buildArcTable(p0, p1, p2)
	local tbl = { { t = 0, len = 0 } }
	local prev, total = p0, 0
	for i = 1, STEPS do
		local tt   = i / STEPS
		local curr = quadBezier(p0, p1, p2, tt)
		total = total + (curr - prev).Magnitude
		tbl[i + 1] = { t = tt, len = total }
		prev = curr
	end
	return tbl, total
end

local function arcLenToT(tbl, targetLen)
	local lo, hi = 1, #tbl
	while lo < hi - 1 do
		local mid = math.floor((lo + hi) / 2)
		if tbl[mid].len < targetLen then lo = mid else hi = mid end
	end
	local a, b = tbl[lo], tbl[hi]
	if b.len == a.len then return a.t end
	return a.t + (targetLen - a.len) / (b.len - a.len) * (b.t - a.t)
end

local function press(key)   VIM:SendKeyEvent(true,  key, false, game) end
local function release(key) VIM:SendKeyEvent(false, key, false, game) end

local function getTarget(root, range)
	local mousePos = UIS:GetMouseLocation()
	local closest, closestDist = nil, math.huge
	for model, data in pairs(targetCache) do
		if model.Parent and data.Humanoid.Health > 0 then
			local dist = (data.Root.Position - root.Position).Magnitude
			if dist <= range then
				local screenPos = workspace.CurrentCamera:WorldToScreenPoint(data.Root.Position)
				local sd = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
				if sd < closestDist then
					closestDist = sd
					closest = data.Root
				end
			end
		else
			targetCache[model] = nil
		end
	end
	return closest
end

local function applyFacing(root, hum, targetRoot)
	if hum then hum.AutoRotate = false end
	local myPos = root.Position
	local dir   = Vector3.new(targetRoot.Position.X - myPos.X, 0, targetRoot.Position.Z - myPos.Z)
	if dir.Magnitude > 0.01 then
		local lookCFrame = CFrame.lookAt(myPos, myPos + dir)
		root.CFrame = CFrame.new(myPos) * (lookCFrame - lookCFrame.Position)
	end
end

local function startCameraLock(root, target)
	local startTime = tick()
	local unlocked  = false

	local function doUnlock()
		if unlocked then return end
		unlocked = true
		RunService:UnbindFromRenderStep("__dashCamLock")
	end

	RunService:BindToRenderStep("__dashCamLock", Enum.RenderPriority.Camera.Value + 1, function()
		if tick() - startTime >= CAM_LOCK_DURATION then
			doUnlock()
			return
		end
		local hum    = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
		local hipH   = hum and hum.HipHeight or 2.35
		local footY  = target.Position.Y - hipH - (target.Size.Y / 2)
		local aimY   = footY + hipH * CAM_AIM_HEIGHT
		local aimPos = Vector3.new(target.Position.X, aimY, target.Position.Z)
		             + camera.CFrame.RightVector * CAM_RIGHT_OFFSET
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aimPos)
	end)

	return doUnlock
end

local function activate()
	local holdingW = UIS:IsKeyDown(Enum.KeyCode.W)
	local holdingS = UIS:IsKeyDown(Enum.KeyCode.S)

	if holdingS then
		local char = getCharacter()
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local target = getTarget(root, math.huge)
		if not target then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		press(Enum.KeyCode.Q)
		task.delay(0.06, function() release(Enum.KeyCode.Q) end)
		local startTime = tick()
		local conn
		conn = trackActive(RunService.RenderStepped:Connect(function()
			if tick() - startTime >= FACING_LINGER then
				conn:Disconnect()
				if hum then hum.AutoRotate = true end
				return
			end
			applyFacing(root, hum, target)
		end))
		local unlockCam = startCameraLock(root, target)
		return
	end

	if holdingW and onCooldownW then return end
	if not holdingW and onCooldown then return end
	local char = getCharacter()
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local target = getTarget(root, holdingW and MAX_RANGE_W or MAX_RANGE)
	if not target then return end
	if holdingW then onCooldownW = true else onCooldown = true end
	local hum = char:FindFirstChildOfClass("Humanoid")

	local startPos      = root.Position
	local targetPos     = Vector3.new(target.Position.X, startPos.Y, target.Position.Z)
	local toTarget      = (targetPos - startPos).Unit
	local distance      = (targetPos - startPos).Magnitude
	local perp          = Vector3.new(-toTarget.Z, 0, toTarget.X)
	local sideDirection = ((root.CFrame.RightVector):Dot(toTarget) >= 0) and 1 or -1
	if holdingW then sideDirection = -sideDirection end
	local sideKey = sideDirection == -1 and Enum.KeyCode.A or Enum.KeyCode.D

	press(sideKey)
	task.wait(0.015)
	press(Enum.KeyCode.Q)
	task.delay(0.06,  function() release(Enum.KeyCode.Q) end)
	task.delay(0.075, function() release(sideKey) end)

	local speed    = holdingW and DASH_SPEED_W or DASH_SPEED
	local traveled = 0
	local connection

	if holdingW then
		local finalPos = targetPos + perp * sideDirection * W_SIDE_OFFSET + toTarget * W_FORWARD_OFFSET
		local totalLen = (finalPos - startPos).Magnitude
		local moveDir  = (finalPos - startPos).Unit
		if hum then hum.AutoRotate = false end
		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			traveled = traveled + speed * dt
			if traveled >= totalLen then
				connection:Disconnect()
				local lingerStart = tick()
				local currentDir  = root.CFrame.LookVector
				local lingerConn
				lingerConn = trackActive(RunService.RenderStepped:Connect(function(ldt)
					if hum then hum.AutoRotate = false end
					if tick() - lingerStart >= FACING_LINGER then
						lingerConn:Disconnect()
						if hum then hum.AutoRotate = true end
						return
					end
					local myPos = root.Position
					local dir2  = Vector3.new(target.Position.X - myPos.X, 0, target.Position.Z - myPos.Z)
					if dir2.Magnitude > 0.01 then
						currentDir = currentDir:Lerp(dir2.Unit, 1 - (0.0001 ^ ldt))
						local lookCFrame = CFrame.lookAt(myPos, myPos + currentDir)
						root.CFrame = CFrame.new(myPos) * (lookCFrame - lookCFrame.Position)
					end
				end))
				local unlockCam = startCameraLock(root, target)
				return
			end
			local pos = startPos + moveDir * traveled
			root.CFrame = CFrame.new(
				Vector3.new(pos.X, root.Position.Y, pos.Z),
				Vector3.new(pos.X + moveDir.X, root.Position.Y, pos.Z + moveDir.Z)
			)
		end))
	else
		local archWidth = ARCH_WIDTH_MIN + (distance / MAX_RANGE) * (ARCH_WIDTH_MAX - ARCH_WIDTH_MIN)
		local finalPos  = targetPos + toTarget * ARCH_OVERSHOOT
		local midpoint  = (startPos + finalPos) / 2 + perp * archWidth * sideDirection
		local arcTable, totalLen = buildArcTable(startPos, midpoint, finalPos)

		local facingConn
		facingConn = trackActive(RunService.RenderStepped:Connect(function()
			applyFacing(root, hum, target)
		end))
		local unlockCam = startCameraLock(root, target)

		connection = trackActive(RunService.Heartbeat:Connect(function(dt)
			if traveled >= totalLen then
				connection:Disconnect()
				facingConn:Disconnect()
				local lingerStart = tick()
				local lingerConn
				lingerConn = trackActive(RunService.RenderStepped:Connect(function()
					if hum then hum.AutoRotate = false end
					if tick() - lingerStart >= FACING_LINGER then
						lingerConn:Disconnect()
						if hum then hum.AutoRotate = true end
						return
					end
					applyFacing(root, hum, target)
				end))
				local lingerCamUnlock = startCameraLock(root, target)
				return
			end
			traveled = traveled + speed * dt
			local t        = arcLenToT(arcTable, math.min(traveled, totalLen))
			local curvePos = quadBezier(startPos, midpoint, finalPos, t)
			root.CFrame = CFrame.new(Vector3.new(curvePos.X, root.Position.Y, curvePos.Z)) * (root.CFrame - root.CFrame.Position)
		end))
	end

	task.delay(holdingW and COOLDOWN_W or COOLDOWN, function()
		if holdingW then onCooldownW = false else onCooldown = false end
	end)
end

local c5 = trackActive(UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E then activate() end
end))
onCleanup(function() c5:Disconnect() end)
