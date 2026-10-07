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

-- ===== A.lua =====
-- Group A food sections: Nugget Steps, Ketchup Slide, Spinning Pizza, Hot Sauce Lava.
-- Everything is placed with "polar" spots: (radius from the middle, angle in degrees).
do
	-- ===== Little helpers shared by the 4 sections below =====

	-- A point that is "out" studs further from the middle and "side" studs sideways
	-- (counter-clockwise) from the spot (radius, angle).
	local function spot(radius: number, angle: number, out: number, side: number): (number, number)
		local a = math.rad(angle)
		local c, s = math.cos(a), math.sin(a)
		return (radius + out) * c - side * s, (radius + out) * s + side * c
	end

	-- Same idea, but starting from any point (x, z) and facing "angle".
	local function nudge(x: number, z: number, angle: number, out: number, side: number): (number, number)
		local a = math.rad(angle)
		local c, s = math.cos(a), math.sin(a)
		return x + out * c - side * s, z + out * s + side * c
	end

	-- A soft coloured glow inside a part.
	local function glow(part: BasePart, color: Color3, range: number, brightness: number)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = part
	end

	-- Spicy flames (no images needed, Fire is built into Roblox).
	local function flames(part: BasePart, size: number)
		local fire = Instance.new("Fire")
		fire.Size = size
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 70, 20)
		fire.SecondaryColor = Color3.fromRGB(255, 190, 40)
		fire.Parent = part
	end

	------------------------------------------------------------------
	-- 1. NUGGET STEPS (easy): crunchy nuggets and dip cups spiral up.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Nugget Steps",
		Creator = "Chef Nugget",
		Difficulty = 1,
		Height = 28,
		Colors = { Main = Color3.fromRGB(255, 204, 40), Accent = Color3.fromRGB(255, 240, 170) },
		Build = function(ctx: Ctx)
			local GOLDEN = Color3.fromRGB(214, 140, 52)
			local CRISPY = Color3.fromRGB(170, 98, 34)
			local CUP = Color3.fromRGB(246, 244, 236)
			local BBQ = Color3.fromRGB(105, 42, 24)
			local SWEET_SOUR = Color3.fromRGB(255, 122, 28)

			-- One chicken nugget: a crunchy block with round bumpy breading bits.
			-- top = the height you stand on, long = size going outwards, wide = size sideways.
			local function nugget(radius: number, angle: number, top: number, long: number, wide: number, twist: number, parent: Instance?)
				local x, z = ctx:Polar(radius, angle)
				local face = angle - twist
				local body = ctx:Platform(x, top, z, long, wide, {
					Yaw = -face,
					Thickness = 1.8,
					Color = GOLDEN,
					Material = Enum.Material.Sand,
					Name = "Nugget",
					Parent = parent,
				})
				-- crunchy bumps on the sides and the far end make it look like a real nugget
				for _, side in ipairs({ -1, 1 }) do
					local bx, bz = nudge(x, z, face, side * 0.6, side * (wide / 2))
					ctx:Ball(bx, top - 0.95, bz, 1.9, { Color = CRISPY, Material = Enum.Material.Sand, Name = "Breading", Parent = parent })
				end
				local ex, ez = nudge(x, z, face, long / 2, 0.4)
				ctx:Ball(ex, top - 1, ez, 1.8, { Color = CRISPY, Material = Enum.Material.Sand, Name = "Breading", Parent = parent })
				return body
			end

			-- A little paper cup full of dipping sauce (a safe resting spot).
			local function dipCup(radius: number, angle: number, top: number, sauce: Color3, name: string)
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top - 0.15, z, 6, { Thickness = 2.6, Color = CUP, Name = "DipCup" })
				local dip = ctx:Disc(x, top, z, 5.2, { Thickness = 0.5, Color = sauce, Reflectance = 0.1, Name = name })
				-- the peeled-back foil lid leaning on the far side
				local lx, lz = spot(radius, angle, 3.25, 0)
				ctx:Block(lx, top + 1.3, lz, 0.25, 3, 4.6, {
					Yaw = -angle,
					Roll = -20,
					Color = Color3.fromRGB(205, 205, 212),
					Material = Enum.Material.Foil,
					CanCollide = false,
					Name = "FoilLid",
				})
				glow(dip, sauce, 10, 0.6)
			end

			-- The climb: nuggets and dip cups spiral up around the tower.
			nugget(10.8, 0, 2.5, 4.6, 4.6, 0)
			nugget(14.5, 33, 5, 4.6, 4.8, 8)
			dipCup(17, 64, 7.5, BBQ, "BBQSauce")
			nugget(16, 95, 10, 5, 4.4, -6)
			nugget(13.5, 125, 12.5, 4.4, 4.6, 5)

			-- One slow sliding nugget (you can hop on it from either end).
			local sx, sz = ctx:Polar(14.8, 153)
			local slider = ctx:Group("SlidingNugget", sx, 14.5, sz)
			nugget(14.8, 153, 14.5, 4.4, 4.4, 0, slider)
			local ta = math.rad(153)
			ctx:Move(slider, Vector3.new(-math.sin(ta), 0, math.cos(ta)) * 3.5, 5, 0)

			nugget(15, 188, 17, 4.6, 4.6, -7)
			dipCup(17, 219, 19.5, SWEET_SOUR, "SweetSourSauce")
			nugget(15, 250, 22, 4.6, 4.6, 6)
			-- last nugget: jump from here onto the exit plate
			nugget(10.5, 283, 25, 4, 5, 0)

			-- Giant nugget box against the wall (decoration you can stand on).
			local boxAngle = 334
			local bx, bz = ctx:Polar(21, boxAngle)
			local box = ctx:Block(bx, 9, bz, 3.4, 10, 7, { Yaw = -boxAngle, Color = Color3.fromRGB(214, 38, 34), Name = "NuggetBox" })
			local fx, fz = spot(21, boxAngle, -1.75, 0)
			ctx:Block(fx, 9.6, fz, 0.2, 2.4, 7.05, {
				Yaw = -boxAngle,
				Color = Color3.fromRGB(255, 206, 40),
				CanCollide = false,
				Name = "BoxStripe",
			})
			ctx:Block(fx, 6.6, fz, 0.2, 0.8, 7.05, {
				Yaw = -boxAngle,
				Color = Color3.fromRGB(255, 255, 255),
				CanCollide = false,
				Name = "BoxStripe",
			})
			-- nuggets poking out of the box
			for i, side in ipairs({ -2.2, 0, 2.2 }) do
				local nx, nz = spot(21, boxAngle, (i - 2) * 0.4, side)
				ctx:Block(nx, 14.4, nz, 2.2, 1.6, 2, {
					Yaw = -boxAngle + i * 25,
					Pitch = (i - 2) * 14,
					Roll = 12,
					Color = GOLDEN,
					Material = Enum.Material.Sand,
					Name = "BoxNugget",
				})
			end
			glow(box, Color3.fromRGB(255, 200, 120), 14, 0.8)

			-- Chef Nugget's giant chef hat on the wall (decoration).
			local hatAngle = 70
			local hx, hz = ctx:Polar(20.5, hatAngle)
			local WHITE = Color3.fromRGB(250, 250, 250)
			ctx:Disc(hx, 22, hz, 4, { Thickness = 2, Color = WHITE, CanCollide = false, Name = "ChefHat" })
			for _, puff in ipairs({ { -1, 23.2, 2.8 }, { 1, 23.2, 2.8 }, { 0, 24.2, 3 } }) do
				local px, pz = spot(20.5, hatAngle, 0, puff[1])
				ctx:Ball(px, puff[2], pz, puff[3], { Color = WHITE, CanCollide = false, Name = "ChefHatPuff" })
			end
		end,
	})

	------------------------------------------------------------------
	-- 2. KETCHUP SLIDE (medium): slippery ketchup, a climb up a giant
	--    bottle, a big slide down, and a squirting ketchup stream.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Ketchup Slide",
		Creator = "Captain Ketchup",
		Difficulty = 2,
		Height = 32,
		Colors = { Main = Color3.fromRGB(200, 32, 28), Accent = Color3.fromRGB(255, 205, 50) },
		Build = function(ctx: Ctx)
			local KETCHUP = Color3.fromRGB(196, 22, 18)
			local MUSTARD = Color3.fromRGB(255, 200, 30)
			local WHITE = Color3.fromRGB(248, 248, 244)

			-- An upside-down squeeze bottle. You stand on its flat bottom (the top).
			local function bottle(radius: number, angle: number, top: number, body: number, width: number, color: Color3, capColor: Color3, labelColor: Color3)
				local x, z = ctx:Polar(radius, angle)
				local main = ctx:Disc(x, top, z, width, { Thickness = body, Color = color, Reflectance = 0.05, Name = "SauceBottle" })
				ctx:Disc(x, top - body * 0.3, z, width + 0.3, {
					Thickness = body * 0.4,
					Color = labelColor,
					CanCollide = false,
					Name = "Label",
				})
				ctx:Disc(x, top - body, z, width * 0.7, { Thickness = 1.2, Color = capColor, Name = "Cap" })
				ctx:Disc(x, top - body - 1.2, z, width * 0.3, { Thickness = 0.8, Color = color, Name = "Nozzle" })
				return main
			end

			-- A ketchup packet step (red with a white tear strip).
			local function packet(radius: number, angle: number, top: number, long: number, wide: number)
				local x, z = ctx:Polar(radius, angle)
				local p = ctx:Platform(x, top, z, long, wide, { Yaw = -angle, Thickness = 0.8, Color = KETCHUP, Name = "KetchupPacket" })
				local sx, sz = spot(radius, angle, 0, wide / 2 - 0.4)
				ctx:Platform(sx, top + 0.05, sz, long + 0.1, 0.7, {
					Yaw = -angle,
					Thickness = 0.85,
					Color = WHITE,
					CanCollide = false,
					Name = "TearStrip",
				})
				return p
			end

			-- A wiggly line of mustard (decoration only).
			local function drizzle(points: { Vector3 })
				for i = 1, #points - 1 do
					ctx:Beam(points[i], points[i + 1], 0.4, 0.4, {
						Round = true,
						Color = MUSTARD,
						CanCollide = false,
						Name = "MustardDrizzle",
					})
				end
			end

			local function at(radius: number, angle: number, y: number): Vector3
				local x, z = ctx:Polar(radius, angle)
				return Vector3.new(x, y, z)
			end

			-- 1) packet + two bottles to climb
			packet(10.5, 0, 3, 4, 5)
			bottle(14.5, 30, 6, 3.6, 5, KETCHUP, WHITE, WHITE)
			bottle(17, 59, 9, 4, 5, MUSTARD, KETCHUP, KETCHUP)

			-- 2) a slippery ketchup puddle on a plate (hot splat on the far edge!)
			local px, pz = ctx:Polar(16, 89)
			ctx:Disc(px, 11.3, pz, 7, { Thickness = 0.6, Color = WHITE, Name = "Plate" })
			local puddle = ctx:Disc(px, 11.5, pz, 5.6, { Thickness = 0.5, Color = KETCHUP, Reflectance = 0.15, Name = "KetchupPuddle" })
			ctx:Slippery(puddle)
			local hx, hz = spot(16, 89, 3, 0)
			local splat1 = ctx:Disc(hx, 11.65, hz, 2, { Thickness = 0.3, Name = "HotKetchup" })
			ctx:Kill(splat1)
			drizzle({ at(14, 83, 11.6), at(15.5, 96, 11.6), at(17, 83, 11.6), at(18, 94, 11.6) })

			-- 3) packets stuck to the side of a GIANT ketchup bottle
			packet(12, 115, 14.5, 4, 4)
			packet(12.5, 141, 17.5, 4, 4)
			local giant = bottle(18, 165, 20.5, 13, 8, KETCHUP, WHITE, WHITE)
			glow(giant, Color3.fromRGB(255, 120, 100), 16, 0.7)

			-- 4) THE KETCHUP SLIDE: zoom down from the bottle top (it is slippery!)
			local slideTop = at(16.8, 176, 20.5 - 0.4)
			local slideEnd = at(16.3, 207, 17.7 - 0.4)
			local slide = ctx:Beam(slideTop, slideEnd, 4, 0.8, { Color = KETCHUP, Reflectance = 0.12, Name = "KetchupSlide" })
			ctx:Slippery(slide)
			drizzle({ at(16.8, 178, 20.45), at(16.3, 205, 17.85) })

			-- landing plate: stop here, the stream ahead pushes you back!
			local lx, lz = ctx:Polar(16, 216)
			ctx:Disc(lx, 17.3, lz, 8, { Thickness = 0.8, Color = WHITE, Name = "LandingPlate" })
			drizzle({ at(13.5, 211, 17.4), at(16, 219, 17.4), at(18.5, 212, 17.4) })

			-- 5) squeeze-bottle stream: walk up it against the flow, or it carries
			--    you back down into the hot ketchup splat at the bottom
			local downstream = at(15, 231, 17.5 - 0.5)
			local upstream = at(15.8, 272, 19.5 - 0.5)
			local stream = ctx:Beam(downstream, upstream, 3.4, 1, { Color = KETCHUP, Reflectance = 0.1, Name = "KetchupStream" })
			local flow = (downstream - upstream).Unit
			ctx:Conveyor(stream, flow * 7)
			local lift = Vector3.new(0, 0.25, 0)
			local splat2 = ctx:Beam(downstream + lift, downstream - flow * 2.6 + lift, 3.7, 1, { Name = "HotKetchup" })
			ctx:Kill(splat2)
			-- the giant squeeze bottle lying down, squirting the stream
			local back = Vector3.new(-flow.X, 0, -flow.Z).Unit
			local nozzlePos = upstream + back * 1.2
			local capPos = upstream + back * 2.6
			local bodyPos = upstream + back * 5.2
			local yaw = math.deg(math.atan2(-back.Z, back.X))
			local bottleY = 19.7
			ctx:Cylinder(nozzlePos.X, bottleY, nozzlePos.Z, 1.6, 1.4, { Yaw = yaw, Color = KETCHUP, Name = "Nozzle" })
			ctx:Cylinder(capPos.X, bottleY, capPos.Z, 1.2, 2.8, { Yaw = yaw, Color = WHITE, Name = "Cap" })
			local lying = ctx:Cylinder(bodyPos.X, bottleY, bodyPos.Z, 4, 4.2, { Yaw = yaw, Color = KETCHUP, Reflectance = 0.05, Name = "SqueezeBottle" })
			ctx:Cylinder(bodyPos.X, bottleY, bodyPos.Z, 1.6, 4.5, { Yaw = yaw, Color = MUSTARD, CanCollide = false, Name = "Label" })
			glow(lying, Color3.fromRGB(255, 90, 70), 12, 0.6)

			-- a box of fries waiting for ketchup (decoration by the wall)
			local fryAngle = 300
			local fbx, fbz = ctx:Polar(21, fryAngle)
			ctx:Block(fbx, 5.5, fbz, 3, 5, 4.5, { Yaw = -fryAngle, Color = Color3.fromRGB(220, 30, 30), Name = "FryBox" })
			for i = 1, 5 do
				local fx, fz = spot(21, fryAngle, (i % 2) * 0.8 - 0.4, (i - 3) * 0.85)
				ctx:Block(fx, 8.4 + (i % 3) * 0.3, fz, 0.7, 4.4, 0.7, {
					Yaw = -fryAngle + i * 17,
					Pitch = (i - 3) * 4,
					Roll = (i % 2) * 12 - 6,
					Color = Color3.fromRGB(252, 212, 96),
					Name = "Fry",
				})
			end

			-- 6) two more bottles and a final packet
			bottle(12, 287, 22.5, 4, 5, KETCHUP, WHITE, MUSTARD)
			bottle(13.5, 314, 25.5, 4, 5, MUSTARD, KETCHUP, WHITE)
			-- last packet: jump from here onto the exit plate
			packet(10.5, 341, 28.5, 4, 5)
		end,
	})

	------------------------------------------------------------------
	-- 3. SPINNING PIZZA (medium): ride turning pizzas up the tower.
	--    Watch out for the pizza cutter sweeping across the middle one!
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Spinning Pizza",
		Creator = "Papa Pepperoni",
		Difficulty = 2,
		Height = 30,
		Colors = { Main = Color3.fromRGB(76, 168, 72), Accent = Color3.fromRGB(255, 214, 90) },
		Build = function(ctx: Ctx)
			local CRUST = Color3.fromRGB(214, 150, 70)
			local SAUCE = Color3.fromRGB(190, 40, 24)
			local CHEESE = Color3.fromRGB(255, 214, 96)
			local PEPPERONI = Color3.fromRGB(160, 30, 26)
			local CARDBOARD = Color3.fromRGB(198, 160, 112)

			-- A pizza box step (stack > 1 makes a little pile of boxes).
			local function pizzaBox(radius: number, angle: number, top: number, size: number, twist: number, stack: number)
				local x, z = ctx:Polar(radius, angle)
				for i = 1, stack do
					local t = top - (stack - i) * 1.2
					ctx:Platform(x, t, z, size, size, {
						Yaw = -angle + twist + (stack - i) * 10,
						Thickness = 1.2,
						Color = CARDBOARD,
						Material = Enum.Material.Cardboard,
						Name = "PizzaBox",
					})
				end
				-- red logo circle on the lid
				ctx:Disc(x, top + 0.05, z, size * 0.55, { Thickness = 0.1, Color = SAUCE, CanCollide = false, Name = "BoxLogo" })
			end

			-- A whole pizza that spins: crust, tomato sauce and melty cheese.
			-- It returns a "topping" function that puts toppings on this pizza.
			local function pizza(name: string, radius: number, angle: number, top: number, size: number, spin: number)
				local x, z = ctx:Polar(radius, angle)
				local group: Instance = ctx:Group(name, x, top, z)
				ctx:Disc(x, top - 0.2, z, size, { Thickness = 1, Color = CRUST, Material = Enum.Material.Sand, Parent = group, Name = "Crust" })
				ctx:Disc(x, top - 0.1, z, size - 1.2, { Thickness = 0.4, Color = SAUCE, Parent = group, Name = "Sauce" })
				ctx:Disc(x, top, z, size - 2.2, { Thickness = 0.4, Color = CHEESE, Parent = group, Name = "Cheese" })
				ctx:Spin(group, spin)
				-- topping(distance from the middle, angle, size, colour)
				return function(distance: number, toppingAngle: number, toppingSize: number, color: Color3)
					local tx, tz = nudge(x, z, toppingAngle, distance, 0)
					ctx:Disc(tx, top + 0.08, tz, toppingSize, {
						Thickness = 0.2,
						Color = color,
						CanCollide = false,
						Parent = group,
						Name = "Topping",
					})
				end
			end

			local GREEN = Color3.fromRGB(60, 160, 60)
			local OLIVE = Color3.fromRGB(35, 30, 35)
			local MUSHROOM = Color3.fromRGB(225, 210, 190)
			local BASIL = Color3.fromRGB(40, 130, 50)

			pizzaBox(10.5, 0, 3, 5, 0, 1)
			pizzaBox(14.5, 36, 6, 5, 6, 2)

			local pepperoni = pizza("PepperoniPizza", 15, 74, 9, 11, 18)
			pepperoni(2.4, 20, 1.7, PEPPERONI)
			pepperoni(3.2, 110, 1.7, PEPPERONI)
			pepperoni(2.2, 200, 1.7, PEPPERONI)
			pepperoni(3.3, 290, 1.7, PEPPERONI)
			pepperoni(0.6, 0, 1.5, PEPPERONI)

			pizzaBox(12.5, 113, 12, 4.6, -5, 1)

			-- the veggie pizza with the pizza cutter
			local cutterPizzaAngle = 156
			local cx, cz = ctx:Polar(15, cutterPizzaAngle)
			local cheeseTop = 15
			local cutterSize = 12.5
			local veggie = pizza("VeggiePizza", 15, cutterPizzaAngle, cheeseTop, cutterSize, 20)
			veggie(2.5, 30, 1.3, GREEN)
			veggie(3.6, 140, 1.3, GREEN)
			veggie(2.8, 250, 1.1, OLIVE)
			veggie(3.8, 320, 1.1, OLIVE)
			veggie(1.6, 190, 1.5, MUSHROOM)
			veggie(3.9, 75, 1.5, MUSHROOM)
			local cutter: Instance = ctx:Group("PizzaCutter", cx, cheeseTop, cz)
			ctx:Disc(cx, cheeseTop + 1.8, cz, 1.6, { Thickness = 1.5, Parent = cutter, Name = "CutterHub" })
			ctx:Block(cx, cheeseTop + 0.7, cz, cutterSize - 2.6, 0.7, 0.5, { Parent = cutter, Name = "CutterBlade" })
			for _, side in ipairs({ -1, 1 }) do
				ctx:Cylinder(cx + side * (cutterSize / 2 - 1.5), cheeseTop + 1.3, cz, 0.35, 2, {
					Yaw = 90,
					Parent = cutter,
					Name = "CutterWheel",
				})
			end
			ctx:Kill(cutter)
			ctx:Spin(cutter, -36)

			pizzaBox(12.5, 199, 18, 4.6, 7, 2)

			local supreme = pizza("SupremePizza", 15, 240, 21, 11, 30)
			supreme(2.6, 10, 1.7, PEPPERONI)
			supreme(3.3, 130, 1.7, PEPPERONI)
			supreme(2.5, 250, 1.7, PEPPERONI)
			supreme(1.2, 80, 1.0, BASIL)
			supreme(3.4, 300, 1.0, BASIL)

			pizzaBox(13, 282, 24, 4.6, -6, 2)
			-- last box: jump from here onto the exit plate
			pizzaBox(10.5, 318, 27, 4, 0, 1)

			-- A giant pizza slice hanging on the wall (decoration).
			local sliceAngle = 85
			local sliceR = 22.6
			for _, side in ipairs({ -1, 1 }) do
				local wx, wz = spot(sliceR, sliceAngle, 0, side * 1.75)
				ctx:Wedge(wx, 24, wz, 0.6, 7, 3.5, {
					Yaw = -sliceAngle,
					Pitch = if side > 0 then 180 else 0,
					Roll = if side > 0 then 0 else 180,
					Color = CHEESE,
					Name = "WallSlice",
				})
			end
			local crustX, crustZ = ctx:Polar(sliceR, sliceAngle)
			ctx:Cylinder(crustX, 27.6, crustZ, 7.8, 1.4, { Yaw = -sliceAngle - 90, Color = CRUST, Material = Enum.Material.Sand, Name = "WallSliceCrust" })
			for _, dot in ipairs({ { -1.2, 25.8 }, { 1.3, 25.4 }, { 0, 22.9 } }) do
				local dx, dz = spot(sliceR, sliceAngle, -0.35, dot[1])
				ctx:Cylinder(dx, dot[2], dz, 0.2, 1.5, { Yaw = -sliceAngle, Color = PEPPERONI, CanCollide = false, Name = "WallPepperoni" })
			end

			-- A brick pizza oven glowing near the wall (decoration).
			local ovenAngle = 200
			local ox, oz = ctx:Polar(21.5, ovenAngle)
			ctx:Block(ox, 4, oz, 3.5, 6, 7, { Yaw = -ovenAngle, Color = Color3.fromRGB(168, 78, 56), Material = Enum.Material.Brick, Name = "PizzaOven" })
			local mx, mz = spot(21.5, ovenAngle, -1.75, 0)
			local mouth = ctx:Block(mx, 3.4, mz, 0.2, 3, 4, { Yaw = -ovenAngle, Color = Color3.fromRGB(30, 18, 14), CanCollide = false, Name = "OvenMouth" })
			flames(mouth, 3)
			glow(mouth, Color3.fromRGB(255, 140, 50), 16, 1.2)
		end,
	})

	------------------------------------------------------------------
	-- 4. HOT SAUCE LAVA (hard): tortilla chips over bubbling hot sauce.
	--    Red-dusted chips heat up, and hot sauce drips on the cheese bridges.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Hot Sauce Lava",
		Creator = "Señor Spicy",
		Difficulty = 3,
		Height = 34,
		Colors = { Main = Color3.fromRGB(255, 118, 20), Accent = Color3.fromRGB(255, 196, 50) },
		Build = function(ctx: Ctx)
			local TORTILLA = Color3.fromRGB(234, 192, 104)
			local TOASTED = Color3.fromRGB(216, 164, 78)
			local SPICY = Color3.fromRGB(226, 120, 62)
			local NACHO = Color3.fromRGB(255, 184, 30)
			local BOTTLE = Color3.fromRGB(176, 18, 10)
			local CAP = Color3.fromRGB(40, 140, 60)

			-- A tortilla chip: a flat triangle (made of two wedges) with the
			-- wide side towards the middle and the tip pointing at the wall.
			local function chip(radius: number, angle: number, top: number, wide: number, long: number, tilt: number, color: Color3, name: string): { BasePart }
				local half = wide / 2
				local thick = 0.6
				local parts = {}
				for _, side in ipairs({ -1, 1 }) do
					local x, z = spot(radius, angle, 0, side * half / 2)
					local wedge = ctx:Wedge(x, top - thick / 2, z, thick, half, long, {
						Yaw = -angle - 90,
						Pitch = tilt,
						Roll = -90 * side,
						Color = color,
						Name = name,
					})
					table.insert(parts, wedge)
				end
				return parts
			end

			-- A chip dusted with chili: it heats up (deadly) every few seconds.
			local function hotChip(radius: number, angle: number, top: number, phase: number)
				for _, part in ipairs(chip(radius, angle, top, 6, 5, 4, SPICY, "SpicyChip")) do
					ctx:Cycle(part, "Hazard", 1.2, 3.6, phase)
				end
			end

			-- A pool of bubbling hot sauce (deadly).
			local function lavaPool(radius: number, angle: number, top: number, size: number)
				local x, z = ctx:Polar(radius, angle)
				local pool = ctx:Disc(x, top, z, size, { Thickness = 0.5, Name = "HotSauceLava" })
				ctx:Kill(pool)
				flames(pool, 3)
				glow(pool, Color3.fromRGB(255, 60, 30), 12, 0.6)
			end

			-- A narrow nacho-cheese beam between two chips.
			local function cheeseBeam(a: Vector3, b: Vector3): BasePart
				return ctx:Beam(a - Vector3.new(0, 0.35, 0), b - Vector3.new(0, 0.35, 0), 1.3, 0.7, {
					Color = NACHO,
					Reflectance = 0.08,
					Name = "NachoCheeseBeam",
				})
			end

			-- A hot sauce bottle pillar whose spout drips deadly sauce onto the
			-- middle of a cheese beam (the point "target", y = beam top there).
			local function dripBottle(target: Vector3, bottom: number, bodyHeight: number, period: number)
				local spoutTo = math.sqrt(target.X * target.X + target.Z * target.Z)
				local angle = math.deg(math.atan2(target.Z, target.X))
				local radius = 20.5
				local x, z = ctx:Polar(radius, angle)
				local bodyTop = bottom + bodyHeight
				ctx:Disc(x, bodyTop, z, 4, { Thickness = bodyHeight, Color = BOTTLE, Reflectance = 0.1, Name = "HotSauceBottle" })
				ctx:Disc(x, bottom + bodyHeight * 0.7, z, 4.3, {
					Thickness = bodyHeight * 0.4,
					Color = Color3.fromRGB(250, 240, 210),
					CanCollide = false,
					Name = "Label",
				})
				ctx:Disc(x, bodyTop + 2.5, z, 2.2, { Thickness = 2.5, Color = BOTTLE, Name = "Neck" })
				ctx:Disc(x, bodyTop + 4.5, z, 2.6, { Thickness = 2, Color = CAP, Name = "Cap" })
				local spoutY = bodyTop + 3.8
				local sx, sz = ctx:Polar((radius + spoutTo) / 2, angle)
				ctx:Cylinder(sx, spoutY, sz, radius - spoutTo, 1, { Yaw = -angle, Color = CAP, Name = "Spout" })
				-- the drip falls to the beam and bobs back up to the spout
				local dx, dz = ctx:Polar(spoutTo, angle)
				local startY = spoutY - 1.1
				local drip = ctx:Ball(dx, startY, dz, 1.2, { Name = "HotSauceDrip" })
				ctx:Kill(drip)
				ctx:Move(drip, Vector3.new(0, (target.Y + 0.65) - startY, 0), period, 0)
			end

			local function at(radius: number, angle: number, y: number): Vector3
				local x, z = ctx:Polar(radius, angle)
				return Vector3.new(x, y, z)
			end

			-- Two chili peppers stuck on the wall (decoration).
			for _, info in ipairs({ { 40, 25 }, { 170, 7 } }) do
				local chiliAngle, chiliY = info[1], info[2]
				local tilt = 25
				local cx, cz = ctx:Polar(22, chiliAngle)
				local a = math.rad(chiliAngle)
				local t = math.rad(tilt)
				local axis = Vector3.new(-math.sin(a) * math.cos(t), math.sin(t), math.cos(a) * math.cos(t))
				local centre = Vector3.new(cx, chiliY, cz)
				local tip = centre - axis * 2.1
				local stem = centre + axis * 2.5
				ctx:Cylinder(cx, chiliY, cz, 4, 1.4, {
					Yaw = -chiliAngle - 90,
					Roll = tilt,
					Color = Color3.fromRGB(205, 22, 18),
					CanCollide = false,
					Name = "ChiliPepper",
				})
				ctx:Ball(tip.X, tip.Y, tip.Z, 1.2, { Color = Color3.fromRGB(205, 22, 18), CanCollide = false, Name = "ChiliTip" })
				ctx:Cylinder(stem.X, stem.Y, stem.Z, 1.2, 0.5, {
					Yaw = -chiliAngle - 90,
					Roll = tilt,
					Color = Color3.fromRGB(60, 140, 50),
					CanCollide = false,
					Name = "ChiliStem",
				})
			end

			-- bubbling hot sauce under the climb
			lavaPool(15.5, 45, 0.5, 10)
			lavaPool(16, 126, 5.5, 10)
			lavaPool(16, 222, 13, 10)
			lavaPool(16, 285, 18.5, 10)

			-- 1) first chips
			chip(11.5, 0, 3.5, 6, 5, 4, TORTILLA, "TortillaChip")
			chip(14.5, 38, 7.5, 6, 5, -4, TOASTED, "TortillaChip")

			-- 2) cheese bridge with a dripping bottle
			local a1 = at(14, 41, 7.5)
			local b1 = at(14.5, 77, 8)
			cheeseBeam(a1, b1)
			chip(15, 80, 8, 6, 5, 5, TORTILLA, "TortillaChip")
			local mid1 = (a1 + b1) / 2
			dripBottle(mid1, 0.5, 13, 3.6)

			-- 3) spicy chips that heat up one after another (wait for the glow to stop!)
			hotChip(14, 103, 9.5, 0)
			hotChip(14.5, 126, 11, 1 / 3)
			hotChip(14, 149, 12.5, 2 / 3)
			-- broken chip crumbs behind the spicy chips: they never heat up,
			-- so hop onto one if your chip starts to glow!
			for i, crumbAngle in ipairs({ 103, 126, 149 }) do
				local kx, kz = ctx:Polar(19, crumbAngle)
				ctx:Platform(kx, 8.5 + i * 1.5, kz, 3, 3, {
					Yaw = -crumbAngle + 15 * i,
					Roll = 4,
					Thickness = 0.6,
					Color = TOASTED,
					Name = "ChipCrumb",
				})
			end
			chip(15, 172, 14, 6, 5, 4, TOASTED, "TortillaChip")

			-- 4) up to the second cheese bridge (it climbs a little)
			chip(12.5, 198, 18, 6, 5, -3, TORTILLA, "TortillaChip")
			local a2 = at(12.5, 204, 18)
			local b2 = at(14.5, 236, 19.5)
			cheeseBeam(a2, b2)
			chip(15, 240, 19.5, 6, 5, 4, TOASTED, "TortillaChip")
			dripBottle((a2 + b2) / 2, 13, 11.5, 3.6)

			-- 5) tilted chips up to the top
			chip(14, 270, 23.5, 5.5, 5, 7, TORTILLA, "TortillaChip")
			chip(14.5, 298, 27.5, 5.5, 5, -6, TOASTED, "TortillaChip")
			-- last chip: jump from here onto the exit plate
			chip(10.5, 326, 31, 6, 5, 0, TORTILLA, "TortillaChip")
		end,
	})
