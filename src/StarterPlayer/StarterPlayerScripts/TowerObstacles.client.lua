--[[
	TOWER OF FOOD - obstacles, moving parts and jumping
	Where it goes: StarterPlayer > StarterPlayerScripts  (type: LocalScript, name: TowerObstacles)

	The server builds the tower and sticks little labels ("tags") on the parts that
	should do something special (see docs/ARCHITECTURE.md, part 9). This script
	brings them to life on YOUR screen:
	  Spin / Move / Swing   pizzas spin, donuts drift, bowls swing - and they carry
	                        you along when you stand on them
	  Kill                  touch it and you're out!
	  Cycle                 popcorn that pops away and comes back, chips that get red hot
	  Melt                  ice cream that melts under your feet
	  Bounce                jelly that throws you up high
	  Conveyor              belts that push you along
	It also does the Double Jump game pass.
	Everything follows the server's clock, so every player sees the same thing.
	You don't need to change anything in here.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local DANGER = Color3.fromRGB(255, 45, 45) -- deadly red (the same red the server uses)
local WARNING = Color3.fromRGB(255, 150, 40) -- a hot chip blinks orange before it turns on
local KILL_GLOW = Color3.fromRGB(255, 130, 95) -- deadly parts gently pulse towards this colour
local WARN_TIME = 0.6 -- seconds of warning before a Cycle part switches
local ANIMATE_DISTANCE = 400 -- moving parts further than this from the camera take a nap
local PULSE_DISTANCE = 160 -- deadly parts closer than this to the camera pulse
local CARRY_REACH = 2 -- a moving part up to this far under your feet still carries you
local MAX_CARRY_STEP = 12 -- never carry you further than this in one frame (safety)
local TOUCH_GAP = 0.6 -- your feet "touch" a part when they are this close to its top
local FOOT_DIP = 0.3 -- the deadly-touch check reaches this far under your feet...
local BODY_PAD = 0.1 -- ...and this far around your body
local BOUNCE_COOLDOWN = 0.3 -- seconds between two jelly bounces
local DOUBLE_JUMP_DELAY = 0.1 -- seconds in the air before you can double jump
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local TWO_PI = 2 * math.pi

-- every tag this script looks after
local TAGS = { "Spin", "Move", "Swing", "Kill", "Cycle", "Melt", "Bounce", "Conveyor" }

------------------------------------------------------------------------
-- Little helpers
------------------------------------------------------------------------
-- Problems are printed at most once every 10 seconds, so the Output stays readable.
local lastReport: { [string]: number } = {}
local function report(where: string, err: any)
	local now = os.clock()
	local last: number? = lastReport[where]
	if last and now - last < 10 then
		return
	end
	lastReport[where] = now
	warn("[TowerObstacles] problem in " .. where .. ": " .. tostring(err))
end

local function asPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function asModel(inst: Instance): Model?
	if inst:IsA("Model") then
		return inst
	end
	return nil
end

local function isFinite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

-- Attributes can arrive a moment after the part, so every read is careful.
local function numberAttr(inst: Instance, name: string): number?
	local value = inst:GetAttribute(name)
	if type(value) == "number" and isFinite(value) then
		return value
	end
	return nil
end

local function vectorAttr(inst: Instance, name: string): Vector3?
	local value = inst:GetAttribute(name)
	if typeof(value) == "Vector3" and isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z) then
		return value
	end
	return nil
end

-- A direction made exactly 1 stud long (nil if it's missing or zero).
local function directionAttr(inst: Instance, name: string): Vector3?
	local value = vectorAttr(inst, name)
	if value and value.Magnitude > 1e-6 then
		return value.Unit
	end
	return nil
end

local function colorAttr(inst: Instance, name: string): Color3?
	local value = inst:GetAttribute(name)
	if typeof(value) == "Color3" then
		return value
	end
	return nil
end

local function cframeAttr(inst: Instance, name: string): CFrame?
	local value = inst:GetAttribute(name)
	if typeof(value) == "CFrame" then
		return value
	end
	return nil
end

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.02 and math.abs(a.G - b.G) < 0.02 and math.abs(a.B - b.B) < 0.02
end

-- How far through a repeating loop we are (0 up to 1).
-- The server clock is a HUGE number, so we chop whole loops off first to stay precise.
local function loopFraction(t: number, period: number, phase: number): number
	return ((t % period) / period + phase) % 1
end

-- Is a Cycle part "on" right now, and how many seconds until it switches?
local function cycleState(onTime: number, offTime: number, phase: number, t: number): (boolean, number)
	if offTime <= 0 then
		return true, math.huge
	elseif onTime <= 0 then
		return false, math.huge
	end
	local total = onTime + offTime
	local at = loopFraction(t, total, phase) * total
	if at < onTime then
		return true, onTime - at
	end
	return false, total - at
end

-- How much a turn rotates things around the up axis (radians). Any tilt is
-- ignored, so a swinging bowl or a rolling wheel never tips you over.
local function yawOf(cf: CFrame): number
	local axis, angle = cf:ToAxisAngle()
	local half = angle / 2
	local yaw = 2 * math.atan2(axis.Y * math.sin(half), math.cos(half))
	if yaw ~= yaw then
		return 0
	end
	return yaw
end

-- Distance from the middle of the HumanoidRootPart down to the soles of your feet.
local function feetOffset(hum: Humanoid, root: BasePart): number
	if hum.RigType == Enum.HumanoidRigType.R6 then
		return root.Size.Y / 2 + 2
	end
	return root.Size.Y / 2 + hum.HipHeight
end

-- Your position, facing the way you face, but standing perfectly straight.
local function uprightCFrame(root: BasePart): CFrame
	local pos = root.Position
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + flat)
end

------------------------------------------------------------------------
-- Shape maths for the deadly-touch check
-- (exact for blocks, balls and cylinders, so round lava pools are fair)
------------------------------------------------------------------------
-- Is there a gap between box A and box B along this axis? (the "separating axis" test)
local function separatedOn(axis: Vector3, gap: Vector3, a1: Vector3, a2: Vector3, a3: Vector3, aHalf: Vector3, b1: Vector3, b2: Vector3, b3: Vector3, bHalf: Vector3): boolean
	if axis:Dot(axis) < 1e-10 then
		return false -- two edges are parallel: the other axes already cover this
	end
	local ra = aHalf.X * math.abs(a1:Dot(axis)) + aHalf.Y * math.abs(a2:Dot(axis)) + aHalf.Z * math.abs(a3:Dot(axis))
	local rb = bHalf.X * math.abs(b1:Dot(axis)) + bHalf.Y * math.abs(b2:Dot(axis)) + bHalf.Z * math.abs(b3:Dot(axis))
	return math.abs(gap:Dot(axis)) > ra + rb
end

-- Do two boxes overlap? Each box is its centre CFrame and half of its size.
local function boxesOverlap(aCF: CFrame, aHalf: Vector3, bCF: CFrame, bHalf: Vector3): boolean
	local a1, a2, a3 = aCF.RightVector, aCF.UpVector, aCF.LookVector
	local b1, b2, b3 = bCF.RightVector, bCF.UpVector, bCF.LookVector
	local gap = bCF.Position - aCF.Position
	local function apart(axis: Vector3): boolean
		return separatedOn(axis, gap, a1, a2, a3, aHalf, b1, b2, b3, bHalf)
	end
	if apart(a1) or apart(a2) or apart(a3) or apart(b1) or apart(b2) or apart(b3) then
		return false
	end
	for _, a in ipairs({ a1, a2, a3 }) do
		if apart(a:Cross(b1)) or apart(a:Cross(b2)) or apart(a:Cross(b3)) then
			return false
		end
	end
	return true
end

-- The point of a box that is closest to "point".
local function closestInBox(point: Vector3, boxCF: CFrame, half: Vector3): Vector3
	local p = boxCF:PointToObjectSpace(point)
	local clamped = Vector3.new(math.clamp(p.X, -half.X, half.X), math.clamp(p.Y, -half.Y, half.Y), math.clamp(p.Z, -half.Z, half.Z))
	return boxCF:PointToWorldSpace(clamped)
end

local function ballTouchesBox(center: Vector3, radius: number, boxCF: CFrame, half: Vector3): boolean
	return (closestInBox(center, boxCF, half) - center).Magnitude <= radius
end

-- Roblox cylinders lie along their own X axis.
local function cylinderTouchesBox(cylCF: CFrame, size: Vector3, boxCF: CFrame, half: Vector3): boolean
	if not boxesOverlap(cylCF, size / 2, boxCF, half) then
		return false
	end
	local radius = math.min(size.Y, size.Z) / 2
	local halfLength = size.X / 2
	local axis = cylCF.RightVector
	local center = cylCF.Position
	-- walk along the middle line of the cylinder and test the nearest bit of the box
	local steps = math.clamp(math.ceil(2 * halfLength / math.max(radius, 0.25)), 1, 32)
	for i = 0, steps do
		local probe = center + axis * (-halfLength + 2 * halfLength * i / steps)
		local rel = closestInBox(probe, boxCF, half) - center
		local along = rel:Dot(axis)
		if math.abs(along) <= halfLength + 0.05 and (rel - axis * along).Magnitude <= radius + 0.05 then
			return true
		end
	end
	return false
end

local function partTouchesBox(part: BasePart, boxCF: CFrame, half: Vector3): boolean
	local size = part.Size
	if part:IsA("Part") then
		if part.Shape == Enum.PartType.Ball then
			return ballTouchesBox(part.Position, math.min(size.X, size.Y, size.Z) / 2, boxCF, half)
		elseif part.Shape == Enum.PartType.Cylinder then
			return cylinderTouchesBox(part.CFrame, size, boxCF, half)
		end
	end
	-- blocks are exact; wedges and anything else count as their full box
	return boxesOverlap(part.CFrame, size / 2, boxCF, half)
end

------------------------------------------------------------------------
-- You (the local player's character) and the tower
------------------------------------------------------------------------
local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local deathSent = false -- we only tell the server once per life
local inAir = false
local airSince = 0
local doubleJumpUsed = false
local lastJumpRequest = 0
local jumpReleasedAt = 0
local lastBounce = 0
local puffEmitter: ParticleEmitter? = nil

local tower: Instance? = nil -- workspace.Tower (a brand new one every round)
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = {}
floorParams.RespectCanCollide = true -- see-through decorations don't count as floor
floorParams.IgnoreWater = true
local touchParams = OverlapParams.new()
touchParams.FilterType = Enum.RaycastFilterType.Include
touchParams.FilterDescendantsInstances = {}

local function findTower(): Instance?
	local current = tower
	if current and current.Parent == workspace and current.Name == "Tower" then
		return current
	end
	local found = workspace:FindFirstChild("Tower")
	if found ~= current then
		tower = found
		local list: { Instance } = {}
		if found then
			list = { found }
		end
		floorParams.FilterDescendantsInstances = list
		touchParams.FilterDescendantsInstances = list
	end
	return found
end

local cachedDeathRemote: RemoteEvent? = nil
local function deathRemote(): RemoteEvent?
	local remote = cachedDeathRemote
	if remote and remote.Parent then
		return remote
	end
	local folder = ReplicatedStorage:FindFirstChild("TowerOfFood")
	local found = folder and folder:FindFirstChild("RequestDeath")
	if found and found:IsA("RemoteEvent") then
		cachedDeathRemote = found
		return found
	end
	return nil
end

-- Out you go! (We don't wait for the server, so it feels instant.)
local function die()
	if deathSent then
		return
	end
	deathSent = true
	local hum = humanoid
	if hum then
		hum.Health = 0
	end
	local remote = deathRemote()
	if remote then
		remote:FireServer()
	end
end

------------------------------------------------------------------------
-- Sounds and sparkly bits (only built-in Roblox sounds, no uploads needed)
------------------------------------------------------------------------
local function makeSound(name: string, volume: number, speed: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = SWOOSH
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Parent = SoundService
	return sound
end

local bounceSound = makeSound("TowerBounceSound", 0.6, 0.8)
local doubleJumpSound = makeSound("TowerDoubleJumpSound", 0.4, 1.35)

local function playSound(sound: Sound)
	sound.TimePosition = 0
	sound:Play()
end

-- A quick puff of little blobs (used for melting ice cream and bouncy jelly).
local function burst(parent: Instance, color: Color3, count: number, speed: number, gravity: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.45, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.35, 0.7)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, -gravity, 0)
	emitter.Parent = parent
	emitter:Emit(count)
	Debris:AddItem(emitter, 1.5)
end

local function stopTweens(list: { Tween })
	for _, tween in ipairs(list) do
		tween:Cancel()
	end
	table.clear(list)
end

local function playTween(list: { Tween }, inst: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	local tween = TweenService:Create(inst, TweenInfo.new(seconds, style, direction), goal)
	table.insert(list, tween)
	tween:Play()
end

------------------------------------------------------------------------
-- MOVING THINGS (Spin / Move / Swing)
-- A "target" is the tagged part or group. We remember where the server put it
-- (its base pivot) and every frame work out where it should be right now.
------------------------------------------------------------------------
type Target = {
	Inst: Instance,
	Base: CFrame, -- where the server put it
	Cur: CFrame, -- where it is now
	Prev: CFrame, -- where it was one frame ago (to carry you along)
	Frame: number, -- the frame it last moved in
	Parts: { BasePart },
	PartBase: { CFrame }, -- where the server put each part
	Offsets: { CFrame }, -- each part compared to the pivot
	Slot: { [BasePart]: number },
	HasSpin: boolean,
	HasMove: boolean,
	HasSwing: boolean,
	Spin: boolean, -- tag there AND numbers ready
	SpinSpeed: number,
	SpinAxis: Vector3,
	Move: boolean,
	MoveOffset: Vector3,
	MovePeriod: number,
	MovePhase: number,
	Swing: boolean,
	SwingPivot: Vector3,
	SwingAxis: Vector3,
	SwingAngle: number,
	SwingPeriod: number,
	SwingPhase: number,
	Index: number, -- place in targetList
	Conns: { RBXScriptConnection },
}

local targetList: { Target } = {}
local targetOf: { [Instance]: Target } = {}
local ownerOf: { [BasePart]: Target } = {} -- which moving thing a part belongs to

local function addTargetPart(tg: Target, part: BasePart)
	if tg.Slot[part] then
		return
	end
	local other: Target? = targetOf[part]
	if other and other ~= tg then
		return -- this part moves on its own (groups must not be nested)
	end
	local i = #tg.Parts + 1
	tg.Parts[i] = part
	tg.PartBase[i] = part.CFrame -- a new part always arrives where the server put it
	tg.Offsets[i] = tg.Base:ToObjectSpace(part.CFrame)
	tg.Slot[part] = i
	ownerOf[part] = tg
end

local function removeTargetPart(tg: Target, part: BasePart)
	local i = tg.Slot[part]
	if not i then
		return
	end
	local last = #tg.Parts
	if i ~= last then
		local moved = tg.Parts[last]
		tg.Parts[i] = moved
		tg.PartBase[i] = tg.PartBase[last]
		tg.Offsets[i] = tg.Offsets[last]
		tg.Slot[moved] = i
	end
	table.remove(tg.Parts, last)
	table.remove(tg.PartBase, last)
	table.remove(tg.Offsets, last)
	tg.Slot[part] = nil
	if ownerOf[part] == tg then
		ownerOf[part] = nil
	end
end

local function createTarget(inst: Instance): Target?
	local part = asPart(inst)
	local model = asModel(inst)
	local base: CFrame
	if part then
		base = part.CFrame
	elseif model then
		base = cframeAttr(model, "GroupPivot") or model:GetPivot()
	else
		return nil
	end
	local tg: Target = {
		Inst = inst,
		Base = base,
		Cur = base,
		Prev = base,
		Frame = -10,
		Parts = {},
		PartBase = {},
		Offsets = {},
		Slot = {},
		HasSpin = false,
		HasMove = false,
		HasSwing = false,
		Spin = false,
		SpinSpeed = 0,
		SpinAxis = Vector3.yAxis,
		Move = false,
		MoveOffset = Vector3.zero,
		MovePeriod = 1,
		MovePhase = 0,
		Swing = false,
		SwingPivot = Vector3.zero,
		SwingAxis = Vector3.xAxis,
		SwingAngle = 0,
		SwingPeriod = 1,
		SwingPhase = 0,
		Index = #targetList + 1,
		Conns = {},
	}
	targetList[tg.Index] = tg
	targetOf[inst] = tg
	if part then
		addTargetPart(tg, part)
	elseif model then
		for _, d in ipairs(model:GetDescendants()) do
			local p = asPart(d)
			if p then
				addTargetPart(tg, p)
			end
		end
		-- parts of a group can stream in (and out) later
		table.insert(
			tg.Conns,
			model.DescendantAdded:Connect(function(d: Instance)
				local p = asPart(d)
				if p and targetOf[inst] == tg then
					addTargetPart(tg, p)
				end
			end)
		)
		table.insert(
			tg.Conns,
			model.DescendantRemoving:Connect(function(d: Instance)
				local p = asPart(d)
				if p then
					removeTargetPart(tg, p)
				end
			end)
		)
	end
	return tg
end

local function destroyTarget(tg: Target)
	for _, conn in ipairs(tg.Conns) do
		conn:Disconnect()
	end
	table.clear(tg.Conns)
	-- if only the tag was taken away, put the parts back where the server has them
	local stillHere = tg.Inst:IsDescendantOf(workspace)
	for i, part in ipairs(tg.Parts) do
		if ownerOf[part] == tg then
			ownerOf[part] = nil
		end
		if stillHere and part.Parent then
			part.CFrame = tg.PartBase[i]
		end
	end
	local index = tg.Index
	if targetList[index] == tg then
		local last = #targetList
		local moved = targetList[last]
		targetList[index] = moved
		moved.Index = index
		table.remove(targetList, last)
	end
	if targetOf[tg.Inst] == tg then
		targetOf[tg.Inst] = nil
	end
end

-- (Re)read the numbers the server wrote on the target.
local function readTarget(tg: Target)
	local inst = tg.Inst
	local model = asModel(inst)
	if model then
		local groupPivot = cframeAttr(model, "GroupPivot")
		if groupPivot and groupPivot ~= tg.Base then
			tg.Base = groupPivot
			for i, partBase in ipairs(tg.PartBase) do
				tg.Offsets[i] = groupPivot:ToObjectSpace(partBase)
			end
		end
	end

	local speed = numberAttr(inst, "SpinSpeed")
	tg.SpinSpeed = speed or 0
	tg.SpinAxis = directionAttr(inst, "SpinAxis") or Vector3.yAxis
	tg.Spin = tg.HasSpin and speed ~= nil and speed ~= 0

	local offset = vectorAttr(inst, "MoveOffset")
	local movePeriod = numberAttr(inst, "MovePeriod")
	tg.MoveOffset = offset or Vector3.zero
	tg.MovePeriod = if movePeriod and movePeriod > 0.05 then movePeriod else 1
	tg.MovePhase = numberAttr(inst, "MovePhase") or 0
	tg.Move = tg.HasMove and offset ~= nil and movePeriod ~= nil and movePeriod > 0.05

	local swingPivot = vectorAttr(inst, "SwingPivot")
	local swingAxis = directionAttr(inst, "SwingAxis")
	local swingAngle = numberAttr(inst, "SwingAngle")
	local swingPeriod = numberAttr(inst, "SwingPeriod")
	tg.SwingPivot = swingPivot or Vector3.zero
	tg.SwingAxis = swingAxis or Vector3.xAxis
	tg.SwingAngle = swingAngle or 0
	tg.SwingPeriod = if swingPeriod and swingPeriod > 0.05 then swingPeriod else 1
	tg.SwingPhase = numberAttr(inst, "SwingPhase") or 0
	tg.Swing = tg.HasSwing and swingPivot ~= nil and swingAxis ~= nil and swingAngle ~= nil and swingPeriod ~= nil and swingPeriod > 0.05
end

-- Switch Spin, Move or Swing on/off for a part or group.
local function setMotion(inst: Instance, kind: string, on: boolean)
	local tg: Target? = targetOf[inst]
	if tg == nil and on then
		tg = createTarget(inst)
	end
	if tg == nil then
		return
	end
	if kind == "Spin" then
		tg.HasSpin = on
	elseif kind == "Move" then
		tg.HasMove = on
	else
		tg.HasSwing = on
	end
	if tg.HasSpin or tg.HasMove or tg.HasSwing then
		readTarget(tg)
	else
		destroyTarget(tg)
	end
end

local function refreshMotion(inst: Instance)
	local tg: Target? = targetOf[inst]
	if tg then
		readTarget(tg)
	end
end

-- Where a target should be at server time t (docs/ARCHITECTURE.md part 9).
local function targetPose(tg: Target, t: number): CFrame
	local cf = tg.Base
	if tg.Spin then
		local degrees = (tg.SpinSpeed * t) % 360
		cf = CFrame.new(cf.Position) * CFrame.fromAxisAngle(tg.SpinAxis, math.rad(degrees)) * cf.Rotation
	end
	if tg.Swing then
		local f = loopFraction(t, tg.SwingPeriod, tg.SwingPhase)
		local angle = math.rad(tg.SwingAngle * math.sin(TWO_PI * f))
		local pivot = tg.SwingPivot
		cf = CFrame.new(pivot) * CFrame.fromAxisAngle(tg.SwingAxis, angle) * CFrame.new(-pivot) * cf
	end
	if tg.Move then
		local f = loopFraction(t, tg.MovePeriod, tg.MovePhase)
		cf = cf + tg.MoveOffset * (0.5 - 0.5 * math.cos(TWO_PI * f))
	end
	return cf
end

------------------------------------------------------------------------
-- DEADLY PARTS (Kill)
------------------------------------------------------------------------
type KillInfo = {
	Part: BasePart,
	Color: Color3,
	Pulse: boolean, -- does it gently glow? (only the normal deadly look does)
	Index: number,
}
local killInfo: { [BasePart]: KillInfo } = {}
local pulseList: { KillInfo } = {}

local function addKill(inst: Instance)
	local part = asPart(inst)
	if not part or killInfo[part] then
		return
	end
	local info: KillInfo = { Part = part, Color = part.Color, Pulse = false, Index = 0 }
	if part.Material == Enum.Material.Neon and sameColor(part.Color, DANGER) then
		info.Pulse = true
		table.insert(pulseList, info)
		info.Index = #pulseList
	end
	killInfo[part] = info
end

local function removeKill(inst: Instance)
	local part = asPart(inst)
	if not part then
		return
	end
	local info: KillInfo? = killInfo[part]
	if not info then
		return
	end
	killInfo[part] = nil
	if info.Pulse then
		local index = info.Index
		if pulseList[index] == info then
			local last = #pulseList
			local moved = pulseList[last]
			pulseList[index] = moved
			moved.Index = index
			table.remove(pulseList, last)
		end
		if part:IsDescendantOf(workspace) then
			part.Color = info.Color
		end
	end
end

------------------------------------------------------------------------
-- POPPING AND HEATING PARTS (Cycle)
--   Vanish: solid while on, gone while off (it flickers before it goes)
--   Hazard: deadly red while on (it blinks orange before it heats up)
------------------------------------------------------------------------
type CycleInfo = {
	Part: BasePart,
	Index: number,
	Ready: boolean, -- all the numbers have arrived
	Hazard: boolean,
	On: number,
	Off: number,
	Phase: number,
	BaseColor: Color3,
	Material: Enum.Material,
	Transparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
	Look: string, -- what it looks like right now
	Deadly: boolean,
}
local cycleInfo: { [BasePart]: CycleInfo } = {}
local cycleList: { CycleInfo } = {}

local function restoreCycle(c: CycleInfo)
	local part = c.Part
	part.Material = c.Material
	part.Color = c.BaseColor
	part.Transparency = c.Transparency
	part.CanQuery = c.CanQuery
	part.CanCollide = c.CanCollide
	c.Look = ""
	c.Deadly = false
end

local function applyCycleLook(c: CycleInfo, look: string)
	local part = c.Part
	if look == "hot" then
		part.Material = Enum.Material.Neon
		part.Color = DANGER
	elseif look == "warn" then
		part.Material = c.Material
		part.Color = WARNING
	elseif look == "cool" then
		part.Material = c.Material
		part.Color = c.BaseColor
	elseif look == "solid" or look == "flicker" then
		part.CanQuery = c.CanQuery
		part.CanCollide = c.CanCollide
		part.Transparency = if look == "flicker" then math.max(c.Transparency, 0.5) else c.Transparency
	else -- "gone" or "ghost" (a faint hint that it's coming back)
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = if look == "ghost" then math.max(c.Transparency, 0.8) else 1
	end
end

local function readCycle(c: CycleInfo)
	local part = c.Part
	local mode = part:GetAttribute("CycleMode")
	local on = numberAttr(part, "CycleOn")
	local off = numberAttr(part, "CycleOff")
	local hazard = mode == "Hazard"
	local ready = (mode == "Hazard" or mode == "Vanish") and on ~= nil and off ~= nil
	if c.Look ~= "" then
		restoreCycle(c) -- start again from the normal look
	end
	c.Hazard = hazard
	c.Ready = ready
	c.On = on or 0
	c.Off = off or 0
	c.Phase = numberAttr(part, "CyclePhase") or 0
	c.BaseColor = colorAttr(part, "BaseColor") or c.BaseColor
	if c.Look == "" then
		part.Color = c.BaseColor
	end
end

local function addCycle(inst: Instance)
	local part = asPart(inst)
	if not part or cycleInfo[part] then
		return
	end
	local c: CycleInfo = {
		Part = part,
		Index = #cycleList + 1,
		Ready = false,
		Hazard = false,
		On = 0,
		Off = 0,
		Phase = 0,
		BaseColor = colorAttr(part, "BaseColor") or part.Color,
		Material = part.Material,
		Transparency = part.Transparency,
		CanCollide = part.CanCollide,
		CanQuery = part.CanQuery,
		Look = "",
		Deadly = false,
	}
	cycleList[c.Index] = c
	cycleInfo[part] = c
	readCycle(c)
end

local function refreshCycle(inst: Instance)
	local part = asPart(inst)
	local c: CycleInfo? = part and cycleInfo[part]
	if c then
		readCycle(c)
	end
end

local function removeCycle(inst: Instance)
	local part = asPart(inst)
	if not part then
		return
	end
	local c: CycleInfo? = cycleInfo[part]
	if not c then
		return
	end
	cycleInfo[part] = nil
	local index = c.Index
	if cycleList[index] == c then
		local last = #cycleList
		local moved = cycleList[last]
		cycleList[index] = moved
		moved.Index = index
		table.remove(cycleList, last)
	end
	if part:IsDescendantOf(workspace) then
		restoreCycle(c)
	end
end

------------------------------------------------------------------------
-- MELTING PARTS (Melt) - only melts on YOUR screen, for you
------------------------------------------------------------------------
type MeltInfo = {
	Part: BasePart,
	Delay: number,
	Respawn: number,
	State: string, -- "solid", "melting" or "gone"
	Token: number, -- changes whenever plans are cancelled
	Transparency: number,
	CanCollide: boolean,
	Size: Vector3,
	Color: Color3,
	Tweens: { Tween },
}
local meltInfo: { [BasePart]: MeltInfo } = {}

local function readMelt(m: MeltInfo)
	m.Delay = math.clamp(numberAttr(m.Part, "MeltDelay") or 0.5, 0, 30)
	m.Respawn = math.clamp(numberAttr(m.Part, "MeltRespawn") or 3, 0.5, 120)
end

local function addMelt(inst: Instance)
	local part = asPart(inst)
	if not part or meltInfo[part] then
		return
	end
	local m: MeltInfo = {
		Part = part,
		Delay = 0.5,
		Respawn = 3,
		State = "solid",
		Token = 0,
		Transparency = part.Transparency,
		CanCollide = part.CanCollide,
		Size = part.Size,
		Color = part.Color,
		Tweens = {},
	}
	readMelt(m)
	meltInfo[part] = m
end

local function refreshMelt(inst: Instance)
	local part = asPart(inst)
	local m: MeltInfo? = part and meltInfo[part]
	if m then
		readMelt(m)
	end
end

local function removeMelt(inst: Instance)
	local part = asPart(inst)
	if not part then
		return
	end
	local m: MeltInfo? = meltInfo[part]
	if not m then
		return
	end
	meltInfo[part] = nil
	m.Token += 1 -- cancels anything still planned
	stopTweens(m.Tweens)
	if part:IsDescendantOf(workspace) then
		part.Size = m.Size
		part.Color = m.Color
		part.Transparency = m.Transparency
		part.CanCollide = m.CanCollide
	end
end

-- You stepped on it: it goes soft, melts away, then comes back later.
local function meltAway(m: MeltInfo)
	local part = m.Part
	m.State = "melting"
	m.Token += 1
	local token = m.Token
	playTween(m.Tweens, part, m.Delay, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, {
		Color = m.Color:Lerp(Color3.new(1, 1, 1), 0.4),
	})
	task.delay(m.Delay, function()
		if m.Token ~= token or meltInfo[part] ~= m then
			return
		end
		m.State = "gone"
		stopTweens(m.Tweens)
		part.CanCollide = false
		burst(part, m.Color, 12, 5, 40)
		playTween(m.Tweens, part, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
			Transparency = 1,
			Size = m.Size * 0.8,
		})
		task.delay(m.Respawn, function()
			if m.Token ~= token or meltInfo[part] ~= m then
				return
			end
			stopTweens(m.Tweens)
			part.Size = m.Size
			part.Color = m.Color
			part.CanCollide = m.CanCollide
			m.State = "solid"
			playTween(m.Tweens, part, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
				Transparency = m.Transparency,
			})
		end)
	end)
end

------------------------------------------------------------------------
-- BOUNCY PARTS (Bounce)
------------------------------------------------------------------------
type BounceInfo = {
	Part: BasePart,
	Power: number,
	Size: Vector3, -- its real size (we squash it for a moment when you bounce)
	Token: number,
	Tweens: { Tween },
}
local bounceInfo: { [BasePart]: BounceInfo } = {}

local function readBounce(b: BounceInfo)
	b.Power = math.clamp(numberAttr(b.Part, "BouncePower") or 80, 0, 500)
end

local function addBounce(inst: Instance)
	local part = asPart(inst)
	if not part or bounceInfo[part] then
		return
	end
	local b: BounceInfo = { Part = part, Power = 80, Size = part.Size, Token = 0, Tweens = {} }
	readBounce(b)
	bounceInfo[part] = b
end

local function refreshBounce(inst: Instance)
	local part = asPart(inst)
	local b: BounceInfo? = part and bounceInfo[part]
	if b then
		readBounce(b)
	end
end

local function removeBounce(inst: Instance)
	local part = asPart(inst)
	if not part then
		return
	end
	local b: BounceInfo? = bounceInfo[part]
	if not b then
		return
	end
	bounceInfo[part] = nil
	b.Token += 1
	stopTweens(b.Tweens)
	if part:IsDescendantOf(workspace) then
		part.Size = b.Size
	end
end

-- The size of the part while it's squashed: flatter along whichever of its
-- sides points up. Only the Size changes (never the position), so it can't
-- fight with the Spin/Move/Swing animation.
local function squashedSize(part: BasePart, size: Vector3): Vector3
	local cf = part.CFrame
	local upX, upY, upZ = math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y)
	if part:IsA("Part") then
		if part.Shape == Enum.PartType.Ball then
			return size * 0.85
		elseif part.Shape == Enum.PartType.Cylinder and upX < math.max(upY, upZ) then
			return Vector3.new(size.X, size.Y * 0.8, size.Z * 0.8) -- a log lying down
		end
	end
	if upX >= upY and upX >= upZ then
		return Vector3.new(size.X * 0.7, size.Y, size.Z)
	elseif upY >= upZ then
		return Vector3.new(size.X, size.Y * 0.7, size.Z)
	end
	return Vector3.new(size.X, size.Y, size.Z * 0.7)
end

local function squash(b: BounceInfo)
	local part = b.Part
	if part:IsA("TrussPart") then
		return -- ladders can only have certain sizes
	end
	b.Token += 1
	local token = b.Token
	stopTweens(b.Tweens)
	part.Size = b.Size
	playTween(b.Tweens, part, 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Size = squashedSize(part, b.Size) })
	task.delay(0.07, function()
		if b.Token ~= token then
			return
		end
		playTween(b.Tweens, part, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Size = b.Size })
		task.delay(0.32, function()
			if b.Token ~= token then
				return
			end
			stopTweens(b.Tweens)
			if part.Parent then
				part.Size = b.Size -- exactly the original size again
			end
		end)
	end)
