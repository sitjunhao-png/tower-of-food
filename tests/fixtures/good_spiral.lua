-- Harness fixture (should PASS): a spiral of waffle steps with moving decorations.
table.insert(Sections, {
	Name = "Fixture Waffle Spiral",
	Creator = "Harness",
	Difficulty = 1,
	Height = 30,
	Colors = { Main = Color3.fromRGB(214, 160, 82), Accent = Color3.fromRGB(255, 236, 170) },
	Build = function(ctx: Ctx)
		local SYRUP = Color3.fromRGB(150, 80, 20)
		local BUTTER = Color3.fromRGB(255, 230, 120)
		-- 11 waffle steps spiral up: 2.5 studs higher and 40 degrees further each time
		for i = 0, 10 do
			local angle = 40 * i
			local x, z = ctx:Polar(11, angle)
			local top = 2 + 2.5 * i
			ctx:Platform(x, top, z, 4, 4, { Yaw = -angle, Name = "Waffle" .. i, Color = (i % 2 == 0) and ctx.Theme.Main or ctx.Theme.Accent })
			local bx, bz = ctx:Polar(12.5, angle)
			ctx:Ball(bx, top + 0.4, bz, 1, { Color = BUTTER, CanCollide = false, Name = "Butter" })
		end
		-- candy-cane poles around the wall
		for i = 0, 5 do
			local x, z = ctx:Polar(22, 60 * i + 20)
			ctx:Cylinder(x, 15, z, 28, 1, { Roll = 90, Color = (i % 2 == 0) and SYRUP or ctx.Theme.Light, Name = "Pole" })
		end
		-- a syrup donut slowly spinning near the wall (decoration)
		local dx, dz = ctx:Polar(18, 200)
		local donut = ctx:Group("Donut", dx, 20, dz)
		for k = 0, 3 do
			local ox, oz = ctx:Polar(2.5, 90 * k)
			ctx:Ball(dx + ox, 20, dz + oz, 1.5, { Color = SYRUP, CanCollide = false, Parent = donut :: Instance, Name = "DonutBit" })
		end
		ctx:Spin(donut, 45)
		-- a swinging sausage on a string (decoration)
		local sx, sz = ctx:Polar(18, 100)
		local sausage = ctx:Cylinder(sx, 12, sz, 3, 1.2, { Color = Color3.fromRGB(170, 70, 50), CanCollide = false, Name = "Sausage" })
		ctx:Swing(sausage, Vector3.new(sx, 16, sz), Vector3.new(1, 0, 0), 30, 3)
	end,
})
