--[[
	TOWER OF FOOD - section library
	Where it goes: ServerScriptService  (type: ModuleScript, name: TowerSections)

	Every obby section of the tower lives in this file. Each section is built in
	local coordinates (origin = top-centre of the plate you start on) using the
	small "ctx" toolkit below, so sections can be stacked and rotated at random.
	See docs/ARCHITECTURE.md in the GitHub repo for the full rules.
]]

local CollectionService = game:GetService("CollectionService")

local TowerSections = {}

local Constants = {
	SHAFT_RADIUS = 26, -- inner face of the tower wall
	USABLE_RADIUS = 24, -- sections must stay inside this radius
	PLATE_RADIUS = 6, -- entry/exit plates (diameter 12)
	KEEP_OUT_RADIUS = 7.5, -- clear space above/below the plates
	TOWER_FLOOR_Y = 12, -- top of the tower floor = BaseY of section 1
	LOBBY_RADIUS = 52,
	LOBBY_CEILING_Y = 34,
	DANGER = Color3.fromRGB(255, 45, 45),
}
TowerSections.Constants = Constants

export type Theme = {
	Main: Color3,
	Accent: Color3,
	Dark: Color3,
	Light: Color3,
	Danger: Color3,
}

export type Opts = {
	Yaw: number?,
	Pitch: number?,
	Roll: number?,
	Color: Color3?,
	Material: Enum.Material?,
	Name: string?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance?,
	Thickness: number?,
	Reflectance: number?,
	Round: boolean?,
}

type CtxData = {
	Model: Model,
	Height: number,
	Origin: CFrame,
	Theme: Theme,
	Rng: Random,
	Name: string,
}

local Ctx = {}
Ctx.__index = Ctx

export type Ctx = typeof(setmetatable({} :: CtxData, Ctx))

export type SectionDef = {
	Name: string,
	Creator: string,
	Difficulty: number,
	Height: number,
	Colors: { Main: Color3, Accent: Color3 },
	Build: (ctx: Ctx) -> (),
}

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------
local function rad(degrees: number?): number
	return math.rad(degrees or 0)
end

-- Yaw around Y, then Pitch around the part's X, then Roll around its Z.
local function orient(opts: Opts?): CFrame
	if not opts then
		return CFrame.identity
	end
	return CFrame.Angles(0, rad(opts.Yaw), 0) * CFrame.Angles(rad(opts.Pitch), 0, 0) * CFrame.Angles(0, 0, rad(opts.Roll))
end

local function newPart(className: string, shape: Enum.PartType?): BasePart
	local part = Instance.new(className) :: BasePart
	if shape and part:IsA("Part") then
		part.Shape = shape
	end
	return part
end

local function finish(self: Ctx, part: BasePart, opts: Opts?): BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = (opts and opts.Material) or Enum.Material.SmoothPlastic
	part.Color = (opts and opts.Color) or self.Theme.Main
	if opts then
		if opts.Name then
			part.Name = opts.Name
		end
		if opts.Transparency then
			part.Transparency = opts.Transparency
		end
		if opts.CanCollide ~= nil then
			part.CanCollide = opts.CanCollide
		end
		if opts.Reflectance then
			part.Reflectance = opts.Reflectance
		end
	end
	part.Parent = (opts and opts.Parent) or self.Model
	return part
end

local function partsOf(target: Instance): { BasePart }
	if target:IsA("BasePart") then
		return { target }
	end
	local parts = {}
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function makeTheme(colors: { Main: Color3, Accent: Color3 }): Theme
	return {
		Main = colors.Main,
		Accent = colors.Accent,
		Dark = colors.Main:Lerp(Color3.new(0, 0, 0), 0.4),
		Light = colors.Main:Lerp(Color3.new(1, 1, 1), 0.5),
		Danger = Constants.DANGER,
	}
end

------------------------------------------------------------------------
-- Ctx: coordinates
------------------------------------------------------------------------
function Ctx.CF(self: Ctx, x: number, y: number, z: number, yaw: number?): CFrame
	return self.Origin * CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw), 0)
end

function Ctx.Pos(self: Ctx, x: number, y: number, z: number): Vector3
	return self.Origin:PointToWorldSpace(Vector3.new(x, y, z))
end

-- x = r*cos(angle), z = r*sin(angle)
function Ctx.Polar(_self: Ctx, radius: number, angleDeg: number): (number, number)
	local a = math.rad(angleDeg)
	return radius * math.cos(a), radius * math.sin(a)
end