end

-- BOING!
local function bounce(b: BounceInfo, now: number)
	local hum, root = humanoid, rootPart
	if not hum or not root or hum.Health <= 0 or b.Power <= 0 then
		return
	end
	if now - lastBounce < BOUNCE_COOLDOWN then
		return
	end
	local v = root.AssemblyLinearVelocity
	if v.Y > b.Power * 0.5 then
		return -- already flying up
	end
	lastBounce = now
	hum:ChangeState(Enum.HumanoidStateType.Freefall) -- let go of the ground
	root.AssemblyLinearVelocity = Vector3.new(v.X, b.Power, v.Z)
	squash(b)
	burst(b.Part, b.Part.Color, 8, 9, 30)
	playSound(bounceSound)
end

------------------------------------------------------------------------
-- CONVEYOR BELTS (Conveyor)
------------------------------------------------------------------------
local conveyors: { [BasePart]: Vector3 } = {}

local function addConveyor(inst: Instance)
	local part = asPart(inst)
	if not part then
		return
	end
	local velocity = vectorAttr(part, "ConveyorVelocity")
	if velocity then
		conveyors[part] = velocity
		part.AssemblyLinearVelocity = velocity
	end
end

local function removeConveyor(inst: Instance)
	local part = asPart(inst)
	if not part or not conveyors[part] then
		return
	end
	conveyors[part] = nil
	if part:IsDescendantOf(workspace) then
		part.AssemblyLinearVelocity = Vector3.zero
	end
