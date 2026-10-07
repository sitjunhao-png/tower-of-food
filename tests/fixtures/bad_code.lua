-- Harness fixtures that must FAIL (coding mistakes). Each one is a working spiral plus one bug.
do
	local function spiral(ctx: Ctx)
		for i = 0, 10 do
			local angle = 40 * i
			local x, z = ctx:Polar(11, angle)
			ctx:Platform(x, 2 + 2.5 * i, z, 4, 4, { Yaw = -angle, Name = "Step" .. i, Color = (i % 2 == 0) and ctx.Theme.Main or ctx.Theme.Accent })
			local bx, bz = ctx:Polar(20, 40 * i)
			ctx:Ball(bx, 3 + 2 * i, bz, 1.5, { Color = Color3.fromRGB(80, 200, 255), CanCollide = false, Name = "Bubble" })
			ctx:Block(-bx * 1.05, 2 + 2 * i, -bz * 1.05, 1, 1, 1, { Color = Color3.fromRGB(255, 255, 255), CanCollide = false, Name = "Sugar" })
		end
	end
	local function def(name: string, build: (ctx: Ctx) -> ())
		table.insert(Sections, {
			Name = name,
			Creator = "Harness",
			Difficulty = 1,
			Height = 30,
			Colors = { Main = Color3.fromRGB(200, 120, 60), Accent = Color3.fromRGB(255, 220, 160) },
			Build = build,
		})
	end

	-- FAIL: "Colour" is not a ctx option (the type checker does NOT catch this one)
	def("Fixture Opts Typo", function(ctx: Ctx)
		spiral(ctx)
		ctx:Platform(15, 20, 0, 3, 3, { Colour = Color3.new(1, 0, 0) })
	end)

	-- FAIL: wrong property name on a part
	def("Fixture Prop Typo", function(ctx: Ctx)
		spiral(ctx)
		local p = ctx:Platform(15, 20, 0, 3, 3)
		p.Colr = Color3.new(1, 0, 0)
	end)

	-- FAIL: runtime crash (indexing a missing table entry)
	def("Fixture Crash", function(ctx: Ctx)
		spiral(ctx)
		local spots: { Vector3 } = {}
		ctx:Platform(spots[3].X, 20, 0, 3, 3)
	end)

	-- FAIL: Vector3 components are read-only (the type checker does NOT catch this one)
	def("Fixture ReadOnly", function(ctx: Ctx)
		spiral(ctx)
		local v = Vector3.new(15, 20, 0)
		v.X = 16
	end)

	-- FAIL: a part parented straight into workspace instead of the section
	def("Fixture Escaped Part", function(ctx: Ctx)
		spiral(ctx)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Parent = workspace
	end)

	-- FAIL: connecting an event in Build
	def("Fixture Touched", function(ctx: Ctx)
		spiral(ctx)
		local p = ctx:Platform(15, 20, 0, 3, 3)
		p.Touched:Connect(function() end)
	end)

	-- FAIL: bad metadata (odd Height, Difficulty 4)
	table.insert(Sections, {
		Name = "Fixture Bad Meta",
		Creator = "Harness",
		Difficulty = 4,
		Height = 31,
		Colors = { Main = Color3.fromRGB(200, 120, 60), Accent = Color3.fromRGB(255, 220, 160) },
		Build = function(ctx: Ctx)
			spiral(ctx)
		end,
	})

	-- FAIL: a ctx argument is nil (size), and a WARN for a nil-parented decoration
	def("Fixture Nil Size", function(ctx: Ctx)
		spiral(ctx)
		local light = Instance.new("PointLight")
		light.Range = 12
		local sizes: { number } = {}
		ctx:Block(15, 20, 0, 2, sizes[1], 2)
	end)
end
