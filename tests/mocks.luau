--[[
	TOWER OF FOOD - fake Roblox for the section test harness   (tests/mocks.luau)

	tools/check.sh glues THIS file + the TowerSections module + tests/section_checks.luau
	into one script and runs it with the plain Luau runtime (no Roblox here!).
	So this file pretends to be Roblox: Vector3, CFrame, Color3, Enum, Random,
	Instance.new, CollectionService, game, workspace...

	The fakes are deliberately STRICT, so mistakes blow up here instead of in Studio:
	  * wrong property names      part.Colour = ...            -> error
	  * wrong value types         part.Color = nil             -> error
	  * read-only things          v.X = 5, cf.Position = ...   -> error
	  * Enum typos                Enum.Material.Neonn          -> error
	  * bad attribute values      part:SetAttribute("A", {})   -> error
	  * events / waiting in Build part.Touched:Connect(...)    -> error

	The class / property / enum lists at the bottom were generated from
	.tools/globalTypes.d.luau (the same Roblox API definitions the type checker uses).
]]

-- Everything the TowerSections module (and the sections) can see, like in Roblox.
local game, workspace, Instance, Enum
local Vector3, Vector2, CFrame, Color3, BrickColor, Random, PhysicalProperties
local NumberSequence, NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, NumberRange
local UDim, UDim2, Font, Rect, TweenInfo
local typeof, tick, time, wait, delay, spawn, task, warn
local Mock = {} -- harness-only helpers (raw access, build log, notes)
local API = {} -- Roblox API data, filled in at the bottom of this file