end

------------------------------------------------------------------------
-- Keeping track of tags. Every tagged thing gets a "watch": we start a tag
-- only while the thing is inside workspace, and stop it when it leaves.
------------------------------------------------------------------------
type Handler = {
	Start: (Instance) -> (),
	Stop: (Instance) -> (),
	Refresh: ((Instance) -> ())?,
}

local HANDLERS: { [string]: Handler } = {
	Spin = {
		Start = function(inst: Instance)
			setMotion(inst, "Spin", true)
		end,
		Stop = function(inst: Instance)
			setMotion(inst, "Spin", false)
		end,
		Refresh = refreshMotion,
	},
	Move = {
		Start = function(inst: Instance)
			setMotion(inst, "Move", true)
		end,
		Stop = function(inst: Instance)
			setMotion(inst, "Move", false)
		end,
		Refresh = refreshMotion,
	},
	Swing = {
		Start = function(inst: Instance)
			setMotion(inst, "Swing", true)
		end,
		Stop = function(inst: Instance)
			setMotion(inst, "Swing", false)
		end,
		Refresh = refreshMotion,
	},
	Kill = { Start = addKill, Stop = removeKill },
	Cycle = { Start = addCycle, Stop = removeCycle, Refresh = refreshCycle },
	Melt = { Start = addMelt, Stop = removeMelt, Refresh = refreshMelt },
	Bounce = { Start = addBounce, Stop = removeBounce, Refresh = refreshBounce },
	Conveyor = { Start = addConveyor, Stop = removeConveyor, Refresh = addConveyor },
}