end

-- ===== B.lua =====
-- Group B food sections: Jelly Bounce, Noodle Swing, Burger Stack, Ice Cream Melt.
-- Everything is placed with "polar" spots: (distance from the middle of the tower, angle in degrees).
do
	-- ===== Little helpers shared by the 4 sections below =====

	-- The point at (radius, angle), pushed "out" studs away from the middle and
	-- "side" studs sideways (counter-clockwise, the way the climb goes).
	local function spot(radius: number, angle: number, out: number, side: number): (number, number)
		local a = math.rad(angle)
		local c, s = math.cos(a), math.sin(a)
		return (radius + out) * c - side * s, (radius + out) * s + side * c
	end

	-- An arrow (local direction) pointing away from the middle at an angle.
	local function outward(angle: number): Vector3
		local a = math.rad(angle)
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end

	-- A soft coloured glow inside a part.
	local function glow(part: BasePart, color: Color3, range: number, brightness: number)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = part
	end

	-- A little bit of twinkle (built into Roblox, no images needed).
	local function twinkle(part: BasePart, color: Color3)
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = color
		sparkles.Parent = part
	end

	------------------------------------------------------------------
	-- 1. JELLY BOUNCE (easy): wobbly see-through jellies throw you up
	--    to cream cakes, one level at a time.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Jelly Bounce",
		Creator = "Jiggly Jen",
		Difficulty = 1,
		Height = 36,
		Colors = { Main = Color3.fromRGB(240, 80, 170), Accent = Color3.fromRGB(255, 230, 245) },
		Build = function(ctx: Ctx)
			local CREAM = Color3.fromRGB(255, 250, 240)
			local SPONGE = Color3.fromRGB(240, 196, 120)
			local CUSTARD = Color3.fromRGB(255, 214, 90)
			local CHERRY = Color3.fromRGB(215, 20, 45)
			local PLATE = Color3.fromRGB(240, 244, 255)
			local STRAWBERRY = Color3.fromRGB(255, 55, 85)
			local LIME = Color3.fromRGB(110, 230, 70)
			local BLUEBERRY = Color3.fromRGB(70, 150, 255)
			local ORANGE = Color3.fromRGB(255, 150, 40)
			local GRAPE = Color3.fromRGB(170, 80, 255)
			local LEMON = Color3.fromRGB(255, 225, 60)
			local MARSH_PINK = Color3.fromRGB(255, 175, 210)
			local MARSH_WHITE = Color3.fromRGB(255, 246, 250)
			local GLASS = Enum.Material.Glass

			-- BOING! A see-through jelly on a plate that throws you high in the air.
			-- top = height of its top, power = how hard it throws (80 = about 16 studs up).
			local function bounceJelly(radius: number, angle: number, top: number, color: Color3, power: number, phase: number)
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top - 3, z, 6.6, { Thickness = 0.4, Color = PLATE, Name = "JellyPlate" })
				local jelly = ctx:Block(x, top - 1.5, z, 5.4, 3, 5.4, {
					Yaw = -angle,
					Color = color,
					Material = GLASS,
					Transparency = 0.25,
					Name = "BouncyJelly",
				})
				ctx:Bounce(jelly, power)
				-- jiggle jiggle: it rocks a tiny bit from side to side
				ctx:Swing(jelly, Vector3.new(x, top - 3, z), outward(angle), 5, 1.3, phase)
				glow(jelly, color, 12, 1.6)
			end

			-- A slice of sponge cake with jam inside and whipped cream on top (a safe spot).
			local function creamCake(radius: number, angle: number, top: number, size: number, jam: Color3)
				local x, z = ctx:Polar(radius, angle)
				ctx:Platform(x, top - 0.6, z, size, size, { Yaw = -angle, Thickness = 2.6, Color = SPONGE, Name = "SpongeCake" })
				ctx:Block(x, top - 1.9, z, size + 0.12, 0.5, size + 0.12, { Yaw = -angle, Color = jam, CanCollide = false, Name = "JamLayer" })
				ctx:Platform(x, top, z, size + 0.4, size + 0.4, { Yaw = -angle, Thickness = 0.6, Color = CREAM, Name = "WhippedCream" })
				-- a cream swirl with a cherry, on the outside edge (out of your way)
				local cx, cz = spot(radius, angle, size / 2 - 0.8, 0)
				ctx:Ball(cx, top + 0.5, cz, 1.8, { Color = CREAM, CanCollide = false, Name = "CreamSwirl" })
				ctx:Ball(cx, top + 1.55, cz, 1.1, { Color = CHERRY, CanCollide = false, Name = "Cherry" })
			end

			-- A fat marshmallow stepping stone.
			local function marshmallow(radius: number, angle: number, top: number, color: Color3)
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top, z, 4.2, { Thickness = 2.4, Color = color, Name = "Marshmallow" })
			end

			-- The last stop: a trifle (cream, jelly, sponge, custard) in a glass bowl.
			local function trifle(radius: number, angle: number, top: number)
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top, z, 6.6, { Thickness = 0.8, Color = CREAM, Name = "TrifleCream" })
				ctx:Disc(x, top - 0.8, z, 6.6, { Thickness = 1.1, Color = STRAWBERRY, Material = GLASS, Transparency = 0.2, Name = "TrifleJelly" })
				ctx:Disc(x, top - 1.9, z, 6.6, { Thickness = 1, Color = SPONGE, Name = "TrifleSponge" })
				ctx:Disc(x, top - 2.9, z, 6.2, { Thickness = 0.9, Color = CUSTARD, Name = "TrifleCustard" })
				ctx:Disc(x, top - 3.8, z, 2.2, { Thickness = 1.6, Color = PLATE, Material = GLASS, Transparency = 0.3, Name = "TrifleStem" })
				ctx:Disc(x, top - 5.4, z, 4.6, { Thickness = 0.4, Color = PLATE, Material = GLASS, Transparency = 0.3, Name = "TrifleFoot" })
				-- strawberries round the edge and a big cherry on the outside
				for i = 0, 2 do
					local sx, sz = spot(radius, angle, 2.4 * math.cos(math.rad(60 + i * 60)), 2.4 * math.sin(math.rad(60 + i * 60)))
					ctx:Ball(sx, top + 0.35, sz, 1.2, { Color = STRAWBERRY, CanCollide = false, Name = "Strawberry" })
				end
				local cx, cz = spot(radius, angle, 1.9, 0)
				ctx:Ball(cx, top + 0.6, cz, 2, { Color = CREAM, CanCollide = false, Name = "CreamSwirl" })
				local cherry = ctx:Ball(cx, top + 1.8, cz, 1.2, { Color = CHERRY, CanCollide = false, Name = "Cherry" })
				twinkle(cherry, Color3.fromRGB(255, 200, 230))
			end

			-- Decoration: a big wobbly jelly mould and glowing jelly cubes on the wall.
			local function jellyMould(radius: number, angle: number, color: Color3)
				local x, z = ctx:Polar(radius, angle)
				local base = ctx:Block(x, 1.6, z, 6, 3.2, 6, { Yaw = -angle, Color = color, Material = GLASS, Transparency = 0.3, CanCollide = false, Name = "JellyMould" })
				ctx:Block(x, 4.6, z, 4.4, 2.8, 4.4, { Yaw = 45 - angle, Color = color, Material = GLASS, Transparency = 0.3, CanCollide = false, Name = "JellyMould" })
				ctx:Block(x, 7.1, z, 3, 2.2, 3, { Yaw = -angle, Color = color, Material = GLASS, Transparency = 0.3, CanCollide = false, Name = "JellyMould" })
				ctx:Ball(x, 8.8, z, 2, { Color = CREAM, CanCollide = false, Name = "CreamSwirl" })
				ctx:Ball(x, 10.1, z, 1.2, { Color = CHERRY, CanCollide = false, Name = "Cherry" })
				glow(base, color, 14, 2)
			end
			-- Decoration: a giant see-through gummy bear stuck on the wall.
			local function gummyBear(angle: number, y: number, color: Color3)
				local function blob(out: number, side: number, up: number, d: number): BasePart
					local bx, bz = spot(21, angle, out, side)
					return ctx:Ball(bx, y + up, bz, d, { Color = color, Material = GLASS, Transparency = 0.3, CanCollide = false, Name = "GummyBear" })
				end
				local belly = blob(0, 0, 0, 4.2)
				blob(0, 0, 3.4, 3.2) -- head
				blob(0, -1.2, 4.9, 1.2) -- ears
				blob(0, 1.2, 4.9, 1.2)
				blob(-0.6, -2.1, 0.9, 1.5) -- arms
				blob(-0.6, 2.1, 0.9, 1.5)
				blob(-0.6, -1.3, -2, 1.8) -- feet
				blob(-0.6, 1.3, -2, 1.8)
				glow(belly, color, 12, 1.5)
			end
			local function wallJelly(angle: number, y: number, color: Color3)
				local x, z = ctx:Polar(21.6, angle)
				local cube = ctx:Block(x, y, z, 3.4, 3.4, 3.4, { Yaw = -angle, Color = color, Material = GLASS, Transparency = 0.3, CanCollide = false, Name = "WallJelly" })
				glow(cube, color, 10, 1.2)
			end

			-- The climb: bounce -> cake -> marshmallow -> bounce -> cake -> marshmallow -> bounce -> trifle -> exit
			bounceJelly(11.5, 0, 3.4, LIME, 80, 0)
			creamCake(15.5, 40, 13.5, 6, STRAWBERRY)
			marshmallow(15.5, 67, 14.5, MARSH_PINK)
			bounceJelly(16, 95, 13.5, BLUEBERRY, 80, 0.35)
			creamCake(15, 130, 23.5, 6, GRAPE)
			marshmallow(14.5, 157, 24.5, MARSH_WHITE)
			-- the last jelly is a bit softer so you land on the trifle, not on the ceiling
			bounceJelly(14, 186, 23.5, ORANGE, 68, 0.7)
			trifle(12, 226, 32.5)

			-- decoration on the free side of the tower
			jellyMould(19, 300, GRAPE)
			wallJelly(255, 11, LEMON)
			gummyBear(285, 19, STRAWBERRY)
			wallJelly(330, 29, LIME)
		end,
	})

	------------------------------------------------------------------
	-- 2. NOODLE SWING (medium): ramen bowls, plates of meatballs that
	--    swing on long noodles, and noodle tightropes.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Noodle Swing",
		Creator = "Noodle Ninja",
		Difficulty = 2,
		Height = 32,
		Colors = { Main = Color3.fromRGB(60, 130, 220), Accent = Color3.fromRGB(250, 215, 120) },
		Build = function(ctx: Ctx)
			local BOWL = Color3.fromRGB(205, 45, 40)
			local BOWL_DARK = Color3.fromRGB(120, 25, 25)
			local BROTH = Color3.fromRGB(222, 150, 70)
			local NOODLE = Color3.fromRGB(250, 222, 140)
			local EGG = Color3.fromRGB(255, 252, 240)
			local YOLK = Color3.fromRGB(255, 165, 30)
			local NORI = Color3.fromRGB(30, 60, 40)
			local FISHCAKE = Color3.fromRGB(255, 150, 185)
			local PLATE = Color3.fromRGB(245, 245, 250)
			local PLATE_RIM = Color3.fromRGB(50, 100, 200)
			local SAUCE = Color3.fromRGB(200, 40, 30)
			local MEATBALL = Color3.fromRGB(105, 58, 35)
			local CHOPSTICK = Color3.fromRGB(175, 115, 60)

			-- Steam rising from hot soup.
			local function steam(part: BasePart)
				local smoke = Instance.new("Smoke")
				smoke.Color = Color3.fromRGB(255, 255, 255)
				smoke.Opacity = 0.06
				smoke.RiseVelocity = 2
				smoke.Size = 1.5
				smoke.Parent = part
			end

			-- A ramen bowl: red bowl, golden broth (you stand on the broth), egg, seaweed, fish cake.
			-- fishSide: 0 = no fish cake, -1 / 1 = fish cake on the left / right (away from the noodle ropes).
			local function ramenBowl(radius: number, angle: number, top: number, size: number, egg: boolean, fishSide: number): BasePart
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top, z, size, { Thickness = 1.4, Color = BOWL, Name = "Bowl" })
				ctx:Disc(x, top - 1.4, z, size - 1.6, { Thickness = 1, Color = BOWL_DARK, Name = "BowlBase" })
				local broth = ctx:Disc(x, top + 0.08, z, size - 0.8, { Thickness = 0.3, Color = BROTH, Name = "Broth" })
				-- seaweed sheet sticking up at the back
				local nx, nz = spot(radius, angle, size / 2 - 0.6, -0.8)
				ctx:Block(nx, top + 0.9, nz, 0.2, 2.4, 2.2, { Yaw = -angle, Roll = -12, Color = NORI, CanCollide = false, Name = "Seaweed" })
				if egg then
					-- half a boiled egg
					local ex, ez = spot(radius, angle, size * 0.14, size * 0.18)
					ctx:Disc(ex, top + 0.35, ez, 1.9, { Thickness = 0.5, Color = EGG, CanCollide = false, Name = "Egg" })
					ctx:Ball(ex, top + 0.3, ez, 1, { Color = YOLK, CanCollide = false, Name = "Yolk" })
				end
				if fishSide ~= 0 then
					local fx, fz = spot(radius, angle, -size * 0.12, fishSide * size * 0.2)
					ctx:Disc(fx, top + 0.2, fz, 1.5, { Thickness = 0.14, Color = FISHCAKE, CanCollide = false, Name = "FishCake" })
				end
				return broth
			end

			-- A thick noodle stretched from one bowl to the next: walk across it!
			local function noodleRope(r1: number, a1: number, top1: number, r2: number, a2: number, top2: number)
				local x1, z1 = ctx:Polar(r1, a1)
				local x2, z2 = ctx:Polar(r2, a2)
				local dir = Vector3.new(x2 - x1, 0, z2 - z1).Unit
				local a = Vector3.new(x1, top1 - 0.6, z1) + dir * 2.4
				local b = Vector3.new(x2, top2 - 0.6, z2) - dir * 2.4
				ctx:Beam(a, b, 1.6, 1.6, { Round = true, Color = NOODLE, Name = "NoodleRope" })
			end

			-- A plate of meatballs hanging from two long noodles. It swings like a
			-- playground swing, sideways along the climb. Two chopsticks poking out of
			-- the wall hold the noodles up.
			local function noodleSwing(radius: number, angle: number, top: number, length: number, amp: number, period: number, phase: number)
				local x, z = ctx:Polar(radius, angle)
				local pivotY = top + length
				-- (typed as Instance so it fits in the opts table as Parent)
				local group: Instance = ctx:Group("NoodleSwing", x, pivotY, z)
				ctx:Disc(x, top, z, 6, { Thickness = 0.5, Color = PLATE, Name = "Plate", Parent = group })
				ctx:Disc(x, top - 0.3, z, 6.5, { Thickness = 0.3, Color = PLATE_RIM, Name = "PlateRim", Parent = group })
				ctx:Disc(x, top + 0.05, z, 3.4, { Thickness = 0.1, Color = SAUCE, CanCollide = false, Name = "TomatoSauce", Parent = group })
				for _, s in ipairs({ -1, 1 }) do
					local mx, mz = spot(radius, angle, s * 1.9, 0)
					ctx:Ball(mx, top + 0.55, mz, 1.5, { Color = MEATBALL, Material = Enum.Material.Slate, CanCollide = false, Name = "Meatball", Parent = group })
					local hx, hz = spot(radius, angle, s * 2.6, 0)
					ctx:Beam(Vector3.new(hx, top, hz), Vector3.new(hx, pivotY, hz), 0.45, 0.45, {
						Round = true,
						Color = NOODLE,
						CanCollide = false,
						Name = "HangingNoodle",
						Parent = group,
					})
				end
				ctx:Swing(group, Vector3.new(x, pivotY, z), outward(angle), amp, period, phase)
				local inner = radius - 3.4
				local len = 23.5 - inner
				for _, s in ipairs({ -1, 1 }) do
					local cx, cz = spot(inner + len / 2, angle, 0, s * 0.3)
					ctx:Cylinder(cx, pivotY + s * 0.15, cz, len, 0.5, { Yaw = -angle, Color = CHOPSTICK, CanCollide = false, Name = "Chopstick" })
				end
			end

			-- The climb
			steam(ramenBowl(12, 0, 3.5, 7.2, true, 0))
			noodleSwing(14, 50, 5.5, 11, 18, 5, 0)
			ramenBowl(13, 98, 8.5, 7.2, false, -1)
			noodleRope(13, 98, 8.5, 14, 160, 11.5)
			steam(ramenBowl(14, 160, 11.5, 7.2, true, 0))
			noodleSwing(14, 210, 14, 10, 20, 4.6, 0.35)
			ramenBowl(13, 258, 17, 7.2, false, -1)
			noodleSwing(14, 308, 19.6, 9, 20, 4.4, 0.7)
			ramenBowl(13, 356, 23.5, 7.2, true, 0)
			local finalTop = 28.5
			noodleRope(13, 356, 23.5, 12.5, 70, finalTop)

			-- The big last bowl, with chopsticks lifting up some noodles.
			local finalBroth = ramenBowl(12.5, 70, finalTop, 8, true, 1)
			steam(finalBroth)
			local function at(out: number, side: number, y: number): Vector3
				local px, pz = spot(12.5, 70, out, side)
				return Vector3.new(px, finalTop + y, pz)
			end
			for _, s in ipairs({ -1, 1 }) do
				ctx:Beam(at(1.6, s * 0.35, 2.3), at(6.8, s * 1.1, 3.1), 0.5, 0.5, { Round = true, Color = CHOPSTICK, CanCollide = false, Name = "Chopstick" })
			end
			for i = -1, 1 do
				ctx:Beam(at(1.7, i * 0.25, 2.2), at(1.2 + i * 0.5, i * 0.4, 0.1), 0.35, 0.35, { Round = true, Color = NOODLE, CanCollide = false, Name = "LiftedNoodle" })
			end
		end,
	})

	------------------------------------------------------------------
	-- 3. BURGER STACK (easy): hop across giant burgers, walk up spatulas,
	--    then climb the sesame ladder up the MEGA burger.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Burger Stack",
		Creator = "Big Bun Bob",
		Difficulty = 1,
		Height = 30,
		Colors = { Main = Color3.fromRGB(190, 115, 55), Accent = Color3.fromRGB(255, 205, 60) },
		Build = function(ctx: Ctx)
			local BUN = Color3.fromRGB(226, 152, 72)
			local BUN_TOP = Color3.fromRGB(212, 128, 50)
			local PATTY = Color3.fromRGB(96, 56, 32)
			local CHEESE = Color3.fromRGB(255, 200, 40)
			local LETTUCE = Color3.fromRGB(110, 200, 60)
			local TOMATO = Color3.fromRGB(225, 50, 40)
			local ONION = Color3.fromRGB(245, 230, 245)
			local SESAME = Color3.fromRGB(252, 240, 205)
			local FRY = Color3.fromRGB(255, 205, 70)
			local METAL = Color3.fromRGB(195, 200, 210)
			local HANDLE = Color3.fromRGB(35, 35, 40)

			-- How thick, how much wider than the bun, what colour and what name each layer is.
			local function layerInfo(kind: string): (number, number, Color3, string)
				if kind == "patty" then
					return 1.2, 0.4, PATTY, "Patty"
				elseif kind == "cheese" then
					return 0.25, 0, CHEESE, "Cheese"
				elseif kind == "lettuce" then
					return 0.35, 0.9, LETTUCE, "Lettuce"
				elseif kind == "tomato" then
					return 0.4, 0.3, TOMATO, "Tomato"
				elseif kind == "onion" then
					return 0.3, 0.1, ONION, "Onion"
				elseif kind == "midbun" then
					return 1.1, 0, BUN, "MiddleBun"
				elseif kind == "top" then
					return 1.5, 0, BUN_TOP, "TopBun"
				elseif kind == "dome" then
					return 1, -2.2, BUN_TOP, "BunDome"
				end
				return 1.6, 0, BUN, "BottomBun"
			end

			-- One giant burger, built from the bottom up. Returns the height of its top.
			-- squash < 1 makes the layers thinner (for a little slider burger).
			local function burger(radius: number, angle: number, base: number, d: number, layers: { string }, seeds: number, squash: number?): number
				local x, z = ctx:Polar(radius, angle)
				local y = base
				for _, kind in ipairs(layers) do
					local thick, extra, color, name = layerInfo(kind)
					thick *= squash or 1
					y += thick
					if kind == "cheese" then
						-- a square cheese slice, turned so its corners droop over the edge
						ctx:Platform(x, y, z, d * 0.8, d * 0.8, { Yaw = 20 - angle, Thickness = thick, Color = color, Name = name })
					else
						local mat = (kind == "lettuce") and Enum.Material.Grass or Enum.Material.SmoothPlastic
						ctx:Disc(x, y, z, d + extra, { Thickness = thick, Color = color, Material = mat, Name = name })
					end
				end
				-- sesame seeds on top
				local seedRing = (d - 2.2) * 0.3
				for i = 1, seeds do
					local a = (i - 1) * 360 / seeds + 15
					local sx, sz = spot(radius, angle, seedRing * math.cos(math.rad(a)), seedRing * math.sin(math.rad(a)))
					ctx:Block(sx, y + 0.06, sz, 0.7, 0.25, 0.4, { Yaw = a * 1.7, Color = SESAME, CanCollide = false, Name = "SesameSeed" })
				end
				return y
			end

			-- Crispy fries standing up as stilts under a burger.
			local function fryStilts(radius: number, angle: number, height: number, count: number)
				for i = 1, count do
					local a = (i - 1) * 360 / count + 30
					local fx, fz = spot(radius, angle, 2.4 * math.cos(math.rad(a)), 2.4 * math.sin(math.rad(a)))
					ctx:Block(fx, height / 2, fz, 0.9, height, 0.9, { Yaw = a, Color = FRY, Name = "Fry" })
				end
			end

			-- A giant metal spatula lying from the middle out to the wall. You walk on the
			-- blade (from rTip to rBase); the handle keeps going and pokes into the wall.
			local function spatula(angle: number, rTip: number, yTip: number, rBase: number, yBase: number)
				local function at(r: number, y: number): Vector3
					local px, pz = ctx:Polar(r, angle)
					return Vector3.new(px, y, pz)
				end
				local slope = (yBase - yTip) / (rBase - rTip)
				local T = 0.4
				ctx:Beam(at(rTip, yTip - T / 2), at(rBase, yBase - T / 2), 4, T, { Color = METAL, Material = Enum.Material.Metal, Name = "SpatulaBlade" })
				-- the slots in the blade
				for _, s in ipairs({ -0.9, 0.9 }) do
					local px1, pz1 = spot(rTip + 1.2, angle, 0, s)
					local px2, pz2 = spot(rBase - 1.2, angle, 0, s)
					ctx:Beam(
						Vector3.new(px1, yTip + slope * 1.2 + 0.02, pz1),
						Vector3.new(px2, yBase - slope * 1.2 + 0.02, pz2),
						0.45,
						0.05,
						{ Color = HANDLE, CanCollide = false, Name = "SpatulaSlot" }
					)
				end
				local rNeck = rBase + 1.4
				local yNeck = yBase + slope * 1.4
				ctx:Beam(at(rBase - 0.2, yBase - T / 2), at(rNeck, yNeck - T / 2), 1.2, T, { Color = METAL, Material = Enum.Material.Metal, Name = "SpatulaNeck" })
				ctx:Beam(at(rNeck - 0.2, yNeck - 0.45), at(23.4, yNeck + slope * (23.4 - rNeck) - 0.45), 0.9, 0.9, { Round = true, Color = HANDLE, Name = "SpatulaHandle" })
			end

			-- The climb
			-- 1) a little slider burger
			burger(11.5, 0, 0, 5, { "bun", "patty", "cheese", "top" }, 0, 0.65)
			-- 2) a cheeseburger with salad
			burger(15, 36, 0, 8, { "bun", "patty", "cheese", "lettuce", "tomato", "top", "dome" }, 3)
			-- 3) walk up the spatula ramp...
			spatula(68, 11.5, 10, 18.5, 7)
			-- 4) ...to a double cheeseburger standing on fries
			burger(12, 100, 4.25, 8, { "bun", "patty", "cheese", "lettuce", "patty", "cheese", "top", "dome" }, 2)
			fryStilts(12, 100, 4.25, 3)
			-- 5) a flat spatula bridge
			spatula(130, 11, 13.2, 18.5, 13.2)
			-- 6) another burger on fries, right next to the ladder
			local b3Top = burger(15, 157.5, 9.5, 8, { "bun", "patty", "cheese", "lettuce", "tomato", "top", "dome" }, 2)
			fryStilts(15, 157.5, 9.5, 3)
			-- 7) the MEGA burger on giant fries, with a sesame-seed ladder up its side
			local megaTop = burger(13.5, 200, 16, 10, {
				"bun", "patty", "cheese", "lettuce", "tomato", "patty", "cheese",
				"midbun", "patty", "cheese", "onion", "top", "dome",
			}, 4)
			fryStilts(13.5, 200, 16, 3)
			-- the ladder starts just under the top of burger 6, so you walk straight onto it
			local lx, lz = spot(13.5, 200, 0, -6.5)
			ctx:Truss(lx, b3Top - 1, lz, megaTop + 2 - b3Top, { Yaw = -200, Color = SESAME, Name = "SesameLadder" })
		end,
	})

	------------------------------------------------------------------
	-- 4. ICE CREAM MELT (medium): scoops melt away right after you land.
	--    Keep moving! Rest on the sundae halfway up.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Ice Cream Melt",
		Creator = "Sundae Sam",
		Difficulty = 2,
		Height = 30,
		Colors = { Main = Color3.fromRGB(110, 220, 185), Accent = Color3.fromRGB(255, 190, 220) },
		Build = function(ctx: Ctx)
			local WAFFLE = Color3.fromRGB(214, 160, 90)
			local WAFFLE_DARK = Color3.fromRGB(184, 124, 62)
			local VANILLA = Color3.fromRGB(255, 246, 220)
			local STRAWBERRY = Color3.fromRGB(255, 160, 190)
			local MINT = Color3.fromRGB(160, 240, 200)
			local CHOCOLATE = Color3.fromRGB(110, 65, 40)
			local BLUE_MOON = Color3.fromRGB(120, 180, 255)
			local CHERRY = Color3.fromRGB(215, 20, 45)
			local COOKIE = Color3.fromRGB(70, 42, 28)
			local GLASS_COLOR = Color3.fromRGB(220, 240, 255)
			local WAFFLE_MAT = Enum.Material.DiamondPlate
			local SPRINKLES = {
				Color3.fromRGB(255, 80, 150),
				Color3.fromRGB(255, 220, 60),
				Color3.fromRGB(80, 170, 255),
				Color3.fromRGB(120, 230, 90),
				Color3.fromRGB(190, 110, 255),
				Color3.fromRGB(255, 255, 255),
			}

			-- Rainbow sprinkles scattered on a top surface (just decoration).
			local function sprinkles(x: number, y: number, z: number, spread: number, count: number)
				for i = 1, count do
					local a = ctx:Random(0, 360)
					local r = ctx:Random(0.3, spread)
					local sx, sz = x + r * math.cos(math.rad(a)), z + r * math.sin(math.rad(a))
					ctx:Block(sx, y, sz, 0.7, 0.2, 0.2, {
						Yaw = ctx:Random(0, 180),
						Color = SPRINKLES[(i - 1) % #SPRINKLES + 1],
						CanCollide = false,
						Name = "Sprinkle",
					})
				end
			end

			-- A scoop of ice cream on a waffle cone. Step on it and it melts away! Keep moving.
			local function meltingScoop(radius: number, angle: number, top: number, d: number, flavour: Color3)
				local x, z = ctx:Polar(radius, angle)
				local cy = top - d / 2
				local scoop = ctx:Ball(x, cy, z, d, { Color = flavour, Name = "MeltingScoop" })
				ctx:Melt(scoop, 0.6, 3)
				-- the cone (you can't stand on it - it's only there to look yummy)
				local coneTop = cy - d * 0.3
				local widths = { 3.6, 2.6, 1.5 }
				for i, w in ipairs(widths) do
					local t = coneTop - (i - 1) * 1.3
					if t - 1.3 >= 0 then
						ctx:Disc(x, t, z, w, {
							Thickness = 1.3,
							Color = (i % 2 == 1) and WAFFLE or WAFFLE_DARK,
							Material = WAFFLE_MAT,
							CanCollide = false,
							Name = "WaffleCone",
						})
					end
				end
				-- a little drip running down the cone
				local dx, dz = spot(radius, angle, 0, -1.7)
				ctx:Ball(dx, coneTop - 0.5, dz, 0.8, { Color = flavour, CanCollide = false, Name = "Drip" })
			end

			-- A crunchy waffle ramp from one spot to another (top surface heights).
			local function waffleRamp(r1: number, a1: number, y1: number, r2: number, a2: number, y2: number)
				local x1, z1 = ctx:Polar(r1, a1)
				local x2, z2 = ctx:Polar(r2, a2)
				ctx:Beam(Vector3.new(x1, y1 - 0.4, z1), Vector3.new(x2, y2 - 0.4, z2), 4, 0.8, { Color = WAFFLE, Material = WAFFLE_MAT, Name = "WaffleRamp" })
			end

			-- The safe sundae in the middle of the climb.
			local function sundae(radius: number, angle: number, top: number)
				local x, z = ctx:Polar(radius, angle)
				local ice = ctx:Disc(x, top, z, 7.6, { Thickness = 0.8, Color = VANILLA, Name = "SundaeIceCream" })
				ctx:Disc(x, top - 0.4, z, 8.4, { Thickness = 2.2, Color = GLASS_COLOR, Material = Enum.Material.Glass, Transparency = 0.35, Name = "SundaeGlass" })
				ctx:Disc(x, top - 2.6, z, 1.6, { Thickness = 2.2, Color = GLASS_COLOR, Material = Enum.Material.Glass, Transparency = 0.35, Name = "SundaeStem" })
				ctx:Disc(x, top - 4.8, z, 5, { Thickness = 0.5, Color = GLASS_COLOR, Material = Enum.Material.Glass, Transparency = 0.35, Name = "SundaeFoot" })
				ctx:Disc(x, top + 0.05, z, 5, { Thickness = 0.1, Color = CHOCOLATE, CanCollide = false, Name = "ChocolateSauce" })
				-- three scoops at the back, cream and a cherry on top
				local flavours = { STRAWBERRY, MINT, CHOCOLATE }
				for i, f in ipairs(flavours) do
					local sx, sz = spot(radius, angle, 2.3, (i - 2) * 1.7)
					ctx:Ball(sx, top + 0.7, sz, 2.8, { Color = f, CanCollide = false, Name = "SundaeScoop" })
				end
				local cx, cz = spot(radius, angle, 2.1, 0)
				ctx:Ball(cx, top + 2.2, cz, 2, { Color = VANILLA, CanCollide = false, Name = "WhippedCream" })
				local cherry = ctx:Ball(cx, top + 3.4, cz, 1.1, { Color = CHERRY, CanCollide = false, Name = "Cherry" })
				twinkle(cherry, Color3.fromRGB(255, 220, 240))
				local wx, wz = spot(radius, angle, 2.8, 1.9)
				ctx:Block(wx, top + 1.6, wz, 0.5, 3.2, 1.2, { Yaw = -angle, Roll = -15, Color = WAFFLE, Material = WAFFLE_MAT, CanCollide = false, Name = "Wafer" })
				sprinkles(x, top + 0.12, z, 2.6, 6)
				glow(ice, Color3.fromRGB(255, 200, 230), 12, 1)
			end

			-- The last stop: a giant ice cream sandwich.
			local function iceCreamSandwich(radius: number, angle: number, top: number)
				local x, z = ctx:Polar(radius, angle)
				ctx:Platform(x, top, z, 5, 7, { Yaw = -angle, Thickness = 0.8, Color = COOKIE, Name = "Cookie" })
				ctx:Platform(x, top - 0.8, z, 4.7, 6.7, { Yaw = -angle, Thickness = 1.4, Color = VANILLA, Name = "VanillaFilling" })
				ctx:Platform(x, top - 2.2, z, 5, 7, { Yaw = -angle, Thickness = 0.8, Color = COOKIE, Name = "Cookie" })
				sprinkles(x, top + 0.07, z, 2.2, 6)
			end

			-- Decoration: a giant cone stuck on the wall.
			local function giantCone(angle: number)
				local x, z = ctx:Polar(20.5, angle)
				local widths = { 5, 4, 3, 2, 1 }
				for i, w in ipairs(widths) do
					ctx:Disc(x, 13 - (i - 1) * 2, z, w, {
						Thickness = 2,
						Color = (i % 2 == 1) and WAFFLE or WAFFLE_DARK,
						Material = WAFFLE_MAT,
						CanCollide = false,
						Name = "GiantCone",
					})
				end
				ctx:Ball(x, 14.6, z, 5.6, { Color = STRAWBERRY, CanCollide = false, Name = "GiantScoop" })
				ctx:Ball(x, 18.4, z, 4.4, { Color = MINT, CanCollide = false, Name = "GiantScoop" })
				local cherry = ctx:Ball(x, 21.2, z, 1.6, { Color = CHERRY, CanCollide = false, Name = "Cherry" })
				glow(cherry, Color3.fromRGB(255, 120, 160), 10, 1)
			end

			-- The climb
			local sx, sz = ctx:Polar(10.5, 0)
			ctx:Platform(sx, 2.5, sz, 4.5, 5, { Yaw = 0, Thickness = 1.2, Color = WAFFLE, Material = WAFFLE_MAT, Name = "WaferStep" })
			waffleRamp(12, 10, 2.5, 15, 44, 6.5)
			meltingScoop(15, 62, 9, 5.5, STRAWBERRY)
			meltingScoop(15.5, 87, 11.5, 5.5, MINT)
			meltingScoop(15, 112, 14, 5.5, BLUE_MOON)
			sundae(13.5, 143, 15.5)
			waffleRamp(13.5, 155, 15.5, 15, 187, 19.5)
			meltingScoop(15, 207, 22, 5.5, CHOCOLATE)
			meltingScoop(15.5, 232, 24.5, 5.5, STRAWBERRY)
			iceCreamSandwich(12, 262, 26.5)

			giantCone(320)
		end,
	})
