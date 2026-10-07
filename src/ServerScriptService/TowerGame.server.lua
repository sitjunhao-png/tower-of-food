--[[
	TOWER OF FOOD - main server script (v2)
	Where it goes: ServerScriptService  (type: Script, name: TowerGame)
	It needs the ModuleScript "TowerSections" right next to it.

	What it does:
	  * builds the lobby (the bottom floor of the tower)
	  * bakes a brand-new random tower of food sections every 6-8 minutes
	  * coins, XP levels, skill points, the shop (coils + trails), gamepasses,
	    codes, round bonuses ("mutators"), saving, and the Top Wins board
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local TowerSections = require(script.Parent:WaitForChild("TowerSections"))

------------------------------------------------------------------------
-- SETTINGS (safe to change)
------------------------------------------------------------------------
local CONFIG = {
	STAGES = 8, -- sections in each tower
	ROUND_MIN_SECONDS = 6 * 60,
	ROUND_MAX_SECONDS = 8 * 60,
	COINS_PER_STAGE = 12.5,
	TOP_BONUS = 100,
	XP_PER_STAGE = 10,
	XP_PER_WIN = 100,
	RESPAWN_TIME = 2,
	MUTATOR_CHANCE = 0.4, -- chance that a round gets a bonus like x2 coins
	DATASTORE_NAME = "TowerOfFood_v1",
	WINS_STORE_NAME = "TowerOfFood_Wins",

	-- Gamepasses: make them on the Roblox website (Creator Hub > your game >
	-- Monetization > Passes) and paste each pass ID here. 0 = "Coming soon".
	PASSES = {
		{ Key = "X2Coins", Name = "x2 Coins", Desc = "Double coins forever!", Id = 0 },
		{ Key = "DoubleJump", Name = "Double Jump", Desc = "Jump again in mid-air.", Id = 0 },
		{ Key = "SkipSection", Name = "Skip Section", Desc = "Skip one section every round.", Id = 0 },
		{ Key = "VIP", Name = "VIP", Desc = "Gold VIP tag + chat tag and +25% coins.", Id = 0 },
		{ Key = "NuggetTrail", Name = "Nugget Trail", Desc = "Leave a trail of tasty nuggets.", Id = 0 },
	},

	-- Music: in Studio open the Toolbox > Audio, pick songs, right-click >
	-- "Copy Asset ID", then add lines like:
	--   { Name = "Cloud Mountain", Id = "rbxassetid://1234567890" },
	MUSIC = {},

	-- Codes players can type in Menu > Codes (code = coins). Each works once per player.
	CODES = {
		FOOD = 100,
		NUGGET = 50,
	},
}

type ShopItem = {
	Id: string,
	Name: string,
	Category: string,
	Price: number,
	Desc: string,
	Color: Color3,
	SpeedBonus: number?,
	GravityCut: number?,
	TrailColors: { Color3 }?,
	Sprinkles: boolean?,
}

local SHOP_ITEMS: { ShopItem } = {
	{ Id = "SpeedCoil", Name = "Speed Coil", Category = "Gear", Price = 250, Desc = "Run way faster while you hold it.", Color = Color3.fromRGB(70, 160, 255), SpeedBonus = 10 },
	{ Id = "GravityCoil", Name = "Gravity Coil", Category = "Gear", Price = 400, Desc = "Super high jumps while you hold it.", Color = Color3.fromRGB(170, 90, 255), GravityCut = 0.55 },
	{ Id = "FusionCoil", Name = "Fusion Coil", Category = "Gear", Price = 1000, Desc = "Speed AND high jumps in one coil!", Color = Color3.fromRGB(255, 110, 190), SpeedBonus = 10, GravityCut = 0.55 },
	{ Id = "KetchupTrail", Name = "Ketchup Trail", Category = "Trail", Price = 150, Desc = "A saucy red streak.", Color = Color3.fromRGB(220, 30, 30), TrailColors = { Color3.fromRGB(255, 40, 30), Color3.fromRGB(170, 0, 0) } },
	{ Id = "MustardTrail", Name = "Mustard Trail", Category = "Trail", Price = 150, Desc = "Zippy yellow mustard.", Color = Color3.fromRGB(255, 205, 40), TrailColors = { Color3.fromRGB(255, 225, 60), Color3.fromRGB(230, 170, 0) } },
	{
		Id = "RainbowTrail",
		Name = "Rainbow Trail",
		Category = "Trail",
		Price = 500,
		Desc = "Every colour of the candy shop.",
		Color = Color3.fromRGB(120, 200, 255),
		TrailColors = {
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(255, 170, 40),
			Color3.fromRGB(255, 240, 60),
			Color3.fromRGB(80, 220, 90),
			Color3.fromRGB(70, 150, 255),
			Color3.fromRGB(180, 90, 255),
		},
	},
	{ Id = "SprinkleTrail", Name = "Sprinkle Trail", Category = "Trail", Price = 800, Desc = "Rains sprinkles wherever you go.", Color = Color3.fromRGB(255, 130, 200), Sprinkles = true },
	{ Id = "GoldenFryTrail", Name = "Golden Fry Trail", Category = "Trail", Price = 1500, Desc = "Shiny golden fries. Fancy!", Color = Color3.fromRGB(255, 200, 40), TrailColors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 170, 0) }, Sprinkles = true },
}

type SkillDef = { Id: string, Name: string, Desc: string, Max: number, PerPoint: number }

local SKILLS: { SkillDef } = {
	{ Id = "Speed", Name = "Quick Feet", Desc = "+0.4 walk speed per point", Max = 10, PerPoint = 0.4 },
	{ Id = "Jump", Name = "Springy Legs", Desc = "+0.3 jump height per point", Max = 10, PerPoint = 0.3 },
	{ Id = "Coins", Name = "Coin Chef", Desc = "+5% coins per point", Max = 10, PerPoint = 0.05 },
	{ Id = "XP", Name = "Fast Learner", Desc = "+5% XP per point", Max = 10, PerPoint = 0.05 },
}

type Mutator = { Key: string, Label: string, Message: string }

local MUTATORS: { Mutator } = {
	{ Key = "x2", Label = "x2", Message = "DOUBLE COINS this round!" },
	{ Key = "LowGravity", Label = "LOW GRAVITY", Message = "Low gravity this round - float away!" },
	{ Key = "Speedy", Label = "SPEEDY", Message = "Everyone is super speedy this round!" },
	{ Key = "Bouncy", Label = "BOUNCY", Message = "Bouncy jumps this round!" },
}

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local K = TowerSections.Constants
local FLOOR_Y = K.TOWER_FLOOR_Y -- 12
local SHAFT_R = K.SHAFT_RADIUS -- 26
local LOBBY_R = K.LOBBY_RADIUS -- 52
local CEILING_Y = K.LOBBY_CEILING_Y -- 34
local WALL_SEGMENTS = 32
local DOOR_ANGLES = { 0, 90, 180, 270 }
local DOOR_TOP_Y = FLOOR_Y + 14
local NORMAL_GRAVITY = 196.2
local BASE_WALKSPEED = 16
local BASE_JUMPHEIGHT = 7.2

local WHITE = Color3.fromRGB(246, 243, 236)
local CREAM = Color3.fromRGB(232, 225, 210)
local STONE = Color3.fromRGB(205, 205, 212)
local GOLD = Color3.fromRGB(255, 200, 60)
local DARK = Color3.fromRGB(40, 32, 28)
local BANNER_COLORS = { Color3.fromRGB(205, 40, 40), Color3.fromRGB(240, 190, 40), Color3.fromRGB(70, 170, 70) }