type Watch = {
	Tags: { [string]: boolean }, -- tags it has
	Active: { [string]: boolean }, -- tags we have started
	Conns: { RBXScriptConnection },
}
local watches: { [Instance]: Watch } = {}

local function sync(inst: Instance)
	local w: Watch? = watches[inst]
	if not w then
		return
	end
	local inWorld = inst:IsDescendantOf(workspace)
	for _, tag in ipairs(TAGS) do
		local want = inWorld and w.Tags[tag] == true
		local handler = HANDLERS[tag]
		if want and not w.Active[tag] then
			w.Active[tag] = true
			local ok: boolean, err: any = pcall(handler.Start, inst)
			if not ok then
				report(tag, err)
			end
		elseif not want and w.Active[tag] then
			w.Active[tag] = nil
			local ok: boolean, err: any = pcall(handler.Stop, inst)
			if not ok then
				report(tag, err)
			end
		end
	end
	if next(w.Tags) == nil then
		for _, conn in ipairs(w.Conns) do
			conn:Disconnect()
		end
		watches[inst] = nil
	end
end

-- The server changed a number on it (or it arrived late): read it again.
local function refreshWatch(inst: Instance)
	local w: Watch? = watches[inst]
	if not w then
		return
	end
	for _, tag in ipairs(TAGS) do
		local refresh = HANDLERS[tag].Refresh
		if refresh and w.Active[tag] then
			local ok: boolean, err: any = pcall(refresh, inst)
			if not ok then
				report(tag, err)
			end
		end
	end
