--[[
	TOWER OF FOOD - main server script
	Where it goes: ServerScriptService  (type: Script)

	This one script builds the whole game when the server starts:
	  * lobby + spawn + glass tower shaft
	  * a random 8-stage food tower that rebuilds every 6-8 minutes
	  * coins (12.5 per stage, +100 for the top), XP levels, wins
	  * leaderboard + overhead level tag
	  * coin shop (coils) saved forever with DataStore
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

------------------------------------------------------------------------
-- SETTINGS (safe to change)
------------------------------------------------------------------------
local CONFIG = {
	STAGES = 8, -- sections in each tower
	SECTION_HEIGHT = 30, -- studs per section
	ROUND_MIN_SECONDS = 6 * 60,
	ROUND_MAX_SECONDS = 8 * 60,
	COINS_PER_STAGE = 12.5,
	TOP_BONUS = 100,
	XP_PER_STAGE = 10,
	XP_PER_WIN = 100,
	RESPAWN_TIME = 2,
	X2_COINS_GAMEPASS_ID = 0, -- put your "x2 Coins" gamepass ID here later (0 = off)
	DATASTORE_NAME = "TowerOfFood_v1",
}

-- Coin shop. GravityCut = how much gravity is removed while holding (0.55 = 55%).
local SHOP_ITEMS = {
	{ Id = "SpeedCoil", Name = "Speed Coil", Price = 250, Desc = "Run much faster while holding it.", Speed = 26, Color = Color3.fromRGB(70, 160, 255) },
	{ Id = "GravityCoil", Name = "Gravity Coil", Price = 400, Desc = "Jump way higher while holding it.", GravityCut = 0.55, Color = Color3.fromRGB(170, 90, 255) },
	{ Id = "FusionCoil", Name = "Fusion Coil", Price = 1000, Desc = "Speed AND high jumps in one coil!", Speed = 26, GravityCut = 0.55, Color = Color3.fromRGB(255, 110, 190) },
}

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local H = CONFIG.SECTION_HEIGHT
local HALF = 20 -- half the width of the tower shaft (shaft is 40 x 40)
local TOWER_CENTER = Vector3.new(0, 0, 0)
local BASE_Y = 0 -- ground level (top of the default Baseplate)
local LOBBY_SPAWN = Vector3.new(0, 0.5, -55)

local ITEMS_BY_ID = {}
for _, item in ipairs(SHOP_ITEMS) do
	ITEMS_BY_ID[item.Id] = item
end

Players.RespawnTime = CONFIG.RESPAWN_TIME

------------------------------------------------------------------------
-- Shared folder + remotes (the client UI script talks to these)
------------------------------------------------------------------------
local shared = ReplicatedStorage:FindFirstChild("TowerOfFood") or Instance.new("Folder")
shared.Name = "TowerOfFood"
shared.Parent = ReplicatedStorage

local function getRemote(className, name)
	local r = shared:FindFirstChild(name) or Instance.new(className)
	r.Name = name
	r.Parent = shared
	return r
end

local notifyEvent = getRemote("RemoteEvent", "Notify")
local buyFunction = getRemote("RemoteFunction", "BuyItem")

local clientItems = {}
for _, item in ipairs(SHOP_ITEMS) do
	table.insert(clientItems, { Id = item.Id, Name = item.Name, Price = item.Price, Desc = item.Desc, Color = item.Color:ToHex() })
end
shared:SetAttribute("ShopItems", HttpService:JSONEncode(clientItems))

------------------------------------------------------------------------
-- Building helpers
------------------------------------------------------------------------
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	for key, value in pairs(props) do
		if key ~= "Parent" and key ~= "Shape" then
			p[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function addSignText(part, face, text)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Parent = label
end

-- A flat disc (cylinder lying down) whose top surface is at topY.
local function discCFrame(x, topY, z, thickness)
	return CFrame.new(x, topY - thickness / 2, z) * CFrame.Angles(0, 0, math.rad(90))
end

local function killFrom(hit)
	local hum = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = 0
	end
end

-- Points spiralling up one section. Every section starts on the pad in the
-- middle and its last point ends close to the next pad, so it is always beatable.
local function makeSpiral(ctx, count, turns)
	local points = {}
	for i = 1, count do
		local t = (count > 1) and (i - 1) / (count - 1) or 0
		local angle = ctx.StartAngle + ctx.Dir * t * turns * math.pi * 2
		local radius = (i == count) and 10 or 13
		local y = ctx.BaseY + H * i / (count + 1)
		points[i] = {
			Position = TOWER_CENTER + Vector3.new(math.sin(angle) * radius, y, math.cos(angle) * radius),
			Angle = angle,
		}
	end
	ctx.EndAngle = points[count].Angle
	return points
end

-- CFrame for a block whose TOP is at the point, facing outwards.
local function platformCF(point, thickness)
	return CFrame.new(point.Position - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, point.Angle, 0)
end

------------------------------------------------------------------------
-- FOOD SECTIONS  (add new ones here - each gets random placement)
------------------------------------------------------------------------
local SECTIONS = {}

SECTIONS["Nugget Steps"] = function(ctx)
	for i, point in ipairs(makeSpiral(ctx, 8, 0.9)) do
		local big = i % 2 == 1
		newPart({
			Name = "Nugget",
			Size = big and Vector3.new(5, 1.5, 4) or Vector3.new(3.5, 1.5, 3),
			CFrame = platformCF(point, 1.5),
			Color = Color3.fromRGB(222, 155, 60),
			Material = Enum.Material.Sand,
			Parent = ctx.Model,
		})
	end
end

SECTIONS["Ketchup Slide"] = function(ctx)
	for _, point in ipairs(makeSpiral(ctx, 8, 0.9)) do
		newPart({
			Name = "Ketchup",
			Size = Vector3.new(5, 1, 5),
			CFrame = platformCF(point, 1) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = Color3.fromRGB(200, 20, 20),
			Material = Enum.Material.Glass,
			CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0.3, 100, 1), -- no friction = slippery
			Parent = ctx.Model,
		})
	end
end

SECTIONS["Spinning Pizza"] = function(ctx)
	for i, point in ipairs(makeSpiral(ctx, 6, 0.85)) do
		local cf = discCFrame(point.Position.X, point.Position.Y, point.Position.Z, 1)
		local axle = newPart({ Name = "Axle", Size = Vector3.new(1, 1, 1), CFrame = cf, Transparency = 1, CanCollide = false, Parent = ctx.Model })
		local pizza = newPart({
			Name = "Pizza",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 8, 8),
			CFrame = cf,
			Anchored = false,
			Color = Color3.fromRGB(245, 195, 90),
			Material = Enum.Material.Sand,
			Parent = ctx.Model,
		})
		for _ = 1, 5 do
			local a, r = math.random() * math.pi * 2, math.random() * 2.8
			local pep = newPart({
				Name = "Pepperoni",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.1, 1.4, 1.4),
				CFrame = cf * CFrame.new(0.55, math.sin(a) * r, math.cos(a) * r),
				Anchored = false,
				CanCollide = false,
				Massless = true,
				Color = Color3.fromRGB(170, 30, 30),
				Parent = ctx.Model,
			})
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = pizza
			weld.Part1 = pep
			weld.Parent = pep
		end
		local a0 = Instance.new("Attachment")
		a0.Parent = axle
		local a1 = Instance.new("Attachment")
		a1.Parent = pizza
		local hinge = Instance.new("HingeConstraint")
		hinge.Attachment0 = a0
		hinge.Attachment1 = a1
		hinge.ActuatorType = Enum.ActuatorType.Motor
		hinge.MotorMaxTorque = 1e9
		hinge.AngularVelocity = (i % 2 == 0) and 0.9 or -0.9
		hinge.Parent = pizza
		pcall(function()
			pizza:SetNetworkOwner(nil)
		end)
	end