local ITEMS_BY_ID: { [string]: ShopItem } = {}
for _, item in ipairs(SHOP_ITEMS) do
	ITEMS_BY_ID[item.Id] = item
end
local SKILLS_BY_ID: { [string]: SkillDef } = {}
for _, skill in ipairs(SKILLS) do
	SKILLS_BY_ID[skill.Id] = skill
end

local rng = Random.new()
Players.RespawnTime = CONFIG.RESPAWN_TIME

------------------------------------------------------------------------
-- Shared folder, remotes and info for the client scripts
------------------------------------------------------------------------
local shared = ReplicatedStorage:FindFirstChild("TowerOfFood")
if not shared then
	shared = Instance.new("Folder")
	shared.Name = "TowerOfFood"
	shared.Parent = ReplicatedStorage
end
local sharedFolder = shared :: Folder

local function getRemote(className: string, name: string): Instance
	local existing = sharedFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = sharedFolder
	return remote
end

local notifyEvent = getRemote("RemoteEvent", "Notify") :: RemoteEvent
local shopFunction = getRemote("RemoteFunction", "ShopAction") :: RemoteFunction
local deathEvent = getRemote("RemoteEvent", "RequestDeath") :: RemoteEvent
local skipEvent = getRemote("RemoteEvent", "SkipSection") :: RemoteEvent
local promptPassEvent = getRemote("RemoteEvent", "PromptPass") :: RemoteEvent

do
	local items = {}
	for _, item in ipairs(SHOP_ITEMS) do
		table.insert(items, { Id = item.Id, Name = item.Name, Category = item.Category, Price = item.Price, Desc = item.Desc, Color = item.Color:ToHex() })
	end
	sharedFolder:SetAttribute("ShopItems", HttpService:JSONEncode(items))

	local skills = {}
	for _, skill in ipairs(SKILLS) do
		table.insert(skills, { Id = skill.Id, Name = skill.Name, Desc = skill.Desc, Max = skill.Max, PerPoint = skill.PerPoint })
	end
	sharedFolder:SetAttribute("Skills", HttpService:JSONEncode(skills))

	local passes = {}
	for _, pass in ipairs(CONFIG.PASSES) do
		table.insert(passes, { Key = pass.Key, Name = pass.Name, Desc = pass.Desc, Id = pass.Id })
	end
	sharedFolder:SetAttribute("Passes", HttpService:JSONEncode(passes))
	sharedFolder:SetAttribute("Music", HttpService:JSONEncode(CONFIG.MUSIC))
	sharedFolder:SetAttribute("Mutator", "")
	sharedFolder:SetAttribute("MutatorLabel", "")
end

local function notify(player: Player, text: string, kind: string)
	notifyEvent:FireClient(player, text, kind)
end

local function notifyAll(text: string, kind: string)
	notifyEvent:FireAllClients(text, kind)
end