end

local function getWatch(inst: Instance): Watch
	local existing: Watch? = watches[inst]
	if existing then
		return existing
	end
	local w: Watch = { Tags = {}, Active = {}, Conns = {} }
	watches[inst] = w
	table.insert(
		w.Conns,
		inst.AncestryChanged:Connect(function()
			sync(inst)
		end)
	)
	table.insert(
		w.Conns,
		inst.AttributeChanged:Connect(function()
			refreshWatch(inst)
		end)
	)
	return w
end

local function onTagAdded(tag: string, inst: Instance)
	getWatch(inst).Tags[tag] = true
	sync(inst)
end

local function onTagRemoved(tag: string, inst: Instance)
	local w: Watch? = watches[inst]
	if w then
		w.Tags[tag] = nil
		sync(inst)
	end
end

------------------------------------------------------------------------
-- EVERY FRAME (before physics, so the physics sees where things are)
------------------------------------------------------------------------
local frameNumber = 0
local frameTime = 0 -- the server clock
local frameClock = 0 -- os.clock()
local frameView = Vector3.zero -- where the camera is
local frameFloor: BasePart? = nil -- the tower part under your feet
local frameGap = math.huge -- how far above it your feet are
local frameCarrier: Target? = nil -- the moving thing you're standing on

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local lastPulse = 0
local lastConveyorCheck = 0