end

SECTIONS["Hot Sauce Lava"] = function(ctx)
	local sauceTiles = {}
	for i, point in ipairs(makeSpiral(ctx, 8, 0.9)) do
		local tile = newPart({
			Name = "Chip",
			Size = Vector3.new(5, 1, 5),
			CFrame = platformCF(point, 1),
			Color = Color3.fromRGB(235, 190, 110),
			Material = Enum.Material.Sand,
			Parent = ctx.Model,
		})
		if i % 2 == 0 then
			tile.Name = "HotSauce"
			table.insert(sauceTiles, tile)
			tile.Touched:Connect(function(hit)
				if tile:GetAttribute("Hot") then
					killFrom(hit)
				end
			end)
		end
	end

	local function setState(color, material, hot)
		for _, tile in ipairs(sauceTiles) do
			tile.Color = color
			tile.Material = material
			tile:SetAttribute("Hot", hot)
			if hot then
				local box = tile.CFrame * CFrame.new(0, 2, 0)
				for _, hit in ipairs(workspace:GetPartBoundsInBox(box, tile.Size + Vector3.new(0, 3, 0))) do
					killFrom(hit)
				end
			end
		end
	end

	task.spawn(function()
		while ctx.Model.Parent do
			setState(Color3.fromRGB(235, 190, 110), Enum.Material.Sand, false)
			task.wait(2.5)
			setState(Color3.fromRGB(255, 140, 0), Enum.Material.SmoothPlastic, false) -- warning!
			task.wait(0.8)
			setState(Color3.fromRGB(255, 30, 0), Enum.Material.Neon, true) -- HOT
			task.wait(2)
		end
	end)