------------------------------------------------------------------------
-- Building helpers
------------------------------------------------------------------------
local function makePart(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, name: string?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if name then
		p.Name = name
	end
	p.Parent = parent
	return p
end

-- Flat round disc centred on (x, z) whose top surface is at topY.
local function makeDisc(parent: Instance, diameter: number, thickness: number, topY: number, color: Color3, material: Enum.Material?, name: string?, x: number?, z: number?): Part
	local cf = CFrame.new(x or 0, topY - thickness / 2, z or 0) * CFrame.Angles(0, 0, math.rad(90))
	return makePart(parent, Vector3.new(thickness, diameter, diameter), cf, color, material, name, Enum.PartType.Cylinder)
end

local function polar(radius: number, angleDeg: number, y: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(radius * math.cos(a), y, radius * math.sin(a))
end

-- A CFrame at (radius, angle, y) whose front (-Z) faces the tower axis.
local function facingAxis(radius: number, angleDeg: number, y: number): CFrame
	local pos = polar(radius, angleDeg, y)
	return CFrame.lookAt(pos, Vector3.new(0, y, 0))
end

-- A CFrame at (radius, angle, y) whose front faces away from the axis.
local function facingOut(radius: number, angleDeg: number, y: number): CFrame
	local pos = polar(radius, angleDeg, y)
	return CFrame.lookAt(pos, pos + Vector3.new(pos.X, 0, pos.Z))
end

local function angleDiff(a: number, b: number): number
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return math.abs(d)
end

-- A ring of wall blocks between y0 and y1. `skip(angle)` can leave gaps (doorways).
local function makeRing(parent: Instance, innerRadius: number, thickness: number, y0: number, y1: number, count: number, color: Color3, transparency: number, material: Enum.Material?, skip: ((number) -> boolean)?)
	local height = y1 - y0
	if height <= 0.05 then
		return
	end
	local center = innerRadius + thickness / 2
	local width = 2 * math.pi * (innerRadius + thickness) / count + 0.2
	for i = 0, count - 1 do
		local angle = i * 360 / count
		if not (skip and skip(angle)) then
			local p = makePart(parent, Vector3.new(width, height, thickness), facingAxis(center, angle, y0 + height / 2), color, material, "Wall")
			p.Transparency = transparency
		end
	end
end

local function addText(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3, font: Enum.Font, strokeTransparency: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.TextStrokeTransparency = strokeTransparency or 1
	label.Parent = parent
	return label
end

-- A sign: a part with a SurfaceGui on its front face. Returns the SurfaceGui.
local function makeSign(parent: Instance, cframe: CFrame, size: Vector3, background: Color3?): SurfaceGui
	local board = makePart(parent, size, cframe, background or WHITE, Enum.Material.SmoothPlastic, "Sign")
	board.CanCollide = false
	if not background then
		board.Transparency = 1
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	return gui
end

------------------------------------------------------------------------
-- LOBBY (built once) - the ground floor of the tower
------------------------------------------------------------------------
local winsBoardRows: { TextLabel } = {}

local function buildLobby()
	local old = workspace:FindFirstChild("TowerOfFoodWorld")
	if old then
		old:Destroy()
	end
	-- Remove the template baseplate + spawn so the tower is the whole game
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end

	local world = Instance.new("Folder")
	world.Name = "TowerOfFoodWorld"
	world.Parent = workspace

	-- Floor with glowing ring inlays
	makeDisc(world, 112, 2, 0, WHITE, Enum.Material.SmoothPlastic, "LobbyFloor")
	makeDisc(world, 90, 0.2, 0.06, Color3.fromRGB(90, 200, 255), Enum.Material.Neon, "FloorRingGlow")
	makeDisc(world, 88, 0.2, 0.08, CREAM, Enum.Material.SmoothPlastic, "FloorRingInner")
	makeDisc(world, 64, 0.2, 0.1, Color3.fromRGB(255, 190, 70), Enum.Material.Neon, "PedestalGlow")

	-- Outer wall, glowing strip, ceiling ring
	makeRing(world, LOBBY_R, 2, -1, CEILING_Y + 2, 40, CREAM, 0)
	makeRing(world, LOBBY_R - 0.4, 0.4, 2, 2.6, 40, Color3.fromRGB(90, 200, 255), 0, Enum.Material.Neon)
	makeRing(world, LOBBY_R - 0.4, 0.4, CEILING_Y - 3, CEILING_Y - 2.4, 40, Color3.fromRGB(255, 190, 70), 0, Enum.Material.Neon)
	for i = 0, 39 do
		local angle = i * 9
		local mid = (SHAFT_R + 2 + LOBBY_R + 2) / 2
		local depth = (LOBBY_R + 2) - (SHAFT_R + 2) + 1
		local width = 2 * math.pi * (LOBBY_R + 2) / 40 + 0.4
		makePart(world, Vector3.new(width, 2, depth), facingAxis(mid, angle, CEILING_Y + 1), STONE, Enum.Material.SmoothPlastic, "Ceiling")
	end

	-- Pedestal = the tower floor (falling players land here)
	makePart(world, Vector3.new(FLOOR_Y, 56, 56), CFrame.new(0, FLOOR_Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.SmoothPlastic, "Pedestal", Enum.PartType.Cylinder)
	makeDisc(world, 57, 0.6, FLOOR_Y - 0.4, Color3.fromRGB(255, 190, 70), Enum.Material.Neon, "PedestalRim")
	makeDisc(world, 46, 0.1, FLOOR_Y + 0.05, CREAM, Enum.Material.SmoothPlastic, "TowerFloorInlay")
	makeDisc(world, 13, 0.1, FLOOR_Y + 0.1, Color3.fromRGB(255, 190, 70), Enum.Material.Neon, "StartGlow")
	makeDisc(world, 12, 0.1, FLOOR_Y + 0.15, WHITE, Enum.Material.SmoothPlastic, "StartPlate")

	-- Lobby band of the shaft wall, with a doorway above each staircase
	local function isDoor(angle: number): boolean
		for _, doorAngle in ipairs(DOOR_ANGLES) do
			if angleDiff(angle, doorAngle) <= 11.3 then
				return true
			end
		end
		return false
	end
	makeRing(world, SHAFT_R, 2, FLOOR_Y, DOOR_TOP_Y, WALL_SEGMENTS, WHITE, 0, Enum.Material.SmoothPlastic, isDoor)
	makeRing(world, SHAFT_R, 2, DOOR_TOP_Y, CEILING_Y, WALL_SEGMENTS, WHITE, 0)

	for _, doorAngle in ipairs(DOOR_ANGLES) do
		-- Staircase: 12 steps, 1 stud up and 1.5 studs in each
		for step = 1, 12 do
			local r = 46 - (step - 0.5) * 1.5
			makePart(world, Vector3.new(12, step, 1.5), facingAxis(r, doorAngle, step / 2), (step % 2 == 0) and WHITE or CREAM, Enum.Material.SmoothPlastic, "Step")
		end
		-- Glowing doorway frame
		local frameColor = Color3.fromRGB(255, 255, 240)
		for _, side in ipairs({ -1, 1 }) do
			local sideAngle = doorAngle + side * 15.5
			makePart(world, Vector3.new(1, 14, 3), facingAxis(SHAFT_R + 1, sideAngle, FLOOR_Y + 7), frameColor, Enum.Material.Neon, "DoorGlow")
		end
		-- "TOWER OF FOOD" sign above the doorway, outside
		local gui = makeSign(world, facingOut(SHAFT_R + 2.3, doorAngle, DOOR_TOP_Y + 4), Vector3.new(16, 5, 0.4), Color3.fromRGB(255, 120, 40))
		addText(gui, "TOWER OF FOOD", UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84), Color3.new(1, 1, 1), Enum.Font.Sarpanch, 0.4)

		-- Braziers either side of the stairs
		for _, side in ipairs({ -1, 1 }) do
			local base = polar(44, doorAngle + side * 12.5, 0)
			local pedestal = makePart(world, Vector3.new(2.4, 4, 2.4), CFrame.new(base + Vector3.new(0, 2, 0)), STONE, Enum.Material.SmoothPlastic, "BrazierStand")
			local bowl = makeDisc(world, 4, 1.2, 5.2, Color3.fromRGB(90, 85, 85), Enum.Material.Metal, "BrazierBowl", base.X, base.Z)
			local flame = makePart(world, Vector3.new(1, 1, 1), CFrame.new(base + Vector3.new(0, 5.6, 0)), Color3.fromRGB(255, 160, 40), Enum.Material.Neon, "Flame")
			flame.Transparency = 1
			flame.CanCollide = false
			local fire = Instance.new("Fire")
			fire.Size = 5
			fire.Heat = 9
			fire.Color = Color3.fromRGB(255, 150, 40)
			fire.SecondaryColor = Color3.fromRGB(255, 230, 120)
			fire.Parent = flame
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 170, 80)
			light.Range = 18
			light.Brightness = 1.6
			light.Parent = flame
			pedestal.CanCollide = true
			bowl.CanCollide = true
		end
	end

	-- Spawn pads between the staircases, facing the tower
	for _, angle in ipairs({ 45, 135, 225, 315 }) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.CFrame = facingAxis(40, angle, 0.5)
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Color = WHITE
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = world
		makePart(world, Vector3.new(9, 0.6, 9), facingAxis(40, angle, 0.3), Color3.fromRGB(255, 190, 70), Enum.Material.Neon, "SpawnGlow")
	end

	-- Soda pools (decoration)
	for _, angle in ipairs({ 22.5, 112.5, 202.5, 292.5 }) do
		local pos = polar(46, angle, 0)
		makeDisc(world, 9, 0.3, 0.22, Color3.fromRGB(60, 160, 255), Enum.Material.Glass, "SodaPool", pos.X, pos.Z).Transparency = 0.2
		makeDisc(world, 10, 0.3, 0.18, WHITE, Enum.Material.SmoothPlastic, "PoolRim", pos.X, pos.Z)
	end

	-- Hanging banners on the outer wall (ketchup / mustard / lettuce)
	local boardAngles = { 157.5, 337.5 }
	local bannerIndex = 0
	for i = 0, 15 do
		local angle = i * 22.5 + 11.25
		local nearBoard = false
		for _, b in ipairs(boardAngles) do
			if angleDiff(angle, b) < 20 then
				nearBoard = true
			end
		end
		if not nearBoard then
			bannerIndex += 1
			local color = BANNER_COLORS[(bannerIndex - 1) % #BANNER_COLORS + 1]
			makePart(world, Vector3.new(5, 12, 0.3), facingAxis(LOBBY_R - 0.6, angle, CEILING_Y - 10), color, Enum.Material.Fabric, "Banner")
			makePart(world, Vector3.new(6, 0.5, 0.5), facingAxis(LOBBY_R - 0.6, angle, CEILING_Y - 3.8), GOLD, Enum.Material.Metal, "BannerRod")
			makePart(world, Vector3.new(3.5, 3.5, 0.32), facingAxis(LOBBY_R - 0.62, angle, CEILING_Y - 15.5) * CFrame.Angles(0, 0, math.rad(45)), color, Enum.Material.Fabric, "BannerTip")
		end
	end

	-- Top Wins board
	local winsGui = makeSign(world, facingAxis(LOBBY_R - 0.5, boardAngles[1], 13), Vector3.new(16, 16, 0.4), DARK)
	addText(winsGui, "TOP WINS", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.12), GOLD, Enum.Font.Sarpanch)
	for row = 1, 10 do
		local label = addText(winsGui, row .. ".  ---", UDim2.fromScale(0.07, 0.15 + (row - 1) * 0.083), UDim2.fromScale(0.86, 0.07), Color3.new(1, 1, 1), Enum.Font.GothamBold)
		label.TextXAlignment = Enum.TextXAlignment.Left
		winsBoardRows[row] = label
	end

	-- How to play board
	local howGui = makeSign(world, facingAxis(LOBBY_R - 0.5, boardAngles[2], 13), Vector3.new(16, 16, 0.4), DARK)
	addText(howGui, "HOW TO PLAY", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.12), GOLD, Enum.Font.Sarpanch)
	local lines = {
		"Climb the tower before the timer runs out!",
		"No checkpoints. If you fall, you fall.",
		"+12.5 coins every section, +100 at the top.",
		"Red glowing stuff = OUCH. Don't touch it.",
		"Open the Menu for coils, trails and skills.",
		"A new tower is baked every 6-8 minutes.",
	}
	for i, line in ipairs(lines) do
		local label = addText(howGui, line, UDim2.fromScale(0.06, 0.17 + (i - 1) * 0.135), UDim2.fromScale(0.88, 0.1), Color3.new(1, 1, 1), Enum.Font.GothamBold)
		label.TextXAlignment = Enum.TextXAlignment.Left
	end
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.Name == "TowerOfFoodFX" then
			child:Destroy()
		end
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "TowerOfFoodFX"
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 0.92
	bloom.Parent = Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "TowerOfFoodFX"
	color.Saturation = 0.12
	color.Contrast = 0.05
	color.Parent = Lighting
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "TowerOfFoodFX"
	atmosphere.Density = 0.2
	atmosphere.Offset = 0.2
	atmosphere.Haze = 0.6
	atmosphere.Glare = 0
	atmosphere.Color = Color3.fromRGB(205, 215, 255)
	atmosphere.Decay = Color3.fromRGB(110, 120, 160)
	atmosphere.Parent = Lighting
end

------------------------------------------------------------------------
-- PLAYER DATA
------------------------------------------------------------------------
type PlayerData = {
	Coins: number,
	XP: number,
	Wins: number,
	Owned: { [string]: boolean },
	EquippedTrail: string,
	Skills: { [string]: number },
	Codes: { [string]: boolean },
	NoSave: boolean,
	SavedWins: number,
}

type RoundState = { Stage: number, Won: boolean }

local store: DataStore? = nil
local winsStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)
		winsStore = DataStoreService:GetOrderedDataStore(CONFIG.WINS_STORE_NAME)
	end)
	if not ok then
		warn("[TowerOfFood] DataStores unavailable, progress will NOT save (publish the game and enable Studio API access): " .. tostring(err))
	end