-- 1) What are you standing on? (checked before anything moves this frame)
local function stepFloor()
	frameFloor = nil
	frameGap = math.huge
	frameCarrier = nil
	local hum, root = humanoid, rootPart
	if not tower or not hum or not root or hum.Health <= 0 or not root.Parent then
		return
	end
	local feet = feetOffset(hum, root)
	local down = Vector3.new(0, -(feet + CARRY_REACH + 0.5), 0)
	-- straight down from your middle...
	local hit = workspace:Raycast(root.Position, down, floorParams)
	if not hit then
		-- ...or anywhere under your feet (standing right on the edge)
		local size = Vector3.new(math.max(root.Size.X - 0.2, 0.5), 0.2, math.max(root.Size.Z - 0.2, 0.5))
		hit = workspace:Blockcast(uprightCFrame(root), size, down, floorParams)
	end
	if hit then
		local part = hit.Instance
		frameFloor = part
		frameGap = (root.Position.Y - feet) - hit.Position.Y
		frameCarrier = ownerOf[part]
	end
end

local function bulkMove()
	workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- 2) Move every spinning / moving / swinging thing to where it should be now.
local function stepAnimate()
	local t = frameTime
	local view = frameView
	local carrier = frameCarrier
	table.clear(moveParts)
	table.clear(moveCFrames)
	local n = 0
	for i = 1, #targetList do
		local tg = targetList[i]
		if (tg.Spin or tg.Move or tg.Swing) and (tg == carrier or (tg.Base.Position - view).Magnitude < ANIMATE_DISTANCE) then
			local pose = targetPose(tg, t)
			-- first frame (or back from a nap): no jump, so it can't fling you
			tg.Prev = if tg.Frame == frameNumber - 1 then tg.Cur else pose
			tg.Cur = pose
			tg.Frame = frameNumber
			local parts, offsets = tg.Parts, tg.Offsets
			for j = 1, #parts do
				n += 1
				moveParts[n] = parts[j]
				moveCFrames[n] = pose * offsets[j]
			end
		end
	end
	if n > 0 and not pcall(bulkMove) then
		-- a part vanished this very moment: move them one at a time instead
		for j = 1, n do
			local part = moveParts[j]
			if part.Parent then
				part.CFrame = moveCFrames[j]
			end
		end
	end