end

-- ===== C.lua =====
-- Group C food sections: Popcorn Pop, Spaghetti Sweeper, Donut Drift, Sushi Conveyor.
-- Everything is placed with "polar" spots: (radius from the middle, angle in degrees).
-- A part with Yaw = -angle has its X size pointing out from the middle and its Z size going sideways.
do
	-- ===== Little helpers shared by the 4 sections below =====

	-- A point that is "out" studs further from the middle and "side" studs sideways
	-- (counter-clockwise) from the spot (radius, angle).
	local function spot(radius: number, angle: number, out: number, side: number): (number, number)
		local a = math.rad(angle)
		local c, s = math.cos(a), math.sin(a)
		return (radius + out) * c - side * s, (radius + out) * s + side * c
	end

	-- A local point (as a Vector3) at (radius, angle) and height y.
	local function polarV(radius: number, angle: number, y: number): Vector3
		local a = math.rad(angle)
		return Vector3.new(radius * math.cos(a), y, radius * math.sin(a))
	end

	-- The sideways (counter-clockwise) direction at an angle, as a flat Vector3.
	local function sideways(angle: number): Vector3
		local a = math.rad(angle)
		return Vector3.new(-math.sin(a), 0, math.cos(a))
	end

	-- A soft coloured glow inside a part.
	local function glow(part: BasePart, color: Color3, range: number, brightness: number)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = part
	end

	------------------------------------------------------------------
	-- 1. POPCORN POP (medium): popcorn pads pop away and come back,
	--    a giant striped bucket, a buttery treadmill and slippery butter.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Popcorn Pop",
		Creator = "Kernel Corn",
		Difficulty = 2,
		Height = 30,
		Colors = { Main = Color3.fromRGB(55, 50, 150), Accent = Color3.fromRGB(255, 214, 70) },
		Build = function(ctx: Ctx)
			local WHITE = Color3.fromRGB(255, 251, 240)
			local CREAM = Color3.fromRGB(250, 236, 192)
			local BUTTERY = Color3.fromRGB(255, 238, 160)
			local KERNEL = Color3.fromRGB(240, 180, 40)
			local HULL = Color3.fromRGB(196, 128, 40)
			local BUTTER = Color3.fromRGB(255, 221, 95)
			local RED = Color3.fromRGB(215, 35, 45)
			local METAL = Color3.fromRGB(190, 192, 200)

			-- One popcorn pad: a fluffy disc with popped puffs on its far side.
			-- It pops away and comes back: solid for 3 s, gone for 1.6 s.
			local function popcorn(radius: number, angle: number, top: number, name: string, phase: number)
				local x, z = ctx:Polar(radius, angle)
				local parts = {}
				table.insert(parts, ctx:Disc(x, top, z, 4.6, { Thickness = 1.2, Color = CREAM, Name = name }))
				local puffColors = { WHITE, BUTTERY, WHITE }
				local puffSizes = { 1.9, 2.2, 1.9 }
				for i, off in ipairs({ -55, 0, 55 }) do
					local ox, oz = ctx:Polar(1.85, angle + off)
					table.insert(parts, ctx:Ball(x + ox, top - 0.3, z + oz, puffSizes[i], { Color = puffColors[i], Name = "Puff" }))
				end
				-- a little golden hull left over from the kernel
				local hx, hz = ctx:Polar(1.2, angle + 25)
				table.insert(parts, ctx:Ball(x + hx, top - 0.1, z + hz, 0.9, { Color = HULL, Name = "Hull" }))
				for _, p in ipairs(parts) do
					ctx:Cycle(p, "Vanish", 3, 1.6, phase)
				end
			end

			-- Start: a tray of golden kernels (always solid).
			local sx, sz = ctx:Polar(10.5, 0)
			ctx:Platform(sx, 2.5, sz, 4.5, 5, { Color = KERNEL, Name = "KernelTray" })
			for i, side in ipairs({ -1.2, 1.3 }) do
				local kx, kz = spot(10.5, 0, 1.2 - i * 0.8, side)
				ctx:Ball(kx, 2.7, kz, 0.9, { Color = HULL, CanCollide = false, Name = "Kernel" })
			end

			-- Wave 1: three popcorn pads. Each one pops in a bit later than the one
			-- before, so you can hop along the wave (wait on the tray for the first).
			popcorn(13.5, 26, 5.5, "Popcorn1", 0)
			popcorn(15, 50, 8.5, "Popcorn2", 0.85)
			popcorn(14.5, 75, 11, "Popcorn3", 0.7)

			-- The giant red-and-white striped popcorn bucket (a safe rest on top).
			local bAngle, bRadius = 103, 17
			local bx, bz = ctx:Polar(bRadius, bAngle)
			ctx:Cylinder(bx, 8.8, bz, 9.6, 7.6, { Roll = 90, Color = WHITE, Name = "Bucket" })
			for k = 0, 5 do
				local a = bAngle + k * 60
				local ox, oz = ctx:Polar(3.85, a)
				ctx:Block(bx + ox, 8.8, bz + oz, 0.5, 9.6, 2, { Yaw = -a, Color = RED, Name = "BucketStripe" })
			end
			ctx:Disc(bx, 14, bz, 8.6, { Thickness = 0.8, Color = RED, Name = "BucketRim" })
			local layer = ctx:Disc(bx, 14.3, bz, 7.8, { Thickness = 0.5, Color = BUTTERY, Name = "BucketPopcorn" })
			glow(layer, Color3.fromRGB(255, 220, 140), 14, 0.8)
			-- a heap of popcorn spilling over the back of the bucket
			-- (out = distance from the bucket centre, turn = angle, y = height, size, color)
			local heap = {
				{ out = 2.6, turn = -70, y = 14.6, size = 2.4, color = WHITE },
				{ out = 2.7, turn = -25, y = 14.7, size = 2.6, color = CREAM },
				{ out = 2.7, turn = 20, y = 14.6, size = 2.4, color = WHITE },
				{ out = 2.6, turn = 65, y = 14.6, size = 2.3, color = BUTTERY },
				{ out = 1.7, turn = -45, y = 15.8, size = 2.2, color = WHITE },
				{ out = 1.7, turn = 35, y = 15.7, size = 2.2, color = WHITE },
			}
			for _, h in ipairs(heap) do
				local ox, oz = ctx:Polar(h.out, bAngle + h.turn)
				ctx:Ball(bx + ox, h.y, bz + oz, h.size, { Color = h.color, Name = "BucketPuff" })
			end

			-- The butter treadmill: it pushes you back toward the bucket, so keep running!
			local beltFrom = polarV(14.5, 125, 16.5)
			local beltTo = polarV(14.5, 175, 16.5)
			local belt = ctx:Beam(beltFrom, beltTo, 4, 1, { Color = BUTTER, Reflectance = 0.1, Name = "ButterBelt" })
			ctx:Conveyor(belt, (beltFrom - beltTo).Unit * 7)
			-- metal rollers across both ends of the belt
			local along = (beltTo - beltFrom).Unit
			local across = Vector3.new(-along.Z, 0, along.X)
			for _, p in ipairs({ beltFrom, beltTo }) do
				local c = p + Vector3.new(0, -0.2, 0)
				ctx:Beam(c - across * 2.1, c + across * 2.1, 1.3, 1.3, {
					Round = true,
					Color = METAL,
					Material = Enum.Material.Metal,
					CanCollide = false,
					Name = "Roller",
				})
			end

			-- Two slippery butter pats (zero grip - land in the middle!).
			local p1x, p1z = ctx:Polar(13, 195)
			local pat1 = ctx:Platform(p1x, 19.5, p1z, 5, 5, { Yaw = -195, Thickness = 1.5, Color = BUTTER, Reflectance = 0.15, Name = "ButterPat1" })
			ctx:Slippery(pat1)
			local kx, kz = spot(13, 195, 1.6, 1.2)
			ctx:Block(kx, 20.6, kz, 0.2, 2.2, 0.9, { Yaw = -195, Roll = 15, Color = METAL, Material = Enum.Material.Metal, CanCollide = false, Name = "ButterKnife" })
			local p2x, p2z = ctx:Polar(13.5, 223)
			local pat2 = ctx:Platform(p2x, 22.5, p2z, 4.5, 4.5, { Yaw = -223, Thickness = 1.5, Color = BUTTER, Reflectance = 0.15, Name = "ButterPat2" })
			ctx:Slippery(pat2)

			-- The popcorn pair: these two take turns, so one of them is always there.
			popcorn(10.5, 248, 25.5, "PopcornA", 0)
			popcorn(15.5, 248, 25.5, "PopcornB", 0.5)

			-- Last ledge: a striped popcorn carton next to the exit.
			local lAngle = 279
			local lx, lz = ctx:Polar(10, lAngle)
			ctx:Platform(lx, 27.5, lz, 4, 5, { Yaw = -lAngle, Thickness = 1.6, Color = RED, Name = "PopcornCarton" })
			for _, side in ipairs({ -1.3, 1.3 }) do
				local wx, wz = spot(10, lAngle, 0, side)
				ctx:Block(wx, 26.75, wz, 4.06, 1.6, 0.8, { Yaw = -lAngle, Color = WHITE, CanCollide = false, Name = "CartonStripe" })
			end
			for i, side in ipairs({ -1.2, 1.1 }) do
				local px, pz = spot(10, lAngle, 1.5, side)
				ctx:Ball(px, 27.6, pz, 1.9 + i * 0.2, { Color = (i == 1) and WHITE or BUTTERY, Name = "CartonPuff" })
			end

			-- Decoration: a popcorn machine against the wall.
			local mAngle, mRadius = 318, 20.5
			local mx, mz = ctx:Polar(mRadius, mAngle)
			ctx:Block(mx, 12, mz, 3, 3, 4, { Yaw = -mAngle, Color = RED, Name = "MachineBase" })
			local glass = ctx:Block(mx, 15.5, mz, 3, 4, 4, {
				Yaw = -mAngle,
				Color = Color3.fromRGB(200, 230, 255),
				Material = Enum.Material.Glass,
				Transparency = 0.55,
				Name = "MachineGlass",
			})
			glow(glass, Color3.fromRGB(255, 210, 120), 12, 1)
			ctx:Block(mx, 17.8, mz, 3.4, 0.6, 4.4, { Yaw = -mAngle, Color = RED, Name = "MachineRoof" })
			ctx:Cylinder(mx, 16.6, mz, 1.2, 1.4, { Roll = 90, Color = METAL, Material = Enum.Material.Metal, CanCollide = false, Name = "Kettle" })
			for i, side in ipairs({ -1, 0.1, 1.1 }) do
				local px, pz = spot(mRadius, mAngle, (i - 2) * 0.5, side)
				ctx:Ball(px, 14.1, pz, 1.1, { Color = (i == 2) and BUTTERY or WHITE, CanCollide = false, Name = "MachinePopcorn" })
			end

			-- Decoration: popcorn puffs bobbing up and down near the walls.
			local floaters = { { 150, 7 }, { 215, 13 }, { 300, 21 }, { 35, 25 } }
			for i, f in ipairs(floaters) do
				local fx, fz = ctx:Polar(21.5, f[1])
				local puff = ctx:Ball(fx, f[2], fz, 1.6, { Color = (i % 2 == 0) and BUTTERY or WHITE, CanCollide = false, Name = "FlyingPopcorn" })
				ctx:Move(puff, Vector3.new(0, 2, 0), 3.5, i * 0.25)
			end
		end,
	})

	------------------------------------------------------------------
	-- 2. SPAGHETTI SWEEPER (medium): three floors of spaghetti plates,
	--    each with a spinning hot-sauce noodle sweeper to jump over.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Spaghetti Sweeper",
		Creator = "Mama Meatball",
		Difficulty = 2,
		Height = 32,
		Colors = { Main = Color3.fromRGB(150, 200, 50), Accent = Color3.fromRGB(250, 214, 120) },
		Build = function(ctx: Ctx)
			local PLATE = Color3.fromRGB(246, 246, 240)
			local PASTA = Color3.fromRGB(244, 204, 110)
			local SAUCE = Color3.fromRGB(165, 45, 25)
			local MEATBALL = Color3.fromRGB(110, 62, 38)
			local CRUST = Color3.fromRGB(205, 145, 65)
			local GARLIC = Color3.fromRGB(238, 222, 140)
			local CHEESE = Color3.fromRGB(246, 234, 182)
			local RIND = Color3.fromRGB(225, 190, 105)
			local SILVER = Color3.fromRGB(200, 202, 210)

			-- One dinner plate with a nest of spaghetti and a spoon of sauce.
			-- top = the height of the spaghetti you stand on.
			local function plate(radius: number, angle: number, top: number, name: string)
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top - 0.3, z, 7.6, { Thickness = 0.6, Color = PLATE, Name = name .. "Plate" })
				ctx:Disc(x, top, z, 6, { Thickness = 0.5, Color = PASTA, Name = name .. "Spaghetti" })
				ctx:Disc(x, top + 0.08, z, 2.8, { Thickness = 0.2, Color = SAUCE, CanCollide = false, Name = "Sauce" })
			end

			-- A spinning sweeper: a hot-sauce noodle with a hot meatball on the end.
			-- It spins around the middle of the tower; jump over it when it comes!
			-- floor = height of the spaghetti it sweeps over, fromR = where the noodle starts.
			local function sweeper(name: string, floor: number, fromR: number, startAngle: number, speed: number, hub: boolean)
				local y = floor + 1.1
				local group: Instance = ctx:Group(name, 0, y, 0)
				local toR = 16
				local mx, mz = ctx:Polar((fromR + toR) / 2, startAngle)
				local noodle = ctx:Cylinder(mx, y, mz, toR - fromR, 0.9, { Yaw = -startAngle, Name = name .. "Noodle", Parent = group })
				local bx, bz = ctx:Polar(15.2, startAngle)
				local ball = ctx:Ball(bx, floor + 1.2, bz, 2.2, { Name = name .. "Meatball", Parent = group })
				ctx:Kill(noodle)
				ctx:Kill(ball)
				glow(ball, Color3.fromRGB(255, 80, 60), 8, 1)
				if hub then
					local center = ctx:Ball(0, y, 0, 3.4, { Color = MEATBALL, CanCollide = false, Name = "MeatballHub", Parent = group })
					glow(center, Color3.fromRGB(255, 200, 150), 12, 0.8)
				end
				ctx:Spin(group, speed)
			end

			-- Garlic bread step (crust + garlic butter on top).
			local function garlicBread(radius: number, angle: number, top: number)
				local x, z = ctx:Polar(radius, angle)
				ctx:Platform(x, top - 0.15, z, 4, 4.6, { Yaw = -angle, Thickness = 1.2, Color = CRUST, Material = Enum.Material.Sand, Name = "GarlicBread" })
				ctx:Platform(x, top, z, 3.3, 3.9, { Yaw = -angle, Thickness = 0.3, Color = GARLIC, Name = "GarlicButter" })
			end

			-- Parmesan cheese step (with a darker rind on the wall side).
			local function parmesan(radius: number, angle: number, top: number)
				local x, z = ctx:Polar(radius, angle)
				ctx:Platform(x, top, z, 4, 4.6, { Yaw = -angle, Thickness = 1.4, Color = CHEESE, Material = Enum.Material.Sand, Name = "Parmesan" })
				local rx, rz = spot(radius, angle, 2.1, 0)
				ctx:Block(rx, top - 0.7, rz, 0.3, 1.45, 4.65, { Yaw = -angle, Color = RIND, CanCollide = false, Name = "Rind" })
			end

			-- Floor 1 (low): four plates. Its sweeper floats (nothing may be near the
			-- middle just above the start plate).
			for i = 0, 3 do
				plate(13, i * 43.5, 3.5, "Floor1_")
			end
			sweeper("Sweeper1", 3.5, 8, 0, 40, false)

			-- Garlic bread steps up to floor 2.
			garlicBread(20, 156, 7)
			garlicBread(20, 176, 10.5)

			-- Floor 2 (middle): five plates and a big meatball hub in the middle.
			for i = 0, 4 do
				plate(13.5, 198 + i * 43.5, 14, "Floor2_")
			end
			sweeper("Sweeper2", 14, 0, 120, -50, true)

			-- Parmesan steps up to floor 3.
			parmesan(20, 38, 17.6)
			parmesan(20, 58, 21.2)
			parmesan(20, 78, 24.8)

			-- Floor 3 (top): three plates right next to the exit, with a floating sweeper.
			for i = 0, 2 do
				plate(12.5, 100 + i * 43.5, 28.4, "Floor3_")
			end
			sweeper("Sweeper3", 28.4, 8, 240, 55, false)

			-- Decoration: a giant fork with a twirl of spaghetti on the wall.
			local fAngle, fRadius = 300, 21.5
			local fx, fz = ctx:Polar(fRadius, fAngle)
			local forkLook = { Yaw = -fAngle, Color = SILVER, Material = Enum.Material.Metal, CanCollide = false, Name = "Fork" }
			ctx:Block(fx, 20.5, fz, 0.5, 9, 1, forkLook)
			ctx:Block(fx, 25.6, fz, 0.5, 1.2, 3, forkLook)
			for _, side in ipairs({ -1.2, -0.4, 0.4, 1.2 }) do
				local tx, tz = spot(fRadius, fAngle, 0, side)
				ctx:Block(tx, 27.8, tz, 0.4, 3.2, 0.35, forkLook)
			end
			local twx, twz = spot(fRadius, fAngle, -0.3, 0)
			ctx:Ball(twx, 27.6, twz, 3.4, { Color = PASTA, CanCollide = false, Name = "SpaghettiTwirl" })
			local mbx, mbz = spot(fRadius, fAngle, -0.9, 0.9)
			ctx:Ball(mbx, 29.1, mbz, 1.6, { Color = MEATBALL, CanCollide = false, Name = "ForkMeatball" })
		end,
	})

	------------------------------------------------------------------
	-- 3. DONUT DRIFT (easy): frosted donuts drift slowly back and forth.
	--    Hop on when the next donut comes close. Coffee cups to rest on.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Donut Drift",
		Creator = "Glazed Gary",
		Difficulty = 1,
		Height = 28,
		Colors = { Main = Color3.fromRGB(175, 120, 235), Accent = Color3.fromRGB(255, 140, 190) },
		Build = function(ctx: Ctx)
			local DOUGH = Color3.fromRGB(226, 162, 88)
			local CUSTARD = Color3.fromRGB(255, 236, 172)
			local PINK = Color3.fromRGB(255, 140, 190)
			local CHOCOLATE = Color3.fromRGB(110, 66, 42)
			local MINT = Color3.fromRGB(150, 228, 196)
			local LEMON = Color3.fromRGB(255, 228, 110)
			local COFFEE = Color3.fromRGB(105, 62, 34)
			local FOAM = Color3.fromRGB(250, 240, 222)
			local SPRINKLES = {
				Color3.fromRGB(70, 140, 255),
				Color3.fromRGB(255, 225, 60),
				Color3.fromRGB(90, 210, 110),
				Color3.fromRGB(250, 250, 250),
				Color3.fromRGB(180, 100, 240),
				Color3.fromRGB(255, 120, 60),
			}

			-- A frosted donut centred at (cx, cz) with its frosting top at "top".
			-- Six puffy dough tubes make the ring, the frosting + custard on top make
			-- the whole donut (even the middle) safe to stand on.
			local function donut(cx: number, cz: number, top: number, frost: Color3, name: string, parent: Instance?)
				for k = 0, 5 do
					local th = k * 60
					local ox, oz = ctx:Polar(2.3, th)
					ctx:Cylinder(cx + ox, top - 0.95, cz + oz, 3.45, 1.8, { Yaw = -(th + 90), Color = DOUGH, Name = "Dough", Parent = parent })
				end
				ctx:Disc(cx, top, cz, 6.4, { Thickness = 0.4, Color = frost, Name = name, Parent = parent })
				ctx:Disc(cx, top + 0.06, cz, 2.4, { Thickness = 0.3, Color = CUSTARD, Name = "Custard", Parent = parent })
				for _ = 1, 3 do
					local sx, sz = ctx:Polar(ctx:Random(1.7, 2.6), ctx:Random(0, 360))
					ctx:Block(cx + sx, top + 0.1, cz + sz, 0.9, 0.22, 0.22, {
						Yaw = ctx:Random(0, 180),
						Color = SPRINKLES[ctx:RandomInt(1, #SPRINKLES)],
						CanCollide = false,
						Name = "Sprinkle",
						Parent = parent,
					})
				end
			end

			-- A donut that drifts 3.5 studs sideways and back (period 8 s, max ~1.4 studs/s).
			-- It starts at the "back" end (towards the previous step); phase 0.5 = opposite timing.
			local function driftingDonut(radius: number, angle: number, top: number, frost: Color3, name: string, phase: number)
				local side = sideways(angle)
				local cx, cz = ctx:Polar(radius, angle)
				local bx, bz = cx - side.X * 1.75, cz - side.Z * 1.75
				local group = ctx:Group(name, bx, top, bz)
				donut(bx, bz, top, frost, name, group)
				ctx:Move(group, side * 3.5, 8, phase)
			end

			-- A big coffee cup you can stand on (coffee filled to the brim, handle on the wall side).
			local function coffeeCup(radius: number, angle: number, top: number, mug: Color3, name: string)
				local x, z = ctx:Polar(radius, angle)
				ctx:Cylinder(x, top - 0.15 - 2.5, z, 5, 7, { Roll = 90, Color = mug, Name = name .. "Mug" })
				local coffee = ctx:Disc(x, top, z, 6.2, { Thickness = 0.3, Color = COFFEE, Reflectance = 0.1, Name = name .. "Coffee" })
				ctx:Disc(x, top + 0.04, z, 2.6, { Thickness = 0.1, Color = FOAM, CanCollide = false, Name = "LatteFoam" })
				local ax, az = spot(radius, angle, 4, 0)
				ctx:Block(ax, top - 1.2, az, 1.6, 0.7, 0.8, { Yaw = -angle, Color = mug, Name = "Handle" })
				ctx:Block(ax, top - 3.8, az, 1.6, 0.7, 0.8, { Yaw = -angle, Color = mug, Name = "Handle" })
				local vx, vz = spot(radius, angle, 4.6, 0)
				ctx:Block(vx, top - 2.5, vz, 0.7, 3.3, 0.8, { Yaw = -angle, Color = mug, Name = "Handle" })
				-- a little steam rising from the hot coffee
				local steam = Instance.new("Smoke")
				steam.Color = Color3.fromRGB(255, 255, 255)
				steam.Opacity = 0.08
				steam.RiseVelocity = 2
				steam.Size = 1.5
				steam.Parent = coffee
			end

			-- Start: a pink donut box (with the lid flipped open).
			local sx, sz = ctx:Polar(10.5, 0)
			ctx:Platform(sx, 3, sz, 4.5, 5, { Thickness = 1.6, Color = Color3.fromRGB(255, 176, 206), Name = "DonutBox" })
			local lx, lz = spot(10.5, 0, 2.5, 0)
			ctx:Block(lx, 4.2, lz, 0.2, 2.6, 5, { Roll = -15, Color = Color3.fromRGB(250, 250, 250), CanCollide = false, Name = "BoxLid" })

			-- The donut staircase. Donuts drift in pairs (same timing), so the jump
			-- between two donuts stays short; to reach a cup, wait until the donut
			-- drifts close to it.
			driftingDonut(13, 42, 6.5, PINK, "PinkDonut", 0)
			driftingDonut(13, 82, 10, CHOCOLATE, "ChocolateDonut", 0)
			coffeeCup(13.5, 123, 13.5, Color3.fromRGB(90, 170, 230), "BlueCup")
			driftingDonut(13.5, 163, 17, MINT, "MintDonut", 0.5)
			driftingDonut(13, 203, 20.5, LEMON, "LemonDonut", 0.5)
			-- Last ledge: a big pink mug right next to the exit.
			coffeeCup(11.5, 247, 24.25, Color3.fromRGB(255, 120, 170), "PinkCup")

			-- Decoration: a giant glazed donut rolling slowly on the wall.
			local dAngle, dRadius, dY = 305, 20.6, 14
			local out = polarV(1, dAngle, 0)
			local side = sideways(dAngle)
			local up = Vector3.new(0, 1, 0)
			local center = polarV(dRadius, dAngle, dY)
			local wheel: Instance = ctx:Group("GiantDonut", center.X, center.Y, center.Z)
			for k = 0, 5 do
				local a1, a2 = math.rad(k * 60 - 8), math.rad(k * 60 + 68)
				local p1 = center + (side * math.cos(a1) + up * math.sin(a1)) * 2.9
				local p2 = center + (side * math.cos(a2) + up * math.sin(a2)) * 2.9
				ctx:Beam(p1, p2, 1.9, 1.9, { Round = true, Color = DOUGH, CanCollide = false, Name = "GiantDough", Parent = wheel })
			end
			local face = center - out * 0.75
			ctx:Cylinder(face.X, face.Y, face.Z, 0.4, 6, { Yaw = -dAngle, Color = PINK, CanCollide = false, Name = "GiantFrosting", Parent = wheel })
			ctx:Cylinder(face.X, face.Y, face.Z, 0.5, 2.2, { Yaw = -dAngle, Color = ctx.Theme.Dark, CanCollide = false, Name = "GiantHole", Parent = wheel })
			for i, sp in ipairs({ { 2.2, 30 }, { 2.4, 200 } }) do
				local a = math.rad(sp[2])
				local p = face - out * 0.25 + (side * math.cos(a) + up * math.sin(a)) * sp[1]
				ctx:Block(p.X, p.Y, p.Z, 0.2, 0.3, 1, { Yaw = -dAngle, Pitch = sp[2], Color = SPRINKLES[i], CanCollide = false, Name = "GiantSprinkle", Parent = wheel })
			end
			ctx:Spin(wheel, 20, out)
		end,
	})

	------------------------------------------------------------------
	-- 4. SUSHI CONVEYOR (hard): sushi belts push you into hot wasabi,
	--    narrow chopstick bridges, sushi-roll stepping stones.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Sushi Conveyor",
		Creator = "Sensei Salmon",
		Difficulty = 3,
		Height = 34,
		Colors = { Main = Color3.fromRGB(25, 120, 130), Accent = Color3.fromRGB(110, 200, 90) },
		Build = function(ctx: Ctx)
			local NORI = Color3.fromRGB(28, 42, 34)
			local RICE = Color3.fromRGB(250, 250, 244)
			local SALMON = Color3.fromRGB(250, 128, 80)
			local TUNA = Color3.fromRGB(200, 50, 70)
			local EGG = Color3.fromRGB(255, 214, 80)
			local BELT = Color3.fromRGB(58, 58, 64)
			local WOOD = Color3.fromRGB(196, 150, 92)
			local LEAF = Color3.fromRGB(90, 180, 70)
			local SOY = Color3.fromRGB(45, 25, 15)
			local PLATES = {
				Color3.fromRGB(220, 60, 60),
				Color3.fromRGB(70, 120, 230),
				Color3.fromRGB(255, 200, 50),
				Color3.fromRGB(80, 190, 110),
			}
			local FISH = { SALMON, TUNA, EGG, SALMON }

			-- A sushi roll (maki): black nori outside, white rice, salmon in the middle.
			local function maki(radius: number, angle: number, top: number, size: number, name: string, thick: number?)
				local x, z = ctx:Polar(radius, angle)
				ctx:Disc(x, top - 0.05, z, size, { Thickness = thick or 2, Color = NORI, Name = name })
				ctx:Disc(x, top, z, size - 0.7, { Thickness = 0.3, Color = RICE, Name = name .. "Rice" })
				ctx:Disc(x, top + 0.04, z, size * 0.36, { Thickness = 0.3, Color = SALMON, Name = name .. "Salmon" })
			end

			-- A sushi plate riding on a belt (decoration, you can walk through it).
			local plateCount = 0
			local function beltPlate(p: Vector3, along: Vector3)
				plateCount += 1
				local color = PLATES[(plateCount - 1) % #PLATES + 1]
				local fish = FISH[(plateCount - 1) % #FISH + 1]
				local yaw = math.deg(math.atan2(-along.Z, along.X))
				ctx:Disc(p.X, p.Y + 0.1, p.Z, 2, { Thickness = 0.15, Color = color, CanCollide = false, Name = "SushiPlate" })
				ctx:Block(p.X, p.Y + 0.35, p.Z, 1.3, 0.5, 0.75, { Yaw = yaw, Color = RICE, CanCollide = false, Name = "Nigiri" })
				ctx:Block(p.X, p.Y + 0.68, p.Z, 1.45, 0.18, 0.9, { Yaw = yaw, Color = fish, CanCollide = false, Name = "NigiriFish" })
			end

			-- A conveyor belt from a to b (centre line, top surface at a.Y + 0.5).
			local function belt(a: Vector3, b: Vector3, push: Vector3, name: string): BasePart
				local part = ctx:Beam(a, b, 4, 1, { Color = BELT, Name = name })
				ctx:Conveyor(part, push)
				local along = (b - a).Unit
				beltPlate(a:Lerp(b, 0.35) + Vector3.new(0, 0.5, 0) + Vector3.new(-along.Z, 0, along.X) * 0.7, along)
				beltPlate(a:Lerp(b, 0.7) + Vector3.new(0, 0.5, 0) - Vector3.new(-along.Z, 0, along.X) * 0.7, along)
				return part
			end

			-- A hot wasabi block (deadly!) with a wasabi leaf behind it.
			local function wasabi(a: Vector3, b: Vector3, width: number, height: number, leafAt: Vector3, leafYaw: number)
				local block = ctx:Beam(a, b, width, height, { Name = "HotWasabi" })
				ctx:Kill(block)
				glow(block, Color3.fromRGB(255, 70, 50), 9, 1)
				ctx:Block(leafAt.X, leafAt.Y, leafAt.Z, 0.2, 2.4, 1.6, { Yaw = leafYaw, Roll = 20, Color = LEAF, CanCollide = false, Name = "WasabiLeaf" })
			end

			-- A pair of chopsticks you can walk on (each one is only 1.2 studs wide!).
			local function chopsticks(a: Vector3, b: Vector3, gap: number)
				local along = (b - a).Unit
				local flat = Vector3.new(along.X, 0, along.Z).Unit
				local offset = Vector3.new(-flat.Z, 0, flat.X) * gap
				local down = Vector3.new(0, -0.4, 0)
				ctx:Beam(a + down, b + down, 1.2, 0.8, { Color = WOOD, Name = "Chopstick" })
				ctx:Beam(a + offset + down, b + offset + down, 1.2, 0.8, { Color = WOOD, Name = "Chopstick" })
			end

			-- Start: a sushi roll next to the entry plate.
			maki(10, 0, 3.5, 4.5, "StartRoll")

			-- Belt 1: you land in the middle and it drags you back into the wasabi. Run!
			local b1a = polarV(17.654, 25, 7)
			local b1b = polarV(17.654, -25, 7)
			local b1dir = (b1b - b1a).Unit
			belt(b1a, b1b, b1dir * 8, "SushiBelt1")
			wasabi(b1b - b1dir * 1.6 + Vector3.new(0, 1.4, 0), b1b + Vector3.new(0, 1.4, 0), 4.4, 1.8, b1b + b1dir * 0.5 + Vector3.new(0, 2.6, 0), 25)

			-- A small roll, then the chopstick bridge up to the soy-sauce bowl.
			maki(17, 42, 11, 4, "Roll1")
			chopsticks(polarV(17.6, 48, 11), polarV(16.3, 82, 15.8), 1.8)

			-- The soy-sauce bowl: a safe rest.
			local sbx, sbz = ctx:Polar(14.5, 100)
			ctx:Cylinder(sbx, 14.6, sbz, 2.4, 6.5, { Roll = 90, Color = RICE, Name = "SoyBowl" })
			ctx:Cylinder(sbx, 14.6, sbz, 0.5, 6.6, { Roll = 90, Color = Color3.fromRGB(60, 90, 170), CanCollide = false, Name = "BowlStripe" })
			local soy = ctx:Disc(sbx, 16, sbz, 5.6, { Thickness = 0.3, Color = SOY, Reflectance = 0.25, Name = "SoySauce" })
			glow(soy, Color3.fromRGB(255, 200, 150), 10, 0.6)

			-- Belt 2 points out to the wall and pushes you into the wasabi at the end.
			-- Run inwards to the giant roll in the middle of the tower.
			local b2a = polarV(4.5, 130, 20)
			local b2b = polarV(20.5, 130, 20)
			local b2dir = (b2b - b2a).Unit
			belt(b2a, b2b, b2dir * 7, "SushiBelt2")
			wasabi(b2b - b2dir * 1.5 + Vector3.new(0, 1.4, 0), b2b + Vector3.new(0, 1.4, 0), 4.4, 1.8, b2b - b2dir * 0.2 + Vector3.new(0, 2.8, 0) + sideways(130) * 1.6, -130)

			-- The giant sushi roll in the middle of the tower.
			maki(0, 0, 22.5, 7, "GiantRoll", 3)

			-- Chopsticks lead back out from the giant roll.
			chopsticks(polarV(2.6, 205, 22.5), polarV(13, 205, 26.5), -1.8)

			-- Belt 3 pushes you sideways towards a wall of wasabi. Stay on the inside!
			local b3a = polarV(16.55, 215, 28)
			local b3b = polarV(16.55, 265, 28)
			belt(b3a, b3b, polarV(6, 240, 0), "SushiBelt3")
			local stripMid = polarV(17.5, 240, 28.7)
			local stripAlong = sideways(240) * 7
			wasabi(stripMid - stripAlong, stripMid + stripAlong, 1, 2.4, polarV(18.6, 240, 30.4), -240)

			-- Last ledge: a sushi roll next to the exit.
			maki(10, 280, 31, 4.5, "LastRoll")

			-- Decoration: a giant salmon nigiri on the wall.
			local nAngle, nRadius = 320, 20.5
			local nx, nz = ctx:Polar(nRadius, nAngle)
			ctx:Block(nx, 13, nz, 3, 2.2, 6, { Yaw = -nAngle, Color = RICE, Name = "GiantNigiri" })
			ctx:Block(nx, 14.5, nz, 3.3, 0.8, 6.6, { Yaw = -nAngle, Color = SALMON, Name = "GiantSalmon" })
			for _, side in ipairs({ -1.6, 0, 1.6 }) do
				local wx, wz = spot(nRadius, nAngle, 0, side)
				ctx:Block(wx, 14.92, wz, 3.32, 0.06, 0.35, { Yaw = -nAngle + 20, Color = RICE, CanCollide = false, Name = "SalmonStripe" })
			end
			ctx:Block(nx, 13.45, nz, 3.06, 3.2, 1.2, { Yaw = -nAngle, Color = NORI, CanCollide = false, Name = "NoriBand" })

			-- Decoration: paper lanterns glowing on the wall.
			for _, l in ipairs({ { 175, 11 }, { 290, 25 } }) do
				local lx, lz = ctx:Polar(21.8, l[1])
				local lantern = ctx:Ball(lx, l[2], lz, 2.2, {
					Color = Color3.fromRGB(255, 236, 200),
					Material = Enum.Material.Neon,
					CanCollide = false,
					Name = "Lantern",
				})
				glow(lantern, Color3.fromRGB(255, 220, 170), 14, 1)
				ctx:Cylinder(lx, l[2] + 1.15, lz, 0.4, 1.2, { Roll = 90, Color = NORI, CanCollide = false, Name = "LanternCap" })
			end
		end,
	})