------------------------------------------------------------------------
-- Ctx: shapes
------------------------------------------------------------------------
function Ctx.Block(self: Ctx, x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: Opts?): BasePart
	local part = newPart("Part")
	part.Size = Vector3.new(sx, sy, sz)
	part.CFrame = self:CF(x, y, z) * orient(opts)
	return finish(self, part, opts)
end

-- Block whose TOP surface is at local y.
function Ctx.Platform(self: Ctx, x: number, y: number, z: number, sx: number, sz: number, opts: Opts?): BasePart
	local thickness = (opts and opts.Thickness) or 1
	return self:Block(x, y - thickness / 2, z, sx, thickness, sz, opts)
end

-- Flat round disc whose TOP surface is at local y.
function Ctx.Disc(self: Ctx, x: number, y: number, z: number, diameter: number, opts: Opts?): BasePart
	local thickness = (opts and opts.Thickness) or 1
	local part = newPart("Part", Enum.PartType.Cylinder)
	part.Size = Vector3.new(thickness, diameter, diameter)
	part.CFrame = self:CF(x, y - thickness / 2, z) * orient(opts) * CFrame.Angles(0, 0, math.rad(90))
	return finish(self, part, opts)
end

function Ctx.Ball(self: Ctx, x: number, y: number, z: number, diameter: number, opts: Opts?): BasePart
	local part = newPart("Part", Enum.PartType.Ball)
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = self:CF(x, y, z) * orient(opts)
	return finish(self, part, opts)
end

-- Cylinder centred at the point; its length runs along local X (before Yaw/Pitch/Roll).
function Ctx.Cylinder(self: Ctx, x: number, y: number, z: number, length: number, diameter: number, opts: Opts?): BasePart
	local part = newPart("Part", Enum.PartType.Cylinder)
	part.Size = Vector3.new(length, diameter, diameter)
	part.CFrame = self:CF(x, y, z) * orient(opts)
	return finish(self, part, opts)
end

-- A plank (or rod with opts.Round) whose centre line runs from local point a to b.
function Ctx.Beam(self: Ctx, a: Vector3, b: Vector3, width: number, thickness: number, opts: Opts?): BasePart
	local wa = self.Origin:PointToWorldSpace(a)
	local wb = self.Origin:PointToWorldSpace(b)
	local length = (wb - wa).Magnitude
	local mid = (wa + wb) / 2
	local up = Vector3.yAxis
	if length > 0 and math.abs((wb - wa).Unit.Y) > 0.99 then
		up = self.Origin.RightVector
	end
	local look = CFrame.lookAt(mid, wb, up) * CFrame.Angles(0, 0, rad(opts and opts.Roll))
	local part
	if opts and opts.Round then
		part = newPart("Part", Enum.PartType.Cylinder)
		part.Size = Vector3.new(length, width, width)
		part.CFrame = look * CFrame.Angles(0, math.rad(90), 0)
	else
		part = newPart("Part")
		part.Size = Vector3.new(width, thickness, length)
		part.CFrame = look
	end
	return finish(self, part, opts)
end

function Ctx.Wedge(self: Ctx, x: number, y: number, z: number, sx: number, sy: number, sz: number, opts: Opts?): BasePart
	local part = newPart("WedgePart")
	part.Size = Vector3.new(sx, sy, sz)
	part.CFrame = self:CF(x, y, z) * orient(opts)
	return finish(self, part, opts)
end

-- Climbable truss ladder, 2 x height x 2, with its BOTTOM at local y.
function Ctx.Truss(self: Ctx, x: number, y: number, z: number, height: number, opts: Opts?): BasePart
	local h = math.max(2, math.ceil(height / 2) * 2)
	local part = newPart("TrussPart")
	part.Size = Vector3.new(2, h, 2)
	part.CFrame = self:CF(x, y + h / 2, z) * CFrame.Angles(0, rad(opts and opts.Yaw), 0)
	return finish(self, part, opts)
end

-- A Model whose pivot is the given local point. Use it as opts.Parent, then
-- animate the whole group with Spin/Move/Swing.
function Ctx.Group(self: Ctx, name: string, x: number, y: number, z: number): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("GroupPivot", self:CF(x, y, z))
	model.Parent = self.Model
	return model
end

------------------------------------------------------------------------
-- Ctx: behaviours (the TowerObstacles client script brings these to life)
------------------------------------------------------------------------
function Ctx.Kill(self: Ctx, target: Instance, keepLook: boolean?)
	for _, part in ipairs(partsOf(target)) do
		CollectionService:AddTag(part, "Kill")
		if not keepLook then
			part.Material = Enum.Material.Neon
			part.Color = self.Theme.Danger
		end
	end