end

-- 3) Ride along with the thing under your feet (it only turns you left/right,
--    so you always stay standing up).
local function stepCarry()
	local tg = frameCarrier
	local hum, root = humanoid, rootPart
	if not tg or not hum or not root or hum.Health <= 0 then
		return
	end
	if frameGap > CARRY_REACH or frameGap < -CARRY_REACH or tg.Frame ~= frameNumber then
		return
	end
	local delta = tg.Cur * tg.Prev:Inverse()
	local here = root.Position
	local there = delta * here
	local distance = (there - here).Magnitude
	local yaw = yawOf(delta)
	if distance > MAX_CARRY_STEP or (distance < 1e-5 and math.abs(yaw) < 1e-7) then
		return
	end
	root.CFrame = CFrame.new(there) * CFrame.Angles(0, yaw, 0) * root.CFrame.Rotation
end

-- 4) Popcorn pops, chips heat up (everyone sees the same timing).
local function stepCycles()
	local t = frameTime
	local blink = math.floor(frameClock * 8) % 2 == 0
	for i = 1, #cycleList do
		local c = cycleList[i]
		if c.Ready then
			local on, left = cycleState(c.On, c.Off, c.Phase, t)
			local warning = left <= WARN_TIME and blink
			local look
			if c.Hazard then
				look = if on then "hot" elseif warning then "warn" else "cool"
			elseif on then
				look = if warning then "flicker" else "solid"
			else
				look = if warning then "ghost" else "gone"
			end
			c.Deadly = c.Hazard and on
			if look ~= c.Look then
				c.Look = look
				applyCycleLook(c, look)
			end
		end
	end
end

-- 5) Melting ice cream and bouncy jelly under your feet.
local function stepTouch()
	local part = frameFloor
	if not part or frameGap > TOUCH_GAP then
		return
	end
	local m: MeltInfo? = meltInfo[part]
	if m and m.State == "solid" then
		meltAway(m)
	end
	local b: BounceInfo? = bounceInfo[part]
	if b then
		bounce(b, frameClock)
	end
end

local function isDeadly(part: BasePart): boolean
	if killInfo[part] then
		return true
	end
	local c: CycleInfo? = cycleInfo[part]
	return c ~= nil and c.Deadly
end