local function buildMocks()
	local fmt = string.format
	local sqrt, sin, cos, abs, floor = math.sqrt, math.sin, math.cos, math.abs, math.floor
	local huge = math.huge
	local TYPE_OF = {} -- metatable -> Roblox type name (for typeof)

	typeof = function(v: any): string
		local t = type(v)
		if t == "table" then
			local mt = getmetatable(v)
			if mt ~= nil then
				local name = TYPE_OF[mt]
				if name then
					return name
				end
			end
		end
		return t
	end

	local notes = {} -- soft problems noticed by the mocks during one build
	local function note(msg: string)
		table.insert(notes, msg)
	end

	-- nice number text: 3, 2.5, 0.333
	local function nstr(n: number): string
		if n ~= n then
			return "nan"
		end
		if n == 0 then
			return "0"
		end
		if n == floor(n) and abs(n) < 1e15 then
			return tostring(floor(n))
		end
		return (fmt("%.3f", n):gsub("0+$", ""))
	end

	-- A library table (Vector3, CFrame...) where unknown names error: Vector3.neww -> error
	local function library(name: string, t: { [string]: any })
		return setmetatable(t, {
			__index = function(_, k)
				error(fmt("%s is not a valid member of %s", tostring(k), name), 2)
			end,
			__newindex = function(_, k)
				error(fmt("%s.%s cannot be assigned to", name, tostring(k)), 2)
			end,
		})
	end

	local function badArg(fname: string, i: number, expected: string, got: any)
		error(fmt("invalid argument #%d to '%s' (%s expected, got %s)", i, fname, expected, typeof(got)), 3)
	end

	-- number argument, nil -> default (like Roblox), anything else -> error
	local function numArg(fname: string, i: number, v: any, default: number?): number
		if v == nil and default ~= nil then
			return default
		end
		if type(v) ~= "number" then
			badArg(fname, i, "number", v)
		end
		return v
	end

	local function colonCheck(ok: boolean, typeName: string, fname: string)
		if not ok then
			error(fmt("Expected ':' not '.' calling member function %s of %s", fname, typeName), 3)
		end
	end

	------------------------------------------------------------------------
	-- Vector3 (components live in slots 1..3 so X/Y/Z stay read-only)
	------------------------------------------------------------------------
	local V3 = {}
	TYPE_OF[V3] = "Vector3"
	local function v3(x: number, y: number, z: number)
		return setmetatable({ x, y, z }, V3)
	end
	local function isV3(v: any): boolean
		return type(v) == "table" and getmetatable(v) == V3
	end
	local function needV3(fname: string, i: number, v: any)
		if not isV3(v) then
			badArg(fname, i, "Vector3", v)
		end
		return v
	end
	local V3M = {}
	V3.__index = function(self, k)
		if k == "X" then
			return self[1]
		elseif k == "Y" then
			return self[2]
		elseif k == "Z" then
			return self[3]
		elseif k == "Magnitude" then
			return sqrt(self[1] * self[1] + self[2] * self[2] + self[3] * self[3])
		elseif k == "Unit" then
			local m = sqrt(self[1] * self[1] + self[2] * self[2] + self[3] * self[3])
			return v3(self[1] / m, self[2] / m, self[3] / m) -- zero vector -> NaN, like Roblox
		end
		local f = V3M[k]
		if f then
			return f
		end
		error(fmt("%s is not a valid member of Vector3", tostring(k)), 2)
	end
	V3.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (Vector3 is read-only, make a new one)", tostring(k)), 2)
	end
	local function arithErr(op: string, a: any, b: any)
		error(fmt("attempt to perform arithmetic (%s) on %s and %s", op, typeof(a), typeof(b)), 3)
	end
	V3.__add = function(a, b)
		if isV3(a) and isV3(b) then
			return v3(a[1] + b[1], a[2] + b[2], a[3] + b[3])
		end
		arithErr("add", a, b)
	end
	V3.__sub = function(a, b)
		if isV3(a) and isV3(b) then
			return v3(a[1] - b[1], a[2] - b[2], a[3] - b[3])
		end
		arithErr("sub", a, b)
	end
	V3.__mul = function(a, b)
		if type(a) == "number" and isV3(b) then
			return v3(a * b[1], a * b[2], a * b[3])
		elseif isV3(a) and type(b) == "number" then
			return v3(a[1] * b, a[2] * b, a[3] * b)
		elseif isV3(a) and isV3(b) then
			return v3(a[1] * b[1], a[2] * b[2], a[3] * b[3])
		end
		arithErr("mul", a, b)
	end
	V3.__div = function(a, b)
		if isV3(a) and type(b) == "number" then
			return v3(a[1] / b, a[2] / b, a[3] / b)
		elseif isV3(a) and isV3(b) then
			return v3(a[1] / b[1], a[2] / b[2], a[3] / b[3])
		elseif type(a) == "number" and isV3(b) then
			return v3(a / b[1], a / b[2], a / b[3])
		end
		arithErr("div", a, b)
	end
	V3.__idiv = function(a, b)
		if isV3(a) and type(b) == "number" then
			return v3(floor(a[1] / b), floor(a[2] / b), floor(a[3] / b))
		elseif isV3(a) and isV3(b) then
			return v3(floor(a[1] / b[1]), floor(a[2] / b[2]), floor(a[3] / b[3]))
		end
		arithErr("idiv", a, b)
	end
	V3.__unm = function(a)
		return v3(-a[1], -a[2], -a[3])
	end
	V3.__eq = function(a, b)
		return isV3(a) and isV3(b) and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end
	V3.__tostring = function(a)
		return nstr(a[1]) .. ", " .. nstr(a[2]) .. ", " .. nstr(a[3])
	end
	V3M.Dot = function(a, b)
		colonCheck(isV3(a), "Vector3", "Dot")
		needV3("Dot", 1, b)
		return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
	end
	V3M.Cross = function(a, b)
		colonCheck(isV3(a), "Vector3", "Cross")
		needV3("Cross", 1, b)
		return v3(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
	end
	V3M.Lerp = function(a, b, t)
		colonCheck(isV3(a), "Vector3", "Lerp")
		needV3("Lerp", 1, b)
		t = numArg("Lerp", 2, t)
		return v3(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
	end
	V3M.Min = function(a, ...)
		colonCheck(isV3(a), "Vector3", "Min")
		local x, y, z = a[1], a[2], a[3]
		for i = 1, select("#", ...) do
			local b = needV3("Min", i, (select(i, ...)))
			x, y, z = math.min(x, b[1]), math.min(y, b[2]), math.min(z, b[3])
		end
		return v3(x, y, z)
	end
	V3M.Max = function(a, ...)
		colonCheck(isV3(a), "Vector3", "Max")
		local x, y, z = a[1], a[2], a[3]
		for i = 1, select("#", ...) do
			local b = needV3("Max", i, (select(i, ...)))
			x, y, z = math.max(x, b[1]), math.max(y, b[2]), math.max(z, b[3])
		end
		return v3(x, y, z)
	end
	V3M.Abs = function(a)
		colonCheck(isV3(a), "Vector3", "Abs")
		return v3(abs(a[1]), abs(a[2]), abs(a[3]))
	end
	V3M.Floor = function(a)
		colonCheck(isV3(a), "Vector3", "Floor")
		return v3(floor(a[1]), floor(a[2]), floor(a[3]))
	end
	V3M.Ceil = function(a)
		colonCheck(isV3(a), "Vector3", "Ceil")
		return v3(math.ceil(a[1]), math.ceil(a[2]), math.ceil(a[3]))
	end
	V3M.Sign = function(a)
		colonCheck(isV3(a), "Vector3", "Sign")
		return v3(math.sign(a[1]), math.sign(a[2]), math.sign(a[3]))
	end
	V3M.FuzzyEq = function(a, b, eps)
		colonCheck(isV3(a), "Vector3", "FuzzyEq")
		needV3("FuzzyEq", 1, b)
		eps = numArg("FuzzyEq", 2, eps, 1e-5)
		return abs(a[1] - b[1]) <= eps and abs(a[2] - b[2]) <= eps and abs(a[3] - b[3]) <= eps
	end
	V3M.Angle = function(a, b, axis)
		colonCheck(isV3(a), "Vector3", "Angle")
		needV3("Angle", 1, b)
		local c = v3(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
		local ang = math.atan2(c.Magnitude, a[1] * b[1] + a[2] * b[2] + a[3] * b[3])
		if axis ~= nil and needV3("Angle", 2, axis) and c:Dot(axis) < 0 then
			ang = -ang
		end
		return ang
	end
	Vector3 = library("Vector3", {
		new = function(x, y, z)
			return v3(numArg("Vector3.new", 1, x, 0), numArg("Vector3.new", 2, y, 0), numArg("Vector3.new", 3, z, 0))
		end,
		zero = v3(0, 0, 0),
		one = v3(1, 1, 1),
		xAxis = v3(1, 0, 0),
		yAxis = v3(0, 1, 0),
		zAxis = v3(0, 0, 1),
		FromNormalId = function(n)
			local name = (typeof(n) == "EnumItem" and n.Name) or ""
			local map = {
				Right = v3(1, 0, 0),
				Left = v3(-1, 0, 0),
				Top = v3(0, 1, 0),
				Bottom = v3(0, -1, 0),
				Back = v3(0, 0, 1),
				Front = v3(0, 0, -1),
			}
			return map[name] or badArg("Vector3.FromNormalId", 1, "Enum.NormalId", n)
		end,
		FromAxis = function(a)
			local name = (typeof(a) == "EnumItem" and a.Name) or ""
			local map = { X = v3(1, 0, 0), Y = v3(0, 1, 0), Z = v3(0, 0, 1) }
			return map[name] or badArg("Vector3.FromAxis", 1, "Enum.Axis", a)
		end,
	})

	------------------------------------------------------------------------
	-- CFrame: slots 1..3 = position, 4..12 = rotation matrix r00 r01 r02 r10 r11 r12 r20 r21 r22
	------------------------------------------------------------------------
	local CF = {}
	TYPE_OF[CF] = "CFrame"
	local function cfr(x, y, z, a, b, c, d, e, f, g, h, i)
		return setmetatable({ x, y, z, a, b, c, d, e, f, g, h, i }, CF)
	end
	local function isCF(v: any): boolean
		return type(v) == "table" and getmetatable(v) == CF
	end
	local function needCF(fname: string, i: number, v: any)
		if not isCF(v) then
			badArg(fname, i, "CFrame", v)
		end
		return v
	end
	local function cfMul(A, B)
		local a00, a01, a02, a10, a11, a12, a20, a21, a22 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
		local b00, b01, b02, b10, b11, b12, b20, b21, b22 = B[4], B[5], B[6], B[7], B[8], B[9], B[10], B[11], B[12]
		local bx, by, bz = B[1], B[2], B[3]
		return cfr(
			a00 * bx + a01 * by + a02 * bz + A[1],
			a10 * bx + a11 * by + a12 * bz + A[2],
			a20 * bx + a21 * by + a22 * bz + A[3],
			a00 * b00 + a01 * b10 + a02 * b20,
			a00 * b01 + a01 * b11 + a02 * b21,
			a00 * b02 + a01 * b12 + a02 * b22,
			a10 * b00 + a11 * b10 + a12 * b20,
			a10 * b01 + a11 * b11 + a12 * b21,
			a10 * b02 + a11 * b12 + a12 * b22,
			a20 * b00 + a21 * b10 + a22 * b20,
			a20 * b01 + a21 * b11 + a22 * b21,
			a20 * b02 + a21 * b12 + a22 * b22
		)
	end
	local function cfPoint(A, x, y, z)
		return A[4] * x + A[5] * y + A[6] * z + A[1], A[7] * x + A[8] * y + A[9] * z + A[2], A[10] * x + A[11] * y + A[12] * z + A[3]
	end
	local function cfVector(A, x, y, z)
		return A[4] * x + A[5] * y + A[6] * z, A[7] * x + A[8] * y + A[9] * z, A[10] * x + A[11] * y + A[12] * z
	end
	local function cfInv(A)
		local px, py, pz = A[1], A[2], A[3]
		return cfr(
			-(A[4] * px + A[7] * py + A[10] * pz),
			-(A[5] * px + A[8] * py + A[11] * pz),
			-(A[6] * px + A[9] * py + A[12] * pz),
			A[4], A[7], A[10],
			A[5], A[8], A[11],
			A[6], A[9], A[12]
		)
	end
	local function rotX(a)
		local c, s = cos(a), sin(a)
		return cfr(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
	end
	local function rotY(a)
		local c, s = cos(a), sin(a)
		return cfr(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
	end
	local function rotZ(a)
		local c, s = cos(a), sin(a)
		return cfr(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
	end
	local IDENTITY = cfr(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	-- rotation matrix -> quaternion (x, y, z, w)
	local function toQuat(A)
		local r00, r01, r02, r10, r11, r12, r20, r21, r22 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
		local tr = r00 + r11 + r22
		if tr > 0 then
			local s = sqrt(tr + 1) * 2
			return (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s, 0.25 * s
		elseif r00 > r11 and r00 > r22 then
			local s = sqrt(1 + r00 - r11 - r22) * 2
			return 0.25 * s, (r01 + r10) / s, (r02 + r20) / s, (r21 - r12) / s
		elseif r11 > r22 then
			local s = sqrt(1 + r11 - r00 - r22) * 2
			return (r01 + r10) / s, 0.25 * s, (r12 + r21) / s, (r02 - r20) / s
		else
			local s = sqrt(1 + r22 - r00 - r11) * 2
			return (r02 + r20) / s, (r12 + r21) / s, 0.25 * s, (r10 - r01) / s
		end
	end
	local function fromQuat(px, py, pz, x, y, z, w)
		local m = sqrt(x * x + y * y + z * z + w * w)
		x, y, z, w = x / m, y / m, z / m, w / m
		return cfr(
			px, py, pz,
			1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
			2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
			2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)
		)
	end
	local function axisAngle(ax, ay, az, t)
		local m = sqrt(ax * ax + ay * ay + az * az)
		ax, ay, az = ax / m, ay / m, az / m
		local c, s = cos(t), sin(t)
		local k = 1 - c
		return cfr(
			0, 0, 0,
			c + ax * ax * k, ax * ay * k - az * s, ax * az * k + ay * s,
			ay * ax * k + az * s, c + ay * ay * k, ay * az * k - ax * s,
			az * ax * k - ay * s, az * ay * k + ax * s, c + az * az * k
		)
	end
	-- columns x, y, z (each 3 numbers) + position
	local function fromColumns(px, py, pz, xx, xy, xz, yx, yy, yz, zx, zy, zz)
		return cfr(px, py, pz, xx, yx, zx, xy, yy, zy, xz, yz, zz)
	end
	local function lookAt(at, target, up)
		local lx, ly, lz = target[1] - at[1], target[2] - at[2], target[3] - at[3]
		local lm = sqrt(lx * lx + ly * ly + lz * lz)
		if lm < 1e-9 then
			return cfr(at[1], at[2], at[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		lx, ly, lz = lx / lm, ly / lm, lz / lm
		local ux, uy, uz = 0, 1, 0
		if up then
			local um = up.Magnitude
			ux, uy, uz = up[1] / um, up[2] / um, up[3] / um
		end
		-- if looking (almost) straight along "up", pick another up (like Roblox/G3D)
		if abs(lx * ux + ly * uy + lz * uz) > 0.9999 then
			ux, uy, uz = 1, 0, 0
			if abs(lx) > 0.9999 then
				ux, uy, uz = 0, 1, 0
			end
		end
		local zx, zy, zz = -lx, -ly, -lz
		-- x = up cross z
		local xx, xy, xz = uy * zz - uz * zy, uz * zx - ux * zz, ux * zy - uy * zx
		local xm = sqrt(xx * xx + xy * xy + xz * xz)
		xx, xy, xz = xx / xm, xy / xm, xz / xm
		-- y = z cross x
		local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
		return fromColumns(at[1], at[2], at[3], xx, xy, xz, yx, yy, yz, zx, zy, zz)
	end
	local function rotationOf(A)
		return cfr(0, 0, 0, A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12])
	end
	local function clamp1(x)
		return math.clamp(x, -1, 1)
	end

	local CFM = {}
	CF.__index = function(self, k)
		if k == "Position" or k == "p" then
			return v3(self[1], self[2], self[3])
		elseif k == "X" then
			return self[1]
		elseif k == "Y" then
			return self[2]
		elseif k == "Z" then
			return self[3]
		elseif k == "LookVector" or k == "lookVector" then
			return v3(-self[6], -self[9], -self[12])
		elseif k == "RightVector" or k == "rightVector" then
			return v3(self[4], self[7], self[10])
		elseif k == "UpVector" or k == "upVector" then
			return v3(self[5], self[8], self[11])
		elseif k == "XVector" then
			return v3(self[4], self[5], self[6])
		elseif k == "YVector" then
			return v3(self[7], self[8], self[9])
		elseif k == "ZVector" then
			return v3(self[10], self[11], self[12])
		elseif k == "Rotation" then
			return rotationOf(self)
		end
		local f = CFM[k]
		if f then
			return f
		end
		error(fmt("%s is not a valid member of CFrame", tostring(k)), 2)
	end
	CF.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (CFrame is read-only, make a new one)", tostring(k)), 2)
	end
	CF.__mul = function(a, b)
		if isCF(a) and isCF(b) then
			return cfMul(a, b)
		elseif isCF(a) and isV3(b) then
			return v3(cfPoint(a, b[1], b[2], b[3]))
		end
		arithErr("mul", a, b)
	end
	CF.__add = function(a, b)
		if isCF(a) and isV3(b) then
			return cfr(a[1] + b[1], a[2] + b[2], a[3] + b[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
		end
		arithErr("add", a, b)
	end
	CF.__sub = function(a, b)
		if isCF(a) and isV3(b) then
			return cfr(a[1] - b[1], a[2] - b[2], a[3] - b[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
		end
		arithErr("sub", a, b)
	end
	CF.__eq = function(a, b)
		if not (isCF(a) and isCF(b)) then
			return false
		end
		for i = 1, 12 do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end
	CF.__tostring = function(a)
		local parts = {}
		for i = 1, 12 do
			parts[i] = nstr(a[i])
		end
		return table.concat(parts, ", ")
	end
	local function eachArg(fname: string, conv, ...)
		local out = {}
		local n = select("#", ...)
		for i = 1, n do
			out[i] = conv(fname, i, (select(i, ...)))
		end
		return table.unpack(out, 1, n)
	end
	CFM.Inverse = function(a)
		colonCheck(isCF(a), "CFrame", "Inverse")
		return cfInv(a)
	end
	CFM.ToWorldSpace = function(a, ...)
		colonCheck(isCF(a), "CFrame", "ToWorldSpace")
		return eachArg("ToWorldSpace", function(f, i, c)
			return cfMul(a, needCF(f, i, c))
		end, ...)
	end
	CFM.ToObjectSpace = function(a, ...)
		colonCheck(isCF(a), "CFrame", "ToObjectSpace")
		local inv = cfInv(a)
		return eachArg("ToObjectSpace", function(f, i, c)
			return cfMul(inv, needCF(f, i, c))
		end, ...)
	end
	CFM.PointToWorldSpace = function(a, ...)
		colonCheck(isCF(a), "CFrame", "PointToWorldSpace")
		return eachArg("PointToWorldSpace", function(f, i, v)
			needV3(f, i, v)
			return v3(cfPoint(a, v[1], v[2], v[3]))
		end, ...)
	end
	CFM.PointToObjectSpace = function(a, ...)
		colonCheck(isCF(a), "CFrame", "PointToObjectSpace")
		local inv = cfInv(a)
		return eachArg("PointToObjectSpace", function(f, i, v)
			needV3(f, i, v)
			return v3(cfPoint(inv, v[1], v[2], v[3]))
		end, ...)
	end
	CFM.VectorToWorldSpace = function(a, ...)
		colonCheck(isCF(a), "CFrame", "VectorToWorldSpace")
		return eachArg("VectorToWorldSpace", function(f, i, v)
			needV3(f, i, v)
			return v3(cfVector(a, v[1], v[2], v[3]))
		end, ...)
	end
	CFM.VectorToObjectSpace = function(a, ...)
		colonCheck(isCF(a), "CFrame", "VectorToObjectSpace")
		local inv = cfInv(a)
		return eachArg("VectorToObjectSpace", function(f, i, v)
			needV3(f, i, v)
			return v3(cfVector(inv, v[1], v[2], v[3]))
		end, ...)
	end
	CFM.GetComponents = function(a)
		colonCheck(isCF(a), "CFrame", "GetComponents")
		return a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
	end
	CFM.components = CFM.GetComponents
	CFM.ToEulerAnglesXYZ = function(a)
		colonCheck(isCF(a), "CFrame", "ToEulerAnglesXYZ")
		return math.atan2(-a[9], a[12]), math.asin(clamp1(a[6])), math.atan2(-a[5], a[4])
	end
	CFM.toEulerAnglesXYZ = CFM.ToEulerAnglesXYZ
	CFM.ToEulerAnglesYXZ = function(a)
		colonCheck(isCF(a), "CFrame", "ToEulerAnglesYXZ")
		return math.asin(clamp1(-a[9])), math.atan2(a[6], a[12]), math.atan2(a[7], a[8])
	end
	CFM.ToOrientation = CFM.ToEulerAnglesYXZ
	CFM.ToAxisAngle = function(a)
		colonCheck(isCF(a), "CFrame", "ToAxisAngle")
		local x, y, z, w = toQuat(a)
		if w < 0 then
			x, y, z, w = -x, -y, -z, -w
		end
		local ang = 2 * math.acos(math.clamp(w, -1, 1))
		local s = sqrt(math.max(0, 1 - w * w))
		if s < 1e-9 then
			return v3(1, 0, 0), 0
		end
		return v3(x / s, y / s, z / s), ang
	end
	CFM.Lerp = function(a, b, t)
		colonCheck(isCF(a), "CFrame", "Lerp")
		needCF("Lerp", 1, b)
		t = numArg("Lerp", 2, t)
		local ax, ay, az, aw = toQuat(a)
		local bx, by, bz, bw = toQuat(b)
		local d = ax * bx + ay * by + az * bz + aw * bw
		if d < 0 then
			bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d
		end
		local k0, k1
		if d > 0.9995 then
			k0, k1 = 1 - t, t
		else
			local th = math.acos(d)
			local st = sin(th)
			k0, k1 = sin((1 - t) * th) / st, sin(t * th) / st
		end
		return fromQuat(
			a[1] + (b[1] - a[1]) * t,
			a[2] + (b[2] - a[2]) * t,
			a[3] + (b[3] - a[3]) * t,
			ax * k0 + bx * k1,
			ay * k0 + by * k1,
			az * k0 + bz * k1,
			aw * k0 + bw * k1
		)
	end
	CFM.Orthonormalize = function(a)
		colonCheck(isCF(a), "CFrame", "Orthonormalize")
		local x = v3(a[4], a[7], a[10]).Unit
		local y = v3(a[5], a[8], a[11])
		y = (y - x * x:Dot(y)).Unit
		local z = x:Cross(y)
		return fromColumns(a[1], a[2], a[3], x[1], x[2], x[3], y[1], y[2], y[3], z[1], z[2], z[3])
	end
	CFM.FuzzyEq = function(a, b, eps)
		colonCheck(isCF(a), "CFrame", "FuzzyEq")
		needCF("FuzzyEq", 1, b)
		eps = numArg("FuzzyEq", 2, eps, 1e-5)
		for i = 1, 12 do
			if abs(a[i] - b[i]) > eps then
				return false
			end
		end
		return true
	end
	local function eulerOrder(rx, ry, rz, order: string)
		local X, Y, Z = rotX(rx), rotY(ry), rotZ(rz)
		local mats = { X = X, Y = Y, Z = Z }
		local o1, o2, o3 = string.sub(order, 1, 1), string.sub(order, 2, 2), string.sub(order, 3, 3)
		return cfMul(cfMul(mats[o1], mats[o2]), mats[o3])
	end
	CFrame = library("CFrame", {
		new = function(...)
			local n = select("#", ...)
			local a, b = ...
			if n == 0 then
				return IDENTITY
			elseif n == 1 then
				needV3("CFrame.new", 1, a)
				return cfr(a[1], a[2], a[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
			elseif n == 2 then
				needV3("CFrame.new", 1, a)
				needV3("CFrame.new", 2, b)
				return lookAt(a, b, nil)
			elseif n == 3 then
				return cfr(numArg("CFrame.new", 1, a), numArg("CFrame.new", 2, b), numArg("CFrame.new", 3, (select(3, ...))), 1, 0, 0, 0, 1, 0, 0, 0, 1)
			elseif n == 7 then
				local v = { ... }
				for i = 1, 7 do
					numArg("CFrame.new", i, v[i])
				end
				return fromQuat(v[1], v[2], v[3], v[4], v[5], v[6], v[7])
			elseif n == 12 then
				local v = { ... }
				for i = 1, 12 do
					numArg("CFrame.new", i, v[i])
				end
				return cfr(table.unpack(v, 1, 12))
			end
			error(fmt("Invalid number of arguments: %d (CFrame.new takes 0, 1, 2, 3, 7 or 12)", n), 2)
		end,
		identity = IDENTITY,
		Angles = function(rx, ry, rz)
			return eulerOrder(numArg("CFrame.Angles", 1, rx, 0), numArg("CFrame.Angles", 2, ry, 0), numArg("CFrame.Angles", 3, rz, 0), "XYZ")
		end,
		fromEulerAnglesXYZ = function(rx, ry, rz)
			return eulerOrder(numArg("CFrame.fromEulerAnglesXYZ", 1, rx, 0), numArg("CFrame.fromEulerAnglesXYZ", 2, ry, 0), numArg("CFrame.fromEulerAnglesXYZ", 3, rz, 0), "XYZ")
		end,
		fromEulerAnglesYXZ = function(rx, ry, rz)
			return eulerOrder(numArg("CFrame.fromEulerAnglesYXZ", 1, rx, 0), numArg("CFrame.fromEulerAnglesYXZ", 2, ry, 0), numArg("CFrame.fromEulerAnglesYXZ", 3, rz, 0), "YXZ")
		end,
		fromOrientation = function(rx, ry, rz)
			return eulerOrder(numArg("CFrame.fromOrientation", 1, rx, 0), numArg("CFrame.fromOrientation", 2, ry, 0), numArg("CFrame.fromOrientation", 3, rz, 0), "YXZ")
		end,
		fromEulerAngles = function(rx, ry, rz, order)
			local o = "XYZ"
			if order ~= nil then
				if typeof(order) ~= "EnumItem" or tostring(order.EnumType) ~= "RotationOrder" then
					badArg("CFrame.fromEulerAngles", 4, "Enum.RotationOrder", order)
				end
				o = order.Name
			end
			return eulerOrder(numArg("CFrame.fromEulerAngles", 1, rx, 0), numArg("CFrame.fromEulerAngles", 2, ry, 0), numArg("CFrame.fromEulerAngles", 3, rz, 0), o)
		end,
		fromAxisAngle = function(axis, angle)
			needV3("CFrame.fromAxisAngle", 1, axis)
			return axisAngle(axis[1], axis[2], axis[3], numArg("CFrame.fromAxisAngle", 2, angle))
		end,
		lookAt = function(at, target, up)
			needV3("CFrame.lookAt", 1, at)
			needV3("CFrame.lookAt", 2, target)
			if up ~= nil then
				needV3("CFrame.lookAt", 3, up)
			end
			return lookAt(at, target, up)
		end,
		lookAlong = function(at, dir, up)
			needV3("CFrame.lookAlong", 1, at)
			needV3("CFrame.lookAlong", 2, dir)
			if up ~= nil then
				needV3("CFrame.lookAlong", 3, up)
			end
			return lookAt(at, at + dir, up)
		end,
		fromMatrix = function(pos, vx, vy, vz)
			needV3("CFrame.fromMatrix", 1, pos)
			needV3("CFrame.fromMatrix", 2, vx)
			needV3("CFrame.fromMatrix", 3, vy)
			if vz == nil then
				vz = vx:Cross(vy).Unit
			else
				needV3("CFrame.fromMatrix", 4, vz)
			end
			return fromColumns(pos[1], pos[2], pos[3], vx[1], vx[2], vx[3], vy[1], vy[2], vy[3], vz[1], vz[2], vz[3])
		end,
		fromRotationBetweenVectors = function(a, b)
			needV3("CFrame.fromRotationBetweenVectors", 1, a)
			needV3("CFrame.fromRotationBetweenVectors", 2, b)
			local ua, ub = a.Unit, b.Unit
			local c = ua:Cross(ub)
			local d = ua:Dot(ub)
			if c.Magnitude < 1e-9 then
				if d > 0 then
					return IDENTITY
				end
				local perp = (abs(ua[1]) < 0.9) and v3(1, 0, 0):Cross(ua) or v3(0, 1, 0):Cross(ua)
				return axisAngle(perp[1], perp[2], perp[3], math.pi)
			end
			return axisAngle(c[1], c[2], c[3], math.atan2(c.Magnitude, d))
		end,
	})

	------------------------------------------------------------------------
	-- Color3
	------------------------------------------------------------------------
	local C3 = {}
	TYPE_OF[C3] = "Color3"
	local function c3(r, g, b)
		return setmetatable({ r, g, b }, C3)
	end
	local function isC3(v: any): boolean
		return type(v) == "table" and getmetatable(v) == C3
	end
	local C3M = {}
	C3.__index = function(self, k)
		if k == "R" or k == "r" then
			return self[1]
		elseif k == "G" or k == "g" then
			return self[2]
		elseif k == "B" or k == "b" then
			return self[3]
		end
		local f = C3M[k]
		if f then
			return f
		end
		error(fmt("%s is not a valid member of Color3", tostring(k)), 2)
	end
	C3.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (Color3 is read-only, make a new one)", tostring(k)), 2)
	end
	C3.__eq = function(a, b)
		return isC3(a) and isC3(b) and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end
	C3.__tostring = function(a)
		return nstr(a[1]) .. ", " .. nstr(a[2]) .. ", " .. nstr(a[3])
	end
	local function byte255(x: number): number
		return math.clamp(floor(x * 255 + 0.5), 0, 255)
	end
	C3M.Lerp = function(a, b, t)
		colonCheck(isC3(a), "Color3", "Lerp")
		if not isC3(b) then
			badArg("Lerp", 1, "Color3", b)
		end
		t = numArg("Lerp", 2, t)
		return c3(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
	end
	C3M.ToHex = function(a)
		colonCheck(isC3(a), "Color3", "ToHex")
		return fmt("%02X%02X%02X", byte255(a[1]), byte255(a[2]), byte255(a[3]))
	end
	C3M.ToHSV = function(a)
		colonCheck(isC3(a), "Color3", "ToHSV")
		local r, g, b = a[1], a[2], a[3]
		local mx, mn = math.max(r, g, b), math.min(r, g, b)
		local d = mx - mn
		local h = 0
		if d > 0 then
			if mx == r then
				h = ((g - b) / d) % 6
			elseif mx == g then
				h = (b - r) / d + 2
			else
				h = (r - g) / d + 4
			end
			h = h / 6
		end
		return h, (mx > 0) and d / mx or 0, mx
	end
	local function hsv(h, s, v)
		h = (h % 1) * 6
		local i = floor(h)
		local f = h - i
		local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
		if i == 0 then
			return c3(v, t, p)
		elseif i == 1 then
			return c3(q, v, p)
		elseif i == 2 then
			return c3(p, v, t)
		elseif i == 3 then
			return c3(p, q, v)
		elseif i == 4 then
			return c3(t, p, v)
		end
		return c3(v, p, q)
	end
	Color3 = library("Color3", {
		new = function(r, g, b)
			return c3(numArg("Color3.new", 1, r, 0), numArg("Color3.new", 2, g, 0), numArg("Color3.new", 3, b, 0))
		end,
		fromRGB = function(r, g, b)
			return c3(numArg("Color3.fromRGB", 1, r, 0) / 255, numArg("Color3.fromRGB", 2, g, 0) / 255, numArg("Color3.fromRGB", 3, b, 0) / 255)
		end,
		fromHSV = function(h, s, v)
			return hsv(numArg("Color3.fromHSV", 1, h), numArg("Color3.fromHSV", 2, s), numArg("Color3.fromHSV", 3, v))
		end,
		fromHex = function(hex)
			if type(hex) ~= "string" then
				badArg("Color3.fromHex", 1, "string", hex)
			end
			local h = hex:gsub("^#", "")
			if #h == 3 then
				h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2)
			end
			if #h ~= 6 or h:find("[^%x]") then
				error(fmt("Unable to convert characters to hex value: %q", hex), 2)
			end
			return c3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
		end,
		toHSV = function(c)
			return C3M.ToHSV(c)
		end,
	})

	------------------------------------------------------------------------
	-- Small value types: Vector2, UDim, UDim2, NumberRange, sequences, PhysicalProperties, Rect, Font, TweenInfo
	------------------------------------------------------------------------
	-- A frozen value object: fields readable, unknown fields error, nothing assignable
	local function valueType(typeName: string, methods: { [string]: any }?)
		local mt = {}
		TYPE_OF[mt] = typeName
		mt.__index = function(self, k)
			local f = methods and methods[k]
			if f then
				return f
			end
			local fields = rawget(self, "__f")
			local v = fields[k]
			if v ~= nil then
				return v
			end
			error(fmt("%s is not a valid member of %s", tostring(k), typeName), 2)
		end
		mt.__newindex = function(_, k)
			error(fmt("%s cannot be assigned to (%s is read-only)", tostring(k), typeName), 2)
		end
		mt.__eq = function(a, b)
			local fa, fb = rawget(a, "__f"), rawget(b, "__f")
			for k, v in pairs(fa) do
				if fb[k] ~= v then
					return false
				end
			end
			return true
		end
		mt.__tostring = function(self)
			return rawget(self, "__s") or typeName
		end
		return function(fields, text: string?)
			return setmetatable({ __f = fields, __s = text }, mt)
		end
	end

	local makeV2 = valueType("Vector2")
	local function v2(x, y)
		local m = sqrt(x * x + y * y)
		return makeV2({ X = x, Y = y, Magnitude = m }, nstr(x) .. ", " .. nstr(y))
	end
	Vector2 = library("Vector2", {
		new = function(x, y)
			return v2(numArg("Vector2.new", 1, x, 0), numArg("Vector2.new", 2, y, 0))
		end,
		zero = v2(0, 0),
		one = v2(1, 1),
		xAxis = v2(1, 0),
		yAxis = v2(0, 1),
	})

	local makeUDim = valueType("UDim")
	local function udim(s, o)
		return makeUDim({ Scale = s, Offset = o }, nstr(s) .. ", " .. nstr(o))
	end
	UDim = library("UDim", {
		new = function(s, o)
			return udim(numArg("UDim.new", 1, s, 0), numArg("UDim.new", 2, o, 0))
		end,
	})
	local makeUDim2 = valueType("UDim2")
	local function udim2(xs, xo, ys, yo)
		return makeUDim2({ X = udim(xs, xo), Y = udim(ys, yo), Width = udim(xs, xo), Height = udim(ys, yo) }, fmt("{%s, %s}, {%s, %s}", nstr(xs), nstr(xo), nstr(ys), nstr(yo)))
	end
	UDim2 = library("UDim2", {
		new = function(xs, xo, ys, yo)
			if typeof(xs) == "UDim" then
				return udim2(xs.Scale, xs.Offset, xo.Scale, xo.Offset)
			end
			return udim2(numArg("UDim2.new", 1, xs, 0), numArg("UDim2.new", 2, xo, 0), numArg("UDim2.new", 3, ys, 0), numArg("UDim2.new", 4, yo, 0))
		end,
		fromScale = function(x, y)
			return udim2(numArg("UDim2.fromScale", 1, x, 0), 0, numArg("UDim2.fromScale", 2, y, 0), 0)
		end,
		fromOffset = function(x, y)
			return udim2(0, numArg("UDim2.fromOffset", 1, x, 0), 0, numArg("UDim2.fromOffset", 2, y, 0))
		end,
	})

	local makeNR = valueType("NumberRange")
	NumberRange = library("NumberRange", {
		new = function(mn, mx)
			mn = numArg("NumberRange.new", 1, mn)
			mx = numArg("NumberRange.new", 2, mx, mn)
			if mx < mn then
				error("NumberRange: invalid range (max is smaller than min)", 2)
			end
			return makeNR({ Min = mn, Max = mx }, nstr(mn) .. " " .. nstr(mx))
		end,
	})

	local makeNSK = valueType("NumberSequenceKeypoint")
	NumberSequenceKeypoint = library("NumberSequenceKeypoint", {
		new = function(t, v, e)
			return makeNSK({ Time = numArg("NumberSequenceKeypoint.new", 1, t), Value = numArg("NumberSequenceKeypoint.new", 2, v), Envelope = numArg("NumberSequenceKeypoint.new", 3, e, 0) })
		end,
	})
	local makeCSK = valueType("ColorSequenceKeypoint")
	ColorSequenceKeypoint = library("ColorSequenceKeypoint", {
		new = function(t, c)
			if not isC3(c) then
				badArg("ColorSequenceKeypoint.new", 2, "Color3", c)
			end
			return makeCSK({ Time = numArg("ColorSequenceKeypoint.new", 1, t), Value = c })
		end,
	})
	local function checkKeypoints(name: string, kps, kpType: string)
		if type(kps) ~= "table" or #kps < 2 then
			error(name .. ": requires at least 2 keypoints", 3)
		end
		for i, kp in ipairs(kps) do
			if typeof(kp) ~= kpType then
				error(fmt("%s: keypoint %d is a %s, expected %s", name, i, typeof(kp), kpType), 3)
			end
			if i > 1 and kp.Time < kps[i - 1].Time then
				error(name .. ": all keypoints must be ordered by time", 3)
			end
		end
		if abs(kps[1].Time) > 1e-4 or abs(kps[#kps].Time - 1) > 1e-4 then
			error(name .. " time must start at 0 and end at 1", 3)
		end
	end
	local makeNS = valueType("NumberSequence")
	NumberSequence = library("NumberSequence", {
		new = function(a, b)
			local kps
			if type(a) == "number" then
				b = numArg("NumberSequence.new", 2, b, a)
				kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }
			else
				checkKeypoints("NumberSequence", a, "NumberSequenceKeypoint")
				kps = table.clone(a)
			end
			return makeNS({ Keypoints = kps })
		end,
	})
	local makeCS = valueType("ColorSequence")
	ColorSequence = library("ColorSequence", {
		new = function(a, b)
			local kps
			if isC3(a) then
				if b ~= nil and not isC3(b) then
					badArg("ColorSequence.new", 2, "Color3", b)
				end
				kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
			else
				checkKeypoints("ColorSequence", a, "ColorSequenceKeypoint")
				kps = table.clone(a)
			end
			return makeCS({ Keypoints = kps })
		end,
	})

	local makePP = valueType("PhysicalProperties")
	PhysicalProperties = library("PhysicalProperties", {
		new = function(d, f, e, fw, ew)
			if typeof(d) == "EnumItem" then
				return makePP({ Density = 0.7, Friction = 0.3, Elasticity = 0.5, FrictionWeight = 1, ElasticityWeight = 1 })
			end
			return makePP({
				Density = numArg("PhysicalProperties.new", 1, d),
				Friction = numArg("PhysicalProperties.new", 2, f),
				Elasticity = numArg("PhysicalProperties.new", 3, e),
				FrictionWeight = numArg("PhysicalProperties.new", 4, fw, 1),
				ElasticityWeight = numArg("PhysicalProperties.new", 5, ew, 1),
			})
		end,
	})

	local makeRect = valueType("Rect")
	Rect = library("Rect", {
		new = function(a, b, c, d)
			if typeof(a) == "Vector2" then
				return makeRect({ Min = a, Max = b, Width = b.X - a.X, Height = b.Y - a.Y })
			end
			a, b, c, d = numArg("Rect.new", 1, a, 0), numArg("Rect.new", 2, b, 0), numArg("Rect.new", 3, c, 0), numArg("Rect.new", 4, d, 0)
			return makeRect({ Min = v2(a, b), Max = v2(c, d), Width = c - a, Height = d - b })
		end,
	})

	local makeFont = valueType("Font")
	Font = library("Font", {
		new = function(family, weight, style)
			if type(family) ~= "string" then
				badArg("Font.new", 1, "string", family)
			end
			return makeFont({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal, Bold = false })
		end,
		fromEnum = function(e)
			if typeof(e) ~= "EnumItem" or tostring(e.EnumType) ~= "Font" then
				badArg("Font.fromEnum", 1, "Enum.Font", e)
			end
			return makeFont({ Family = "rbxasset://fonts/families/" .. e.Name .. ".json", Weight = Enum.FontWeight.Regular, Style = Enum.FontStyle.Normal, Bold = false })
		end,
		fromName = function(name, weight, style)
			if type(name) ~= "string" then
				badArg("Font.fromName", 1, "string", name)
			end
			return makeFont({ Family = "rbxasset://fonts/families/" .. name .. ".json", Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal, Bold = false })
		end,
	})

	local makeTI = valueType("TweenInfo")
	TweenInfo = library("TweenInfo", {
		new = function(t, ...)
			return makeTI({ Time = numArg("TweenInfo.new", 1, t, 1) })
		end,
	})

	------------------------------------------------------------------------
	-- BrickColor (small palette; Roblox silently turns unknown names into grey)
	------------------------------------------------------------------------
	local PALETTE = {
		{ "White", 242, 243, 243, 1 },
		{ "Institutional white", 248, 248, 248, 1001 },
		{ "Light stone grey", 229, 228, 223, 208 },
		{ "Medium stone grey", 163, 162, 165, 194 },
		{ "Dark stone grey", 99, 95, 98, 199 },
		{ "Black", 27, 42, 53, 26 },
		{ "Really black", 17, 17, 17, 1003 },
		{ "Bright red", 196, 40, 28, 21 },
		{ "Really red", 255, 0, 0, 1004 },
		{ "Bright orange", 218, 133, 65, 106 },
		{ "Neon orange", 213, 115, 61, 1005 },
		{ "Bright yellow", 245, 205, 48, 24 },
		{ "New Yeller", 255, 255, 0, 1009 },
		{ "Bright green", 75, 151, 75, 37 },
		{ "Lime green", 0, 255, 0, 1020 },
		{ "Dark green", 40, 127, 71, 28 },
		{ "Bright blue", 13, 105, 172, 23 },
		{ "Really blue", 0, 0, 255, 1010 },
		{ "Toothpaste", 0, 255, 255, 1019 },
		{ "Cyan", 4, 175, 236, 1013 },
		{ "Hot pink", 255, 0, 191, 1032 },
		{ "Pink", 255, 102, 204, 1016 },
		{ "Magenta", 170, 0, 170, 1015 },
		{ "Bright violet", 107, 50, 124, 104 },
		{ "Brown", 124, 92, 70, 192 },
		{ "Reddish brown", 105, 64, 40, 192 },
		{ "Nougat", 204, 142, 105, 18 },
		{ "Brick yellow", 215, 197, 154, 5 },
		{ "Pastel brown", 255, 204, 153, 1030 },
		{ "Cool yellow", 253, 234, 141, 226 },
	}
	local BC = {}
	TYPE_OF[BC] = "BrickColor"
	local function bcFrom(entry)
		local col = c3(entry[2] / 255, entry[3] / 255, entry[4] / 255)
		return setmetatable({ Name = entry[1], Number = entry[5], Color = col, r = col[1], g = col[2], b = col[3] }, BC)
	end
	BC.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (BrickColor is read-only)", tostring(k)), 2)
	end
	BC.__tostring = function(self)
		return rawget(self, "Name")
	end
	BC.__eq = function(a, b)
		return rawget(a, "Name") == rawget(b, "Name")
	end
	BC.__index = function(_, k)
		error(fmt("%s is not a valid member of BrickColor", tostring(k)), 2)
	end
	local function bcNearest(col)
		local best, bestD = PALETTE[4], huge
		for _, e in ipairs(PALETTE) do
			local d = (e[2] / 255 - col[1]) ^ 2 + (e[3] / 255 - col[2]) ^ 2 + (e[4] / 255 - col[3]) ^ 2
			if d < bestD then
				best, bestD = e, d
			end
		end
		return bcFrom(best)
	end
	local function bcNamed(name: string)
		for _, e in ipairs(PALETTE) do
			if e[1] == name then
				return bcFrom(e)
			end
		end
		note(fmt("BrickColor.new(%q): not in the harness palette (if it is not a real Roblox BrickColor name, Roblox silently uses Medium stone grey). Prefer Color3.", name))
		return bcFrom(PALETTE[4])
	end
	BrickColor = library("BrickColor", {
		new = function(a, b, c)
			if type(a) == "string" then
				return bcNamed(a)
			elseif isC3(a) then
				return bcNearest(a)
			elseif type(a) == "number" and b ~= nil then
				return bcNearest(c3(a / 255, numArg("BrickColor.new", 2, b) / 255, numArg("BrickColor.new", 3, c) / 255))
			elseif type(a) == "number" then
				for _, e in ipairs(PALETTE) do
					if e[5] == a then
						return bcFrom(e)
					end
				end
				return bcFrom(PALETTE[4])
			end
			badArg("BrickColor.new", 1, "string, number or Color3", a)
		end,
		palette = function(i)
			return bcFrom(PALETTE[(numArg("BrickColor.palette", 1, i) % #PALETTE) + 1])
		end,
		random = function()
			return bcFrom(PALETTE[math.random(1, #PALETTE)])
		end,
		White = function()
			return bcNamed("White")
		end,
		Gray = function()
			return bcNamed("Medium stone grey")
		end,
		DarkGray = function()
			return bcNamed("Dark stone grey")
		end,
		Black = function()
			return bcNamed("Black")
		end,
		Red = function()
			return bcNamed("Bright red")
		end,
		Yellow = function()
			return bcNamed("Bright yellow")
		end,
		Green = function()
			return bcNamed("Bright green")
		end,
		Blue = function()
			return bcNamed("Bright blue")
		end,
	})

	------------------------------------------------------------------------
	-- Random (deterministic xorshift; same seed -> same numbers)
	------------------------------------------------------------------------
	local RNG = {}
	TYPE_OF[RNG] = "Random"
	local RNGM = {}
	RNG.__index = function(_, k)
		local f = RNGM[k]
		if f then
			return f
		end
		error(fmt("%s is not a valid member of Random", tostring(k)), 2)
	end
	RNG.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (Random)", tostring(k)), 2)
	end
	local function isRng(v)
		return type(v) == "table" and getmetatable(v) == RNG
	end
	local function rngNext(self): number
		local x = rawget(self, "s")
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		rawset(self, "s", x)
		return x / 4294967296
	end
	local function newRng(seed: number)
		local s = floor(abs(seed) * 7919 + 0.5) % 4294967296
		s = bit32.bxor(s, 0x9E3779B9)
		if s == 0 then
			s = 0x1234567
		end
		local r = setmetatable({ s = s }, RNG)
		for _ = 1, 8 do
			rngNext(r) -- warm up
		end
		return r
	end
	RNGM.NextNumber = function(self, mn, mx)
		colonCheck(isRng(self), "Random", "NextNumber")
		local u = rngNext(self)
		if mn == nil and mx == nil then
			return u
		end
		mn, mx = numArg("NextNumber", 1, mn), numArg("NextNumber", 2, mx)
		return mn + (mx - mn) * u
	end
	RNGM.NextInteger = function(self, mn, mx)
		colonCheck(isRng(self), "Random", "NextInteger")
		mn, mx = numArg("NextInteger", 1, mn), numArg("NextInteger", 2, mx)
		mn, mx = floor(mn), floor(mx)
		if mx < mn then
			error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
		end
		return mn + floor(rngNext(self) * (mx - mn + 1))
	end
	RNGM.NextUnitVector = function(self)
		colonCheck(isRng(self), "Random", "NextUnitVector")
		local z = rngNext(self) * 2 - 1
		local a = rngNext(self) * 2 * math.pi
		local r = sqrt(1 - z * z)
		return v3(r * cos(a), r * sin(a), z)
	end
	RNGM.Shuffle = function(self, t)
		colonCheck(isRng(self), "Random", "Shuffle")
		if type(t) ~= "table" then
			badArg("Shuffle", 1, "table", t)
		end
		for i = #t, 2, -1 do
			local j = 1 + floor(rngNext(self) * i)
			t[i], t[j] = t[j], t[i]
		end
	end
	RNGM.Clone = function(self)
		colonCheck(isRng(self), "Random", "Clone")
		return setmetatable({ s = rawget(self, "s") }, RNG)
	end
	Random = library("Random", {
		new = function(seed)
			return newRng(numArg("Random.new", 1, seed, 12345))
		end,
	})

	------------------------------------------------------------------------
	-- Enum (built from the API data; unknown names error)
	------------------------------------------------------------------------
	local ENUM, ITEM = {}, {}
	TYPE_OF[ENUM] = "Enum"
	TYPE_OF[ITEM] = "EnumItem"
	local enumCache = {}
	local knownEnumNames = {}
	for _, n in ipairs(string.split(API.ENUM_NAMES, " ")) do
		knownEnumNames[n] = true
	end
	ITEM.__index = function(self, k)
		local f = rawget(self, "__f")
		if k == "IsA" then
			return function(_, name)
				return tostring(f.EnumType) == name
			end
		end
		local v = f[k]
		if v ~= nil then
			return v
		end
		error(fmt("%s is not a valid member of %s", tostring(k), tostring(self)), 2)
	end
	ITEM.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (EnumItem is read-only)", tostring(k)), 2)
	end
	ITEM.__tostring = function(self)
		local f = rawget(self, "__f")
		return "Enum." .. tostring(f.EnumType) .. "." .. f.Name
	end
	ENUM.__tostring = function(self)
		return rawget(self, "__name")
	end
	ENUM.__newindex = function(_, k)
		error(fmt("%s cannot be assigned to (Enum is read-only)", tostring(k)), 2)
	end
	ENUM.__index = function(self, k)
		local items = rawget(self, "__items")
		local it = items[k]
		if it then
			return it
		end
		local list = rawget(self, "__list")
		if k == "GetEnumItems" then
			return function()
				return table.clone(list)
			end
		elseif k == "FromName" then
			return function(_, n)
				return items[n]
			end
		elseif k == "FromValue" then
			return function(_, v)
				return list[v + 1]
			end
		end
		error(fmt("%s is not a valid member of \"Enum.%s\"", tostring(k), rawget(self, "__name")), 2)
	end
	local function getEnum(name: string)
		local e = enumCache[name]
		if e then
			return e
		end
		local itemStr = API.ENUMS[name]
		if not itemStr then
			return nil
		end
		e = setmetatable({ __name = name, __items = {}, __list = {} }, ENUM)
		for i, itemName in ipairs(string.split(itemStr, " ")) do
			-- (Value numbers here are just the position in the list, not Roblox's real numbers)
			local item = setmetatable({ __f = { Name = itemName, Value = i - 1, EnumType = e } }, ITEM)
			rawget(e, "__items")[itemName] = item
			table.insert(rawget(e, "__list"), item)
		end
		enumCache[name] = e
		return e
	end
	Enum = setmetatable({}, {
		__index = function(_, k)
			local e = getEnum(k)
			if e then
				return e
			end
			if k == "GetEnums" then
				return function()
					local out = {}
					for n in pairs(API.ENUMS) do
						table.insert(out, getEnum(n))
					end
					return out
				end
			end
			if knownEnumNames[k] then
				error(fmt("Enum.%s exists in Roblox but the test harness does not know its items (ask the harness owner to add it to API.ENUMS)", tostring(k)), 2)
			end
			error(fmt("%s is not a valid member of \"Enum\"", tostring(k)), 2)
		end,
		__newindex = function(_, k)
			error("Enum cannot be changed", 2)
		end,
	})
	local function isEnumItemOf(v, enumName: string): boolean
		return typeof(v) == "EnumItem" and tostring(v.EnumType) == enumName
	end

	------------------------------------------------------------------------
	-- Instances
	------------------------------------------------------------------------
	local PRIV = {} -- private key holding each instance's data
	local INST = {}
	TYPE_OF[INST] = "Instance"
	local CLASSES = {} -- class name -> class record
	local createdLog = {} -- every instance made by Instance.new / Clone during the current build
	local seq = 0
	local NIL = {} -- "default is nil" marker
	local ALLOWED_ASSET = "136713011360148"

	local function idata(v: any)
		if type(v) == "table" and getmetatable(v) == INST then
			return v[PRIV]
		end
		return nil
	end
	local function isInst(v: any): boolean
		return idata(v) ~= nil
	end
	local function needSelf(v: any, fname: string)
		local d = idata(v)
		if not d then
			error(fmt("Expected ':' not '.' calling member function %s", fname), 3)
		end
		return d
	end
	local function fullName(inst): string
		local names = {}
		local cur = inst
		while cur do
			local d = cur[PRIV]
			if d.cls.Name == "DataModel" then
				break
			end
			table.insert(names, 1, d.props.Name)
			cur = d.parent
		end
		return table.concat(names, ".")
	end

	-- property type spec from the API text ("Vector3", "Enum.Material", "BasePart?", ...)
	local VALUE_KINDS = {
		Vector3 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, Vector2 = true,
		NumberRange = true, NumberSequence = true, ColorSequence = true, PhysicalProperties = true,
		BrickColor = true, Font = true, Rect = true,
	}
	local function parseType(t: string)
		local opt = false
		if string.sub(t, -1) == "?" then
			opt = true
			t = string.sub(t, 1, -2)
		end
		if t == "number" or t == "boolean" then
			return { k = t, opt = opt, name = t }
		elseif t == "string" or t == "ContentId" or t == "ProtectedString" then
			return { k = "string", opt = opt, name = "string" }
		elseif string.sub(t, 1, 5) == "Enum." then
			return { k = "enum", opt = opt, name = string.sub(t, 6) }
		elseif VALUE_KINDS[t] then
			return { k = "value", opt = opt, name = t }
		elseif t == "any" or t == "Content" or t == "Faces" or t == "Axes" then
			return { k = "any", opt = true, name = t }
		end
		return { k = "inst", opt = true, name = t } -- instance refs may always be nil
	end

	-- value -> (converted value) or (nil, error text)
	local function coerce(spec, v: any)
		if v == nil then
			if spec.opt or spec.k == "any" then
				return nil
			end
			return nil, fmt("%s expected, got nil", spec.name)
		end
		local k = spec.k
		if k == "number" then
			if type(v) == "number" then
				return v
			end
		elseif k == "boolean" then
			if type(v) == "boolean" then
				return v
			end
		elseif k == "string" then
			if type(v) == "string" then
				return v
			elseif type(v) == "number" then
				return tostring(v)
			end
		elseif k == "value" then
			if typeof(v) == spec.name then
				return v
			end
		elseif k == "enum" then
			local e = getEnum(spec.name)
			if not e then
				return v -- enum we do not know: accept
			end
			if typeof(v) == "EnumItem" then
				if tostring(v.EnumType) == spec.name then
					return v
				end
				return nil, fmt("Enum.%s expected, got %s", spec.name, tostring(v))
			elseif type(v) == "string" then
				local it = rawget(e, "__items")[v]
				if it then
					return it
				end
				return nil, fmt("%q is not a valid Enum.%s", v, spec.name)
			end
		elseif k == "inst" then
			local d = idata(v)
			if d and (d.cls.IsA[spec.name] or not CLASSES[spec.name]) then
				return v
			end
		else
			return v
		end
		return nil, fmt("%s expected, got %s", spec.k == "enum" and ("Enum." .. spec.name) or spec.name, typeof(v))
	end

	local DEFAULTS = {
		["BasePart.Size"] = v3(4, 1, 2),
		["TrussPart.Size"] = v3(2, 2, 2),
		["CornerWedgePart.Size"] = v3(2, 2, 2),
		["BasePart.Color"] = c3(163 / 255, 162 / 255, 165 / 255),
		["BasePart.CFrame"] = IDENTITY,
		["BasePart.PivotOffset"] = IDENTITY,
		["BasePart.CustomPhysicalProperties"] = NIL,
		["BasePart.CanCollide"] = true,
		["BasePart.CanTouch"] = true,
		["BasePart.CanQuery"] = true,
		["BasePart.CastShadow"] = true,
		["BasePart.AudioCanCollide"] = true,
		["BasePart.CollisionGroup"] = "Default",
		["Model.WorldPivot"] = IDENTITY,
		["Light.Brightness"] = 1,
		["Light.Color"] = c3(1, 1, 1),
		["PointLight.Range"] = 8,
		["SpotLight.Range"] = 16,
		["SpotLight.Angle"] = 90,
		["SurfaceLight.Range"] = 16,
		["SurfaceLight.Angle"] = 90,
		["ParticleEmitter.Rate"] = 20,
		["ParticleEmitter.Speed"] = makeNR({ Min = 5, Max = 5 }),
		["ParticleEmitter.Lifetime"] = makeNR({ Min = 5, Max = 10 }),
		["ParticleEmitter.Texture"] = "rbxasset://textures/particles/sparkles_main.dds",
		["ParticleEmitter.Brightness"] = 1,
		["ParticleEmitter.LightInfluence"] = 1,
		["ParticleEmitter.TimeScale"] = 1,
		["Fire.Size"] = 5,
		["Fire.Heat"] = 9,
		["Fire.Color"] = c3(236 / 255, 139 / 255, 70 / 255),
		["Fire.SecondaryColor"] = c3(139 / 255, 80 / 255, 55 / 255),
		["Fire.TimeScale"] = 1,
		["Smoke.Size"] = 1,
		["Smoke.Opacity"] = 0.5,
		["Smoke.RiseVelocity"] = 1,
		["Smoke.Color"] = c3(1, 1, 1),
		["Smoke.TimeScale"] = 1,
		["Sparkles.SparkleColor"] = c3(144 / 255, 25 / 255, 1),
		["Sparkles.TimeScale"] = 1,
		["TextLabel.Text"] = "Label",
		["TextLabel.TextSize"] = 14,
		["TextLabel.TextColor3"] = c3(27 / 255, 42 / 255, 53 / 255),
		["TextLabel.TextStrokeTransparency"] = 1,
		["TextLabel.LineHeight"] = 1,
		["GuiObject.BackgroundColor3"] = c3(1, 1, 1),
		["GuiObject.Size"] = udim2(0, 100, 0, 100),
		["UIStroke.Thickness"] = 1,
		["UIStroke.Color"] = c3(0, 0, 0),
		["UICorner.CornerRadius"] = udim(0, 8),
		["SurfaceGui.PixelsPerStud"] = 50,
		["SurfaceGui.CanvasSize"] = v2(800, 600),
		["SurfaceGui.LightInfluence"] = 1,
		["BillboardGui.LightInfluence"] = 1,
		["BillboardGui.MaxDistance"] = huge,
		["SurfaceGui.MaxDistance"] = 1000,
		["Highlight.FillColor"] = c3(1, 0, 0),
		["Highlight.FillTransparency"] = 0.5,
		["Highlight.OutlineColor"] = c3(1, 1, 1),
		["Beam.Width0"] = 1,
		["Beam.Width1"] = 1,
		["Beam.Segments"] = 10,
		["Trail.Lifetime"] = 2,
		["DataModelMesh.Scale"] = v3(1, 1, 1),
		["Decal.Color3"] = c3(1, 1, 1),
		["Texture.StudsPerTileU"] = 2,
		["Texture.StudsPerTileV"] = 2,
		["Enabled"] = true,
		["Visible"] = true,
		["Archivable"] = true,
		["Material"] = "Plastic",
		["Shape"] = "Block",
		["TopSurface"] = "Smooth",
		["BottomSurface"] = "Smooth",
		["FrontSurface"] = "Smooth",
		["BackSurface"] = "Smooth",
		["LeftSurface"] = "Smooth",
		["RightSurface"] = "Smooth",
		["Face"] = "Front",
		["Style"] = "AlternatingSupports",
	}
	local READ_ONLY = {
		ClassName = true, AssemblyMass = true, AssemblyCenterOfMass = true, AssemblyRootPart = true,
		CenterOfMass = true, CurrentPhysicalProperties = true, ExtentsCFrame = true, ExtentsSize = true,
		Mass = true, ReceiveAge = true, ResizeIncrement = true, ResizeableFaces = true,
		AbsolutePosition = true, AbsoluteSize = true, AbsoluteRotation = true, TextBounds = true,
		TextFits = true, ContentText = true, LocalizedText = true, IsLoaded = true, CurrentDistance = true,
		AbsoluteContentSize = true, OpenTypeFeaturesError = true, Sandboxed = true, Capabilities = true,
	}

	local function defaultFor(rec, prop: string, spec)
		local cached = rec.DefaultCache[prop]
		if cached ~= nil then
			if cached == NIL then
				return nil
			end
			return cached
		end
		local v
		local r = rec
		while r and v == nil do
			v = DEFAULTS[r.Name .. "." .. prop]
			r = r.Super
		end
		if v == nil then
			v = DEFAULTS[prop]
		end
		if spec.k == "enum" then
			local e = getEnum(spec.name)
			if e then
				if type(v) == "string" then
					v = rawget(e, "__items")[v]
				end
				v = v or rawget(e, "__list")[1]
			end
		elseif v == nil then
			local k, n = spec.k, spec.name
			if spec.opt or k == "inst" or k == "any" then
				v = NIL
			elseif k == "number" then
				v = 0
			elseif k == "boolean" then
				v = false
			elseif k == "string" then
				v = ""
			elseif n == "Vector3" then
				v = v3(0, 0, 0)
			elseif n == "CFrame" then
				v = IDENTITY
			elseif n == "Color3" then
				v = c3(0, 0, 0)
			elseif n == "Vector2" then
				v = v2(0, 0)
			elseif n == "UDim" then
				v = udim(0, 0)
			elseif n == "UDim2" then
				v = udim2(0, 0, 0, 0)
			elseif n == "NumberRange" then
				v = makeNR({ Min = 0, Max = 0 })
			elseif n == "NumberSequence" then
				v = NumberSequence.new(0)
			elseif n == "ColorSequence" then
				v = ColorSequence.new(c3(1, 1, 1))
			elseif n == "PhysicalProperties" then
				v = NIL
			elseif n == "BrickColor" then
				v = bcFrom(PALETTE[4])
			elseif n == "Font" then
				v = Font.fromName("SourceSansPro")
			else
				v = NIL
			end
		end
		rec.DefaultCache[prop] = v
		if v == NIL then
			return nil
		end
		return v
	end

	local function newInstanceData(rec)
		seq += 1
		return {
			cls = rec,
			props = { Name = rec.Name },
			children = {},
			parent = nil,
			attrs = {},
			attrOrder = {},
			tags = {},
			tagOrder = {},
			destroyed = false,
			seq = seq,
			isService = false,
			pivotSet = false,
		}
	end
	local function wrap(d)
		return setmetatable({ [PRIV] = d }, INST)
	end

	local function isAncestorOf(anc, inst): boolean
		local cur = inst[PRIV].parent
		while cur do
			if cur == anc then
				return true
			end
			cur = cur[PRIV].parent
		end
		return false
	end

	local function detach(inst)
		local d = inst[PRIV]
		local p = d.parent
		if p then
			local kids = p[PRIV].children
			local i = table.find(kids, inst)
			if i then
				table.remove(kids, i)
			end
			d.parent = nil
		end
	end

	-- returns error text or nil
	local function setParent(inst, newParent): string?
		local d = inst[PRIV]
		if d.destroyed then
			return fmt("The Parent property of %s is locked, current parent: NULL, new parent %s", d.props.Name, newParent and newParent[PRIV].props.Name or "NULL")
		end
		if d.isService then
			return fmt("cannot change the Parent of service %s", d.props.Name)
		end
		if newParent ~= nil then
			local pd = idata(newParent)
			if not pd then
				return "Unable to assign property Parent. Instance expected, got " .. typeof(newParent)
			end
			if newParent == inst or isAncestorOf(inst, newParent) then
				return fmt("Attempt to set parent of %s to %s would result in circular reference", fullName(inst), fullName(newParent))
			end
			if pd.destroyed then
				return fmt("cannot parent %s to %s: it has been Destroyed", d.props.Name, pd.props.Name)
			end
		end
		if d.parent == newParent then
			return nil
		end
		detach(inst)
		if newParent ~= nil then
			d.parent = newParent
			table.insert(newParent[PRIV].children, inst)
		end
		return nil
	end

	local function descendants(inst, out)
		for _, c in ipairs(inst[PRIV].children) do
			table.insert(out, c)
			descendants(c, out)
		end
		return out
	end

	local function destroy(inst)
		local d = inst[PRIV]
		if d.isService then
			error(fmt("cannot Destroy service %s", d.props.Name), 3)
		end
		for _, c in ipairs(table.clone(d.children)) do
			destroy(c)
		end
		detach(inst)
		d.destroyed = true
	end

	local function signal(ownerName: string, eventName: string)
		local s = {}
		local function forbid(_, ...)
			error(fmt("%s.%s - a section's Build must not connect events or wait (the tower is built instantly on the server). Use the ctx helpers (ctx:Kill, ctx:Bounce, ctx:Spin, ...) instead.", ownerName, eventName), 2)
		end
		s.Connect, s.Once, s.Wait, s.ConnectParallel = forbid, forbid, forbid, forbid
		return library("RBXScriptSignal", s)
	end

	local ATTR_TYPES = {
		boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true,
		Color3 = true, Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true,
		ColorSequence = true, NumberRange = true, Rect = true, Font = true, EnumItem = true,
	}
	local function checkAttrName(name: any)
		if type(name) ~= "string" then
			error(fmt("Attribute name must be a string, got %s", typeof(name)), 3)
		end
		if #name == 0 or #name > 100 or name:find("[^%w_]") or name:sub(1, 3) == "RBX" then
			error(fmt("Attribute name %q is invalid (letters, digits and _ only, max 100, not starting with RBX)", name), 3)
		end
	end

	local function boundingBox(parts, frame)
		-- axis-aligned box in "frame" space around every part's 8 corners
		local inv = cfInv(frame)
		local mnx, mny, mnz, mxx, mxy, mxz = huge, huge, huge, -huge, -huge, -huge
		for _, p in ipairs(parts) do
			local pd = p[PRIV]
			local cf = cfMul(inv, pd.props.CFrame or IDENTITY)
			local s = pd.props.Size or DEFAULTS["BasePart.Size"]
			for _, sx in ipairs({ -0.5, 0.5 }) do
				for _, sy in ipairs({ -0.5, 0.5 }) do
					for _, sz in ipairs({ -0.5, 0.5 }) do
						local x, y, z = cfPoint(cf, s[1] * sx, s[2] * sy, s[3] * sz)
						mnx, mny, mnz = math.min(mnx, x), math.min(mny, y), math.min(mnz, z)
						mxx, mxy, mxz = math.max(mxx, x), math.max(mxy, y), math.max(mxz, z)
					end
				end
			end
		end
		if mnx == huge then
			return frame, v3(0, 0, 0)
		end
		local cx, cy, cz = (mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2
		return cfMul(frame, cfr(cx, cy, cz, 1, 0, 0, 0, 1, 0, 0, 0, 1)), v3(mxx - mnx, mxy - mny, mxz - mnz)
	end
	local function partsUnder(inst)
		local out = {}
		for _, d in ipairs(descendants(inst, {})) do
			if d[PRIV].cls.IsA.BasePart then
				table.insert(out, d)
			end
		end
		return out
	end
	local function modelPivot(model)
		local d = model[PRIV]
		local pp = d.props.PrimaryPart
		if pp and isAncestorOf(model, pp) then
			local pd = pp[PRIV]
			return cfMul(pd.props.CFrame or IDENTITY, pd.props.PivotOffset or IDENTITY)
		end
		if d.pivotSet then
			return d.props.WorldPivot
		end
		local parts = partsUnder(model)
		if #parts == 0 then
			return IDENTITY
		end
		note(fmt("Model %q: GetPivot()/PivotTo() used before its WorldPivot was set, so Roblox uses the centre of its bounding box here (ctx:Group pivots are only applied when Build finishes).", d.props.Name))
		local box = boundingBox(parts, IDENTITY)
		return box
	end
	local function movePartsBy(model, delta)
		for _, p in ipairs(partsUnder(model)) do
			local pd = p[PRIV]
			pd.props.CFrame = cfMul(delta, pd.props.CFrame or IDENTITY)
		end
	end

	-- Method implementations, per class (inherited by subclasses)
	local IMPL = {}
	IMPL.Instance = {
		IsA = function(self, name)
			local d = needSelf(self, "IsA")
			return d.cls.IsA[name] == true
		end,
		FindFirstChild = function(self, name, recursive)
			local d = needSelf(self, "FindFirstChild")
			if type(name) ~= "string" then
				badArg("FindFirstChild", 1, "string", name)
			end
			local list = recursive and descendants(self, {}) or d.children
			for _, c in ipairs(list) do
				if c[PRIV].props.Name == name then
					return c
				end
			end
			return nil
		end,
		FindFirstChildOfClass = function(self, className)
			local d = needSelf(self, "FindFirstChildOfClass")
			for _, c in ipairs(d.children) do
				if c[PRIV].cls.Name == className then
					return c
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(self, className, recursive)
			local d = needSelf(self, "FindFirstChildWhichIsA")
			local list = recursive and descendants(self, {}) or d.children
			for _, c in ipairs(list) do
				if c[PRIV].cls.IsA[className] then
					return c
				end
			end
			return nil
		end,
		FindFirstAncestor = function(self, name)
			local cur = needSelf(self, "FindFirstAncestor").parent
			while cur do
				if cur[PRIV].props.Name == name then
					return cur
				end
				cur = cur[PRIV].parent
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(self, className)
			local cur = needSelf(self, "FindFirstAncestorOfClass").parent
			while cur do
				if cur[PRIV].cls.Name == className then
					return cur
				end
				cur = cur[PRIV].parent
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(self, className)
			local cur = needSelf(self, "FindFirstAncestorWhichIsA").parent
			while cur do
				if cur[PRIV].cls.IsA[className] then
					return cur
				end
				cur = cur[PRIV].parent
			end
			return nil
		end,
		FindFirstDescendant = function(self, name)
			needSelf(self, "FindFirstDescendant")
			for _, c in ipairs(descendants(self, {})) do
				if c[PRIV].props.Name == name then
					return c
				end
			end
			return nil
		end,
		GetChildren = function(self)
			return table.clone(needSelf(self, "GetChildren").children)
		end,
		GetDescendants = function(self)
			needSelf(self, "GetDescendants")
			return descendants(self, {})
		end,
		IsDescendantOf = function(self, anc)
			needSelf(self, "IsDescendantOf")
			if anc == nil then
				return self[PRIV].parent == nil
			end
			if not isInst(anc) then
				badArg("IsDescendantOf", 1, "Instance", anc)
			end
			return isAncestorOf(anc, self)
		end,
		IsAncestorOf = function(self, desc)
			needSelf(self, "IsAncestorOf")
			if not isInst(desc) then
				badArg("IsAncestorOf", 1, "Instance", desc)
			end
			return isAncestorOf(self, desc)
		end,
		Destroy = function(self)
			needSelf(self, "Destroy")
			destroy(self)
		end,
		Remove = function(self)
			needSelf(self, "Remove")
			detach(self)
		end,
		ClearAllChildren = function(self)
			local d = needSelf(self, "ClearAllChildren")
			for _, c in ipairs(table.clone(d.children)) do
				destroy(c)
			end
		end,
		GetFullName = function(self)
			needSelf(self, "GetFullName")
			return fullName(self)
		end,
		Clone = function(self)
			needSelf(self, "Clone")
			local function copy(src)
				local sd = src[PRIV]
				if sd.props.Archivable == false then
					return nil
				end
				local nd = newInstanceData(sd.cls)
				for k, v in pairs(sd.props) do
					nd.props[k] = v
				end
				nd.props.Parent = nil
				for k, v in pairs(sd.attrs) do
					nd.attrs[k] = v
				end
				nd.attrOrder = table.clone(sd.attrOrder)
				for k, v in pairs(sd.tags) do
					nd.tags[k] = v
				end
				nd.tagOrder = table.clone(sd.tagOrder)
				nd.pivotSet = sd.pivotSet
				local ni = wrap(nd)
				table.insert(createdLog, ni)
				for _, c in ipairs(sd.children) do
					local cc = copy(c)
					if cc then
						cc[PRIV].parent = ni
						table.insert(nd.children, cc)
					end
				end
				return ni
			end
			return copy(self)
		end,
		SetAttribute = function(self, name, value)
			local d = needSelf(self, "SetAttribute")
			checkAttrName(name)
			if value ~= nil and not ATTR_TYPES[typeof(value)] then
				error(fmt("SetAttribute(%q): a %s cannot be stored as an attribute (allowed: nil, boolean, number, string, Vector3, CFrame, Color3, UDim2, Vector2, NumberRange, ...)", name, typeof(value)), 2)
			end
			if d.attrs[name] == nil and value ~= nil then
				table.insert(d.attrOrder, name)
			elseif value == nil then
				local i = table.find(d.attrOrder, name)
				if i then
					table.remove(d.attrOrder, i)
				end
			end
			d.attrs[name] = value
		end,
		GetAttribute = function(self, name)
			local d = needSelf(self, "GetAttribute")
			checkAttrName(name)
			return d.attrs[name]
		end,
		GetAttributes = function(self)
			local d = needSelf(self, "GetAttributes")
			local out = {}
			for k, v in pairs(d.attrs) do
				out[k] = v
			end
			return out
		end,
		AddTag = function(self, tag)
			local d = needSelf(self, "AddTag")
			if type(tag) ~= "string" then
				badArg("AddTag", 1, "string", tag)
			end
			if not d.tags[tag] then
				d.tags[tag] = true
				table.insert(d.tagOrder, tag)
			end
		end,
		RemoveTag = function(self, tag)
			local d = needSelf(self, "RemoveTag")
			if d.tags[tag] then
				d.tags[tag] = nil
				table.remove(d.tagOrder, table.find(d.tagOrder, tag))
			end
		end,
		HasTag = function(self, tag)
			return needSelf(self, "HasTag").tags[tag] == true
		end,
		GetTags = function(self)
			return table.clone(needSelf(self, "GetTags").tagOrder)
		end,
		WaitForChild = function(self, name, timeout)
			local found = IMPL.Instance.FindFirstChild(self, name)
			if found then
				return found
			end
			error(fmt("WaitForChild(%q) would wait forever: %s has no child with that name (Build must not wait)", tostring(name), fullName(self)), 2)
		end,
		GetPropertyChangedSignal = function(self, prop)
			return signal(needSelf(self, "GetPropertyChangedSignal").props.Name, "GetPropertyChangedSignal(" .. tostring(prop) .. ")")
		end,
		GetAttributeChangedSignal = function(self, attr)
			return signal(needSelf(self, "GetAttributeChangedSignal").props.Name, "GetAttributeChangedSignal(" .. tostring(attr) .. ")")
		end,
	}
	IMPL.BasePart = {
		GetPivot = function(self)
			local d = needSelf(self, "GetPivot")
			return cfMul(d.props.CFrame or IDENTITY, d.props.PivotOffset or IDENTITY)
		end,
		PivotTo = function(self, cf)
			local d = needSelf(self, "PivotTo")
			needCF("PivotTo", 1, cf)
			d.props.CFrame = cfMul(cf, cfInv(d.props.PivotOffset or IDENTITY))
		end,
		GetMass = function(self)
			local d = needSelf(self, "GetMass")
			local s = d.props.Size or DEFAULTS["BasePart.Size"]
			return s[1] * s[2] * s[3] * 0.7
		end,
	}
	IMPL.Model = {
		GetPivot = function(self)
			needSelf(self, "GetPivot")
			return modelPivot(self)
		end,
		PivotTo = function(self, cf)
			local d = needSelf(self, "PivotTo")
			needCF("PivotTo", 1, cf)
			local cur = modelPivot(self)
			movePartsBy(self, cfMul(cf, cfInv(cur)))
			if not (d.props.PrimaryPart and isAncestorOf(self, d.props.PrimaryPart)) then
				d.props.WorldPivot = cf
				d.pivotSet = true
			end
		end,
		TranslateBy = function(self, delta)
			local d = needSelf(self, "TranslateBy")
			needV3("TranslateBy", 1, delta)
			local cur = modelPivot(self)
			IMPL.Model.PivotTo(self, cur + delta)
			return d and nil
		end,
		GetBoundingBox = function(self)
			needSelf(self, "GetBoundingBox")
			return boundingBox(partsUnder(self), rotationOf(modelPivot(self)) + v3(0, 0, 0))
		end,
		GetExtentsSize = function(self)
			needSelf(self, "GetExtentsSize")
			local _, size = boundingBox(partsUnder(self), rotationOf(modelPivot(self)))
			return size
		end,
		GetScale = function(self)
			needSelf(self, "GetScale")
			return 1
		end,
		SetPrimaryPartCFrame = function(self, cf)
			local d = needSelf(self, "SetPrimaryPartCFrame")
			needCF("SetPrimaryPartCFrame", 1, cf)
			local pp = d.props.PrimaryPart
			if not pp then
				error("Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.", 2)
			end
			movePartsBy(self, cfMul(cf, cfInv(pp[PRIV].props.CFrame or IDENTITY)))
		end,
		GetPrimaryPartCFrame = function(self)
			local d = needSelf(self, "GetPrimaryPartCFrame")
			local pp = d.props.PrimaryPart
			if not pp then
				error("Model:GetPrimaryPartCFrame() failed because no PrimaryPart has been set", 2)
			end
			return pp[PRIV].props.CFrame or IDENTITY
		end,
	}
	IMPL.ParticleEmitter = {
		Emit = function(self, n)
			needSelf(self, "Emit")
		end,
		Clear = function(self)
			needSelf(self, "Clear")
		end,
	}
	local function inDataModel(inst)
		local cur = inst
		while cur do
			if cur == game then
				return true
			end
			cur = cur[PRIV].parent
		end
		return false
	end
	local function needInstArg(fname: string, i: number, v: any)
		if not isInst(v) then
			badArg(fname, i, "Instance", v)
		end
		return v
	end
	IMPL.CollectionService = {
		AddTag = function(self, inst, tag)
			needSelf(self, "AddTag")
			needInstArg("AddTag", 1, inst)
			IMPL.Instance.AddTag(inst, tag)
		end,
		RemoveTag = function(self, inst, tag)
			needSelf(self, "RemoveTag")
			needInstArg("RemoveTag", 1, inst)
			IMPL.Instance.RemoveTag(inst, tag)
		end,
		HasTag = function(self, inst, tag)
			needSelf(self, "HasTag")
			needInstArg("HasTag", 1, inst)
			return IMPL.Instance.HasTag(inst, tag)
		end,
		GetTags = function(self, inst)
			needSelf(self, "GetTags")
			needInstArg("GetTags", 1, inst)
			return IMPL.Instance.GetTags(inst)
		end,
		GetTagged = function(self, tag)
			needSelf(self, "GetTagged")
			local out = {}
			for _, d in ipairs(descendants(game, {})) do
				if d[PRIV].tags[tag] then
					table.insert(out, d)
				end
			end
			return out
		end,
		GetAllTags = function(self)
			needSelf(self, "GetAllTags")
			local seen, out = {}, {}
			for _, d in ipairs(descendants(game, {})) do
				for _, t in ipairs(d[PRIV].tagOrder) do
					if not seen[t] then
						seen[t] = true
						table.insert(out, t)
					end
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(self, tag)
			needSelf(self, "GetInstanceAddedSignal")
			return signal("CollectionService", "GetInstanceAddedSignal(" .. tostring(tag) .. ")")
		end,
		GetInstanceRemovedSignal = function(self, tag)
			needSelf(self, "GetInstanceRemovedSignal")
			return signal("CollectionService", "GetInstanceRemovedSignal(" .. tostring(tag) .. ")")
		end,
	}
	IMPL.Workspace = {
		GetServerTimeNow = function(self)
			needSelf(self, "GetServerTimeNow")
			return 0
		end,
	}
	IMPL.RunService = {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return true
		end,
	}

	-- Special property getters / setters (per class, inherited)
	local SPECIAL = {}
	local function quantize(c)
		return c3(byte255(c[1]) / 255, byte255(c[2]) / 255, byte255(c[3]) / 255)
	end
	local function clampSize(s)
		return v3(math.clamp(s[1], 0.001, 2048), math.clamp(s[2], 0.001, 2048), math.clamp(s[3], 0.001, 2048))
	end
	local function getCF(d)
		return d.props.CFrame or IDENTITY
	end
	SPECIAL.Instance = {
		Name = {
			set = function(inst, d, v)
				d.props.Name = v
			end,
		},
		Parent = {
			get = function(inst, d)
				return d.parent
			end,
			set = function(inst, d, v)
				return setParent(inst, v)
			end,
		},
		ClassName = {
			get = function(inst, d)
				return d.cls.Name
			end,
		},
	}
	SPECIAL.BasePart = {
		Position = {
			get = function(inst, d)
				return getCF(d).Position
			end,
			set = function(inst, d, v)
				local c = getCF(d)
				d.props.CFrame = cfr(v[1], v[2], v[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
			end,
		},
		Orientation = {
			get = function(inst, d)
				local rx, ry, rz = CFM.ToOrientation(getCF(d))
				return v3(math.deg(rx), math.deg(ry), math.deg(rz))
			end,
			set = function(inst, d, v)
				local c = getCF(d)
				local r = eulerOrder(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]), "YXZ")
				d.props.CFrame = cfr(c[1], c[2], c[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12])
			end,
		},
		Rotation = {
			get = function(inst, d)
				local rx, ry, rz = CFM.ToEulerAnglesXYZ(getCF(d))
				return v3(math.deg(rx), math.deg(ry), math.deg(rz))
			end,
			set = function(inst, d, v)
				local c = getCF(d)
				local r = eulerOrder(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]), "XYZ")
				d.props.CFrame = cfr(c[1], c[2], c[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12])
			end,
		},
		Size = {
			set = function(inst, d, v)
				local s = clampSize(v)
				local shape = d.props.Shape
				if d.cls.Name == "Part" and shape and shape.Name == "Ball" then
					if not (s[1] == s[2] and s[2] == s[3]) then
						note(fmt("Ball part %q given a non-uniform Size %s; Roblox forces balls to be round (the harness uses the smallest side)", d.props.Name, tostring(v)))
					end
					local m = math.min(s[1], s[2], s[3])
					s = v3(m, m, m)
				end
				if d.cls.Name == "TrussPart" then
					for i = 1, 3 do
						local r = s[i] / 2
						if abs(r - floor(r + 0.5)) > 1e-6 or s[i] < 2 then
							note(fmt("TrussPart %q Size %s is not made of whole multiples of 2 (Roblox snaps truss sizes)", d.props.Name, tostring(v)))
							break
						end
					end
				end
				d.props.Size = s
			end,
		},
		Color = {
			set = function(inst, d, v)
				d.props.Color = quantize(v)
			end,
		},
		BrickColor = {
			get = function(inst, d)
				return bcNearest(d.props.Color or DEFAULTS["BasePart.Color"])
			end,
			set = function(inst, d, v)
				d.props.Color = quantize(v.Color)
			end,
		},
	}
	SPECIAL.Part = {
		Shape = {
			set = function(inst, d, v)
				d.props.Shape = v
				if v.Name == "Ball" then
					local s = d.props.Size or DEFAULTS["BasePart.Size"]
					local m = math.min(s[1], s[2], s[3])
					d.props.Size = v3(m, m, m)
				end
			end,
		},
	}
	SPECIAL.Model = {
		WorldPivot = {
			get = function(inst, d)
				return modelPivot(inst)
			end,
			set = function(inst, d, v)
				local pp = d.props.PrimaryPart
				if pp and isAncestorOf(inst, pp) then
					local pd = pp[PRIV]
					pd.props.PivotOffset = cfMul(cfInv(pd.props.CFrame or IDENTITY), v)
				else
					d.props.WorldPivot = v
					d.pivotSet = true
				end
			end,
		},
	}

	-- Build the class records from the generated API data
	local creatable = {}
	for _, n in ipairs(string.split(API.CREATABLE, " ")) do
		creatable[n] = true
	end
	local robloxServices = {}
	for _, n in ipairs(string.split(API.SERVICES, " ")) do
		robloxServices[n] = true
	end
	local function merge(dst, src)
		if src then
			for k, v in pairs(src) do
				dst[k] = v
			end
		end
		return dst
	end
	for _, row in ipairs(API.CLASSES) do
		local name, parentName, propStr, methodStr, eventStr = row[1], row[2], row[3], row[4], row[5]
		local super = parentName and CLASSES[parentName]
		local rec = {
			Name = name,
			Super = super,
			Props = merge({}, super and super.Props),
			Members = merge({}, super and super.Members),
			Events = merge({}, super and super.Events),
			Impl = merge({}, super and super.Impl),
			Special = merge({}, super and super.Special),
			IsA = merge({}, super and super.IsA),
			DefaultCache = {},
		}
		rec.IsA[name] = true
		if propStr ~= "" then
			for _, pair in ipairs(string.split(propStr, " ")) do
				local pn, pt = string.match(pair, "^([%w_]+):(.+)$")
				rec.Props[pn] = parseType(pt)
			end
		end
		if methodStr ~= "" then
			for _, m in ipairs(string.split(methodStr, " ")) do
				rec.Members[m] = true
			end
		end
		if eventStr ~= "" then
			for _, e in ipairs(string.split(eventStr, " ")) do
				rec.Events[e] = true
			end
		end
		merge(rec.Impl, IMPL[name])
		merge(rec.Special, SPECIAL[name])
		CLASSES[name] = rec
	end
	-- the harness can make these with Instance.new
	local MOCKED_NEW = {}
	for _, n in ipairs(string.split("Part WedgePart CornerWedgePart TrussPart Model Folder PointLight SpotLight SurfaceLight ParticleEmitter Fire Smoke Sparkles Attachment SurfaceGui BillboardGui TextLabel Frame ImageLabel UICorner UIStroke UIGradient UIListLayout UIPadding UIAspectRatioConstraint UIScale Decal Texture Highlight Beam Trail SpecialMesh SelectionBox", " ")) do
		MOCKED_NEW[n] = true
	end

	local function checkAssetText(d, prop: string, s: string)
		local id = string.match(s, "rbxassetid://(%d+)") or string.match(s, "assetid=(%d+)")
		if id and id ~= ALLOWED_ASSET then
			note(fmt("%s %q: %s = %q uses an asset id that is not on the allowed list (ARCHITECTURE section 1); unknown ids may be private or deleted", d.cls.Name, d.props.Name, prop, s))
		elseif string.find(s, "^https?://") then
			note(fmt("%s %q: %s = %q is a web URL; Roblox can't load those", d.cls.Name, d.props.Name, prop, s))
		end
	end

	INST.__index = function(self, k)
		local d = self[PRIV]
		local rec = d.cls
		local f = rec.Impl[k]
		if f then
			return f
		end
		local spec = rec.Props[k]
		if spec then
			local sp = rec.Special[k]
			if sp and sp.get then
				return sp.get(self, d)
			end
			local v = d.props[k]
			if v == nil then
				v = defaultFor(rec, k, spec)
			end
			return v
		end
		if rec.Events[k] then
			return signal(d.props.Name, k)
		end
		if rec.Members[k] then
			return function()
				error(fmt("%s:%s() is not supported by the test harness (sections normally don't need it)", rec.Name, k), 2)
			end
		end
		if type(k) == "string" then
			for _, c in ipairs(d.children) do
				if c[PRIV].props.Name == k then
					return c
				end
			end
		end
		error(fmt("%s is not a valid member of %s \"%s\"", tostring(k), rec.Name, fullName(self)), 2)
	end
	INST.__newindex = function(self, k, v)
		local d = self[PRIV]
		local rec = d.cls
		local spec = type(k) == "string" and rec.Props[k]
		if not spec then
			if rec.Impl[k] or rec.Members[k] or rec.Events[k] then
				error(fmt("%s is a method/event of %s, it can't be assigned", tostring(k), rec.Name), 2)
			end
			error(fmt("%s is not a valid member of %s \"%s\"", tostring(k), rec.Name, fullName(self)), 2)
		end
		if READ_ONLY[k] then
			error(fmt("Unable to assign property %s. Property is read only", k), 2)
		end
		local val, err = coerce(spec, v)
		if err then
			error(fmt("Unable to assign property %s of %s %q. %s", k, rec.Name, d.props.Name, err), 2)
		end
		if type(val) == "string" then
			checkAssetText(d, k, val)
		end
		local sp = rec.Special[k]
		if sp and sp.set then
			local e2 = sp.set(self, d, val)
			if e2 then
				error(e2, 2)
			end
		else
			d.props[k] = val
		end
	end
	INST.__tostring = function(self)
		return self[PRIV].props.Name
	end

	local function newInstance(className: string)
		local rec = CLASSES[className]
		local inst = wrap(newInstanceData(rec))
		return inst
	end

	Instance = library("Instance", {
		new = function(className, parent)
			if type(className) ~= "string" then
				badArg("Instance.new", 1, "string", className)
			end
			if not MOCKED_NEW[className] then
				if creatable[className] then
					error(fmt("Instance.new(%q) is not supported by the test harness (sections should only make parts, models and simple decorations like lights, particles, fire and signs)", className), 2)
				end
				error(fmt("Unable to create an Instance of type %q", className), 2)
			end
			local inst = newInstance(className)
			table.insert(createdLog, inst)
			if parent ~= nil then
				local e = setParent(inst, parent)
				if e then
					error(e, 2)
				end
			end
			return inst
		end,
	})

	-- game, services and workspace
	game = wrap(newInstanceData(CLASSES.DataModel))
	game[PRIV].props.Name = "Game"
	game[PRIV].isService = true
	local services = {}
	local function getService(name: string)
		local s = services[name]
		if s then
			return s
		end
		if CLASSES[name] and robloxServices[name] then
			s = newInstance(name)
			s[PRIV].isService = true
			s[PRIV].parent = game
			table.insert(game[PRIV].children, s)
			services[name] = s
			return s
		end
		return nil
	end
	workspace = getService("Workspace")
	local SP = {
		GetService = function(self, name)
			needSelf(self, "GetService")
			if type(name) ~= "string" then
				badArg("GetService", 1, "string", name)
			end
			local s = getService(name)
			if s then
				return s
			end
			if robloxServices[name] then
				error(fmt("game:GetService(%q) is not supported by the test harness (sections should not need it)", name), 2)
			end
			error(fmt("'%s' is not a valid Service name", name), 2)
		end,
		FindService = function(self, name)
			needSelf(self, "FindService")
			return services[name]
		end,
	}
	merge(CLASSES.DataModel.Impl, SP)
	CLASSES.DataModel.Special.Workspace = {
		get = function()
			return workspace
		end,
	}

	-- Roblox globals that make no sense inside a Build
	local function forbidden(name: string)
		return function()
			error(name .. "() must not be used inside a section Build: the tower is built instantly. Animate with ctx:Spin / ctx:Move / ctx:Swing / ctx:Cycle instead.", 2)
		end
	end
	wait, delay, spawn = forbidden("wait"), forbidden("delay"), forbidden("spawn")
	task = setmetatable({}, {
		__index = function(_, k)
			return forbidden("task." .. tostring(k))
		end,
	})
	tick = os.clock
	time = function()
		return 0
	end
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		note("warn(): " .. table.concat(parts, " "))
	end

	-- Harness-only helpers (section_checks.luau uses these; sections never see them)
	Mock.data = idata
	Mock.isInstance = isInst
	Mock.PRIV = PRIV
	Mock.v3 = v3
	Mock.cf = cfr
	Mock.cfMul = cfMul
	Mock.cfInv = cfInv
	Mock.cfPoint = cfPoint
	Mock.cfVector = cfVector
	Mock.axisAngle = axisAngle
	Mock.classRecord = function(name: string)
		return CLASSES[name]
	end
	Mock.descendants = function(inst)
		return descendants(inst, {})
	end
	Mock.inDataModel = inDataModel
	Mock.fullName = fullName
	Mock.startBuildLog = function()
		createdLog = {}
		notes = {}
	end
	Mock.buildLog = function()
		return createdLog, notes
	end
	Mock.note = note
	Mock.nstr = nstr
	Mock.services = services
end

------------------------------------------------------------------------
-- Roblox API data (generated from .tools/globalTypes.d.luau - do not edit by hand)
-- Each class row: { name, parent, "Prop:Type ...", "Method ...", "Event ..." }
------------------------------------------------------------------------
API.CLASSES = {
	{ "Object", nil, "ClassName:string", "GetPropertyChangedSignal IsA isA", "Changed" },
	{ "Instance", "Object", "Archivable:boolean Capabilities:SecurityCapabilities Name:string Parent:Instance? Sandboxed:boolean", "AddTag ClearAllChildren Clone Destroy FindFirstAncestor FindFirstAncestorOfClass FindFirstAncestorWhichIsA FindFirstChild FindFirstChildOfClass FindFirstChildWhichIsA FindFirstDescendant GetActor GetAttribute GetAttributeChangedSignal GetAttributes GetChildren GetDescendants GetFullName GetStyled GetStyledPropertyChangedSignal GetTags HasTag IsAncestorOf IsDescendantOf IsPropertyModified QueryDescendants Remove RemoveTag ResetPropertyToDefault SetAttribute WaitForChild children clone destroy findFirstChild getChildren isDescendantOf remove", "AncestryChanged AttributeChanged ChildAdded ChildRemoved DescendantAdded DescendantRemoving Destroying StyledPropertiesChanged" },
	{ "PVInstance", "Instance", "", "GetPivot PivotTo", "" },
	{ "BasePart", "PVInstance", "Anchored:boolean AssemblyAngularVelocity:Vector3 AssemblyCenterOfMass:Vector3 AssemblyLinearVelocity:Vector3 AssemblyMass:number AssemblyRootPart:BasePart AudioCanCollide:boolean BackSurface:Enum.SurfaceType BottomSurface:Enum.SurfaceType BrickColor:BrickColor CFrame:CFrame CanCollide:boolean CanQuery:boolean CanTouch:boolean CastShadow:boolean CenterOfMass:Vector3 CollisionGroup:string Color:Color3 CurrentPhysicalProperties:PhysicalProperties CustomPhysicalProperties:PhysicalProperties EnableFluidForces:boolean ExtentsCFrame:CFrame ExtentsSize:Vector3 FrontSurface:Enum.SurfaceType LeftSurface:Enum.SurfaceType LocalTransparencyModifier:number Locked:boolean Mass:number Massless:boolean Material:Enum.Material MaterialVariant:string Orientation:Vector3 PivotOffset:CFrame Position:Vector3 ReceiveAge:number Reflectance:number ResizeIncrement:number ResizeableFaces:Faces RightSurface:Enum.SurfaceType RootPriority:number Rotation:Vector3 Size:Vector3 TopSurface:Enum.SurfaceType Transparency:number", "AngularAccelerationToTorque ApplyAngularImpulse ApplyImpulse ApplyImpulseAtPosition BindToCollisionSummaries BreakJoints CanCollideWith CanSetNetworkOwnership GetClosestPointOnSurface GetConnectedParts GetJoints GetMass GetNetworkOwner GetNetworkOwnershipAuto GetNoCollisionConstraints GetRenderCFrame GetRootPart GetTouchingParts GetVelocityAtPosition IntersectAsync IsGrounded MakeJoints Resize SetNetworkOwner SetNetworkOwnershipAuto SubtractAsync TorqueToAngularAcceleration UnionAsync breakJoints getMass makeJoints resize", "TouchEnded Touched" },
	{ "FormFactorPart", "BasePart", "", "", "" },
	{ "Part", "FormFactorPart", "Shape:Enum.PartType", "", "" },
	{ "WedgePart", "FormFactorPart", "", "", "" },
	{ "CornerWedgePart", "BasePart", "", "", "" },
	{ "TrussPart", "BasePart", "Style:Enum.Style", "", "" },
	{ "Model", "PVInstance", "ModelStreamingMode:Enum.ModelStreamingMode PrimaryPart:BasePart? WorldPivot:CFrame", "AddPersistentPlayer BreakJoints GetBoundingBox GetExtentsSize GetModelCFrame GetModelSize GetPersistentPlayers GetPrimaryPartCFrame GetScale MakeJoints MoveTo RemovePersistentPlayer ResetOrientationToIdentity ScaleTo SetIdentityOrientation SetPrimaryPartCFrame TranslateBy breakJoints makeJoints move moveTo", "" },
	{ "Folder", "Instance", "IconTint:Color3", "", "" },
	{ "Light", "Instance", "Brightness:number Color:Color3 Enabled:boolean Shadows:boolean", "", "" },
	{ "PointLight", "Light", "Range:number", "", "" },
	{ "SpotLight", "Light", "Angle:number Face:Enum.NormalId Range:number", "", "" },
	{ "SurfaceLight", "Light", "Angle:number Face:Enum.NormalId Range:number", "", "" },
	{ "ParticleEmitter", "Instance", "Acceleration:Vector3 Brightness:number Color:ColorSequence Drag:number EmissionDirection:Enum.NormalId Enabled:boolean FlipbookBlendFrames:boolean FlipbookFramerate:NumberRange FlipbookIncompatible:string FlipbookLayout:Enum.ParticleFlipbookLayout FlipbookMode:Enum.ParticleFlipbookMode FlipbookSizeX:number FlipbookSizeY:number FlipbookStartRandom:boolean Lifetime:NumberRange LightEmission:number LightInfluence:number LocalTransparencyModifier:number LockedToPart:boolean Orientation:Enum.ParticleOrientation Rate:number RotSpeed:NumberRange Rotation:NumberRange Shape:Enum.ParticleEmitterShape ShapeInOut:Enum.ParticleEmitterShapeInOut ShapePartial:number ShapeStyle:Enum.ParticleEmitterShapeStyle Size:NumberSequence Speed:NumberRange SpreadAngle:Vector2 Squash:NumberSequence Texture:ContentId TextureContent:Content TimeScale:number Transparency:NumberSequence VelocityInheritance:number WindAffectsDrag:boolean ZOffset:number", "Clear Emit", "OnClearRequested OnEmitRequested" },
	{ "Fire", "Instance", "Color:Color3 Enabled:boolean Heat:number LocalTransparencyModifier:number SecondaryColor:Color3 Size:number TimeScale:number", "", "" },
	{ "Smoke", "Instance", "Color:Color3 Enabled:boolean LocalTransparencyModifier:number Opacity:number RiseVelocity:number Size:number TimeScale:number", "", "" },
	{ "Sparkles", "Instance", "Color:Color3 Enabled:boolean LocalTransparencyModifier:number SparkleColor:Color3 TimeScale:number", "", "" },
	{ "Attachment", "Instance", "Axis:Vector3 CFrame:CFrame Orientation:Vector3 Position:Vector3 SecondaryAxis:Vector3 Visible:boolean WorldAxis:Vector3 WorldCFrame:CFrame WorldOrientation:Vector3 WorldPosition:Vector3 WorldSecondaryAxis:Vector3", "GetAxis GetConstraints GetSecondaryAxis SetAxis SetSecondaryAxis", "" },
	{ "GuiBase", "Instance", "", "", "" },
	{ "GuiBase2d", "GuiBase", "AbsolutePosition:Vector2 AbsoluteRotation:number AbsoluteSize:Vector2 AutoLocalize:boolean RootLocalizationTable:LocalizationTable SelectionBehaviorDown:Enum.SelectionBehavior SelectionBehaviorLeft:Enum.SelectionBehavior SelectionBehaviorRight:Enum.SelectionBehavior SelectionBehaviorUp:Enum.SelectionBehavior SelectionGroup:boolean", "", "SelectionChanged" },
	{ "LayerCollector", "GuiBase2d", "Enabled:boolean ResetOnSpawn:boolean ZIndexBehavior:Enum.ZIndexBehavior", "GetLayoutNodeTree", "" },
	{ "SurfaceGuiBase", "LayerCollector", "Active:boolean Adornee:Instance Face:Enum.NormalId", "", "" },
	{ "SurfaceGui", "SurfaceGuiBase", "AlwaysOnTop:boolean Brightness:number CanvasSize:Vector2 ClipsDescendants:boolean LightInfluence:number MaxDistance:number PixelsPerStud:number SizingMode:Enum.SurfaceGuiSizingMode ToolPunchThroughDistance:number ZOffset:number", "", "" },
	{ "BillboardGui", "LayerCollector", "Active:boolean Adornee:Instance AlwaysOnTop:boolean Brightness:number ClipsDescendants:boolean CurrentDistance:number DistanceStep:number ExtentsOffset:Vector3 ExtentsOffsetWorldSpace:Vector3 LightInfluence:number MaxDistance:number PlayerToHideFrom:Instance Size:UDim2 SizeOffset:Vector2 StudsOffset:Vector3 StudsOffsetWorldSpace:Vector3", "", "" },
	{ "GuiObject", "GuiBase2d", "Active:boolean AnchorPoint:Vector2 AutomaticSize:Enum.AutomaticSize BackgroundColor3:Color3 BackgroundTransparency:number BorderColor3:Color3 BorderMode:Enum.BorderMode BorderSizePixel:number ClipsDescendants:boolean GuiState:Enum.GuiState InputSink:Enum.InputSink Interactable:boolean LayoutOrder:number NextSelectionDown:GuiObject NextSelectionLeft:GuiObject NextSelectionRight:GuiObject NextSelectionUp:GuiObject Position:UDim2 Rotation:number Selectable:boolean SelectionImageObject:GuiObject SelectionOrder:number Size:UDim2 SizeConstraint:Enum.SizeConstraint Visible:boolean ZIndex:number", "TweenPosition TweenSize TweenSizeAndPosition", "InputBegan InputChanged InputEnded MouseEnter MouseLeave MouseMoved MouseWheelBackward MouseWheelForward SelectionGained SelectionLost TouchLongPress TouchPan TouchPinch TouchRotate TouchSwipe TouchTap" },
	{ "GuiLabel", "GuiObject", "", "", "" },
	{ "TextLabel", "GuiLabel", "ContentText:string Font:Enum.Font FontFace:Font LineHeight:number LocalizedText:string MaxVisibleGraphemes:number OpenTypeFeatures:string OpenTypeFeaturesError:string RichText:boolean Text:string TextBounds:Vector2 TextColor3:Color3 TextDirection:Enum.TextDirection TextFits:boolean TextScaled:boolean TextSize:number TextStrokeColor3:Color3 TextStrokeTransparency:number TextTransparency:number TextTruncate:Enum.TextTruncate TextWrapped:boolean TextXAlignment:Enum.TextXAlignment TextYAlignment:Enum.TextYAlignment", "", "" },
	{ "Frame", "GuiObject", "Style:Enum.FrameStyle", "", "" },
	{ "ImageLabel", "GuiLabel", "Image:ContentId ImageColor3:Color3 ImageContent:Content ImageRectOffset:Vector2 ImageRectSize:Vector2 ImageTransparency:number IsLoaded:boolean ResampleMode:Enum.ResamplerMode ScaleType:Enum.ScaleType SliceCenter:Rect SliceScale:number TileSize:UDim2", "", "" },
	{ "UIBase", "Instance", "", "", "" },
	{ "UIComponent", "UIBase", "", "", "" },
	{ "UICorner", "UIComponent", "BottomLeftRadius:UDim BottomRightRadius:UDim CornerRadius:UDim TopLeftRadius:UDim TopRightRadius:UDim", "", "" },
	{ "UIStroke", "UIComponent", "ApplyStrokeMode:Enum.ApplyStrokeMode BorderOffset:UDim BorderStrokePosition:Enum.BorderStrokePosition Color:Color3 Enabled:boolean LineJoinMode:Enum.LineJoinMode StrokeSizingMode:Enum.StrokeSizingMode Thickness:number Transparency:number ZIndex:number", "", "" },
	{ "UIGradient", "UIComponent", "Color:ColorSequence Enabled:boolean Offset:Vector2 Rotation:number Scale:number TileMode:Enum.GradientTileMode Transparency:NumberSequence Type:Enum.GradientType", "", "" },
	{ "UILayout", "UIComponent", "", "", "" },
	{ "UIGridStyleLayout", "UILayout", "AbsoluteContentSize:Vector2 FillDirection:Enum.FillDirection HorizontalAlignment:Enum.HorizontalAlignment SortOrder:Enum.SortOrder VerticalAlignment:Enum.VerticalAlignment", "ApplyLayout SetCustomSortFunction", "" },
	{ "UIListLayout", "UIGridStyleLayout", "HorizontalFlex:Enum.UIFlexAlignment ItemLineAlignment:Enum.ItemLineAlignment Padding:UDim VerticalFlex:Enum.UIFlexAlignment Wraps:boolean", "", "" },
	{ "UIPadding", "UIComponent", "PaddingBottom:UDim PaddingLeft:UDim PaddingRight:UDim PaddingTop:UDim", "", "" },
	{ "UIConstraint", "UIComponent", "", "", "" },
	{ "UIAspectRatioConstraint", "UIConstraint", "AspectRatio:number AspectType:Enum.AspectType DominantAxis:Enum.DominantAxis", "", "" },
	{ "UIScale", "UIComponent", "Scale:number", "", "" },
	{ "FaceInstance", "Instance", "Face:Enum.NormalId", "", "" },
	{ "Decal", "FaceInstance", "AutoLocalize:boolean Color3:Color3 ColorMap:ContentId ColorMapContent:Content EmissiveMaskContent:Content EmissiveStrength:number EmissiveTint:Color3 LocalTransparencyModifier:number MetalnessMapContent:Content NormalMapContent:Content Rotation:number RoughnessMapContent:Content Texture:ContentId TextureContent:Content Transparency:number UVOffset:Vector2 UVScale:Vector2 ZIndex:number", "", "" },
	{ "Texture", "Decal", "OffsetStudsU:number OffsetStudsV:number StudsPerTileU:number StudsPerTileV:number", "", "" },
	{ "Highlight", "Instance", "Adornee:Instance? DepthMode:Enum.HighlightDepthMode Enabled:boolean FillColor:Color3 FillTransparency:number OutlineColor:Color3 OutlineTransparency:number", "", "" },
	{ "Beam", "Instance", "Attachment0:Attachment? Attachment1:Attachment? Brightness:number Color:ColorSequence CurveSize0:number CurveSize1:number Enabled:boolean FaceCamera:boolean LightEmission:number LightInfluence:number LocalTransparencyModifier:number Segments:number Texture:ContentId TextureContent:Content TextureLength:number TextureMode:Enum.TextureMode TextureSpeed:number Transparency:NumberSequence Width0:number Width1:number ZOffset:number", "SetTextureOffset", "" },
	{ "Trail", "Instance", "Attachment0:Attachment? Attachment1:Attachment? Brightness:number Color:ColorSequence Enabled:boolean FaceCamera:boolean Lifetime:number LightEmission:number LightInfluence:number LocalTransparencyModifier:number MaxLength:number MinLength:number Texture:ContentId TextureContent:Content TextureLength:number TextureMode:Enum.TextureMode Transparency:NumberSequence WidthScale:NumberSequence", "Clear", "OnClearRequested" },
	{ "DataModelMesh", "Instance", "Offset:Vector3 Scale:Vector3 VertexColor:Vector3", "", "" },
	{ "FileMesh", "DataModelMesh", "MeshContent:Content MeshId:ContentId TextureContent:Content TextureId:ContentId", "", "" },
	{ "SpecialMesh", "FileMesh", "MeshType:Enum.MeshType", "", "" },
	{ "GuiBase3d", "GuiBase", "Color3:Color3 Transparency:number Visible:boolean", "", "" },
	{ "InstanceAdornment", "GuiBase3d", "Adornee:Instance?", "", "" },
	{ "SelectionBox", "InstanceAdornment", "LineThickness:number SurfaceColor3:Color3 SurfaceTransparency:number", "", "" },
	{ "WorldRoot", "Model", "", "ArePartsTouchingOthers Blockcast BulkMoveTo CollisionGroupSetCollidable CollisionGroupsAreCollidable FindPartOnRay FindPartOnRayWithIgnoreList FindPartOnRayWithWhitelist FindPartsInRegion3 FindPartsInRegion3WithIgnoreList FindPartsInRegion3WithWhiteList GetMaxCollisionGroups GetPartBoundsInBox GetPartBoundsInRadius GetPartsInPart GetRegisteredCollisionGroups IsCollisionGroupRegistered IsRegion3Empty IsRegion3EmptyWithIgnoreList Raycast RegisterCollisionGroup RenameCollisionGroup Shapecast Spherecast UnregisterCollisionGroup findPartOnRay findPartsInRegion3", "" },
	{ "Workspace", "WorldRoot", "AirDensity:number AirTurbulenceIntensity:number AllowThirdPartySales:boolean ClientAnimatorThrottling:Enum.ClientAnimatorThrottlingMode CurrentCamera:Camera DistributedGameTime:number FallHeightEnabled:boolean FallenPartsDestroyHeight:number GlobalWind:Vector3 Gravity:number InsertPoint:Vector3 Retargeting:Enum.AnimatorRetargetingMode StreamingAdaptiveRadius:boolean StreamingEnabled:boolean Terrain:Terrain", "GetNumAwakeParts GetPhysicsThrottling GetRealPhysicsFPS GetServerTimeNow JoinToOutsiders PGSIsEnabled UnjoinFromOutsiders", "PersistentLoaded" },
	{ "CollectionService", "Instance", "", "AddTag CreateCollection GetAllTags GetCollection GetInstanceAddedSignal GetInstanceRemovedSignal GetTagged GetTags HasTag RemoveTag", "TagAdded TagRemoved" },
	{ "ReplicatedStorage", "Instance", "", "", "" },
	{ "ServerStorage", "Instance", "", "", "" },
	{ "ServerScriptService", "Instance", "", "", "" },
	{ "Lighting", "Instance", "Ambient:Color3 Brightness:number ClockTime:number ColorShift_Bottom:Color3 ColorShift_Top:Color3 EnvironmentDiffuseScale:number EnvironmentSpecularScale:number ExposureCompensation:number FogColor:Color3 FogEnd:number FogStart:number GeographicLatitude:number GlobalShadows:boolean LightingStyle:Enum.LightingStyle OutdoorAmbient:Color3 PrioritizeLightingQuality:boolean ShadowSoftness:number TimeOfDay:string", "GetMinutesAfterMidnight GetMoonDirection GetMoonPhase GetSunDirection SetMinutesAfterMidnight getMinutesAfterMidnight setMinutesAfterMidnight", "LightingChanged" },
	{ "Players", "Instance", "BubbleChat:boolean CharacterAutoLoads:boolean ClassicChat:boolean LocalPlayer:Player MaxPlayers:number PreferredPlayers:number RespawnTime:number", "BanAsync CreateHumanoidModelFromDescription CreateHumanoidModelFromDescriptionAsync CreateHumanoidModelFromUserId CreateHumanoidModelFromUserIdAsync GetBanHistoryAsync GetCharacterAppearanceAsync GetCharacterAppearanceInfoAsync GetFriendsAsync GetHumanoidDescriptionFromOutfitId GetHumanoidDescriptionFromOutfitIdAsync GetHumanoidDescriptionFromUserId GetHumanoidDescriptionFromUserIdAsync GetNameFromUserIdAsync GetPlayerByUserId GetPlayerFromCharacter GetPlayers GetProfileConfigurationFromUserIdAsync GetUserIdFromNameAsync GetUserThumbnailAsync UnbanAsync getPlayers playerFromCharacter players", "PlayerAdded PlayerChatted PlayerMembershipChanged PlayerRemoving UserSubscriptionStatusChanged" },
	{ "RunService", "Instance", "FrameNumber:number", "BindToAnimation BindToRenderStep BindToSimulation GetPredictionStatus IsClient IsResimulating IsRunMode IsRunning IsServer IsStudio SetPredictionMode UnbindFromRenderStep", "Heartbeat Misprediction PostSimulation PreAnimation PreRender PreSimulation RenderStepped Rollback Stepped" },
	{ "TweenService", "Instance", "", "Create GetValue SmoothDamp", "" },
	{ "Debris", "Instance", "", "AddItem addItem", "" },
	{ "ServiceProvider", "Instance", "", "FindService GetService getService service", "Close ServiceAdded ServiceRemoving" },
	{ "DataModel", "ServiceProvider", "CreatorId:number CreatorType:Enum.CreatorType GameId:number Genre:Enum.Genre JobId:string MatchmakingType:Enum.MatchmakingType PlaceId:number PlaceVersion:number PrivateServerId:string PrivateServerOwnerId:number RunService:RunService Workspace:Workspace", "BindToClose GetMessage GetRemoteBuildMode IsGearTypeAllowed IsLoaded SavePlace", "GraphicsQualityChangeRequest Loaded ServerLifecycleChanged ServerLowMemoryWarning ServerRestartScheduled" },
}
API.ENUMS = {
	AnimatorRetargetingMode = "Default Disabled Enabled",
	ApplyStrokeMode = "Border Contextual",
	AspectType = "FitWithinMaxSize ScaleWithParentSize",
	AutomaticSize = "None X XY Y",
	Axis = "X Y Z",
	BorderMode = "Inset Middle Outline",
	BorderStrokePosition = "Center Inner Outer",
	ClientAnimatorThrottlingMode = "Default Disabled Enabled",
	CollisionFidelity = "Box Default Hull PreciseConvexDecomposition Tunable",
	CreatorType = "Group User",
	DominantAxis = "Height Width",
	EasingDirection = "In InOut Out",
	EasingStyle = "Back Bounce Circular Cubic Elastic Exponential Linear Quad Quart Quint Sine",
	FillDirection = "Horizontal Vertical",
	Font = "AmaticSC Antique Arcade Arial ArialBold Arimo ArimoBold Bangers Bodoni BuilderSans BuilderSansBold BuilderSansExtraBold BuilderSansMedium Cartoon Code Creepster DenkOne Fantasy Fondamento FredokaOne Garamond Gotham GothamBlack GothamBold GothamMedium GrenzeGotisch Highway IndieFlower JosefinSans Jura Kalam Legacy LuckiestGuy Merriweather Michroma Nunito Oswald PatrickHand PermanentMarker Roboto RobotoCondensed RobotoMono Sarpanch SciFi SourceSans SourceSansBold SourceSansItalic SourceSansLight SourceSansSemibold SpecialElite TitilliumWeb Ubuntu Unknown",
	FontStyle = "Italic Normal",
	FontWeight = "Bold ExtraBold ExtraLight Heavy Light Medium Regular SemiBold Thin",
	FrameStyle = "ChatBlue ChatGreen ChatRed Custom DropShadow RobloxRound RobloxSquare",
	Genre = "Adventure All Fantasy Funny Ninja Pirate Scary SciFi SkatePark Sports TownAndCity Tutorial War WildWest",
	GradientTileMode = "Clamp Mirror Repeat",
	GradientType = "Conical Elliptical Linear Radial",
	GuiState = "Hover Idle NonInteractable Press",
	HighlightDepthMode = "AlwaysOnTop Occluded",
	HorizontalAlignment = "Center Left Right",
	InputSink = "Activate All None",
	ItemLineAlignment = "Automatic Center End Start Stretch",
	LightingStyle = "Realistic Soft",
	LineJoinMode = "Bevel Miter Round",
	MatchmakingType = "Default PlayStationOnly XboxOnly",
	Material = "Air Asphalt Basalt Brick Cardboard Carpet CeramicTiles ClayRoofTiles Cobblestone Concrete CorrodedMetal CrackedLava DiamondPlate Fabric Foil ForceField Glacier Glass Granite Grass Ground Ice LeafyGrass Leather Limestone Marble Metal Mud Neon Pavement Pebble Plaster Plastic Rock RoofShingles Rubber Salt Sand Sandstone Slate SmoothPlastic Snow Water Wood WoodPlanks",
	MeshType = "Brick CornerWedge Cylinder FileMesh Head ParallelRamp Prism Pyramid RightAngleRamp Sphere Torso Wedge",
	ModelStreamingMode = "Atomic Default Nonatomic Persistent PersistentPerPlayer",
	NormalId = "Back Bottom Front Left Right Top",
	PartType = "Ball Block CornerWedge Cylinder Wedge",
	ParticleEmitterShape = "Box Cylinder Disc Sphere",
	ParticleEmitterShapeInOut = "InAndOut Inward Outward",
	ParticleEmitterShapeStyle = "Surface Volume",
	ParticleFlipbookLayout = "Custom Grid2x2 Grid4x4 Grid8x8 None",
	ParticleFlipbookMode = "Loop OneShot PingPong Random",
	ParticleOrientation = "FacingCamera FacingCameraWorldUp VelocityParallel VelocityPerpendicular",
	RenderFidelity = "Automatic Performance Precise",
	ResamplerMode = "Default Pixelated",
	RotationOrder = "XYZ XZY YXZ YZX ZXY ZYX",
	ScaleType = "Crop Fit Slice Stretch Tile",
	SelectionBehavior = "Escape Stop",
	SizeConstraint = "RelativeXX RelativeXY RelativeYY",
	SortOrder = "Custom LayoutOrder Name",
	StrokeSizingMode = "FixedSize ScaledSize",
	Style = "AlternatingSupports BridgeStyleSupports NoSupports",
	SurfaceGuiSizingMode = "FixedSize PixelsPerStud",
	SurfaceType = "Glue Hinge Inlet Motor Smooth SmoothNoOutlines SteppingMotor Studs Universal Weld",
	TextDirection = "Auto LeftToRight RightToLeft",
	TextTruncate = "AtEnd None SplitWord",
	TextXAlignment = "Center Left Right",
	TextYAlignment = "Bottom Center Top",
	TextureMode = "Static Stretch Wrap",
	UIFlexAlignment = "Fill None SpaceAround SpaceBetween SpaceEvenly",
	VerticalAlignment = "Bottom Center Top",
	ZIndexBehavior = "Global Sibling",
}
API.ENUM_NAMES = "AccessModifierType AccessoryType ActionOnAutoResumeSync ActionOnStopSync ActionType ActivePayerStatus ActuatorRelativeTo ActuatorType AdAvailabilityResult AdEventType AdFormat AdShape AdTeleportMethod AdUIEventType AdUIType AdUnitStatus AdornCullingMode AdornShading AgeCheckStatus AlignType AlphaMode AnalyticsCustomFieldKeys AnalyticsEconomyAction AnalyticsEconomyFlowType AnalyticsEconomyTransactionType AnalyticsLogLevel AnalyticsProgressionStatus AnalyticsProgressionType AnimatedImagePlaybackState AnimatedImageScaleType AnimationClipFromVideoStatus AnimationNodeBlend2DInputMode AnimationNodeBlendMode AnimationNodeInterruptible AnimationNodePhaseSync AnimationNodePlayMode AnimationNodeTransitionType AnimationNodeTransitionWhen AnimationNodeType AnimationNodeWaitFor AnimationPriority AnimationValueNodeType AnimatorRetargetingMode AnnotationChannelContentPreference AnnotationEditingMode AnnotationPlaceContentPreference AnnotationRequestStatus AnnotationRequestType AntiAliasing AppLifecycleManagerState AppShellActionType AppShellFeature AppUpdateStatus ApplyShadowMode ApplyStrokeMode AspectType AssetCreatorType AssetFetchStatus AssetRepresentation AssetType AssetTypeVerification AudioApiRollout AudioCaptureMode AudioChannelLayout AudioFilterType AudioPositionType AudioSampleFormat AudioSimulationFidelity AudioSubType AudioWindowSize AuthorityMode AutoIndentRule AutomaticSize AvatarAssetType AvatarChatServiceFeature AvatarContextMenuOption AvatarGenerationError AvatarItemType AvatarPromptResult AvatarSettingsAccessoryLimitMethod AvatarSettingsAccessoryMode AvatarSettingsAnimationClipsMode AvatarSettingsAnimationPacksMode AvatarSettingsAppearanceMode AvatarSettingsBuildMode AvatarSettingsCharacterControllerMode AvatarSettingsClothingMode AvatarSettingsCollisionMode AvatarSettingsCustomAccessoryMode AvatarSettingsCustomBodyType AvatarSettingsCustomClothingMode AvatarSettingsHitAndTouchDetectionMode AvatarSettingsJumpMode AvatarSettingsLegacyCollisionMode AvatarSettingsScaleMode AvatarThumbnailCustomizationType AvatarUnificationMode Axis BasicMeshPartShape BenefitType BinType BodyPart BodyPartR15 BorderMode BorderStrokePosition BranchStatus BreakReason BreakpointRemoveReason BulkMoveMode BundleType Button ButtonStyle CageType CameraMode CameraNavigationModel CameraPanMode CameraSpeedAdjustBinding CameraType CanCollaborateError CaptureGalleryPermission CaptureType CatalogCategoryFilter CatalogSortAggregation CatalogSortType CellBlock CellMaterial CellOrientation CenterDialogType CharacterControlMode ChatCallbackType ChatColor ChatMode ChatPrivacyMode ChatRestrictionStatus ChatStyle ChatVersion ClientAnimatorThrottlingMode CloseReason CollaboratorStatus CollisionFidelity CommandPermission CompileTarget CompletionAcceptanceBehavior CompletionItemKind CompletionItemTag CompletionTriggerKind CompositeValueCurveType CompressionAlgorithm ComputerCameraMovementMode ComputerMovementMode ConfigSnapshotErrorState ConnectionError ConnectionState ContentSourceType ContextActionPriority ContextActionResult ControlMode CoreGuiType CreateAssetResult CreateContentResult CreateOutfitFailure CreatorType CreatorTypeFilter CurrencyType CustomCameraMode DataModelChangeType DataModelExtractorFileType DataStoreRequestType DebugBreakModeType DebuggerEndReason DebuggerExceptionBreakMode DebuggerFrameType DebuggerPauseReason DebuggerResumeType DebuggerStatus DefaultScriptSyncFileType DevCameraOcclusionMode DevComputerCameraMovementMode DevComputerMovementMode DevTouchCameraMovementMode DevTouchMovementMode DeveloperMemoryTag DeviceFeatureType DeviceForm DeviceLevel DeviceSimulatorScalingMode DeviceType DialogBehaviorType DialogPurpose DialogTone DigitsRigDescriptionSide DiscountType DisplayScalingMode DisplaySize DistanceAttenuationMode DomainType DominantAxis DraftStatusCode DragDetectorDragStyle DragDetectorPermissionPolicy DragDetectorResponseStyle DraggerCoordinateSpace DraggerMovementMode DraggingScrollBar EasingDirection EasingStyle EditableStatus ElasticBehavior EmitterPositionType EngagementLevel EngineFolder EnviromentalPhysicsThrottle ExperienceActivationStatus ExperienceAuthScope ExperienceEventStatus ExperienceStateCaptureSelectionMode ExperienceStateRecordingLoadMode ExperienceStateRecordingLoadSourceType ExperienceStateRecordingPlaybackMode ExplosionType ExternalEditorMode FACSDataLod FacialAgeEstimationResultType FacialAnimationStreamingState FacsActionUnit FeatureRestrictionAbuseVector FeedbackType FieldOfViewMode FillDirection FilterErrorType FilterResult FilterType FinishRecordingOperation FluidFidelity FluidForces Font FontSize FontStyle FontWeight ForceLimitMode FormFactor FrameStyle FramerateManagerMode FriendRequestEvent FriendStatus FriendsCallingEndReason FriendsCallingParticipantErrors FriendsCallingParticipantLeaveReason FriendsCallingParticipantStatus FriendsCallingPhase FrustumStreamingMode FunctionalTestResult GameAvatarType GamepadType GearGenreSetting GearType GenerateMomentTextResult Genre GradientTileMode GradientType GraphicsMode GraphicsOptimizationMode GroupMembershipStatus GuiState GuiType HandlesStyle HapticEffectType HashAlgorithm HighlightDepthMode HorizontalAlignment HoverAnimateSpeed HttpCachePolicy HttpCompression HttpContentType HttpError HttpRequestType HumanoidCollisionType HumanoidDisplayDistanceType HumanoidHealthDisplayType HumanoidRigType HumanoidStateType IKCollisionsMode IKControlConstraintSupport IKControlType IXPLoadingStatus ImageAlphaType ImageCombineType InOut InfoType InitialDockState InputActionType InputBindingType InputSink InputType InstanceFileSyncStatus IntentReplicability IntermediateMeshGenerationResult InternalVideoUsage InterpolationThrottlingMode InviteState ItemLineAlignment JoinSource JointCreationMode KeyCode KeyCodeStringFormat KeyInterpolationMode KeywordFilterType KnownWindow LeftRight LexemeType LightingStyle Limb LineJoinMode ListDisplayMode ListenerLocation ListenerPositionType ListenerType LiveEditingAtomicUpdateResponse LiveEditingBroadcastMessageType LoadCharacterLayeredClothing LoadDynamicHeads LocationType LuauTypeCheckMode MakeupType MarketplaceBulkPurchasePromptStatus MarketplaceItemPurchaseStatus MarketplaceProductType MarkupKind MatchmakingType Material MaterialPattern MembershipType MergeResolution MergeStatus MeshAttribute MeshPartDetailLevel MeshPartHeadsAndAccessories MeshScaleUnit MeshType MessageType ModelLevelOfDetail ModelStreamingBehavior ModelStreamingMode ModerationResultCategory ModerationResultLabel ModerationStatus ModifierKey MouseBehavior MoveState MuteState NameOcclusion NegateOperationHiddenHistory NetworkOwnership NetworkStatus NoiseType NormalId NotificationButtonType OperationType OrientationAlignmentMode OutfitSource OutfitType OutputLayoutMode OverrideMouseIconBehavior PackagePermission PageMilestoneType PageType PartType ParticleEmitterShape ParticleEmitterShapeInOut ParticleEmitterShapeStyle ParticleFlipbookLayout ParticleFlipbookMode ParticleFlipbookTextureCompatible ParticleOrientation PathStatus PathWaypointAction PathfindingUseImprovedSearch PeoplePageLayout PerformanceOverlayMode PermissionLevelShown PhysicalConstraintType PhysicsSimulationRate PhysicsSteppingMethod PinExperienceStatus PioneerSource PlaceContentPreference PlacePublishType Platform PlaybackState PlayerActions PlayerCharacterDestroyBehavior PlayerChatType PlayerDataErrorState PlayerDataLoadFailureBehavior PlayerExitReason PlayerPlatformActivationStatus PlayerPlatformSpenderStatus PluginConnectionTargetType PoseEasingDirection PoseEasingStyle PositionAlignmentMode PredictionMode PredictionStatus PredictiveStreamingMode PreferredInput PreferredTextSize PrefetchDownloadStatus PrimalPhysicsSolver PrimitiveType PrivilegeType ProductLocationRestriction ProductPurchaseChannel ProductPurchaseDecision ProjectServiceOperationResult PromptCreateAssetResult PromptCreateAvatarResult PromptCreateOutfitResult PromptCreatePlatformContentResult PromptExperienceDetailsResult PromptLinkSharingResult PromptPublishAssetResult PropertyStatus ProximityPromptExclusivity ProximityPromptInputType ProximityPromptStyle PurchaseOption QualityLevel QueueDecision R15CollisionType RaycastFilterType ReadCapturesFromGalleryResult ReceiptDecision ReceiptType RecommendationActionType RecommendationDepartureIntent RecommendationImpressionType RecommendationItemContentType RecommendationItemVisibility RecommendationPreferenceTargetType RecommendationPreferenceType RejectCharacterDeletions RenderFidelity RenderPriority RenderingCacheOptimizationMode RenderingTestComparisonMethod ReplicateInstanceDestroySetting ResamplerMode ReservedHighlightId RestPose RestPoseModel ReturnKeyType ReverbType ReviewableContentState RibbonTool RigLabel RigScale RigType RollOffMode RolloutState RotationOrder RotationType RsvpStatus RtlTextSupport RunContext RunState RuntimeUndoBehavior SafeAreaCompatibility SalesTypeFilter SandboxedInstanceMode SaveAvatarThumbnailCustomizationFailure SaveFilter SavedQualitySetting ScaleType ScopeCheckResult ScreenInsets ScreenOrientation ScreenshotCaptureResult ScriptScannerUpdateType ScriptStoppedReason ScriptVariableScope ScrollBarInset ScrollState ScrollingDirection SecurityCapability SelectionBehavior SelectionRenderMode SelfViewPosition SensorMode SensorUpdateType ServerLiveEditingMode ServiceVisibility Severity ShowAdResult SignalBehavior SimulationMode SizeConstraint SlimTintMode SlimTranscoderStatus SlimViewContext SolverConvergenceMetricType SolverConvergenceVisualizationMode SortDirection SortOrder SpecialKey StartCorner StateObjectFieldType StateReferenceFrame Status StepFrequency StreamOutBehavior StreamingIntegrityMode StreamingPauseMode StrokeSizingMode StudioAction StudioCaptureBufferStatus StudioCaptureScreenshotFormat StudioCloseMode StudioDataModelType StudioPlaceUpdateFailureReason StudioScriptEditorColorCategories StudioScriptEditorColorPresets StudioStyleGuideColor StudioStyleGuideModifier Style SubscriptionExpirationReason SubscriptionPaymentStatus SubscriptionPeriod SubscriptionState SurfaceConstraint SurfaceGuiShape SurfaceGuiSizingMode SurfaceType SwipeDirection SystemThemeValue TableMajorAxis TeamCreateErrorState Technology TelemetryBackend TelemetryStandardizedField TeleportMethod TeleportResult TeleportState TeleportType TerrainAcquisitionMethod TerrainFace TerrainLiquidMergeOperation TerrainSolidMergeOperation TextChannelDisplayMode TextChatMessageStatus TextDirection TextFilterContext TextInputType TextTruncate TextXAlignment TextYAlignment TextureMode TextureQueryType ThreadPoolConfig ThrottlingPriority ThumbnailSize ThumbnailType TickCountSampleMethod TitleBarControlsPosition TitleBarMode TonemapperPreset TopBottom TouchCameraMovementMode TouchMovementMode TrackerError TrackerExtrapolationFlagMode TrackerFaceTrackingStatus TrackerLodFlagMode TrackerLodValueMode TrackerMode TrackerPromptEvent TrackerType TriStateBoolean TweenStatus UICaptureMode UIDragDetectorBoundingBehavior UIDragDetectorDragRelativity UIDragDetectorDragSpace UIDragDetectorDragStyle UIDragDetectorResponseStyle UIDragSpeedAxisMapping UIFlexAlignment UIFlexMode UITheme UiMessageType UpdateState UploadCaptureResult UsageContext UserAcquisitionSource UserCFrame UserIdMode UserInputState UserInputType UserNewReturningStatus UserReturnStatus VRComfortSetting VRControllerModelMode VRDeviceType VRLaserPointerMode VRSafetyBubbleMode VRScaling VRSessionState VRTouchpad VRTouchpadMode VelocityConstraintMode VerifiedLevel VerticalAlignment VerticalScrollBarPosition VibrationMotor VideoCaptureResult VideoCaptureStartedResult VideoDeviceCaptureQuality VideoError VideoSampleSize ViewMode VirtualCursorMode VirtualInputMode VoiceChatDistanceAttenuationType VoiceChatState VoiceClientLeaveReasons VoiceControlPath VoiceRccReconnectReason VolumetricAudio WaterDirection WaterForce WebSocketState WebStreamClientState WebStreamClientType WeldConstraintPreserve WhenUserFirstPlayed WhisperChatPrivacyMode WindSoundProfile WindowState WrapLayerAutoSkin WrapLayerDebugMode WrapTargetDebugMode ZIndexBehavior"
API.CREATABLE = "AccessoryDescription Accoutrement Accessory Hat AdPlacement AdPortal AdvancedDragger Animation AnimationGraphDefinition CurveAnimation KeyframeSequence AnimationController AnimationNodeDefinition AnimationRigData AnimationValueNodeDefinition AnimationValueOutputDefinition Animator Annotation WorkspaceAnnotation Atmosphere Attachment Bone AudioAnalyzer AudioChannelMixer AudioChannelSplitter AudioChorus AudioCompressor AudioDeviceInput AudioDeviceOutput AudioDistortion AudioEcho AudioEmitter AudioEqualizer AudioFader AudioFilter AudioFlanger AudioGate AudioLimiter AudioListener AudioPitchShifter AudioPlayer AudioRecorder AudioReverb AudioSearchParams AudioSpeechToText AudioTextToSpeech AudioTremolo AudioWindSynthesizer AvatarAbilityRules AvatarAccessoryRules AvatarAnimationRules AvatarBodyRules AvatarClothingRules AvatarCollisionRules AvatarRules Backpack RemoteEvent UnreliableRemoteEvent WrapDeformer WrapLayer WrapTarget Beam BindableEvent BindableFunction BodyAngularVelocity BodyForce BodyGyro BodyPosition BodyThrust BodyVelocity RocketPropulsion BodyPartDescription Breakpoint BodyColors CharacterMesh Pants Shirt ShirtGraphic Skin ClickDetector DragDetector Clouds CompositeValueCurve Configuration AlignOrientation AlignPosition AngularVelocity AnimationConstraint BallSocketConstraint HingeConstraint LineForce LinearVelocity PlaneConstraint Plane RigidConstraint RodConstraint RopeConstraint CylindricalConstraint PrismaticConstraint SpringConstraint Torque TorsionSpringConstraint UniversalConstraint VectorForce ControlState HumanoidController SkateboardController VehicleController AirController ClimbController GroundController SwimController ControllerManager CustomEvent CustomEventReceiver CustomLog BlockMesh CylinderMesh FileMesh SpecialMesh DataStoreGetOptions DataStoreIncrementOptions DataStoreOptions DataStoreSetOptions DebuggerWatch Dialog DialogChoice DigitsRigDescription Dragger EulerRotationCurve ExperienceInviteOptions ExplorerFilter Explosion FaceControls Decal Texture Hole MotorFeature Fire FloatCurve FlyweightService CSGDictionaryService NonReplicatedCSGDictionaryService Folder GeneratedFolder ForceField FunctionalTest GetTextBoundsParams CanvasGroup Frame ImageButton TextButton ImageLabel TextLabel InputActionLabel RelativeGui ScrollingFrame TextBox TextChannelWindow VideoDisplay VideoFrame ViewportFrame BillboardGui ScreenGui GuiMain AdGui SurfaceGui FloorWire SelectionBox BoxHandleAdornment ConeHandleAdornment CylinderHandleAdornment ImageHandleAdornment LineHandleAdornment PyramidHandleAdornment SphereHandleAdornment WireframeHandleAdornment ParabolaAdornment SelectionSphere ArcHandles Handles SurfaceSelection SelectionPartLasso SelectionPointLasso Path2D HapticEffect HeightmapImporterService HiddenSurfaceRemovalAsset Highlight Humanoid HumanoidDescription HumanoidRigDescription IKControl InputAction InputBinding InputContext InternalSyncItem RotateP RotateV Glue ManualGlue ManualWeld Motor Motor6D Rotate Snap VelocityMotor Weld Keyframe KeyframeMarker PointLight SpotLight SurfaceLight LocalizationTable AuroraScript Script LocalScript ModuleScript MakeupDescription MarkerCurve MaterialVariant MemoryStoreService Message Hint NoCollisionConstraint Noise OperationGraph CornerWedgePart Part FlagStand Seat SkateboardPlatform SpawnLocation WedgePart MeshPart PartOperation IntersectOperation NegateOperation UnionOperation TrussPart VehicleSeat Camera ViewportCamera Model Actor HopperBin Tool Flag ProceduralModel WorldModel PartOperationAsset ParticleEmitter Path3D PathfindingLink PathfindingModifier Player PluginAction PluginCapabilities NumberPose Pose BloomEffect BlurEffect ColorCorrectionEffect ColorGradingEffect DepthOfFieldEffect SunRaysEffect ProximityPrompt ProximityPromptService RTAnimationTracker RealtimeMedia ReflectionMetadata ReflectionMetadataCallbacks ReflectionMetadataClasses ReflectionMetadataEnums ReflectionMetadataEvents ReflectionMetadataFunctions ReflectionMetadataClass ReflectionMetadataEnum ReflectionMetadataEnumItem ReflectionMetadataMember ReflectionMetadataProperties ReflectionMetadataYieldFunctions RemoteFunction RenderingTest RotationCurve AtmosphereSensor BuoyancySensor ControllerPartSensor FluidForceSensor Sky Smoke Sound ChorusSoundEffect CompressorSoundEffect DistortionSoundEffect EchoSoundEffect EqualizerSoundEffect FlangeSoundEffect PitchShiftSoundEffect ReverbSoundEffect TremoloSoundEffect SoundGroup Sparkles StandalonePluginScripts StarterGear StateMachineDefinition StateMachineTransitionDefinition StudioAttachment StudioCallout StyleRule StyleSheet StyleDerive StyleLink StyleQuery SurfaceAppearance Team TeleportOptions TerrainDetail TerrainRegion TestService TextChannel TextChatCommand TextChatMessageProperties BubbleChatMessageProperties TextDocument TextGenerator TrackerStreamAnimation Trail Tween UIAspectRatioConstraint UISizeConstraint UITextSizeConstraint UICorner UIDragDetector UIFlexItem UIGradient UIGridLayout UIListLayout UIPageLayout UITableLayout UIPadding UIScale UIShadow UIStroke BinaryStringValue BoolValue BrickColorValue CFrameValue Color3Value DoubleConstrainedValue IntConstrainedValue IntValue NumberValue ObjectValue RayValue StringValue Vector3Value ValueCurve Vector3Curve VideoDeviceInput VideoPlayer VirtualInputManager VisualizationMode VisualizationModeCategory WeldConstraint Wire WrapTextureTransfer"
API.SERVICES = "AccountService AchievementService ActivityHistoryEventService AdService AnalyticsService AnimatedImageService AnimationClipProvider AnimationFromVideoCreatorService AnimationFromVideoCreatorStudioService AnnotationsService AppAgeSignalsService AppLifecycleObserverService AppRatingPromptService AppUpdateService AssetCounterService AssetDeliveryProxy AssetImportService AssetManagerService AssetQualityService AssetService AudioFocusService AuroraScriptService AuroraService AvatarChatService AvatarCreationService AvatarEditorService AvatarImportService AvatarSettings BackendReplicatedStorage BackendServerScriptService BackendServerStorage BadgeService CoreGui StarterGui BranchService BrowserService BugReporterService BulkImportService CacheableContentProvider HSRDataContentProvider MeshContentProvider SlimContentProvider SolidModelContentProvider WrapContentProvider CallingService CalloutService CaptureService ChangeHistoryService ChangeHistoryStreamingService Chat ClientStorageService CloudCRUDService CloudExecutionService ClusterPacketCache CollaboratorsService CollectionService CommerceService ConfigService ConfigureServerService ConnectivityService ContentProvider ContextActionService ControllerService CookiesService CoreGuiConfiguration CorePackages CoreScriptDebuggingManagerHelper CoreScriptSyncService CreationDBService CreatorStoreService CrossDMScriptChangeListener DataStoreService Debris DebugSettings DebuggablePluginWatcher DebuggerConnectionManager DebuggerManager DebuggerUIService DeferredAssetManagerService DesignFoundationsService DeviceDisplayService DeviceIdService DraftsService DraggerService EditableService EditorSourceService EncodingService EventIngestService ExampleV2Service ExperienceAuthService ExperienceNotificationService ExperienceService ExperienceStateCaptureService ExperienceStateRecordingService ExplorerServiceVisibilityService ExternalIdentityService FaceAnimatorService FacialAgeEstimationService FacialAnimationRecordingService FacialAnimationStreamingServiceV2 FeatureRestrictionManager FileManagerService FileSyncReplicationService FlagStandService FlyweightService CSGDictionaryService NonReplicatedCSGDictionaryService FriendService GamePassService GameSettings GamepadService GenerationService GenericChallengeService Geometry GeometryService GongService GroupService GuiService GuidRegistryService HapticService HarmonyService HeapProfilerService HeatmapQueryService HeatmapService HeightmapImporterService Hopper HttpRbxApiService HttpService ILegacyStudioBridge LegacyStudioBridge IXPService ImageScreenCaptureService IncrementalPatchBuilder InsertService InstanceExtensionsService InstanceFileSyncService IntentService InternalMessagingService InternalMessagingServiceVerifier InternalSyncService JointsService KeyboardService KeyframeSequenceProvider LanguageService Lighting LinkingService LiveScriptingService LiveSyncService LocalStorageService AppStorageService UserStorageService LocalizationService LodDataService LogReporterService LogService LoginService LuaSettings LuaWebService LuauExpressionService LuauScriptAnalyzerService MLModelDeliveryService MLService MarketplaceService MatchmakingService MaterialGenerationService MaterialService MemStorageService MemoryStoreService MessageBusService MessagingService MetaBreakpointManager MicroProfilerService ModerationService MomentsService MouseService NetworkClient NetworkServer NetworkSettings NotificationService OmniRecommendationsService OpenCloudService Workspace PackageService PackageUIService Packages PartyEmulatorService PatchBundlerFileWatch PathfindingService PerformanceControlService PermissionsService PhysicsService PhysicsSettings PinShortcutService PlaceAssetIdsService PlaceStatsService PlacesService PlatformCloudStorageService PlatformFriendsService PlatformLibraries PlayerDataService PlayerEmulatorService PlayerHydrationService PlayerViewService Players PluginConnectionService PluginDebugService PluginGuiService PluginManagementService PluginPolicyService PointsService PolicyService PopLatencyService Preloaded ProceduralBehaviorSchedulerService ProcessInstancePhysicsService ProjectService ProximityPromptService PublishService QueueService RbxAnalyticsService RecommendationService ReflectionService RemoteCommandService RemoteCursorService RemoteDebuggerServer RenderSettings ReplicatedFirst ReplicatedStorage RequestOrchestratorService RibbonNotificationService RobloxPluginGuiService RobloxReplicatedStorage RobloxServerStorage RolloutValidationService RomarkRbxAnalyticsService RomarkService RtMessagingService RunService RuntimeContentService RuntimeScriptService SafetyService SceneAnalysisService ScriptChangeService ScriptCloneWatcher ScriptCloneWatcherHelper ScriptCommitService ScriptContext ScriptDebuggerService ScriptEditorService ScriptProfilerService ScriptRegistrationService ScriptScannerService ScriptService Selection SelectionHighlightManager SerializationService ServerScriptService ServerStorage ServiceVisibilityService SessionCheckService SessionService SharedTableRegistry SlimAnimationReplicationService SlimDebugSettings SlimReplicationService SlimService SmoothVoxelsUpgraderService SocialService SoundService SoundShimService SpawnerService StartPageService StarterPack StarterPlayer StartupMessageService Stats StopWatchReporter Studio StudioAssetService StudioCameraService StudioCaptureService StudioData StudioDeviceEmulatorService StudioDeviceSimulatorService StudioPublishService StudioScriptDebugEventListener StudioSdkService StudioService StudioTestService StudioUserService StudioWidgetsService StylingService SystemThemeService TaskScheduler TeamCreateData TeamCreatePublishService TeamCreateService Teams TelemetryService TeleportService TemporaryCageMeshProvider TemporaryScriptService TestService TextBoxService TextChatService TextService TextureGenerationService ThirdPartyUserService TimerService ToastNotificationService TouchInputService TraceRouteService TracerService TutorialService TweenService UGCAvatarService UGCValidationService UIDragDetectorService UniqueIdLookupService UnvalidatedAssetService UserGameSettings UserInputService UserService VRService VRStatusService VersionControlService VideoCaptureService VideoScreenCaptureService VideoService VirtualInputManager VirtualUser VisibilityCheckDispatcher Visit VisualizationModeService VoiceChatInternal VoiceChatService WebSocketService WebViewService WindowProtocolService WrapDeformMeshProvider"

buildMocks()
local MOCK_LINES = debug.info(1, "l") -- keep this the LAST line (the harness uses it to map line numbers)