end

function Ctx.Spin(self: Ctx, target: Instance, degPerSec: number, axis: Vector3?)
	CollectionService:AddTag(target, "Spin")
	target:SetAttribute("SpinSpeed", degPerSec)
	target:SetAttribute("SpinAxis", self.Origin:VectorToWorldSpace(axis or Vector3.yAxis).Unit)
end

function Ctx.Move(self: Ctx, target: Instance, offset: Vector3, period: number, phase: number?)
	CollectionService:AddTag(target, "Move")
	target:SetAttribute("MoveOffset", self.Origin:VectorToWorldSpace(offset))
	target:SetAttribute("MovePeriod", period)
	target:SetAttribute("MovePhase", phase or 0)
end

function Ctx.Swing(self: Ctx, target: Instance, pivot: Vector3, axis: Vector3, amplitudeDeg: number, period: number, phase: number?)
	CollectionService:AddTag(target, "Swing")
	target:SetAttribute("SwingPivot", self.Origin:PointToWorldSpace(pivot))
	target:SetAttribute("SwingAxis", self.Origin:VectorToWorldSpace(axis).Unit)
	target:SetAttribute("SwingAngle", amplitudeDeg)
	target:SetAttribute("SwingPeriod", period)
	target:SetAttribute("SwingPhase", phase or 0)
end

-- mode "Hazard": deadly while on.  mode "Vanish": solid while on, gone while off.
function Ctx.Cycle(_self: Ctx, part: BasePart, mode: string, onTime: number, offTime: number, phase: number?)
	assert(mode == "Hazard" or mode == "Vanish", "Cycle mode must be Hazard or Vanish")
	CollectionService:AddTag(part, "Cycle")
	part:SetAttribute("CycleMode", mode)
	part:SetAttribute("CycleOn", onTime)
	part:SetAttribute("CycleOff", offTime)
	part:SetAttribute("CyclePhase", phase or 0)
	part:SetAttribute("BaseColor", part.Color)
end

function Ctx.Melt(_self: Ctx, part: BasePart, delay: number?, respawn: number?)
	CollectionService:AddTag(part, "Melt")
	part:SetAttribute("MeltDelay", delay or 0.5)
	part:SetAttribute("MeltRespawn", respawn or 3)
end

function Ctx.Bounce(_self: Ctx, part: BasePart, power: number?)
	CollectionService:AddTag(part, "Bounce")
	part:SetAttribute("BouncePower", power or 80)
end

function Ctx.Conveyor(self: Ctx, part: BasePart, velocity: Vector3)
	local world = self.Origin:VectorToWorldSpace(velocity)
	CollectionService:AddTag(part, "Conveyor")
	part:SetAttribute("ConveyorVelocity", world)
	part.AssemblyLinearVelocity = world
end

function Ctx.Slippery(_self: Ctx, part: BasePart)
	part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0.5, 100, 1)
end

------------------------------------------------------------------------
-- Ctx: randomness
------------------------------------------------------------------------
function Ctx.Random(self: Ctx, min: number, max: number): number
	return self.Rng:NextNumber(min, max)
end

function Ctx.RandomInt(self: Ctx, min: number, max: number): number
	return self.Rng:NextInteger(min, max)
end

function Ctx.Chance(self: Ctx, p: number): boolean
	return self.Rng:NextNumber() < p
end

------------------------------------------------------------------------
-- SECTIONS  (each one: table.insert(Sections, { Name, Creator, ... }))
------------------------------------------------------------------------
local Sections: { SectionDef } = {}

-- >>> SECTIONS START
-- <<< SECTIONS END

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
TowerSections.List = Sections

function TowerSections.Build(def: SectionDef, params: { Parent: Instance, BaseY: number, Rotation: number, Seed: number }): (Model, Ctx)
	local model = Instance.new("Model")
	model.Name = "Section_" .. def.Name
	model.Parent = params.Parent

	local data: CtxData = {
		Model = model,
		Height = def.Height,
		Origin = CFrame.new(0, params.BaseY, 0) * CFrame.Angles(0, params.Rotation, 0),
		Theme = makeTheme(def.Colors),
		Rng = Random.new(params.Seed),
		Name = def.Name,
	}
	local ctx = setmetatable(data, Ctx)
	def.Build(ctx)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("Model") then
			local pivot = d:GetAttribute("GroupPivot")
			if typeof(pivot) == "CFrame" then
				d.WorldPivot = pivot
			end
		end
	end
	return model, ctx
end

return TowerSections