end

-- ===== D.lua =====
-- Group D food sections: Waffle Wall, Cheese Maze, Chocolate River, Cake Tiers.
-- Spots are given as (radius from the middle of the tower, angle in degrees).
-- "out" moves a spot further from the middle, "side" moves it sideways (counter-clockwise).
do
	-- ===== Little helpers shared by the 4 sections below =====

	-- The (x, z) of a point "out" studs further out and "side" studs sideways from the spot (radius, angle).
	local function spot(radius: number, angle: number, out: number, side: number): (number, number)
		local a = math.rad(angle)
		local c, s = math.cos(a), math.sin(a)
		return (radius + out) * c - side * s, (radius + out) * s + side * c
	end

	-- A soft coloured light inside a part.
	local function glow(part: BasePart, color: Color3, range: number, brightness: number)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = part
	end

	------------------------------------------------------------------
	-- 1. WAFFLE WALL (easy): climb the golden waffle ladders up giant
	--    waffles, hop along the butter pats and don't slip in the syrup!
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Waffle Wall",
		Creator = "Syrup Steve",
		Difficulty = 1,
		Height = 32,
		Colors = { Main = Color3.fromRGB(226, 168, 74), Accent = Color3.fromRGB(255, 226, 120) },
		Build = function(ctx: Ctx)
			local WAFFLE = Color3.fromRGB(228, 166, 74)
			local TOASTED = Color3.fromRGB(166, 98, 34)
			local LADDER = Color3.fromRGB(250, 192, 64)
			local SYRUP = Color3.fromRGB(168, 86, 14)
			local BUTTER = Color3.fromRGB(255, 222, 100)
			local SHINE = Color3.fromRGB(255, 244, 190)
			local CREAM = Color3.fromRGB(255, 252, 242)
			local CAP = Color3.fromRGB(200, 40, 36)
			local BERRY = Color3.fromRGB(222, 30, 52)

			-- A flat waffle you can stand on: a golden slab with a toasted 3 x 3 grid on top.
			-- long = size going outwards, wide = size sideways. The grid lines don't block your feet.
			local function waffle(radius: number, angle: number, top: number, long: number, wide: number, name: string): BasePart
				local x, z = ctx:Polar(radius, angle)
				local base = ctx:Platform(x, top, z, long, wide, { Yaw = -angle, Thickness = 1.2, Color = WAFFLE, Material = Enum.Material.Sand, Name = name })
				for _, k in ipairs({ -1, 1 }) do
					local ax, az = spot(radius, angle, 0, k * wide / 6)
					ctx:Block(ax, top + 0.15, az, long - 0.4, 0.3, 0.5, { Yaw = -angle, Color = TOASTED, Material = Enum.Material.Sand, CanCollide = false, Name = "WaffleGrid" })
					local bx, bz = spot(radius, angle, k * long / 6, 0)
					ctx:Block(bx, top + 0.15, bz, 0.5, 0.3, wide - 0.4, { Yaw = -angle, Color = TOASTED, Material = Enum.Material.Sand, CanCollide = false, Name = "WaffleGrid" })
				end
				return base
			end

			-- A giant waffle standing up like a wall, with its grid on one face.
			-- inner = radius of its inside face, thick = how deep it is (going outwards),
			-- face = -1 puts the grid on the inside face, 1 on the outside face.
			local function waffleWall(inner: number, angle: number, bottom: number, top: number, wide: number, thick: number, face: number, name: string): BasePart
				local high = top - bottom
				local cx, cz = ctx:Polar(inner + thick / 2, angle)
				local wall = ctx:Block(cx, bottom + high / 2, cz, thick, high, wide, { Yaw = -angle, Color = WAFFLE, Material = Enum.Material.Sand, Name = name })
				local faceRadius = (face > 0) and (inner + thick + 0.1) or (inner - 0.1)
				for _, k in ipairs({ -1, 1 }) do
					local vx, vz = spot(faceRadius, angle, 0, k * wide / 6)
					ctx:Block(vx, bottom + high / 2, vz, 0.3, high - 0.4, 0.5, { Yaw = -angle, Color = TOASTED, Material = Enum.Material.Sand, CanCollide = false, Name = "WaffleGrid" })
					local hx, hz = spot(faceRadius, angle, 0, 0)
					ctx:Block(hx, bottom + high / 2 + k * high / 6, hz, 0.3, 0.5, wide - 0.4, { Yaw = -angle, Color = TOASTED, Material = Enum.Material.Sand, CanCollide = false, Name = "WaffleGrid" })
				end
				return wall
			end

			-- A golden "waffle ladder" (truss) you can climb. Its bottom is at "bottom".
			local function ladder(radius: number, angle: number, bottom: number, height: number)
				local x, z = ctx:Polar(radius, angle)
				ctx:Truss(x, bottom, z, height, { Yaw = -angle, Color = LADDER, Name = "WaffleLadder" })
			end

			-- A pat of butter to hop on, with a shiny top and a warm glow.
			local function butter(radius: number, angle: number, top: number, size: number, name: string): BasePart
				local x, z = ctx:Polar(radius, angle)
				local pat = ctx:Platform(x, top, z, size, size, { Yaw = -angle, Thickness = 1.4, Color = BUTTER, Name = name })
				ctx:Platform(x, top + 0.1, z, size - 1, size - 1, { Yaw = -angle, Thickness = 0.3, Color = SHINE, CanCollide = false, Name = "ButterShine" })
				glow(pat, Color3.fromRGB(255, 214, 110), 9, 0.7)
				return pat
			end

			-- A puddle of syrup on top of a waffle. It's SLIPPERY!
			local function syrupPuddle(radius: number, angle: number, top: number, size: number)
				local x, z = ctx:Polar(radius, angle)
				local puddle = ctx:Disc(x, top + 0.1, z, size, {
					Thickness = 0.3,
					Color = SYRUP,
					Material = Enum.Material.Glass,
					Transparency = 0.15,
					Reflectance = 0.15,
					Name = "SyrupPuddle",
				})
				ctx:Slippery(puddle)
				glow(puddle, Color3.fromRGB(255, 160, 60), 8, 0.5)
			end

			-- A maple syrup bottle (decoration) from the middle of its bottom to its open top.
			local function syrupBottle(base: Vector3, mouth: Vector3, width: number, capped: boolean)
				local dir = mouth - base
				local bodyEnd = base + dir * 0.6
				local glass = { Round = true, Color = SYRUP, Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Name = "SyrupBottle" }
				ctx:Beam(base, bodyEnd, width, width, glass)
				ctx:Beam(base + dir * 0.16, base + dir * 0.46, width + 0.3, width + 0.3, { Round = true, Color = CREAM, CanCollide = false, Name = "BottleLabel" })
				ctx:Ball(bodyEnd.X, bodyEnd.Y, bodyEnd.Z, width, glass)
				ctx:Beam(bodyEnd, mouth, width * 0.4, width * 0.4, glass)
				if capped then
					local tip = mouth + dir.Unit * 0.5
					ctx:Beam(mouth - dir.Unit * 0.5, tip, width * 0.5, width * 0.5, { Round = true, Color = CAP, CanCollide = false, Name = "BottleCap" })
				end
			end

			---------------- The climb ----------------
			-- 1) first waffle step, then the landing at the foot of the first waffle wall
			waffle(10.5, 0, 2.5, 5, 5, "Waffle1")
			waffle(13.5, 40, 5.5, 6, 6.5, "WaffleLanding")
			-- 2) the first waffle wall with a golden ladder up its face
			waffleWall(16.5, 40, 4.3, 13.5, 9, 2, -1, "WaffleWall")
			ladder(15.5, 40, 5.5, 8)
			-- the ledge on top of the wall
			waffle(19.5, 40, 13.5, 6, 7, "WaffleLedge")
			-- 3) a syrupy waffle (a bottle is pouring syrup on it from above!)
			waffle(19, 78, 15.5, 6, 7, "SyrupWaffle")
			syrupPuddle(19, 78, 15.5, 4.6)
			-- 4) butter pats stuck on the waffle wall
			butter(19.5, 105, 17.5, 3.5, "ButterPat1")
			butter(19.5, 128, 19.5, 3.5, "ButterPat2")
			butter(19.5, 151, 21.5, 3.5, "ButterPat3")
			-- 5) the landing at the foot of the last waffle wall (with a bit of syrup)
			waffle(14, 178, 21.5, 6, 6.5, "WaffleLanding2")
			syrupPuddle(15.3, 178, 21.5, 3)
			-- 6) the last waffle wall: climb its ladder, stand on top, jump to the exit!
			waffleWall(8, 178, 20.3, 29.5, 8, 3, 1, "LastWaffle")
			ladder(12, 178, 21.5, 8)
			for _, k in ipairs({ -1, 1 }) do
				local ax, az = spot(9.5, 178, 0, k * 8 / 6)
				ctx:Block(ax, 29.65, az, 2.6, 0.3, 0.5, { Yaw = -178, Color = TOASTED, Material = Enum.Material.Sand, CanCollide = false, Name = "WaffleGrid" })
			end
			local mx, mz = ctx:Polar(9.5, 178)
			ctx:Block(mx, 29.65, mz, 0.5, 0.3, 7.6, { Yaw = -178, Color = TOASTED, Material = Enum.Material.Sand, CanCollide = false, Name = "WaffleGrid" })

			---------------- Decorations ----------------
			-- the waffle wall behind the butter pats (just for looks, you can't stand on it)
			for i, angle in ipairs({ 116, 147 }) do
				local backdrop = waffleWall(22, angle, 12 + 2 * i, 23 + 2 * i, 11, 1, -1, "WaffleBackdrop")
				backdrop.CanCollide = false
			end
			-- a tipped-over syrup bottle pouring onto the syrupy waffle
			local bx, bz = ctx:Polar(22.2, 74)
			local px, pz = ctx:Polar(19.6, 78)
			syrupBottle(Vector3.new(bx, 27, bz), Vector3.new(px, 22.4, pz), 3.2, false)
			local sx, sz = ctx:Polar(19.3, 78)
			ctx:Beam(Vector3.new(sx, 22.2, sz), Vector3.new(sx, 15.7, sz), 0.6, 0.6, {
				Round = true,
				Color = SYRUP,
				Material = Enum.Material.Glass,
				Transparency = 0.2,
				CanCollide = false,
				Name = "SyrupStream",
			})
			-- a giant syrup bottle standing at the bottom of the tower
			local gx, gz = ctx:Polar(20.5, 285)
			syrupBottle(Vector3.new(gx, 0, gz), Vector3.new(gx, 14, gz), 4.4, true)
			-- whipped cream with a strawberry on top, on the first ledge
			local cx, cz = spot(19.5, 40, 2, -2.3)
			ctx:Ball(cx, 14.1, cz, 2, { Color = CREAM, CanCollide = false, Name = "WhippedCream" })
			ctx:Ball(cx, 15.5, cz, 1.3, { Color = BERRY, CanCollide = false, Name = "Strawberry" })
		end,
	})

	------------------------------------------------------------------
	-- 2. CHEESE MAZE (medium): a twisty Swiss cheese ledge around the
	--    tower, a sliding cheese block, and a cracker bridge that goes
	--    right through a giant slice of Swiss cheese.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Cheese Maze",
		Creator = "Swiss Miss",
		Difficulty = 2,
		Height = 30,
		Colors = { Main = Color3.fromRGB(255, 228, 120), Accent = Color3.fromRGB(255, 246, 196) },
		Build = function(ctx: Ctx)
			local CHEESE = Color3.fromRGB(255, 206, 72)
			local PALE = Color3.fromRGB(255, 230, 140)
			local HOLE = Color3.fromRGB(212, 144, 28)
			local RIND = Color3.fromRGB(238, 148, 38)
			local CRACKER = Color3.fromRGB(226, 180, 108)
			local DOT = Color3.fromRGB(150, 100, 46)
			local MOUSE = Color3.fromRGB(150, 150, 160)
			local PINK = Color3.fromRGB(255, 160, 180)

			-- the ledge that hugs the tower wall goes from radius 18 to 22.5
			local LEDGE_IN, LEDGE_OUT = 18, 22.5
			local LEDGE_MID = (LEDGE_IN + LEDGE_OUT) / 2

			-- A round "hole" on the face of the cheese (decoration). yaw = which way the hole faces.
			local function hole(x: number, y: number, z: number, size: number, yaw: number)
				ctx:Cylinder(x, y, z, 0.12, size, { Yaw = yaw, Color = HOLE, CanCollide = false, Name = "CheeseHole" })
			end

			-- A chunky cheese block you can stand on (top at "top"), with holes on its inside face.
			local function cheeseBlock(radius: number, angle: number, top: number, long: number, wide: number, high: number, name: string, parent: Instance?): BasePart
				local x, z = ctx:Polar(radius, angle)
				local block = ctx:Platform(x, top, z, long, wide, { Yaw = -angle, Thickness = high, Color = CHEESE, Name = name, Parent = parent })
				local hx, hz = spot(radius, angle, -long / 2 - 0.05, wide * 0.18)
				ctx:Cylinder(hx, top - high * 0.5, hz, 0.12, math.min(high, wide) * 0.55, { Yaw = -angle, Color = HOLE, CanCollide = false, Name = "CheeseHole", Parent = parent })
				return block
			end

			-- One piece of the cheese ledge that hugs the tower wall.
			-- (a piece that steps up is made thicker so it sits right on the piece before it)
			local function ledge(angle: number, top: number, chord: number, thick: number, name: string): BasePart
				local x, z = ctx:Polar(LEDGE_MID, angle)
				return ctx:Platform(x, top, z, LEDGE_OUT - LEDGE_IN, chord, { Yaw = -angle, Thickness = thick, Color = CHEESE, Name = name })
			end

			-- A cheese-wedge ramp: just walk up the slope!
			-- outwards = true: it climbs away from the middle, false: it climbs counter-clockwise.
			local function ramp(radius: number, angle: number, bottom: number, rise: number, length: number, width: number, outwards: boolean, name: string)
				local x, z = ctx:Polar(radius, angle)
				local yaw = outwards and (90 - angle) or -angle
				ctx:Wedge(x, bottom + rise / 2, z, width, rise, length, { Yaw = yaw, Color = PALE, Name = name })
				-- a hole on the side of the wedge
				local side = outwards and -(width / 2 + 0.06) or 0
				local out = outwards and 0.6 or -(width / 2 + 0.06)
				local hx, hz = spot(radius, angle, out, side)
				hole(hx, bottom + rise * 0.3, hz, rise * 0.4, outwards and (-angle - 90) or -angle)
			end

			-- A Swiss cheese wall across the ledge with a doorway (doorIn..doorOut = radius range of the door).
			local function swissWall(angle: number, floor: number, doorIn: number, doorOut: number)
				local wallIn, wallOut, thick, tall, doorTall = 17.4, 23.2, 1.4, 7.6, 5.8
				local function slab(r0: number, r1: number, y0: number, y1: number)
					local x, z = ctx:Polar((r0 + r1) / 2, angle)
					ctx:Block(x, (y0 + y1) / 2, z, r1 - r0, y1 - y0, thick, { Yaw = -angle, Color = CHEESE, Name = "SwissWall" })
				end
				if doorIn > wallIn + 0.05 then
					slab(wallIn, doorIn, floor, floor + tall)
				end
				if doorOut < wallOut - 0.05 then
					slab(doorOut, wallOut, floor, floor + tall)
				end
				slab(doorIn, doorOut, floor + doorTall, floor + tall)
				-- big round holes on both faces of the widest post
				local postR = ((doorIn - wallIn) > (wallOut - doorOut)) and (wallIn + doorIn) / 2 or (doorOut + wallOut) / 2
				for _, k in ipairs({ -1, 1 }) do
					local hx, hz = spot(postR, angle, 0, k * (thick / 2 + 0.06))
					hole(hx, floor + 3.2, hz, 1.5, -angle - 90)
				end
			end

			---------------- The climb ----------------
			-- 1) a cheese block, then a cheese-wedge ramp up to the ledge
			cheeseBlock(10.5, 0, 2.5, 5, 5, 1.4, "CheeseBlock1")
			ramp(15.75, 0, 2.5, 3, 5.5, 4.5, true, "CheeseRamp")
			-- 2) the ledge around the tower, with Swiss cheese walls in the way.
			--    Find the doorway in each wall!
			ledge(10, 5.5, 11, 1.6, "CheeseLedge1")
			ledge(42, 5.5, 11, 1.6, "CheeseLedge2")
			swissWall(42, 5.5, 19.4, 22.6) -- doorway on the outside
			ramp(LEDGE_MID, 63, 5.5, 3, 6, 4.5, false, "CheeseRamp")
			ledge(86, 8.5, 11, 1.6, "CheeseLedge3")
			swissWall(86, 8.5, 17.4, 21.2) -- doorway on the inside
			ledge(114, 10.5, 11, 2, "CheeseLedge4")
			cheeseBlock(LEDGE_MID, 114, 13, 4.9, 3, 2.5, "CheeseHurdle") -- hop over it
			ramp(LEDGE_MID, 137, 10.5, 3, 6, 4.5, false, "CheeseRamp")
			ledge(160, 13.5, 11, 1.6, "CheeseLedge5")
			swissWall(160, 13.5, 19.4, 22.6) -- doorway on the outside
			ledge(188, 15.5, 11, 2, "CheeseLedge6")
			-- 3) a sliding cheese block takes you towards the middle
			local mx, mz = ctx:Polar(16, 195)
			local slider = ctx:Group("SlidingCheese", mx, 15.5, mz)
			cheeseBlock(16, 195, 15.5, 4, 4.5, 1.6, "SlidingCheese", slider)
			local inward = Vector3.new(-math.cos(math.rad(195)), 0, -math.sin(math.rad(195)))
			ctx:Move(slider, inward * 6, 4.5, 0)
			-- 4) the cracker bridge across the middle of the tower
			for i, s in ipairs({ -5.1, 0, 5.1 }) do
				local x, z = ctx:Polar(s, 15)
				ctx:Platform(x, 15.5, z, 4.6, 4.2, { Yaw = -15, Thickness = 0.6, Color = CRACKER, Material = Enum.Material.Sand, Name = "Cracker" .. i })
				for _, d in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
					local dx, dz = spot(s, 15, d[1] * 1.1, d[2] * 1.1)
					ctx:Cylinder(dx, 15.53, dz, 0.1, 0.45, { Roll = 90, Color = DOT, CanCollide = false, Name = "CrackerDot" })
				end
			end
			-- the giant slice of Swiss cheese the bridge goes through
			local function sliceBlock(v0: number, v1: number, y0: number, y1: number)
				local x, z = spot(0, 15, 0, (v0 + v1) / 2)
				ctx:Block(x, (y0 + y1) / 2, z, 1.4, y1 - y0, v1 - v0, { Yaw = -15, Color = CHEESE, Name = "SwissSlice" })
			end
			sliceBlock(-6, -1.8, 13, 22.9)
			sliceBlock(1.8, 6, 13, 22.9)
			sliceBlock(-1.8, 1.8, 21.2, 22.9)
			for _, h in ipairs({ { -4, 19.5, 1.8 }, { 3.9, 16.5, 1.4 } }) do
				for _, k in ipairs({ -1, 1 }) do
					local hx, hz = spot(0, 15, k * 0.76, h[1])
					hole(hx, h[2], hz, h[3], -15)
				end
			end
			-- 5) cheese steps and a wedge up to the last cheese block
			cheeseBlock(11, 40, 19, 4, 4, 2, "CheeseStep")
			local rx, rz = spot(11, 40, 0, 5)
			ctx:Wedge(rx, 20.75, rz, 4, 3.5, 6, { Yaw = -40, Color = PALE, Name = "CheeseRamp" })
			local tx, tz = spot(11, 40, 0, 10)
			ctx:Platform(tx, 22.5, tz, 4, 4, { Yaw = -40, Thickness = 2, Color = CHEESE, Name = "CheeseStep" })
			-- 6) the last cheese block: jump from here to the exit!
			cheeseBlock(10.75, 100, 26.5, 4.5, 4.5, 1.6, "LastCheese")

			---------------- Decorations ----------------
			-- a giant cheese wheel against the wall
			local wx, wz = ctx:Polar(21.5, 285)
			ctx:Cylinder(wx, 9, wz, 3, 9, { Yaw = -285, Color = RIND, CanCollide = false, Name = "CheeseWheel" })
			local fx, fz = ctx:Polar(19.95, 285)
			ctx:Cylinder(fx, 9, fz, 0.12, 8.2, { Yaw = -285, Color = PALE, CanCollide = false, Name = "CheeseWheel" })
			for _, h in ipairs({ { -1.8, 10.5, 1.6 }, { 1.6, 7.6, 1.2 } }) do
				local hx, hz = spot(19.9, 285, 0, h[1])
				hole(hx, h[2], hz, h[3], -285)
			end
			-- a little mouse nibbling the cheese hurdle
			local function mousePart(out: number, side: number, y: number): (number, number, number)
				local x, z = spot(LEDGE_MID, 108, out, side)
				return x, y, z
			end
			local bx, by, bz = mousePart(1.2, 0, 11.3)
			ctx:Ball(bx, by, bz, 1.6, { Color = MOUSE, CanCollide = false, Name = "Mouse" })
			local hx, hy, hz = mousePart(1.2, 1.1, 11.7)
			ctx:Ball(hx, hy, hz, 1.1, { Color = MOUSE, CanCollide = false, Name = "Mouse" })
			for _, k in ipairs({ -1, 1 }) do
				local ex, ey, ez = mousePart(1.2 + k * 0.45, 0.9, 12.3)
				ctx:Cylinder(ex, ey, ez, 0.15, 0.7, { Yaw = -108 - 90, Color = PINK, CanCollide = false, Name = "MouseEar" })
			end
			local ux, uy, uz = mousePart(1.2, -1.4, 10.9)
			ctx:Cylinder(ux, uy, uz, 1.6, 0.2, { Yaw = -108 - 90, Roll = 20, Color = PINK, CanCollide = false, Name = "MouseTail" })
		end,
	})

	------------------------------------------------------------------
	-- 3. CHOCOLATE RIVER (hard): hop across marshmallows and ride the
	--    cookie rafts over a river of hot melted chocolate, then climb the
	--    wafers while giant spoons swing past. Don't touch the chocolate!
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Chocolate River",
		Creator = "Choco Chuck",
		Difficulty = 3,
		Height = 34,
		Colors = { Main = Color3.fromRGB(122, 70, 38), Accent = Color3.fromRGB(245, 228, 200) },
		Build = function(ctx: Ctx)
			local DARK = Color3.fromRGB(66, 36, 18)
			local MILK = Color3.fromRGB(120, 66, 34)
			local MELTED = Color3.fromRGB(112, 50, 20) -- glowing melted chocolate (deadly!)
			local COOKIE = Color3.fromRGB(212, 154, 82)
			local CHIP = Color3.fromRGB(58, 30, 14)
			local MARSHMALLOW = Color3.fromRGB(252, 250, 244)
			local TOASTED = Color3.fromRGB(242, 214, 168)
			local WAFER = Color3.fromRGB(232, 190, 128)
			local FILLING = Color3.fromRGB(255, 246, 228)
			local WRAPPER = Color3.fromRGB(200, 30, 40)
			local GOLD = Color3.fromRGB(255, 200, 60)

			-- Melted chocolate kills you. It glows so you can tell it's hot!
			local function hotChocolate(part: BasePart)
				part.Material = Enum.Material.Neon
				ctx:Kill(part, true)
			end

			-- A chocolate chip cookie (top at "top"). parent = a group if it moves.
			local function cookie(x: number, top: number, z: number, size: number, name: string, parent: Instance?): BasePart
				local c = ctx:Disc(x, top, z, size, { Thickness = 0.8, Color = COOKIE, Material = Enum.Material.Sand, Name = name, Parent = parent })
				for i = 0, 2 do
					local a = math.rad(120 * i + 30)
					local r = size * 0.24
					ctx:Ball(x + r * math.cos(a), top, z + r * math.sin(a), 0.8, { Color = CHIP, CanCollide = false, Name = "ChocolateChip", Parent = parent })
				end
				return c
			end

			-- A big marshmallow stepping stone (its top is at "top").
			local function marshmallow(radius: number, angle: number, top: number, color: Color3, name: string)
				local x, z = ctx:Polar(radius, angle)
				ctx:Ball(x, top - 2, z, 4, { Color = color, Name = name })
			end

			-- A wafer: crunchy biscuit with a creamy filling line round its middle.
			-- long = size going outwards, wide = size sideways.
			local function wafer(radius: number, angle: number, top: number, long: number, wide: number, name: string)
				local x, z = ctx:Polar(radius, angle)
				ctx:Platform(x, top, z, long, wide, { Yaw = -angle, Thickness = 1.2, Color = WAFER, Material = Enum.Material.Sand, Name = name })
				ctx:Platform(x, top - 0.5, z, long + 0.1, wide + 0.1, { Yaw = -angle, Thickness = 0.2, Color = FILLING, CanCollide = false, Name = "WaferFilling" })
			end

			-- A long wafer bar to balance on, from spot (radius, a0) to (radius, a1).
			local function waferBeam(radius: number, a0: number, a1: number, top: number, name: string)
				local x0, z0 = ctx:Polar(radius, a0)
				local x1, z1 = ctx:Polar(radius, a1)
				local p0, p1 = Vector3.new(x0, top - 0.5, z0), Vector3.new(x1, top - 0.5, z1)
				ctx:Beam(p0, p1, 1.6, 1, { Color = WAFER, Material = Enum.Material.Sand, Name = name })
				ctx:Beam(p0, p1, 1.7, 0.2, { Color = FILLING, CanCollide = false, Name = "WaferFilling" })
			end

			-- A giant spoon hanging from a chocolate stick. It swings across the wafer bar
			-- below it: wait for it to swing away, then run!
			local function spoon(radius: number, angle: number, beamTop: number, phase: number)
				local px, pz = ctx:Polar(radius, angle)
				local pivotY = beamTop + 9
				local group = ctx:Group("SwingingSpoon", px, pivotY, pz)
				ctx:Cylinder(px, pivotY - 3.4, pz, 5.8, 0.5, { Roll = 90, Parent = group :: Instance, Name = "SpoonHandle" })
				-- two round pieces make the oval bowl of the spoon
				ctx:Cylinder(px, pivotY - 6.4, pz, 0.6, 2, { Yaw = -angle - 90, Parent = group :: Instance, Name = "SpoonBowl" })
				ctx:Cylinder(px, pivotY - 7.3, pz, 0.7, 2.6, { Yaw = -angle - 90, Parent = group :: Instance, Name = "SpoonBowl" })
				ctx:Kill(group)
				local a = math.rad(angle)
				ctx:Swing(group, Vector3.new(px, pivotY, pz), Vector3.new(-math.sin(a), 0, math.cos(a)), 45, 3.4, phase)
				-- the chocolate stick it hangs from (just for looks)
				local wx, wz = ctx:Polar(23.4, angle)
				ctx:Beam(Vector3.new(wx, pivotY, wz), Vector3.new(px, pivotY, pz), 0.8, 0.8, { Round = true, Color = DARK, CanCollide = false, Name = "SpoonHanger" })
			end

			---------------- The river ----------------
			-- Five pieces of river around the tower. Each has a solid chocolate bed
			-- with the hot melted chocolate on top. (The river sits up high, so nobody
			-- climbing the section below can bump into the hot chocolate by accident.)
			for i, angle in ipairs({ 72, 110, 148, 186, 224 }) do
				local bx, bz = ctx:Polar(16.5, angle)
				ctx:Platform(bx, 5.4, bz, 11, 16, { Yaw = -angle, Thickness = 1.4, Color = DARK, Name = "RiverBed" })
				local x, z = ctx:Polar(17, angle)
				local river = ctx:Platform(x, 6, z, 10, 16, { Yaw = -angle, Thickness = 0.6, Color = MELTED, Name = "ChocolateRiver" })
				hotChocolate(river)
				if i % 2 == 0 then
					local steam = Instance.new("Smoke")
					steam.Color = Color3.fromRGB(150, 110, 90)
					steam.Opacity = 0.06
					steam.RiseVelocity = 1.5
					steam.Size = 4
					steam.Parent = river
				end
			end
			-- bubbles of hot chocolate on the river (just for looks)
			for _, b in ipairs({ { 15.5, 100, 1.3 }, { 20, 170, 1.6 }, { 14.5, 228, 1.2 } }) do
				local x, z = ctx:Polar(b[1], b[2])
				ctx:Ball(x, 6, z, b[3], { Color = DARK, Reflectance = 0.1, CanCollide = false, Name = "ChocolateBubble" })
			end
			-- a melted chocolate waterfall pours into the river (deadly too)
			local fx, fz = ctx:Polar(21.8, 56)
			local fall = ctx:Block(fx, 11.4, fz, 0.8, 10.8, 4, { Yaw = -56, Color = MELTED, Name = "ChocolateFall" })
			hotChocolate(fall)
			local tx, tz = ctx:Polar(22.3, 56)
			ctx:Block(tx, 17.8, tz, 2, 2.4, 6, { Yaw = -56, Color = DARK, CanCollide = false, Name = "ChocolateTap" })

			---------------- The climb ----------------
			-- 1) two cookie steps, then marshmallows sticking out of the river
			local c1x, c1z = ctx:Polar(10.5, -5)
			cookie(c1x, 3, c1z, 5.5, "Cookie1", nil)
			local c2x, c2z = ctx:Polar(10.2, 33)
			cookie(c2x, 6, c2z, 4.6, "Cookie2", nil)
			marshmallow(15.5, 50, 9, MARSHMALLOW, "Marshmallow1")
			marshmallow(17.5, 72, 9, MARSHMALLOW, "Marshmallow2")
			-- 2) two cookie rafts float back and forth along the river
			for i, info in ipairs({ { 88, 126, 6, 0 }, { 158, 196, 6.5, 0.5 } }) do
				local x0, z0 = ctx:Polar(18.5, info[1])
				local x1, z1 = ctx:Polar(18.5, info[2])
				local raft = ctx:Group("CookieRaft" .. i, x0, 6.9, z0)
				cookie(x0, 6.9, z0, 5, "CookieRaft", raft)
				ctx:Move(raft, Vector3.new(x1 - x0, 0, z1 - z0), info[3], info[4])
			end
			marshmallow(17, 142, 9, TOASTED, "Marshmallow3")
			marshmallow(17, 212, 9, MARSHMALLOW, "Marshmallow4")
			-- 3) a chocolate bar on the far bank
			local bx, bz = ctx:Polar(17.5, 240)
			ctx:Platform(bx, 9.5, bz, 8, 6, { Yaw = -240, Thickness = 1.6, Color = MILK, Name = "ChocolateBar" })
			ctx:Platform(bx, 9.55, bz, 8.05, 0.3, { Yaw = -240, Thickness = 0.2, Color = DARK, CanCollide = false, Name = "ChocolateGroove" })
			ctx:Platform(bx, 9.55, bz, 0.3, 6.05, { Yaw = -240, Thickness = 0.2, Color = DARK, CanCollide = false, Name = "ChocolateGroove" })
			-- 4) wafer steps up to the first swinging spoon
			wafer(17, 264, 13, 6, 2.4, "Wafer1")
			wafer(15.5, 286, 16.5, 6, 2.4, "Wafer2")
			waferBeam(15.5, 298, 336, 16.5, "WaferBar1")
			spoon(15.5 * math.cos(math.rad(19)), 317, 16.5, 0)
			-- 5) more marshmallows and wafers up to the second spoon
			marshmallow(15, 351, 20, TOASTED, "Marshmallow5")
			wafer(15, 10, 23.5, 6, 2.4, "Wafer3")
			waferBeam(15.5, 22, 60, 23.5, "WaferBar2")
			spoon(15.5 * math.cos(math.rad(19)), 41, 23.5, 0.25)
			marshmallow(14, 74, 27, MARSHMALLOW, "Marshmallow6")
			-- 6) the last chocolate bar: jump from here to the exit!
			local lx, lz = ctx:Polar(10.75, 98)
			ctx:Platform(lx, 30.5, lz, 4.5, 4.5, { Yaw = -98, Thickness = 1.6, Color = MILK, Name = "LastChocolate" })
			ctx:Platform(lx, 30.55, lz, 4.55, 0.3, { Yaw = -98, Thickness = 0.2, Color = DARK, CanCollide = false, Name = "ChocolateGroove" })

			---------------- Decorations ----------------
			-- a giant chocolate bar in its wrapper, leaning on the wall
			local cx, cz = ctx:Polar(22.6, 322)
			ctx:Block(cx, 7, cz, 1.2, 12, 7, { Yaw = -322, Color = MILK, Name = "GiantChocolate", CanCollide = false })
			for _, y in ipairs({ 5, 9 }) do
				local sx, sz = ctx:Polar(21.95, 322)
				ctx:Block(sx, y, sz, 0.12, 0.3, 7, { Yaw = -322, Color = DARK, CanCollide = false, Name = "ChocolateGroove" })
			end
			ctx:Block(cx, 2.4, cz, 1.5, 4.2, 7.3, { Yaw = -322, Color = WRAPPER, CanCollide = false, Name = "Wrapper" })
			ctx:Block(cx, 2.4, cz, 1.6, 0.8, 7.4, { Yaw = -322, Color = GOLD, Material = Enum.Material.Foil, CanCollide = false, Name = "Wrapper" })
		end,
	})

	------------------------------------------------------------------
	-- 4. CAKE TIERS (hard): climb a giant 3-layer party cake. Each layer
	--    has a burning candle sweeping round it - jump over it! Strawberries
	--    take you up to the next layer, and a cherry waits at the top.
	------------------------------------------------------------------
	table.insert(Sections, {
		Name = "Cake Tiers",
		Creator = "Baker Betty",
		Difficulty = 3,
		Height = 36,
		Colors = { Main = Color3.fromRGB(255, 150, 190), Accent = Color3.fromRGB(255, 246, 236) },
		Build = function(ctx: Ctx)
			local SPONGE = Color3.fromRGB(246, 214, 146)
			local PINK = Color3.fromRGB(255, 160, 200)
			local WHITE = Color3.fromRGB(255, 248, 240)
			local JAM = Color3.fromRGB(214, 40, 70)
			local SHELL = Color3.fromRGB(255, 176, 210)
			local BERRY = Color3.fromRGB(222, 30, 52)
			local LEAF = Color3.fromRGB(64, 170, 64)
			local CHERRY = Color3.fromRGB(196, 0, 30)
			local FLAME = Color3.fromRGB(255, 214, 90)

			-- One piece of a cake layer: sponge cake with frosting on top.
			-- inner/outer = how far its inside and outside faces are from the middle.
			local function cakePiece(angle: number, inner: number, outer: number, bottom: number, top: number, chord: number, frosting: Color3, name: string)
				local x, z = ctx:Polar((inner + outer) / 2, angle)
				local spongeTop = top - 0.6
				ctx:Block(x, (bottom + spongeTop) / 2, z, outer - inner, spongeTop - bottom, chord, { Yaw = -angle, Color = SPONGE, Material = Enum.Material.Sand, Name = "Sponge" })
				ctx:Platform(x, top, z, outer - inner + 0.2, chord + 0.2, { Yaw = -angle, Thickness = 0.6, Color = frosting, Name = name })
			end

			-- A burning candle that sweeps round a layer like a clock hand. JUMP over it!
			local function candle(top: number, r0: number, r1: number, speed: number, startAngle: number, name: string)
				local group = ctx:Group(name, 0, top + 0.75, 0)
				local x, z = ctx:Polar((r0 + r1) / 2, startAngle)
				local stick = ctx:Cylinder(x, top + 0.75, z, r1 - r0, 1, { Yaw = -startAngle, Parent = group :: Instance, Name = "Candle" })
				ctx:Kill(stick)
				-- the flame on its tip (just for looks)
				local fx, fz = ctx:Polar(r1 - 0.35, startAngle)
				local flame = ctx:Ball(fx, top + 1.65, fz, 0.9, { Color = FLAME, Material = Enum.Material.Neon, CanCollide = false, Parent = group :: Instance, Name = "CandleFlame" })
				local fire = Instance.new("Fire")
				fire.Size = 2
				fire.Heat = 4
				fire.Color = Color3.fromRGB(255, 140, 30)
				fire.SecondaryColor = Color3.fromRGB(255, 220, 100)
				fire.Parent = flame
				glow(flame, Color3.fromRGB(255, 190, 90), 10, 1)
				ctx:Spin(group, speed)
			end

			-- A giant strawberry step: stand on its flat leafy top.
			local function strawberry(radius: number, angle: number, top: number, size: number, name: string)
				local x, z = ctx:Polar(radius, angle)
				ctx:Ball(x, top - size * 0.55, z, size, { Color = BERRY, Name = "Strawberry" })
				ctx:Disc(x, top, z, size * 0.8, { Thickness = 0.4, Color = LEAF, Name = name })
			end

			---------------- The cake ----------------
			-- Layer 1 (bottom, widest): pink frosting with a SLIPPERY frosting border round the edge.
			for _, angle in ipairs({ 0, 45, 90, 135, 180, 225, 315 }) do
				cakePiece(angle, 17, 22.5, 0.6, 4, 12, PINK, "Layer1")
				local bx, bz = ctx:Polar(22.05, angle)
				local border = ctx:Cylinder(bx, 4.45, bz, 11, 0.9, { Yaw = -angle - 90, Color = WHITE, Name = "FrostingEdge" })
				ctx:Slippery(border)
			end
			-- Layer 2 (middle): tall vanilla layer with a stripe of jam inside.
			-- There's a slice missing above the start so you can jump out to layer 1.
			for _, angle in ipairs({ 45, 95, 195, 245, 295 }) do
				cakePiece(angle, 12, 16, 6, 16.5, 10, WHITE, "Layer2")
				local jx, jz = ctx:Polar(14, angle)
				ctx:Block(jx, 11, jz, 4.1, 0.6, 10.1, { Yaw = -angle, Color = JAM, CanCollide = false, Name = "JamStripe" })
			end
			-- Layer 3 (top, smallest)
			for _, angle in ipairs({ 20, 80, 140, 200, 260 }) do
				cakePiece(angle, 8, 11.4, 18, 26, 7, PINK, "Layer3")
			end
			-- the candles: each one sweeps towards you as you walk round its layer
			candle(4, 16.6, 21.3, 45, 100, "Candle1")
			candle(16.5, 11.6, 16.4, -55, 330, "Candle2")
			candle(26, 7.6, 11, -65, 200, "Candle3")

			---------------- The climb ----------------
			-- 1) a macaron step, then jump out through the missing slice onto layer 1
			ctx:Disc(10.5, 1.7, 0, 5, { Thickness = 0.7, Color = SHELL, Name = "Macaron" })
			ctx:Disc(10.5, 2, 0, 4.6, { Thickness = 0.3, Color = WHITE, Name = "MacaronCream" })
			ctx:Disc(10.5, 2.8, 0, 5, { Thickness = 0.8, Color = SHELL, Name = "Macaron" })
			-- 2) walk round layer 1 (counter-clockwise) to the strawberries at the gap
			strawberry(19.5, 255, 9, 3.2, "StrawberryStep1")
			strawberry(19, 275, 12.75, 3.2, "StrawberryStep2")
			-- 3) walk round layer 2 (clockwise) to the next strawberry
			strawberry(13.8, 162, 21.3, 3, "StrawberryStep3")
			-- 4) walk round layer 3 (clockwise) to the last strawberry
			strawberry(14, 350, 29.3, 3.2, "StrawberryStep4")
			-- 5) the cherry-topped cake top: jump from here to the exit!
			local tx, tz = ctx:Polar(12, 320)
			ctx:Disc(tx, 32.5, tz, 7, { Thickness = 1.5, Color = WHITE, Name = "CakeTop" })
			ctx:Disc(tx, 31.6, tz, 7.3, { Thickness = 0.5, Color = PINK, CanCollide = false, Name = "CakeTopIcing" })
			local cx, cz = ctx:Polar(14, 320)
			local cherry = ctx:Ball(cx, 33.5, cz, 2.2, { Color = CHERRY, Reflectance = 0.2, CanCollide = false, Name = "Cherry" })
			local sx, sz = ctx:Polar(14.3, 320)
			ctx:Cylinder(sx, 35, sz, 1.6, 0.2, { Roll = 70, Yaw = -320, Color = LEAF, CanCollide = false, Name = "CherryStem" })
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = Color3.fromRGB(255, 220, 230)
			sparkles.Parent = cherry
			for _, angle in ipairs({ 306, 334 }) do
				local wx, wz = ctx:Polar(13.6, angle)
				ctx:Ball(wx, 32.9, wz, 1.4, { Color = WHITE, CanCollide = false, Name = "WhippedCream" })
			end
		end,
	})
end
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