-- 6) Are you touching anything deadly? (Two boxes: your legs, and your body
--    with arms and head. They follow your body size.)
local function stepDeath()
	local hum, root = humanoid, rootPart
	if deathSent or not tower or not hum or not root or hum.Health <= 0 or not root.Parent then
		return
	end
	local feet = feetOffset(hum, root)
	local s = math.clamp(feet / 3, 0.4, 3) -- 1 for a normal sized character
	local base = uprightCFrame(root)
	local legsLow, legsHigh = -feet - FOOT_DIP, -1.0 * s
	local bodyLow, bodyHigh = -1.2 * s, 2.3 * s
	local legsCF = base * CFrame.new(0, (legsLow + legsHigh) / 2, 0)
	local legsHalf = Vector3.new(1.0 * s + BODY_PAD, (legsHigh - legsLow) / 2, 0.5 * s + BODY_PAD)
	local bodyCF = base * CFrame.new(0, (bodyLow + bodyHigh) / 2, 0)
	local bodyHalf = Vector3.new(2.0 * s + BODY_PAD, (bodyHigh - bodyLow) / 2, 0.6 * s + BODY_PAD)
	local allCF = base * CFrame.new(0, (legsLow + bodyHigh) / 2, 0)
	local allSize = Vector3.new(bodyHalf.X * 2, bodyHigh - legsLow, bodyHalf.Z * 2)
	for _, part in ipairs(workspace:GetPartBoundsInBox(allCF, allSize, touchParams)) do
		if isDeadly(part) and (partTouchesBox(part, legsCF, legsHalf) or partTouchesBox(part, bodyCF, bodyHalf)) then
			die()
			return
		end
	end
end

-- 7) Deadly parts near you glow a little, like they're hot.
local function stepPulse()
	if frameClock - lastPulse < 1 / 15 then
		return
	end
	lastPulse = frameClock
	local color = DANGER:Lerp(KILL_GLOW, 0.25 + 0.25 * math.sin(frameClock * 5))
	local view = frameView
	for i = 1, #pulseList do
		local part = pulseList[i].Part
		if not cycleInfo[part] and (part.Position - view).Magnitude < PULSE_DISTANCE then
			part.Color = color
		end
	end
end

-- 8) Keep the conveyor belts running (checked once a second).
local function stepConveyors()
	if frameClock - lastConveyorCheck < 1 then
		return
	end
	lastConveyorCheck = frameClock
	for part, velocity in pairs(conveyors) do
		if part.AssemblyLinearVelocity ~= velocity then
			part.AssemblyLinearVelocity = velocity
		end
	end
end

local function runStep(name: string, fn: () -> ())
	local ok: boolean, err: any = pcall(fn)
	if not ok then
		report(name, err)
	end
end

local function onFrame()
	frameNumber += 1
	frameTime = workspace:GetServerTimeNow()
	frameClock = os.clock()
	local camera = workspace.CurrentCamera
	if camera then
		frameView = camera.CFrame.Position
	end
	findTower()
	runStep("floor", stepFloor) -- what you stand on (before anything moves)
	runStep("animate", stepAnimate) -- move everything...
	runStep("carry", stepCarry) -- ...then carry you along with it
	runStep("cycle", stepCycles)
	runStep("touch", stepTouch)
	runStep("death", stepDeath)
	runStep("glow", stepPulse)
	runStep("conveyor", stepConveyors)
end

------------------------------------------------------------------------
-- DOUBLE JUMP (game pass: player attribute Pass_DoubleJump)
------------------------------------------------------------------------
local stateConn: RBXScriptConnection? = nil

local function makePuff(root: BasePart, feet: number): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "DoubleJumpPuff"
	attachment.Position = Vector3.new(0, -feet, 0)
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new(0.8, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.3, 0.5)
	emitter.Speed = NumberRange.new(8, 12)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(75, 75)
	emitter.Drag = 6
	emitter.Acceleration = Vector3.new(0, 6, 0)
	emitter.Parent = attachment
	return emitter
end

-- How fast a normal jump goes up (so the double jump is just as high).
local function jumpSpeed(hum: Humanoid): number
	local speed
	if hum.UseJumpPower then
		speed = hum.JumpPower
	else
		speed = math.sqrt(2 * workspace.Gravity * math.max(hum.JumpHeight, 0))
	end
	return math.clamp(speed, 35, 120)
end

local function hookHumanoid(hum: Humanoid, root: BasePart)
	local old = stateConn
	if old then
		old:Disconnect()
	end
	inAir = false
	doubleJumpUsed = false
	stateConn = hum.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			if not inAir then
				inAir = true
				airSince = os.clock()
			end
		elseif
			new == Enum.HumanoidStateType.Landed
			or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.RunningNoPhysics
			or new == Enum.HumanoidStateType.Climbing
			or new == Enum.HumanoidStateType.Swimming
			or new == Enum.HumanoidStateType.Seated
		then
			inAir = false
			doubleJumpUsed = false
		end
	end)
	local ok, emitter = pcall(makePuff, root, feetOffset(hum, root))
	puffEmitter = if ok then emitter else nil
end

local function onCharacterAdded(char: Model)
	character = char
	humanoid = nil
	rootPart = nil
	puffEmitter = nil
	deathSent = false
	inAir = false
	doubleJumpUsed = false
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 20)
		local root = char:WaitForChild("HumanoidRootPart", 20)
		if character ~= char then
			return -- you respawned again in the meantime
		end
		if hum and hum:IsA("Humanoid") and root and root:IsA("BasePart") then
			humanoid = hum
			rootPart = root
			hookHumanoid(hum, root)
		end
	end)
end

local function onJumpRequest()
	local now = os.clock()
	-- JumpRequest repeats while the button is held, so only a NEW press counts
	local fresh = now - lastJumpRequest > 0.09 or jumpReleasedAt > lastJumpRequest
	lastJumpRequest = now
	if not fresh or doubleJumpUsed or player:GetAttribute("Pass_DoubleJump") ~= true then
		return
	end
	local hum, root = humanoid, rootPart
	if not hum or not root or hum.Health <= 0 then
		return
	end
	local state = hum:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end
	if not inAir or now - airSince < DOUBLE_JUMP_DELAY then
		return
	end
	doubleJumpUsed = true
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, jumpSpeed(hum), v.Z)
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	local emitter = puffEmitter
	if emitter and emitter.Parent then
		emitter:Emit(14)
	end
	playSound(doubleJumpSound)
end

------------------------------------------------------------------------
-- START
------------------------------------------------------------------------
for _, tag in ipairs(TAGS) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
		onTagAdded(tag, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		onTagRemoved(tag, inst)
	end)
end
for _, tag in ipairs(TAGS) do
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		onTagAdded(tag, inst)
	end
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(function(char: Model)
	if character == char then
		character = nil
		humanoid = nil
		rootPart = nil
		puffEmitter = nil
	end
end)
local firstCharacter = player.Character
if firstCharacter then
	onCharacterAdded(firstCharacter)
end

UserInputService.JumpRequest:Connect(onJumpRequest)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		jumpReleasedAt = os.clock()
	end
end)

RunService.PreSimulation:Connect(onFrame)