end

SECTIONS["Jelly Bounce"] = function(ctx)
	local colors = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(120, 230, 90), Color3.fromRGB(90, 160, 255), Color3.fromRGB(255, 200, 60) }
	for i, point in ipairs(makeSpiral(ctx, 5, 0.7)) do
		local jelly = newPart({
			Name = "Jelly",
			Size = Vector3.new(6, 1.5, 6),
			CFrame = platformCF(point, 1.5),
			Color = colors[(i - 1) % #colors + 1],
			Material = Enum.Material.Glass,
			Transparency = 0.25,
			Parent = ctx.Model,
		})
		jelly:SetAttribute("Power", 75)
		CollectionService:AddTag(jelly, "JellyBounce") -- the client script does the bounce
	end
end

SECTIONS["Noodle Tightrope"] = function(ctx)
	local points = makeSpiral(ctx, 6, 0.8)
	for i, point in ipairs(points) do
		newPart({
			Name = "Meatball",
			Size = Vector3.new(3, 1.6, 3),
			CFrame = platformCF(point, 1.6),
			Color = Color3.fromRGB(120, 60, 35),
			Material = Enum.Material.Slate,
			Parent = ctx.Model,
		})
		local nextPoint = points[i + 1]
		if nextPoint then
			local a = point.Position - Vector3.new(0, 0.8, 0)
			local b = nextPoint.Position - Vector3.new(0, 0.8, 0)
			newPart({
				Name = "Noodle",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((b - a).Magnitude, 1.6, 1.6),
				CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0),
				Color = Color3.fromRGB(250, 225, 130),
				Material = Enum.Material.SmoothPlastic,
				Parent = ctx.Model,
			})
		end
	end
end

SECTIONS["Burger Stack"] = function(ctx)
	local layers = {
		{ "TopBun", 1.2, Color3.fromRGB(215, 145, 65), 5.0 },
		{ "Cheese", 0.25, Color3.fromRGB(255, 205, 40), 5.6 },
		{ "Patty", 0.8, Color3.fromRGB(95, 55, 30), 5.4 },
		{ "Lettuce", 0.25, Color3.fromRGB(90, 190, 60), 5.8 },
		{ "BottomBun", 0.8, Color3.fromRGB(215, 145, 65), 5.0 },
	}
	for i, point in ipairs(makeSpiral(ctx, 7, 0.85)) do
		local scale = 1 - (i - 1) * 0.06 -- burgers get smaller as you climb
		local top = point.Position.Y
		for _, layer in ipairs(layers) do
			local name, thick, color, width = layer[1], layer[2], layer[3], layer[4] * scale
			newPart({
				Name = name,
				Size = Vector3.new(width, thick, width),
				CFrame = CFrame.new(point.Position.X, top - thick / 2, point.Position.Z) * CFrame.Angles(0, point.Angle, 0),
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				Parent = ctx.Model,
			})
			top -= thick
		end
	end
end

