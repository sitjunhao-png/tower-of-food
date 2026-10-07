-- Harness fixtures that must FAIL (geometry). Each one is a working spiral plus one mistake.
do
	-- the same climbable spiral as the good fixture: steps 0..10, top y = 2 + 2.5 * i
	local function spiral(ctx: Ctx, skip: { [number]: boolean }?, radius: number?)
		for i = 0, 10 do
			if not (skip and skip[i]) then
				local angle = 40 * i
				local x, z = ctx:Polar(radius or 11, angle)
				ctx:Platform(x, 2 + 2.5 * i, z, 4, 4, { Yaw = -angle, Name = "Step" .. i, Color = (i % 2 == 0) and ctx.Theme.Main or ctx.Theme.Accent })
			end
			local bx, bz = ctx:Polar(20, 40 * i)
			ctx:Ball(bx, 3 + 2 * i, bz, 1.5, { Color = Color3.fromRGB(80, 200, 255), CanCollide = false, Name = "Bubble" })
			ctx:Block(-bx * 1.05, 2 + 2 * i, -bz * 1.05, 1, 1, 1, { Color = Color3.fromRGB(255, 255, 255), CanCollide = false, Name = "Sugar" })
		end
	end

	-- FAIL: a step pokes out of radius 24, and an arm only pokes out while spinning
	table.insert(Sections, {
		Name = "Fixture Bad Radius",
		Creator = "Harness",
		Difficulty = 1,
		Height = 30,
		Colors = { Main = Color3.fromRGB(255, 120, 120), Accent = Color3.fromRGB(255, 200, 200) },
		Build = function(ctx: Ctx)
			spiral(ctx)
			ctx:Platform(23, 12, 0, 4, 4, { Name = "TooFar" })
			local spinner = ctx:Group("Spinner", 14, 18, 0)
			ctx:Block(8, 18, 0, 12, 1, 1, { Name = "SpinArm", Parent = spinner :: Instance, CanCollide = false })
			ctx:Spin(spinner, 40)
		end,
	})

	-- FAIL: a solid block in the launch space and a deadly bar sliding through the exit space
	table.insert(Sections, {
		Name = "Fixture Bad KeepOut",
		Creator = "Harness",
		Difficulty = 2,
		Height = 30,
		Colors = { Main = Color3.fromRGB(120, 255, 120), Accent = Color3.fromRGB(200, 255, 200) },
		Build = function(ctx: Ctx)
			spiral(ctx)
			ctx:Block(0, 3, 0, 3, 1, 3, { Name = "Blocker" })
			-- not solid, so this one is allowed in the keep-out zone
			ctx:Ball(2, 4, 2, 1, { Name = "GhostSprinkle", CanCollide = false })
			local bar = ctx:Block(-15, 27, 0, 2, 1, 2, { Name = "LaserBar", CanCollide = false })
			ctx:Kill(bar)
			ctx:Move(bar, Vector3.new(30, 0, 0), 4)
		end,
	})

	-- FAIL: steps 5 and 6 are missing, so the climb stops at y = 12
	table.insert(Sections, {
		Name = "Fixture Bad Gap",
		Creator = "Harness",
		Difficulty = 1,
		Height = 30,
		Colors = { Main = Color3.fromRGB(120, 120, 255), Accent = Color3.fromRGB(200, 200, 255) },
		Build = function(ctx: Ctx)
			spiral(ctx, { [5] = true, [6] = true })
		end,
	})

	-- FAIL rule 4: reachable, but the last step is too far from the exit plate (nearest edge 11)
	table.insert(Sections, {
		Name = "Fixture No Exit Ledge",
		Creator = "Harness",
		Difficulty = 1,
		Height = 30,
		Colors = { Main = Color3.fromRGB(255, 255, 120), Accent = Color3.fromRGB(255, 255, 200) },
		Build = function(ctx: Ctx)
			spiral(ctx, nil, 13)
		end,
	})

	-- FAIL: an animated group inside another animated group
	table.insert(Sections, {
		Name = "Fixture Nested Spin",
		Creator = "Harness",
		Difficulty = 1,
		Height = 30,
		Colors = { Main = Color3.fromRGB(255, 120, 255), Accent = Color3.fromRGB(255, 200, 255) },
		Build = function(ctx: Ctx)
			spiral(ctx)
			local outer = ctx:Group("Outer", 16, 15, 0)
			local inner = ctx:Group("Inner", 16, 15, 0)
			inner.Parent = outer
			ctx:Block(17, 15, 0, 2, 1, 1, { Name = "Fan", Parent = inner :: Instance, CanCollide = false })
			ctx:Move(outer, Vector3.new(0, 2, 0), 3)
			ctx:Spin(inner, 90)
		end,
	})
end