end

local playerData: { [Player]: PlayerData } = {}
local roundState: { [Player]: RoundState } = {}
local lastAction: { [Player]: number } = {}

local function defaultData(): PlayerData
	return {
		Coins = 0,
		XP = 0,
		Wins = 0,
		Owned = {},
		EquippedTrail = "",
		Skills = {},
		Codes = {},
		NoSave = false,
		SavedWins = 0,
	}
end

local function loadData(player: Player): PlayerData
	local d = defaultData()
	local ds = store
	if not ds then
		d.NoSave = true
		return d
	end
	local ok, saved = false, nil
	for attempt = 1, 3 do
		ok, saved = pcall(function()
			return ds:GetAsync("Player_" .. player.UserId)
		end)
		if ok then
			break
		end
		local message = tostring(saved)
		if string.find(message, "403") or string.find(message, "Studio") or string.find(message, "publish") then
			break -- saving isn't allowed here (e.g. Studio without API access), retrying won't help
		end
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	if not ok then
		warn("[TowerOfFood] Could not load data for " .. player.Name .. ": " .. tostring(saved))
		d.NoSave = true -- never overwrite real data with an empty save
		return d
	end
	if type(saved) == "table" then
		d.Coins = tonumber(saved.Coins) or 0
		d.XP = tonumber(saved.XP) or 0
		d.Wins = tonumber(saved.Wins) or 0
		if type(saved.Owned) == "table" then
			for id, owned in pairs(saved.Owned) do
				if type(id) == "string" and owned == true then
					d.Owned[id] = true
				end
			end
		end
		if type(saved.EquippedTrail) == "string" then
			d.EquippedTrail = saved.EquippedTrail
		end
		if type(saved.Skills) == "table" then
			for id, points in pairs(saved.Skills) do
				if type(id) == "string" and SKILLS_BY_ID[id] and tonumber(points) then
					d.Skills[id] = math.clamp(math.floor(tonumber(points) :: number), 0, SKILLS_BY_ID[id].Max)
				end
			end
		end
		if type(saved.Codes) == "table" then
			for code, used in pairs(saved.Codes) do
				if type(code) == "string" and used == true then
					d.Codes[code] = true
				end
			end
		end
	end
	d.SavedWins = d.Wins
	return d
end

