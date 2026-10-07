-- Harness fixture (must FAIL + WARN): exercises Cycle/Melt/Conveyor/Slippery steps and odd code.
-- Expected FAIL: "NoAxis" SpinAxis is NaN (zero axis), and rule 4 (the only last ledge is a Hazard).
-- Expected WARN: odd truss size, non-round ball, warn() call, group pivot used early,
-- Kill part without the deadly look, invisible solid part, part with two animations.
do
	local function spiral(ctx: Ctx)
		for i = 0, 10 do
			local angle = 40 * i
			local x, z = ctx:Polar(11, angle)
			local p = ctx:Platform(x, 2 + 2.5 * i, z, 4, 4, { Yaw = -angle, Name = "Step" .. i, Color = (i % 2 == 0) and ctx.Theme.Main or ctx.Theme.Accent })
			if i == 3 then
				ctx:Cycle(p, "Vanish", 2, 1)
			elseif i == 4 then
				ctx:Melt(p)
			elseif i == 5 then
				ctx:Conveyor(p, Vector3.new(0, 0, 4))
			elseif i == 6 then
				ctx:Slippery(p)
			elseif i == 10 then
				ctx:Cycle(p, "Hazard", 2, 2) -- the last ledge is a hazard: rule 4 should fail
			end
			local bx, bz = ctx:Polar(20, 40 * i)
			ctx:Ball(bx, 3 + 2 * i, bz, 1.5, { Color = Color3.fromRGB(80, 200, 255), CanCollide = false, Name = "Bubble" })
			ctx:Block(-bx * 1.05, 2 + 2 * i, -bz * 1.05, 1, 1, 1, { Color = Color3.fromRGB(255, 255, 255), CanCollide = false, Name = "Sugar" })
		end
	end

	table.insert(Sections, {
		Name = "Fixture Edge Cases",
		Creator = "Harness",
		Difficulty = 3,
		Height = 30,
		Colors = { Main = Color3.fromRGB(200, 120, 60), Accent = Color3.fromRGB(255, 220, 160) },
		Build = function(ctx: Ctx)
			spiral(ctx)
			-- zero spin axis -> NaN SpinAxis
			local bad = ctx:Block(15, 20, 0, 2, 1, 2, { Name = "NoAxis", CanCollide = false })
			ctx:Spin(bad, 30, Vector3.zero)
			-- truss with an odd size made by hand
			local t = Instance.new("TrussPart")
			t.Size = Vector3.new(2, 5, 2)
			t.CFrame = ctx:CF(-15, 5, -5)
			t.Parent = ctx.Model
			-- ball given a non-round size by hand
			local b = Instance.new("Part")
			b.Shape = Enum.PartType.Ball
			b.Size = Vector3.new(3, 1, 3)
			b.CFrame = ctx:CF(-16, 10, 6)
			b.Parent = ctx.Model
			warn("hello from the section")
			-- kill part keeping its own look
			local k = ctx:Block(-17, 12, -4, 1, 1, 1, { Name = "SneakyKill", Color = Color3.new(0, 1, 0) })
			ctx:Kill(k, true)
			-- invisible but solid
			ctx:Block(-18, 14, 2, 2, 1, 2, { Name = "Ghost", Transparency = 1 })
			-- a group moved before Build finishes
			local g = ctx:Group("Early", -12, 18, 10)
			ctx:Block(-12, 18, 10, 2, 1, 2, { Name = "EarlyPart", Parent = g :: Instance, CanCollide = false })
			g:PivotTo(g:GetPivot() + Vector3.new(0, 1, 0))
			-- cloned decoration
			local c = (ctx:Ball(-14, 22, -10, 1, { Name = "Cherry", CanCollide = false, Color = Color3.new(1, 0, 0) })):Clone()
			c.Position = c.Position + Vector3.new(1, 0, 0)
			c.Parent = ctx.Model
			-- one part with two animations
			local both = ctx:Block(16, 8, 8, 1, 1, 1, { Name = "Both", CanCollide = false })
			ctx:Spin(both, 20)
			ctx:Move(both, Vector3.new(0, 2, 0), 3)
		end,
	})
end
