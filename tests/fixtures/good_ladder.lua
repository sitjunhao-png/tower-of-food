-- Harness fixture (should PASS): a truss ladder, a bounce pad and a moving platform.
table.insert(Sections, {
	Name = "Fixture Pretzel Ladder",
	Creator = "Harness",
	Difficulty = 2,
	Height = 36,
	Colors = { Main = Color3.fromRGB(160, 100, 50), Accent = Color3.fromRGB(240, 240, 240) },
	Build = function(ctx: Ctx)
		local SALT = Color3.fromRGB(250, 250, 250)
		local DOUGH = Color3.fromRGB(200, 140, 70)
		-- first step off the entry plate
		ctx:Platform(10.5, 2, 0, 5, 5, { Name = "Start" })
		-- a pretzel-stick ladder up to y = 16
		ctx:Truss(13.5, 2, 0, 14, { Name = "Ladder", Color = DOUGH })
		ctx:Platform(13.5, 16, 4, 4, 4, { Name = "LadderTop", Color = ctx.Theme.Accent })
		-- a bounce pad launches you to the next ledge (rise 9)
		ctx:Platform(10, 16, 8, 3, 3, { Name = "Bouncer", Color = Color3.fromRGB(255, 80, 160) })
		ctx:Bounce(ctx:Platform(10, 16.2, 8, 2.5, 2.5, { Name = "Pad", Thickness = 0.2, Color = SALT }))
		ctx:Platform(4, 25, 12, 5, 5, { Name = "HighLedge" })
		-- a sliding platform carries you to the last ledge
		local slider = ctx:Platform(-3, 27, 13, 4, 4, { Name = "Slider", Color = DOUGH })
		ctx:Move(slider, Vector3.new(-6, 0, -4), 4)
		-- last safe ledge next to the exit plate (rule 4)
		ctx:Platform(-9.5, 32, 4, 4, 5, { Name = "LastLedge" })
		-- decorations: salt crystals and pretzel loops on the wall
		for i = 0, 15 do
			local x, z = ctx:Polar(21, 22.5 * i)
			ctx:Block(x, 3 + i * 2, z, 1, 1, 1, { Color = SALT, Material = Enum.Material.Glass, CanCollide = false, Yaw = 45 * i, Name = "Salt" })
			if i % 2 == 0 then
				ctx:Cylinder(x, 4 + i * 2, z, 0.6, 3, { Yaw = 22.5 * i, Color = (i % 4 == 0) and DOUGH or ctx.Theme.Main, CanCollide = false, Name = "Loop" })
			end
		end
	end,
})