local function saveData(player: Player)
	local d = playerData[player]
	local ds = store
	if not d or d.NoSave or not ds then
		return
	end
	local payload = {
		Coins = d.Coins,
		XP = d.XP,
		Wins = d.Wins,
		Owned = d.Owned,
		EquippedTrail = d.EquippedTrail,
		Skills = d.Skills,
		Codes = d.Codes,
	}
	local ok, err = pcall(function()
		ds:SetAsync("Player_" .. player.UserId, payload)
	end)
	if not ok then
		warn("[TowerOfFood] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
	local ws = winsStore
	if ws and d.Wins ~= d.SavedWins then
		local okWins = pcall(function()
			ws:SetAsync(tostring(player.UserId), d.Wins)
		end)
		if okWins then
			d.SavedWins = d.Wins
		end
	end
end

------------------------------------------------------------------------
-- Levels, skills, coins
------------------------------------------------------------------------
local function levelInfo(xp: number): (number, number, number)
	local level, need = 1, 100
	while xp >= need do
		xp -= need
		level += 1
		need = 100 + (level - 1) * 50
	end
	return level, xp, need
end

local function skillLevel(player: Player, id: string): number
	local d = playerData[player]
	return d and (d.Skills[id] or 0) or 0
end

local function spentSkillPoints(d: PlayerData): number
	local total = 0
	for _, points in pairs(d.Skills) do
		total += points
	end
	return total
end

local function roundTo(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

local function formatCoins(n: number): string
	if n % 1 == 0 then
		return tostring(math.floor(n))
	end
	return string.format("%.1f", n)
end

local currentMutator = ""

local function getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return char, hum, (root and root:IsA("BasePart")) and root or nil
end

local function updateOverhead(player: Player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local tag: Instance? = head:FindFirstChild("FoodTag")
	if not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = "FoodTag"
		gui.Size = UDim2.fromOffset(110, 44)
		gui.StudsOffset = Vector3.new(0, 2.3, 0)
		gui.MaxDistance = 70
		gui.LightInfluence = 0
		gui.Parent = head
		local vip = addText(gui, "VIP", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.45), GOLD, Enum.Font.Sarpanch, 0.3)
		vip.Name = "VIP"
		local level = addText(gui, "Lv. 1", UDim2.fromScale(0, 0.45), UDim2.fromScale(1, 0.55), Color3.new(1, 1, 1), Enum.Font.Sarpanch, 0.3)
		level.Name = "Level"
		tag = gui
	end
	local tagGui = tag :: Instance
	local levelLabel = tagGui:FindFirstChild("Level")
	local vipLabel = tagGui:FindFirstChild("VIP")
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = "Lv. " .. tostring(player:GetAttribute("Level") or 1)
	end
	if vipLabel and vipLabel:IsA("TextLabel") then
		vipLabel.Visible = player:GetAttribute("Pass_VIP") == true
	end
end

local function refreshStats(player: Player)
	local d = playerData[player]
	if not d then
		return
	end
	local level, into, need = levelInfo(d.XP)
	local oldLevel = player:GetAttribute("Level")
	player:SetAttribute("Coins", d.Coins)
	player:SetAttribute("Level", level)
	player:SetAttribute("LevelXP", into)
	player:SetAttribute("LevelNeed", need)
	player:SetAttribute("Wins", d.Wins)
	player:SetAttribute("SkillPoints", math.max(0, (level - 1) - spentSkillPoints(d)))
	for _, skill in ipairs(SKILLS) do
		player:SetAttribute("Skill_" .. skill.Id, d.Skills[skill.Id] or 0)
	end
	for _, item in ipairs(SHOP_ITEMS) do
		player:SetAttribute("Owned_" .. item.Id, d.Owned[item.Id] == true)
	end
	player:SetAttribute("EquippedTrail", d.EquippedTrail)

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local levelValue = ls:FindFirstChild("Level")
		local winsValue = ls:FindFirstChild("Wins")
		if levelValue and levelValue:IsA("IntValue") then
			levelValue.Value = level
		end
		if winsValue and winsValue:IsA("IntValue") then
			winsValue.Value = d.Wins
		end
	end
	updateOverhead(player)
	if typeof(oldLevel) == "number" and level > oldLevel then
		notify(player, "LEVEL UP! You are now Level " .. level .. " - you got a skill point!", "level")
	end
end

local function coinMultiplier(player: Player): number
	local m = 1
	if player:GetAttribute("Pass_X2Coins") == true then
		m *= 2
	end
	if player:GetAttribute("Pass_VIP") == true then
		m *= 1.25
	end
	m *= 1 + skillLevel(player, "Coins") * SKILLS_BY_ID.Coins.PerPoint
	if currentMutator == "x2" then
		m *= 2
	end
	return m
end

local function award(player: Player, coins: number, xp: number, message: string)
	local d = playerData[player]
	if not d then
		return
	end
	coins = roundTo(coins * coinMultiplier(player), 0.1)
	xp = math.floor(xp * (1 + skillLevel(player, "XP") * SKILLS_BY_ID.XP.PerPoint) + 0.5)
	d.Coins = roundTo(d.Coins + coins, 0.1)
	d.XP += xp
	refreshStats(player)
	notify(player, ("%s  +%s coins  +%d XP"):format(message, formatCoins(coins), xp), "coins")
end

------------------------------------------------------------------------
-- Movement (skills, coils and mutators all feed into this)
------------------------------------------------------------------------
local function equippedCoil(char: Model): ShopItem?
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			local id = child:GetAttribute("CoilId")
			if type(id) == "string" and ITEMS_BY_ID[id] then
				return ITEMS_BY_ID[id]
			end
		end
	end
	return nil
end

local function applyMovement(player: Player)
	local char, hum, root = getCharacterParts(player)
	if not char or not hum or not root then
		return
	end
	local speed = BASE_WALKSPEED + skillLevel(player, "Speed") * SKILLS_BY_ID.Speed.PerPoint
	local jump = BASE_JUMPHEIGHT + skillLevel(player, "Jump") * SKILLS_BY_ID.Jump.PerPoint
	if currentMutator == "Speedy" then
		speed += 8
	elseif currentMutator == "Bouncy" then
		jump += 3
	end
	local coil = equippedCoil(char)
	if coil and coil.SpeedBonus then
		speed += coil.SpeedBonus
	end
	hum.UseJumpPower = false
	hum.WalkSpeed = speed
	hum.JumpHeight = jump

	for _, child in ipairs(root:GetChildren()) do
		if child.Name == "CoilAntiGravity" then
			child:Destroy()
		end
	end
	if coil and coil.GravityCut then
		local att = root:FindFirstChild("CoilAttachment")
		if not att or not att:IsA("Attachment") then
			local newAtt = Instance.new("Attachment")
			newAtt.Name = "CoilAttachment"
			newAtt.Parent = root
			att = newAtt
		end
		local force = Instance.new("VectorForce")
		force.Name = "CoilAntiGravity"
		force.Attachment0 = att :: Attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = true
		force.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * coil.GravityCut, 0)
		force.Parent = root
	end
end

local function makeCoil(player: Player, item: ShopItem): Tool
	local tool = Instance.new("Tool")
	tool.Name = item.Name
	tool.ToolTip = item.Desc
	tool.CanBeDropped = false
	tool:SetAttribute("CoilId", item.Id)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(1.8, 0.9, 0.9)
	handle.Color = item.Color
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	-- little spring rings so it looks like a coil
	for i = -2, 2 do
		local ringPart = Instance.new("Part")
		ringPart.Name = "CoilRing"
		ringPart.Shape = Enum.PartType.Cylinder
		ringPart.Size = Vector3.new(0.18, 1.25, 1.25)
		ringPart.Color = item.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		ringPart.Material = Enum.Material.SmoothPlastic
		ringPart.CanCollide = false
		ringPart.Massless = true
		ringPart.CFrame = handle.CFrame * CFrame.new(i * 0.35, 0, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = ringPart
		weld.Parent = ringPart
		ringPart.Parent = tool
	end

	tool.Equipped:Connect(function()
		task.defer(applyMovement, player)
	end)
	tool.Unequipped:Connect(function()
		task.defer(applyMovement, player)
	end)
	return tool
end

local function giveTools(player: Player)
	local d = playerData[player]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not d or not backpack then
		return
	end
	for _, item in ipairs(SHOP_ITEMS) do
		if item.Category == "Gear" and d.Owned[item.Id] and not backpack:FindFirstChild(item.Name) then
			local char = player.Character
			if not (char and char:FindFirstChild(item.Name)) then
				makeCoil(player, item).Parent = backpack
			end
		end
	end
end

------------------------------------------------------------------------
-- Trails (shop trails + Nugget Trail pass)
------------------------------------------------------------------------
local function colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for i, c in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keypoints)
end

local function applyTrail(player: Player)
	local _, _, root = getCharacterParts(player)
	local d = playerData[player]
	if not root or not d then
		return
	end
	for _, child in ipairs(root:GetChildren()) do
		if child.Name == "FoodTrailFX" then
			child:Destroy()
		end
	end

	local item = ITEMS_BY_ID[d.EquippedTrail]
	if item and item.Category == "Trail" and d.Owned[item.Id] then
		if item.TrailColors then
			local top = Instance.new("Attachment")
			top.Name = "FoodTrailFX"
			top.Position = Vector3.new(0, 0.9, 0)
			top.Parent = root
			local bottom = Instance.new("Attachment")
			bottom.Name = "FoodTrailFX"
			bottom.Position = Vector3.new(0, -0.9, 0)
			bottom.Parent = root
			local trail = Instance.new("Trail")
			trail.Name = "FoodTrailFX"
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Color = colorSequence(item.TrailColors)
			trail.Lifetime = 0.55
			trail.LightEmission = 0.4
			trail.FaceCamera = true
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.2),
			})
			trail.Parent = root
		end
		if item.Sprinkles then
			local sprinkles = Instance.new("ParticleEmitter")
			sprinkles.Name = "FoodTrailFX"
			sprinkles.Color = colorSequence(item.TrailColors or {
				Color3.fromRGB(255, 90, 140),
				Color3.fromRGB(90, 200, 255),
				Color3.fromRGB(255, 230, 80),
				Color3.fromRGB(120, 230, 120),
			})
			sprinkles.Size = NumberSequence.new(0.22)
			sprinkles.Rate = 22
			sprinkles.Lifetime = NumberRange.new(0.8, 1.3)
			sprinkles.Speed = NumberRange.new(1, 3)
			sprinkles.SpreadAngle = Vector2.new(180, 180)
			sprinkles.Acceleration = Vector3.new(0, -12, 0)
			sprinkles.LightEmission = 0.3
			sprinkles.Parent = root
		end
	end

	if player:GetAttribute("Pass_NuggetTrail") == true then
		local nuggets = Instance.new("ParticleEmitter")
		nuggets.Name = "FoodTrailFX"
		nuggets.Texture = "rbxassetid://136713011360148"
		nuggets.Size = NumberSequence.new(0.9)
		nuggets.Rate = 6
		nuggets.Lifetime = NumberRange.new(1.2, 1.8)
		nuggets.Speed = NumberRange.new(0.5, 1.5)
		nuggets.SpreadAngle = Vector2.new(60, 60)
		nuggets.Rotation = NumberRange.new(0, 360)
		nuggets.RotSpeed = NumberRange.new(-90, 90)
		nuggets.Acceleration = Vector3.new(0, -6, 0)
		nuggets.Parent = root
	end