SECTIONS["Ice Cream Melt"] = function(ctx)
	local flavours = { Color3.fromRGB(255, 170, 200), Color3.fromRGB(160, 240, 200), Color3.fromRGB(255, 245, 210), Color3.fromRGB(120, 75, 50) }
	for i, point in ipairs(makeSpiral(ctx, 8, 0.9)) do
		local scoop = newPart({
			Name = "IceCream",
			Size = Vector3.new(4.5, 1.2, 4.5),
			CFrame = platformCF(point, 1.2),
			Color = flavours[(i - 1) % #flavours + 1],
			Material = Enum.Material.SmoothPlastic,
			Parent = ctx.Model,
		})
		local melting = false
		scoop.Touched:Connect(function(hit)
			if melting or not (hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")) then
				return
			end
			melting = true
			task.wait(0.6)
			TweenService:Create(scoop, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.wait(0.4)
			scoop.CanCollide = false
			task.wait(2.5)
			scoop.CanCollide = true
			scoop.Transparency = 0
			melting = false
		end)
	end
end

SECTIONS["Popcorn Pop"] = function(ctx)
	for _, point in ipairs(makeSpiral(ctx, 9, 0.9)) do
		local kernel = newPart({
			Name = "Popcorn",
			Size = Vector3.new(3.5, 1.2, 3.5),
			CFrame = platformCF(point, 1.2),
			Color = Color3.fromRGB(255, 248, 220),
			Material = Enum.Material.SmoothPlastic,
			Parent = ctx.Model,
		})
		task.spawn(function()
			task.wait(math.random() * 3)
			while ctx.Model.Parent do
				kernel.Transparency = 0
				kernel.CanCollide = true
				task.wait(2 + math.random() * 2)
				kernel.Transparency = 0.5 -- about to pop!
				task.wait(0.6)
				kernel.Transparency = 1
				kernel.CanCollide = false
				task.wait(1.2)
			end
		end)
	end
end

------------------------------------------------------------------------
-- World (lobby + shaft) - built once
------------------------------------------------------------------------
local function buildWorld()
	local old = workspace:FindFirstChild("TowerOfFoodWorld")
	if old then
		old:Destroy()
	end
	-- remove the template spawn so players start in our lobby
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end

	local world = Instance.new("Folder")
	world.Name = "TowerOfFoodWorld"
	world.Parent = workspace

	if not workspace:FindFirstChild("Baseplate") then
		newPart({ Name = "Ground", Size = Vector3.new(300, 2, 300), Position = Vector3.new(0, -1, 0), Color = Color3.fromRGB(110, 190, 90), Material = Enum.Material.Grass, Parent = world })
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.lookAt(LOBBY_SPAWN, Vector3.new(TOWER_CENTER.X, LOBBY_SPAWN.Y, TOWER_CENTER.Z))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 170, 40)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = world

	local wallH = CONFIG.STAGES * H + 25
	local function wall(name, size, offset)
		return newPart({
			Name = name,
			Size = size,
			Position = TOWER_CENTER + offset,
			Color = Color3.fromRGB(255, 240, 220),
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			Parent = world,
		})
	end
	wall("BackWall", Vector3.new(44, wallH, 2), Vector3.new(0, wallH / 2, HALF + 1))
	wall("LeftWall", Vector3.new(2, wallH, 40), Vector3.new(-(HALF + 1), wallH / 2, 0))
	wall("RightWall", Vector3.new(2, wallH, 40), Vector3.new(HALF + 1, wallH / 2, 0))
	-- front wall has a 10 x 12 doorway facing the lobby
	wall("FrontWallL", Vector3.new(17, wallH, 2), Vector3.new(-13.5, wallH / 2, -(HALF + 1)))
	wall("FrontWallR", Vector3.new(17, wallH, 2), Vector3.new(13.5, wallH / 2, -(HALF + 1)))
	wall("FrontWallTop", Vector3.new(10, wallH - 12, 2), Vector3.new(0, 12 + (wallH - 12) / 2, -(HALF + 1)))

	local title = newPart({
		Name = "TitleSign",
		Size = Vector3.new(30, 8, 1),
		Position = TOWER_CENTER + Vector3.new(0, 17, -(HALF + 2.5)),
		Color = Color3.fromRGB(255, 120, 40),
		Material = Enum.Material.SmoothPlastic,
		Parent = world,
	})
	addSignText(title, Enum.NormalId.Front, "TOWER OF FOOD")
end

------------------------------------------------------------------------
-- Player data, coins, XP, levels
------------------------------------------------------------------------
local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[TowerOfFood] DataStore unavailable, progress will NOT save: " .. tostring(result))
	end
end

local playerData = {} -- [player] = { Coins, XP, Wins, Owned = {}, NoSave }
local hasX2 = {}
local roundState = {} -- [player] = { Stage, Won }

local function levelInfo(xp)
	local level, need = 1, 100
	while xp >= need do
		xp -= need
		level += 1
		need = 100 + (level - 1) * 50
	end
	return level, xp, need
end

local function formatCoins(n)
	if n % 1 == 0 then
		return tostring(math.floor(n))
	end
	return string.format("%.1f", n)
end

local function updateOverhead(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = head:FindFirstChild("LevelTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "LevelTag"
		tag.Size = UDim2.fromOffset(160, 36)
		tag.StudsOffset = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 90
		tag.Parent = head
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 220, 80)
		label.Parent = tag
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
	end
	tag.Label.Text = "Lv. " .. (player:GetAttribute("Level") or 1)
end

local function refreshStats(player)
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
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Coins.Value = d.Coins
		ls.Level.Value = level
		ls.Wins.Value = d.Wins
	end
	updateOverhead(player)
	if oldLevel and level > oldLevel then
		notifyEvent:FireClient(player, "LEVEL UP! You are now Level " .. level .. "!")
	end
end

local function award(player, coins, xp, message)
	local d = playerData[player]
	if not d then
		return
	end
	if hasX2[player] then
		coins *= 2
	end
	d.Coins += coins
	d.XP += xp
	refreshStats(player)
	notifyEvent:FireClient(player, ("%s  +%s coins  +%d XP"):format(message, formatCoins(coins), xp))
end

local function loadData(player)
	local d = { Coins = 0, XP = 0, Wins = 0, Owned = {} }
	if not store then
		d.NoSave = true
		return d
	end
	local ok, saved = pcall(store.GetAsync, store, "Player_" .. player.UserId)
	if not ok then
		warn("[TowerOfFood] Could not load data for " .. player.Name .. ": " .. tostring(saved))
		d.NoSave = true -- never overwrite real data with an empty save
	elseif type(saved) == "table" then
		d.Coins = tonumber(saved.Coins) or 0
		d.XP = tonumber(saved.XP) or 0
		d.Wins = tonumber(saved.Wins) or 0
		d.Owned = type(saved.Owned) == "table" and saved.Owned or {}
	end
	return d
end

local function saveData(player)
	local d = playerData[player]
	if not d or d.NoSave or not store then
		return
	end
	local ok, err = pcall(store.SetAsync, store, "Player_" .. player.UserId, {
		Coins = d.Coins,
		XP = d.XP,
		Wins = d.Wins,
		Owned = d.Owned,
	})
	if not ok then
		warn("[TowerOfFood] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

------------------------------------------------------------------------
-- Coils (shop tools)
------------------------------------------------------------------------
local DEFAULT_WALKSPEED = 16

local function makeCoil(item)
	local tool = Instance.new("Tool")
	tool.Name = item.Name
	tool.ToolTip = item.Desc
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(1.6, 1, 1)
	handle.Color = item.Color
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	tool.Equipped:Connect(function()
		local char = tool.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not root then
			return
		end
		if item.Speed then
			hum.WalkSpeed = item.Speed
		end
		if item.GravityCut then
			local att = root:FindFirstChild("CoilAttachment") or Instance.new("Attachment")
			att.Name = "CoilAttachment"
			att.Parent = root
			local force = Instance.new("VectorForce")
			force.Name = "CoilAntiGravity"
			force.Attachment0 = att
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = true
			force.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * item.GravityCut, 0)
			force.Parent = root
		end
	end)

	tool.Unequipped:Connect(function()
		local player = tool:FindFirstAncestorOfClass("Player")
		local char = player and player.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if hum then
			hum.WalkSpeed = DEFAULT_WALKSPEED
		end
		if root then
			for _, child in ipairs(root:GetChildren()) do
				if child.Name == "CoilAntiGravity" then
					child:Destroy()
				end
			end
		end
	end)

	return tool
end

local function giveTool(player, item)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and not backpack:FindFirstChild(item.Name) then
		makeCoil(item).Parent = backpack
	end
end

buyFunction.OnServerInvoke = function(player, itemId)
	local item = ITEMS_BY_ID[itemId]
	local d = playerData[player]
	if not item then
		return false, "That item doesn't exist."
	end
	if not d then
		return false, "Your data is still loading, try again."
	end
	if d.Owned[itemId] then
		return false, "You already own " .. item.Name .. "."
	end
	if d.Coins < item.Price then
		return false, ("You need %s more coins."):format(formatCoins(item.Price - d.Coins))
	end
	d.Coins -= item.Price
	d.Owned[itemId] = true
	player:SetAttribute("Owned_" .. itemId, true)
	refreshStats(player)
	giveTool(player, item)
	task.spawn(saveData, player)
	return true, "You bought the " .. item.Name .. "! Check your backpack."
end

------------------------------------------------------------------------
-- Players joining / leaving
------------------------------------------------------------------------
local function onCharacterAdded(player, char)
	char:WaitForChild("Head", 10)
	updateOverhead(player)
	player:WaitForChild("Backpack", 10)
	local d = playerData[player]
	if d then
		for _, item in ipairs(SHOP_ITEMS) do
			if d.Owned[item.Id] then
				giveTool(player, item)
			end
		end
	end
end

local function onPlayerAdded(player)
	local d = loadData(player)
	if not player.Parent then
		return
	end
	playerData[player] = d

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("NumberValue")
	coins.Name = "Coins"
	coins.Parent = ls
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = ls
	ls.Parent = player

	for id in pairs(d.Owned) do
		player:SetAttribute("Owned_" .. id, true)
	end

	if CONFIG.X2_COINS_GAMEPASS_ID ~= 0 then
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, CONFIG.X2_COINS_GAMEPASS_ID)
		hasX2[player] = ok and owns
	end

	refreshStats(player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased and passId == CONFIG.X2_COINS_GAMEPASS_ID and CONFIG.X2_COINS_GAMEPASS_ID ~= 0 then
		hasX2[player] = true
		notifyEvent:FireClient(player, "x2 Coins unlocked!")
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	playerData[player] = nil
	hasX2[player] = nil
	roundState[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
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

------------------------------------------------------------------------
-- Tower + rounds
------------------------------------------------------------------------
local function getRoundState(player)
	local s = roundState[player]
	if not s then
		s = { Stage = 0, Won = false }
		roundState[player] = s
	end
	return s
end

local function onWinTouched(hit)
	local char = hit.Parent
	local player = Players:GetPlayerFromCharacter(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not player or not hum or hum.Health <= 0 then
		return
	end
	local state = getRoundState(player)
	if state.Won then
		return
	end
	state.Won = true
	local missing = CONFIG.STAGES - state.Stage
	state.Stage = CONFIG.STAGES
	local d = playerData[player]
	if d then
		d.Wins += 1
	end
	award(player, missing * CONFIG.COINS_PER_STAGE + CONFIG.TOP_BONUS, missing * CONFIG.XP_PER_STAGE + CONFIG.XP_PER_WIN, "YOU REACHED THE TOP!")
	notifyEvent:FireAllClients(player.DisplayName .. " beat the Tower of Food!")
	task.delay(3, function()
		if player.Parent and player.Character == char then
			player:LoadCharacter()
		end
	end)
end

local towerFolder

local function buildTower()
	if towerFolder then
		towerFolder:Destroy()
	end
	towerFolder = Instance.new("Folder")
	towerFolder.Name = "Tower"
	towerFolder.Parent = workspace

	local names = {}
	for name in pairs(SECTIONS) do
		table.insert(names, name)
	end
	table.sort(names)
	for i = #names, 2, -1 do
		local j = math.random(i)
		names[i], names[j] = names[j], names[i]
	end

	local chosen = {}
	local angle = math.random() * math.pi * 2
	for stage = 1, CONFIG.STAGES do
		local name = names[(stage - 1) % #names + 1]
		chosen[stage] = name
		local baseY = BASE_Y + (stage - 1) * H

		local model = Instance.new("Model")
		model.Name = ("Stage%d_%s"):format(stage, name)
		model.Parent = towerFolder

		if stage > 1 then
			newPart({
				Name = "LandingPad",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 10, 10),
				CFrame = discCFrame(TOWER_CENTER.X, baseY, TOWER_CENTER.Z, 1),
				Color = Color3.fromRGB(255, 255, 255),
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
		end

		local sign = newPart({
			Name = "StageSign",
			Size = Vector3.new(18, 3.5, 0.4),
			Position = TOWER_CENTER + Vector3.new(0, baseY + 9, HALF - 0.4),
			Color = Color3.fromRGB(255, 120, 40),
			CanCollide = false,
			Parent = model,
		})
		addSignText(sign, Enum.NormalId.Front, ("Stage %d: %s"):format(stage, name))

		local ctx = { Model = model, BaseY = baseY, StartAngle = angle, Dir = (math.random(2) == 1) and 1 or -1 }
		local ok, err = pcall(SECTIONS[name], ctx)
		if not ok then
			warn("[TowerOfFood] Section " .. name .. " failed: " .. tostring(err))
		end
		-- next section starts on the opposite side so nobody bonks their head
		angle = (ctx.EndAngle or angle) + math.pi
	end

	local topY = BASE_Y + CONFIG.STAGES * H
	newPart({
		Name = "FinishPlatform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 12, 12),
		CFrame = discCFrame(TOWER_CENTER.X, topY, TOWER_CENTER.Z, 1),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
		Parent = towerFolder,
	})
	local winPad = newPart({
		Name = "WinPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 7, 7),
		CFrame = discCFrame(TOWER_CENTER.X, topY + 0.4, TOWER_CENTER.Z, 0.4),
		Color = Color3.fromRGB(255, 210, 40),
		Material = Enum.Material.Neon,
		Parent = towerFolder,
	})
	winPad.Touched:Connect(onWinTouched)

	local trophy = Instance.new("BillboardGui")
	trophy.Size = UDim2.fromOffset(200, 50)
	trophy.StudsOffset = Vector3.new(0, 4, 0)
	trophy.Parent = winPad
	local trophyText = Instance.new("TextLabel")
	trophyText.Size = UDim2.fromScale(1, 1)
	trophyText.BackgroundTransparency = 1
	trophyText.Font = Enum.Font.FredokaOne
	trophyText.TextScaled = true
	trophyText.TextColor3 = Color3.fromRGB(255, 220, 60)
	trophyText.Text = "THE TOP!"
	trophyText.Parent = trophy

	return chosen
end

-- Award coins whenever a player stands on a new stage's landing pad.
local function checkProgress(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return
	end
	if hum.FloorMaterial == Enum.Material.Air then
		return -- only count it when they are actually standing
	end
	local rel = root.Position - TOWER_CENTER
	if math.abs(rel.X) > HALF or math.abs(rel.Z) > HALF then
		return
	end
	local feetY
	if hum.RigType == Enum.HumanoidRigType.R6 then
		feetY = root.Position.Y - 3
	else
		feetY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	end
	-- the last stage's coins are paid out by the win pad together with the top bonus
	local completed = math.clamp(math.floor((feetY - BASE_Y + 1.5) / H), 0, CONFIG.STAGES - 1)
	local state = getRoundState(player)
	if completed > state.Stage then
		local gained = completed - state.Stage
		state.Stage = completed
		award(player, gained * CONFIG.COINS_PER_STAGE, gained * CONFIG.XP_PER_STAGE, "Stage " .. completed .. " cleared!")
	end
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			checkProgress(player)
		end
		task.wait(0.25)
	end
end)

local function startRound()
	roundState = {}
	local chosen = buildTower()
	local duration = math.random(CONFIG.ROUND_MIN_SECONDS, CONFIG.ROUND_MAX_SECONDS)
	shared:SetAttribute("RoundEnd", workspace:GetServerTimeNow() + duration)
	shared:SetAttribute("Sections", table.concat(chosen, ","))
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
	notifyEvent:FireAllClients("A brand new tower has been served!")
	return duration
end

buildWorld()
task.spawn(function()
	while true do
		task.wait(startRound())
	end
end)