end

------------------------------------------------------------------------
-- THE TOWER (rebuilt every round)
------------------------------------------------------------------------
type SectionDef = TowerSections.SectionDef

type SectionInfo = {
	Name: string,
	Creator: string,
	Color: Color3,
	BaseY: number,
	Height: number,
	Difficulty: number,
}

-- Used only if a section ever errors while building, so the tower is never broken.
local FALLBACK: SectionDef = {
	Name = "Plain Plates",
	Creator = "Kitchen Staff",
	Difficulty = 1,
	Height = 30,
	Colors = { Main = Color3.fromRGB(230, 230, 236), Accent = Color3.fromRGB(255, 190, 90) },
	Build = function(ctx)
		for i = 1, 8 do
			local angle = (i - 1) * 40
			local radius = (i == 8) and 10.2 or 13
			local x, z = ctx:Polar(radius, angle)
			ctx:Platform(x, 30 * i / 9, z, 5, 5, { Yaw = -angle, Color = (i % 2 == 0) and ctx.Theme.Accent or ctx.Theme.Main })
		end
	end,
}

local towerFolder: Folder? = nil
local sectionInfos: { SectionInfo } = {}
local towerTopY = FLOOR_Y
local roundId = 0
local onWinTouched: (BasePart) -> ()

local function pickSections(): { SectionDef }
	local list = TowerSections.List
	local used: { [SectionDef]: boolean } = {}
	local chosen: { SectionDef } = {}
	for stage = 1, CONFIG.STAGES do
		local want = 1 + math.floor((stage - 1) * 3 / CONFIG.STAGES)
		local best: { SectionDef } = {}
		local bestDistance = math.huge
		for _, def in ipairs(list) do
			if not used[def] then
				local distance = math.abs(def.Difficulty - want)
				if distance < bestDistance then
					bestDistance = distance
					best = { def }
				elseif distance == bestDistance then
					table.insert(best, def)
				end
			end
		end
		if #best == 0 then
			best = (#list > 0) and table.clone(list) or { FALLBACK }
		end
		local def = best[rng:NextInteger(1, #best)]
		used[def] = true
		chosen[stage] = def
	end
	return chosen
end

local function buildPlate(parent: Instance, baseY: number, color: Color3)
	makeDisc(parent, 12, 1, baseY, WHITE, Enum.Material.SmoothPlastic, "Plate")
	makeDisc(parent, 12.8, 0.6, baseY - 0.25, color, Enum.Material.Neon, "PlateRim")
	makeDisc(parent, 7, 0.05, baseY + 0.03, color:Lerp(WHITE, 0.6), Enum.Material.SmoothPlastic, "PlateCenter")
end

local function buildSectionSign(parent: Instance, info: SectionInfo, angle: number)
	local y = info.BaseY + 9
	if info.BaseY < CEILING_Y then
		y = math.max(y, DOOR_TOP_Y + 5) -- section 1: keep the sign above the doorways
	end
	local gui = makeSign(parent, facingAxis(SHAFT_R - 0.15, angle, y), Vector3.new(24, 8, 0.2))
	local ink = info.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	local title = addText(gui, string.upper(info.Name), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.68), ink, Enum.Font.Sarpanch)
	title.TextTransparency = 0.1
	local by = addText(gui, "by " .. info.Creator, UDim2.fromScale(0.2, 0.68), UDim2.fromScale(0.6, 0.3), ink, Enum.Font.Sarpanch)
	by.TextTransparency = 0.15
end

local function buildFinish(parent: Instance, topY: number)
	local pad = makeDisc(parent, 12, 1, topY, GOLD, Enum.Material.Neon, "WinPad")
	pad.Touched:Connect(function(hit)
		onWinTouched(hit)
	end)
	makeDisc(parent, 13, 0.6, topY - 0.3, Color3.fromRGB(255, 255, 255), Enum.Material.Neon, "WinPadRim")

	local confetti = Instance.new("ParticleEmitter")
	confetti.Color = colorSequence({ Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 200, 255), Color3.fromRGB(120, 230, 120) })
	confetti.Size = NumberSequence.new(0.35)
	confetti.Rate = 30
	confetti.Lifetime = NumberRange.new(1.5, 2.5)
	confetti.Speed = NumberRange.new(10, 18)
	confetti.SpreadAngle = Vector2.new(35, 35)
	confetti.Acceleration = Vector3.new(0, -20, 0)
	confetti.EmissionDirection = Enum.NormalId.Top
	confetti.Parent = pad

	-- Golden pillars + floating trophy (no collisions near the pad)
	for i = 0, 5 do
		local angle = i * 60 + 30
		makePart(parent, Vector3.new(2, 14, 2), CFrame.new(polar(20, angle, topY + 7)), GOLD, Enum.Material.Metal, "FinishPillar")
		local orb = makePart(parent, Vector3.new(2.6, 2.6, 2.6), CFrame.new(polar(20, angle, topY + 15.3)), Color3.fromRGB(255, 240, 180), Enum.Material.Neon, "FinishOrb", Enum.PartType.Ball)
		orb.CanCollide = false
	end
	local cup = makePart(parent, Vector3.new(3, 4, 4), CFrame.new(0, topY + 13, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, "TrophyCup", Enum.PartType.Cylinder)
	cup.CanCollide = false
	local stem = makePart(parent, Vector3.new(0.8, 3, 0.8), CFrame.new(0, topY + 10, 0), GOLD, Enum.Material.Metal, "TrophyStem")
	stem.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 24
	light.Brightness = 2
	light.Parent = cup

	for _, angle in ipairs({ 0, 180 }) do
		local gui = makeSign(parent, facingAxis(SHAFT_R - 0.15, angle, topY + 9), Vector3.new(22, 7, 0.2))
		addText(gui, "YOU MADE IT!", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(150, 100, 0), Enum.Font.Sarpanch)
	end
end

local function buildTower(): (Folder, { SectionInfo }, number)
	local folder = Instance.new("Folder")
	folder.Name = "TowerBuilding"
	folder.Parent = workspace

	local infos: { SectionInfo } = {}
	local baseY = FLOOR_Y
	for stage, chosenDef in ipairs(pickSections()) do
		local def = chosenDef
		local color = def.Colors.Main
		if stage > 1 then
			buildPlate(folder, baseY, color)
		end
		local rotation = rng:NextNumber(0, math.pi * 2)
		local ok, err = pcall(function()
			TowerSections.Build(def, { Parent = folder, BaseY = baseY, Rotation = rotation, Seed = rng:NextInteger(1, 2 ^ 30) })
		end)
		if not ok then
			warn("[TowerOfFood] Section '" .. def.Name .. "' failed to build, using a plain one instead: " .. tostring(err))
			local broken = folder:FindFirstChild("Section_" .. def.Name)
			if broken then
				broken:Destroy()
			end
			def = FALLBACK
			pcall(function()
				TowerSections.Build(FALLBACK, { Parent = folder, BaseY = baseY, Rotation = rotation, Seed = 1 })
			end)
		end

		local info: SectionInfo = {
			Name = def.Name,
			Creator = def.Creator,
			Color = def.Colors.Main,
			BaseY = baseY,
			Height = def.Height,
			Difficulty = def.Difficulty,
		}
		infos[stage] = info

		-- coloured wall band for this section (the lobby band covers the bottom)
		local bandBottom = math.max(baseY, CEILING_Y)
		makeRing(folder, SHAFT_R, 2, bandBottom, baseY + def.Height, WALL_SEGMENTS, def.Colors.Main, 0.12)
		buildSectionSign(folder, info, math.deg(rotation) + 180)
		baseY += def.Height
	end

	buildFinish(folder, baseY)
	makeRing(folder, SHAFT_R, 2, baseY, baseY + 22, WALL_SEGMENTS, Color3.fromRGB(255, 225, 140), 0.12)
	return folder, infos, baseY
end

------------------------------------------------------------------------
-- Progress, winning, skipping
------------------------------------------------------------------------
local function getRoundState(player: Player): RoundState
	local s = roundState[player]
	if not s then
		s = { Stage = 0, Won = false }
		roundState[player] = s
	end
	return s
end

local function feetY(hum: Humanoid, root: BasePart): number
	if hum.RigType == Enum.HumanoidRigType.R6 then
		return root.Position.Y - 3
	end
	return root.Position.Y - root.Size.Y / 2 - hum.HipHeight
end

local function insideShaft(root: BasePart): boolean
	local p = root.Position
	return math.sqrt(p.X * p.X + p.Z * p.Z) < SHAFT_R
end

-- index of the section the player's feet are in (0 = below the tower floor)
local function currentSection(y: number): number
	local index = 0
	for i, info in ipairs(sectionInfos) do
		if y >= info.BaseY - 1 then
			index = i
		end
	end
	return index
end

local function checkProgress(player: Player)
	local _, hum, root = getCharacterParts(player)
	if not hum or not root or hum.Health <= 0 or #sectionInfos == 0 then
		return
	end
	if hum.FloorMaterial == Enum.Material.Air or not insideShaft(root) then
		return
	end
	-- standing in section i+1 means section i is cleared; the last one is paid by the WinPad
	local cleared = math.clamp(currentSection(feetY(hum, root)) - 1, 0, #sectionInfos - 1)
	local state = getRoundState(player)
	if cleared > state.Stage and not state.Won then
		local gained = cleared - state.Stage
		state.Stage = cleared
		player:SetAttribute("Stage", cleared)
		award(player, gained * CONFIG.COINS_PER_STAGE, gained * CONFIG.XP_PER_STAGE, "Section " .. cleared .. " cleared!")
	end
end

onWinTouched = function(hit: BasePart)
	local char = hit.Parent
	if not char or not char:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not player or not hum or hum.Health <= 0 then
		return
	end
	local state = getRoundState(player)
	if state.Won then
		return
	end
	state.Won = true
	local missing = math.max(0, #sectionInfos - state.Stage)
	state.Stage = #sectionInfos
	player:SetAttribute("Stage", state.Stage)
	local d = playerData[player]
	if d then
		d.Wins += 1
	end
	award(player, missing * CONFIG.COINS_PER_STAGE + CONFIG.TOP_BONUS, missing * CONFIG.XP_PER_STAGE + CONFIG.XP_PER_WIN, "YOU BEAT THE TOWER!")
	notify(player, "YOU BEAT THE TOWER!", "win")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			notify(other, player.DisplayName .. " beat the Tower of Food!", "round")
		end
	end
	task.delay(3, function()
		if player.Parent and player.Character == char then
			player:LoadCharacter()
		end
	end)
	task.spawn(saveData, player)
end

skipEvent.OnServerEvent:Connect(function(player: Player)
	if player:GetAttribute("Pass_SkipSection") ~= true then
		return
	end
	if player:GetAttribute("SkipUsed") == true then
		notify(player, "You already skipped a section this round.", "error")
		return
	end
	local _, hum, root = getCharacterParts(player)
	if not hum or not root or hum.Health <= 0 or not insideShaft(root) then
		notify(player, "Get inside the tower first!", "error")
		return
	end
	local index = currentSection(feetY(hum, root))
	if index < 1 or index >= #sectionInfos then
		notify(player, "You can't skip the last section - finish it!", "error")
		return
	end
	local state = getRoundState(player)
	state.Stage = math.max(state.Stage, index) -- skipped sections don't pay coins
	player:SetAttribute("Stage", state.Stage)
	player:SetAttribute("SkipUsed", true)
	local target = sectionInfos[index + 1]
	root.CFrame = CFrame.new(0, target.BaseY + 3.5, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	notify(player, "Skipped to section " .. (index + 1) .. "!", "info")
end)

deathEvent.OnServerEvent:Connect(function(player: Player)
	local _, hum = getCharacterParts(player)
	if hum and hum.Health > 0 then
		hum.Health = 0
	end
end)

------------------------------------------------------------------------
-- Shop, skills, codes
------------------------------------------------------------------------
local function handleShop(player: Player, action: unknown, id: unknown): (boolean, string)
	local d = playerData[player]
	if not d then
		return false, "Your data is still loading, try again in a moment."
	end
	if type(action) ~= "string" or type(id) ~= "string" then
		return false, "Something went wrong."
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.15 then
		return false, "Slow down a little!"
	end
	lastAction[player] = now

	if action == "Buy" then
		local item = ITEMS_BY_ID[id]
		if not item then
			return false, "That item doesn't exist."
		end
		if d.Owned[id] then
			return false, "You already own the " .. item.Name .. "."
		end
		if d.Coins < item.Price then
			return false, ("You need %s more coins."):format(formatCoins(item.Price - d.Coins))
		end
		d.Coins = roundTo(d.Coins - item.Price, 0.1)
		d.Owned[id] = true
		if item.Category == "Trail" then
			d.EquippedTrail = id
			applyTrail(player)
		else
			giveTools(player)
		end
		refreshStats(player)
		task.spawn(saveData, player)
		if item.Category == "Gear" then
			return true, "You bought the " .. item.Name .. "! It's in your backpack."
		end
		return true, "You bought the " .. item.Name .. "! It's equipped."
	elseif action == "Equip" then
		local item = ITEMS_BY_ID[id]
		if not item or not d.Owned[id] then
			return false, "You don't own that yet."
		end
		if item.Category ~= "Trail" then
			return true, "Gear is always in your backpack."
		end
		d.EquippedTrail = id
		applyTrail(player)
		refreshStats(player)
		return true, item.Name .. " equipped!"
	elseif action == "Unequip" then
		d.EquippedTrail = ""
		applyTrail(player)
		refreshStats(player)
		return true, "Trail taken off."
	elseif action == "Skill" then
		local skill = SKILLS_BY_ID[id]
		if not skill then
			return false, "That skill doesn't exist."
		end
		local points = player:GetAttribute("SkillPoints")
		if typeof(points) ~= "number" or points < 1 then
			return false, "No skill points left. Level up to get more!"
		end
		local current = d.Skills[id] or 0
		if current >= skill.Max then
			return false, skill.Name .. " is already maxed out!"
		end
		d.Skills[id] = current + 1
		refreshStats(player)
		applyMovement(player)
		return true, skill.Name .. " is now level " .. (current + 1) .. "!"
	elseif action == "Redeem" then
		local code = string.upper((string.gsub(id, "%s", "")))
		local reward = (CONFIG.CODES :: { [string]: number })[code]
		if not reward then
			return false, "That code doesn't work."
		end
		if d.Codes[code] then
			return false, "You already used that code."
		end
		d.Codes[code] = true
		d.Coins = roundTo(d.Coins + reward, 0.1)
		refreshStats(player)
		task.spawn(saveData, player)
		return true, "Code redeemed! +" .. reward .. " coins"
	end
	return false, "Unknown action."
end

shopFunction.OnServerInvoke = function(player: Player, action: unknown, id: unknown)
	local ok, success, message = pcall(handleShop, player, action, id)
	if not ok then
		warn("[TowerOfFood] Shop error: " .. tostring(success))
		return false, "Shop error, please try again."
	end
	return success, message
end

------------------------------------------------------------------------
-- Gamepasses
------------------------------------------------------------------------
type PassInfo = { Key: string, Name: string, Desc: string, Id: number }

local function passByKey(key: string): PassInfo?
	for _, pass in ipairs(CONFIG.PASSES) do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

local function applyPassPerks(player: Player)
	applyTrail(player)
	updateOverhead(player)
end

local function checkPasses(player: Player)
	for _, pass in ipairs(CONFIG.PASSES) do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			player:SetAttribute("Pass_" .. pass.Key, ok and owns == true)
		else
			player:SetAttribute("Pass_" .. pass.Key, false)
		end
	end
end

promptPassEvent.OnServerEvent:Connect(function(player: Player, key: unknown)
	if type(key) ~= "string" then
		return
	end
	local pass = passByKey(key)
	if not pass or pass.Id == 0 then
		notify(player, "That pass is coming soon!", "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for _, pass in ipairs(CONFIG.PASSES) do
		if pass.Id ~= 0 and pass.Id == passId then
			player:SetAttribute("Pass_" .. pass.Key, true)
			applyPassPerks(player)
			notify(player, "Thanks! " .. pass.Name .. " unlocked!", "win")
		end
	end
end)

------------------------------------------------------------------------
-- Players joining / leaving
------------------------------------------------------------------------
local function onCharacterAdded(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	char:WaitForChild("HumanoidRootPart", 10)
	char:WaitForChild("Head", 10)
	if not hum or player.Character ~= char then
		return
	end
	player:WaitForChild("Backpack", 10)
	giveTools(player)
	applyTrail(player)
	updateOverhead(player)
	applyMovement(player)
end

local function onPlayerAdded(player: Player)
	local d = loadData(player)
	if not player.Parent then
		return
	end
	playerData[player] = d

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = 1
	level.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = ls
	ls.Parent = player

	player:SetAttribute("Stage", 0)
	player:SetAttribute("SkipUsed", false)
	checkPasses(player)
	refreshStats(player)

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	playerData[player] = nil
	roundState[player] = nil
	lastAction[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			saveData(player)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

------------------------------------------------------------------------
-- Top Wins board
------------------------------------------------------------------------
local nameCache: { [number]: string } = {}

local function refreshWinsBoard()
	local ws = winsStore
	if not ws then
		return
	end
	local ok, pages = pcall(function()
		return ws:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		return
	end
	local entries = pages:GetCurrentPage()
	for row = 1, 10 do
		local label = winsBoardRows[row]
		local entry = entries[row]
		if label then
			if entry then
				local userId = tonumber(entry.key) or 0
				local name = nameCache[userId]
				if not name then
					local okName, result = pcall(function()
						return Players:GetNameFromUserIdAsync(userId)
					end)
					name = okName and result or "Player"
					nameCache[userId] = name
				end
				label.Text = ("%d.  %s  -  %d wins"):format(row, name, tonumber(entry.value) or 0)
			else
				label.Text = row .. ".  ---"
			end
		end
	end
end

------------------------------------------------------------------------
-- Rounds
------------------------------------------------------------------------
local function startRound(): number
	roundId += 1
	local mutator: Mutator? = nil
	if rng:NextNumber() < CONFIG.MUTATOR_CHANCE then
		mutator = MUTATORS[rng:NextInteger(1, #MUTATORS)]
	end
	currentMutator = mutator and mutator.Key or ""
	workspace.Gravity = (currentMutator == "LowGravity") and NORMAL_GRAVITY * 0.6 or NORMAL_GRAVITY

	local folder, infos, topY = buildTower()
	if towerFolder then
		towerFolder:Destroy()
	end
	folder.Name = "Tower"
	towerFolder = folder
	sectionInfos = infos
	towerTopY = topY
	roundState = {}

	local layoutSections = {}
	for _, info in ipairs(infos) do
		table.insert(layoutSections, {
			Name = info.Name,
			Creator = info.Creator,
			Color = info.Color:ToHex(),
			BaseY = info.BaseY,
			Height = info.Height,
			Difficulty = info.Difficulty,
		})
	end
	sharedFolder:SetAttribute("Layout", HttpService:JSONEncode({
		TopY = towerTopY,
		TopBonus = CONFIG.TOP_BONUS,
		CoinsPerStage = CONFIG.COINS_PER_STAGE,
		Sections = layoutSections,
	}))
	local duration = rng:NextInteger(CONFIG.ROUND_MIN_SECONDS, CONFIG.ROUND_MAX_SECONDS)
	sharedFolder:SetAttribute("RoundEnd", workspace:GetServerTimeNow() + duration)
	sharedFolder:SetAttribute("Mutator", currentMutator)
	sharedFolder:SetAttribute("MutatorLabel", mutator and mutator.Label or "")
	sharedFolder:SetAttribute("RoundId", roundId)

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Stage", 0)
		player:SetAttribute("SkipUsed", false)
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
	notifyAll("A fresh tower just came out of the oven!", "round")
	if mutator then
		notifyAll(mutator.Message, "round")
	end
	print(("[TowerOfFood] Round %d: %d sections, top at y=%d, mutator=%s"):format(roundId, #infos, towerTopY, currentMutator == "" and "none" or currentMutator))
	return duration
end

------------------------------------------------------------------------
-- Start everything
------------------------------------------------------------------------
setupLighting()
buildLobby()

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			checkProgress(player)
		end
		task.wait(0.25)
	end
end)

task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)

task.spawn(function()
	while true do
		refreshWinsBoard()
		task.wait(90)
	end
end)

task.spawn(function()
	while true do
		task.wait(startRound())
	end
end)
