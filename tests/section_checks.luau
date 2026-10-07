local CHECKS_LINE1 = debug.info(1, "l") -- keep this on line 1 (used to map error line numbers)
--[[
	TOWER OF FOOD - section test harness   (tests/section_checks.luau)

	Runs after tests/mocks.luau (fake Roblox) and the TowerSections module.
	For every section in TowerSections.List it:
	  1. checks the metadata (Name, Creator, Difficulty, Height, Colors, Build)
	  2. builds it 14 times (different Seed / Rotation / BaseY) - any error = FAIL
	  3. counts parts (FAIL > 120 or < 15, WARN outside 25..70)
	  4. checks every part is Anchored
	  5. checks every part (and every moving part over its whole motion) stays
	     inside radius 24 and between y = 0 and y = Height
	  6. checks the keep-out zones above the entry plate and below the exit plate
	  7. checks the exit can be reached by jumping (rough physics), and that
	     there is a safe last platform near the exit plate (ARCHITECTURE rule 4)
	It prints "PASS <Name> ..." or "FAIL <Name>: ..." per section, then a summary,
	and errors at the end if anything failed (so check.sh exits non-zero).
]]

local fmt = string.format
local sqrt, abs, floor, huge = math.sqrt, math.abs, math.floor, math.huge
local PRIV = Mock.PRIV
local cfMul, cfInv, cfPoint = Mock.cfMul, Mock.cfInv, Mock.cfPoint

local K = {
	USABLE = 24, -- ARCHITECTURE section 2
	BOUND_TOL = 0.05,
	KEEP_R = 7.5,
	GRAVITY = 196.2,
	WALK = 16,
	JUMP_HEIGHT = 7.2,
	MAX_PARTS = 120,
	MIN_PARTS = 15,
	SPIN_SAMPLES = 120, -- poses per spin turn for bounds / keep-out
	REACH_SPIN = 24, -- poses per spin turn for reachability
}
K.V0 = sqrt(2 * K.GRAVITY * K.JUMP_HEIGHT)

local ANIM_TAGS = { "Spin", "Move", "Swing" }
local KNOWN_TAGS = { Kill = true, Spin = true, Move = true, Swing = true, Cycle = true, Melt = true, Bounce = true, Conveyor = true }
local DANGER = Color3.fromRGB(255, 45, 45)

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local U = {}

function U.n1(n: number): string
	if n ~= n then
		return "nan"
	end
	local s = fmt("%.1f", n)
	if s == "-0.0" then
		s = "0.0"
	end
	return s
end

function U.finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

-- "harness_run.luau:1234" -> "TowerSections.lua:345" (same numbers as the type checker)
function U.mapLine(L: number): string
	if L <= MOCK_LINES then
		return "tests/mocks.luau:" .. L
	elseif L < CHECKS_LINE1 then
		return "TowerSections.lua:" .. (L - MOCK_LINES - 3)
	end
	return "tests/section_checks.luau:" .. (L - CHECKS_LINE1 + 1)
end
function U.moduleLine(L: number): number?
	if L > MOCK_LINES and L < CHECKS_LINE1 then
		return L - MOCK_LINES - 3
	end
	return nil
end
function U.mapText(s: any): string
	return (string.gsub(tostring(s), "[^%s:\"'%[%]]*%.luau?:(%d+)", function(n)
		return U.mapLine(tonumber(n) :: number)
	end))
end

function U.data(inst)
	return Mock.data(inst)
end
function U.hasTag(inst, tag: string): boolean
	return U.data(inst).tags[tag] == true
end
function U.attr(inst, name: string)
	return U.data(inst).attrs[name]
end

------------------------------------------------------------------------
-- 2D geometry (x, z) used for footprints and keep-out
------------------------------------------------------------------------
local G2 = {}

-- convex hull (Andrew's monotone chain), points are { x, z }; returns CCW list
function G2.hull(pts)
	local n = #pts
	if n <= 1 then
		return pts
	end
	table.sort(pts, function(a, b)
		if a[1] == b[1] then
			return a[2] < b[2]
		end
		return a[1] < b[1]
	end)
	local function cross(o, a, b)
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local lower, upper = {}, {}
	for i = 1, n do
		local p = pts[i]
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 1e-12 do
			table.remove(lower)
		end
		table.insert(lower, p)
	end
	for i = n, 1, -1 do
		local p = pts[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 1e-12 do
			table.remove(upper)
		end
		table.insert(upper, p)
	end
	table.remove(lower)
	table.remove(upper)
	for _, p in ipairs(upper) do
		table.insert(lower, p)
	end
	if #lower == 0 then
		return { pts[1] }
	end
	return lower
end

-- distance from point (px, pz) to segment a-b, plus the closest point
function G2.pointSeg(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-18 then
		t = math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1)
	end
	local cx, cz = ax + dx * t, az + dz * t
	return sqrt((px - cx) ^ 2 + (pz - cz) ^ 2), cx, cz
end

function G2.inside(poly, x, z): boolean
	local n = #poly
	if n < 3 then
		return false
	end
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		if (b[1] - a[1]) * (z - a[2]) - (b[2] - a[2]) * (x - a[1]) < -1e-9 then
			return false
		end
	end
	return true
end

-- distance from point to convex polygon (0 if inside), plus closest point
function G2.pointPoly(poly, x, z)
	local n = #poly
	if n == 0 then
		return huge, x, z
	elseif n == 1 then
		return sqrt((poly[1][1] - x) ^ 2 + (poly[1][2] - z) ^ 2), poly[1][1], poly[1][2]
	end
	if G2.inside(poly, x, z) then
		return 0, x, z
	end
	local best, bx, bz = huge, x, z
	local last = (n == 2) and 1 or n
	for i = 1, last do
		local a, b = poly[i], poly[i % n + 1]
		local d, cx, cz = G2.pointSeg(x, z, a[1], a[2], b[1], b[2])
		if d < best then
			best, bx, bz = d, cx, cz
		end
	end
	return best, bx, bz
end

local function orient(ax, az, bx, bz, cx, cz)
	return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
end
function G2.segSeg(ax, az, bx, bz, cx, cz, dx, dz): number
	local o1, o2 = orient(ax, az, bx, bz, cx, cz), orient(ax, az, bx, bz, dx, dz)
	local o3, o4 = orient(cx, cz, dx, dz, ax, az), orient(cx, cz, dx, dz, bx, bz)
	if ((o1 > 0 and o2 < 0) or (o1 < 0 and o2 > 0)) and ((o3 > 0 and o4 < 0) or (o3 < 0 and o4 > 0)) then
		return 0
	end
	return math.min(
		(G2.pointSeg(ax, az, cx, cz, dx, dz)),
		(G2.pointSeg(bx, bz, cx, cz, dx, dz)),
		(G2.pointSeg(cx, cz, ax, az, bx, bz)),
		(G2.pointSeg(dx, dz, ax, az, bx, bz))
	)
end

-- distance between two convex polygons (0 if they overlap)
function G2.polyPoly(P, Q): number
	if #P >= 3 and G2.inside(P, Q[1][1], Q[1][2]) then
		return 0
	end
	if #Q >= 3 and G2.inside(Q, P[1][1], P[1][2]) then
		return 0
	end
	local best = huge
	local np, nq = #P, #Q
	local lp = (np <= 2) and 1 or np
	local lq = (nq <= 2) and 1 or nq
	for i = 1, lp do
		local a, b = P[i], P[i % np + 1]
		for j = 1, lq do
			local c, d = Q[j], Q[j % nq + 1]
			local dd = G2.segSeg(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2])
			if dd < best then
				best = dd
				if best == 0 then
					return 0
				end
			end
		end
	end
	return best
end

function G2.circle(r: number, n: number)
	local pts = {}
	local rr = r / math.cos(math.pi / n) -- circumscribed polygon
	for i = 0, n - 1 do
		local a = 2 * math.pi * i / n
		table.insert(pts, { rr * math.cos(a), rr * math.sin(a) })
	end
	return pts
end

function G2.box(poly)
	local a, b, c, d = huge, -huge, huge, -huge
	for _, p in ipairs(poly) do
		a, b = math.min(a, p[1]), math.max(b, p[1])
		c, d = math.min(c, p[2]), math.max(d, p[2])
	end
	return a, b, c, d
end

------------------------------------------------------------------------
-- 3D solids in section-local space
------------------------------------------------------------------------
local G3 = {}

local BOX_EDGES = { { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 }, { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }

-- what shape a part really is
function G3.kind(part): string
	local d = U.data(part)
	local cls = d.cls.Name
	if cls == "Part" then
		local sh = d.props.Shape
		local n = sh and sh.Name or "Block"
		if n == "Ball" then
			return "ball"
		elseif n == "Cylinder" then
			return "cylinder"
		elseif n == "Wedge" then
			return "wedge"
		elseif n == "CornerWedge" then
			return "cornerwedge"
		end
		return "box"
	elseif cls == "WedgePart" then
		return "wedge"
	elseif cls == "CornerWedgePart" then
		return "cornerwedge"
	elseif cls == "TrussPart" then
		return "truss"
	end
	return "box"
end

-- Solid = { verts = { {x,y,z}... }, edges = { {i,j}... } } or { ball = {x,y,z,r} }.
-- Wedges/trusses use their full box (a safe over-estimate). Cylinders use rings of n points
-- (scale > 1 makes the ring a circumscribed polygon so it never under-estimates).
function G3.solid(kind: string, c, size, ringN: number, ringScale: number)
	if kind == "ball" then
		local x, y, z = c[1], c[2], c[3]
		return { ball = { x, y, z, math.min(size[1], size[2], size[3]) / 2 } }
	end
	if kind == "cylinder" then
		local hl = size[1] / 2
		local r = math.min(size[2], size[3]) / 2 * ringScale
		local verts, edges = {}, {}
		for side = 1, 2 do
			local ex = (side == 1) and -hl or hl
			for i = 0, ringN - 1 do
				local a = 2 * math.pi * i / ringN
				local x, y, z = cfPoint(c, ex, r * math.cos(a), r * math.sin(a))
				table.insert(verts, { x, y, z })
			end
		end
		for i = 1, ringN do
			local j = i % ringN + 1
			table.insert(edges, { i, j })
			table.insert(edges, { ringN + i, ringN + j })
			table.insert(edges, { i, ringN + i })
		end
		return { verts = verts, edges = edges }
	end
	local hx, hy, hz = size[1] / 2, size[2] / 2, size[3] / 2
	local verts = {}
	for i = 0, 7 do
		local sx = (i % 2 == 1) and hx or -hx
		local sy = (floor(i / 2) % 2 == 1) and hy or -hy
		local sz = (floor(i / 4) % 2 == 1) and hz or -hz
		local x, y, z = cfPoint(c, sx, sy, sz)
		verts[i + 1] = { x, y, z }
	end
	return { verts = verts, edges = BOX_EDGES }
end

-- Same numbers as G3.extent(G3.solid(kind, c, size, 64, 1)) but without building tables (fast path
-- for the bounds check, which looks at every part in up to 120 spin poses).
local RING_N = 64
local RING_COS, RING_SIN = {}, {}
for i = 0, RING_N - 1 do
	RING_COS[i], RING_SIN[i] = math.cos(2 * math.pi * i / RING_N), math.sin(2 * math.pi * i / RING_N)
end
function G3.extentOf(kind: string, c, size)
	if kind == "ball" then
		local r = math.min(size[1], size[2], size[3]) / 2
		local rc = sqrt(c[1] * c[1] + c[3] * c[3])
		return rc + r, c[2] - r, c[2] + r, c[1] - r, c[1] + r, c[3] - r, c[3] + r
	end
	local maxR2, minY, maxY = 0, huge, -huge
	local x0, x1, z0, z1 = huge, -huge, huge, -huge
	if kind == "cylinder" then
		local hl = size[1] / 2
		local r = math.min(size[2], size[3]) / 2
		for side = -1, 1, 2 do
			local ex = side * hl
			for i = 0, RING_N - 1 do
				local x, y, z = cfPoint(c, ex, r * RING_COS[i], r * RING_SIN[i])
				local r2 = x * x + z * z
				if r2 > maxR2 then
					maxR2 = r2
				end
				if y < minY then
					minY = y
				end
				if y > maxY then
					maxY = y
				end
				if x < x0 then
					x0 = x
				end
				if x > x1 then
					x1 = x
				end
				if z < z0 then
					z0 = z
				end
				if z > z1 then
					z1 = z
				end
			end
		end
	else
		local hx, hy, hz = size[1] / 2, size[2] / 2, size[3] / 2
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local x, y, z = cfPoint(c, sx * hx, sy * hy, sz * hz)
					local r2 = x * x + z * z
					if r2 > maxR2 then
						maxR2 = r2
					end
					if y < minY then
						minY = y
					end
					if y > maxY then
						maxY = y
					end
					if x < x0 then
						x0 = x
					end
					if x > x1 then
						x1 = x
					end
					if z < z0 then
						z0 = z
					end
					if z > z1 then
						z1 = z
					end
				end
			end
		end
	end
	return sqrt(maxR2), minY, maxY, x0, x1, z0, z1
end

-- max horizontal radius, min y, max y, and an AABB of a solid
function G3.extent(s)
	if s.ball then
		local b = s.ball
		local rc = sqrt(b[1] * b[1] + b[3] * b[3])
		return rc + b[4], b[2] - b[4], b[2] + b[4], b[1] - b[4], b[1] + b[4], b[3] - b[4], b[3] + b[4]
	end
	local maxR, minY, maxY = 0, huge, -huge
	local x0, x1, z0, z1 = huge, -huge, huge, -huge
	for _, v in ipairs(s.verts) do
		local r = v[1] * v[1] + v[3] * v[3]
		if r > maxR then
			maxR = r
		end
		minY, maxY = math.min(minY, v[2]), math.max(maxY, v[2])
		x0, x1 = math.min(x0, v[1]), math.max(x1, v[1])
		z0, z1 = math.min(z0, v[3]), math.max(z1, v[3])
	end
	return sqrt(maxR), minY, maxY, x0, x1, z0, z1
end

-- Does the body swept between solids A and B (same part, two nearby poses) enter the
-- zone { horizontal radius < R, y0 < y < y1 }? Returns (radius, x, z) of the closest point or nil.
function G3.zoneHit(A, B, y0: number, y1: number, R: number)
	if A.ball then
		local a, b = A.ball, B.ball
		local dist = sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
		local steps = math.max(1, math.ceil(dist / 0.2))
		for i = 0, steps do
			local t = i / steps
			local cx, cy, cz, r = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4]
			local yy = math.clamp(cy, y0, y1)
			local dy = abs(yy - cy)
			if dy < r then
				local rho = sqrt(r * r - dy * dy)
				local rc = sqrt(cx * cx + cz * cz)
				local d = math.max(0, rc - rho)
				if d < R - 1e-6 then
					local k = (rc > 1e-9) and (d / rc) or 0
					return d, cx * k, cz * k, yy
				end
			end
		end
		return nil
	end
	local pts = {}
	local ysum, ycount = 0, 0
	local function addVert(v)
		if v[2] >= y0 and v[2] <= y1 then
			table.insert(pts, { v[1], v[3] })
			ysum, ycount = ysum + v[2], ycount + 1
		end
	end
	local function addSeg(p, q)
		for _, h in ipairs({ y0, y1 }) do
			if (p[2] - h) * (q[2] - h) < 0 then
				local t = (h - p[2]) / (q[2] - p[2])
				table.insert(pts, { p[1] + (q[1] - p[1]) * t, p[3] + (q[3] - p[3]) * t })
				ysum, ycount = ysum + h, ycount + 1
			end
		end
	end
	for _, v in ipairs(A.verts) do
		addVert(v)
	end
	for _, e in ipairs(A.edges) do
		addSeg(A.verts[e[1]], A.verts[e[2]])
	end
	if B ~= A then
		for _, v in ipairs(B.verts) do
			addVert(v)
		end
		for _, e in ipairs(B.edges) do
			addSeg(B.verts[e[1]], B.verts[e[2]])
		end
		for i, v in ipairs(A.verts) do
			addSeg(v, B.verts[i])
		end
	end
	if #pts == 0 then
		return nil
	end
	local hull = G2.hull(pts)
	local d, cx, cz = G2.pointPoly(hull, 0, 0)
	if d < R - 1e-6 then
		return d, cx, cz, ysum / ycount
	end
	return nil
end

-- The surface a player could stand on, for one pose: { poly = {{x,z}...}, lo, hi }
function G3.walkFace(kind: string, c, size)
	local hx, hy, hz = size[1] / 2, size[2] / 2, size[3] / 2
	local function corners(list)
		local poly, lo, hi = {}, huge, -huge
		for _, l in ipairs(list) do
			local x, y, z = cfPoint(c, l[1], l[2], l[3])
			table.insert(poly, { x, z })
			lo, hi = math.min(lo, y), math.max(hi, y)
		end
		return { poly = G2.hull(poly), lo = lo, hi = hi }
	end
	if kind == "ball" then
		local r = math.min(size[1], size[2], size[3]) / 2
		local top = c[2] + r
		local poly = {}
		for _, p in ipairs(G2.circle(r * 0.35, 8)) do
			table.insert(poly, { c[1] + p[1], c[3] + p[2] })
		end
		return { poly = poly, lo = top, hi = top }
	end
	if kind == "cylinder" then
		local r = math.min(size[2], size[3]) / 2
		local ax, ay, az = c[4], c[7], c[10] -- the cylinder's axis (local X column)
		if abs(ay) >= 0.7 then
			local sgn = (ay >= 0) and 1 or -1
			local tx, ty, tz = cfPoint(c, sgn * hx, 0, 0)
			local tilt = r * sqrt(math.max(0, 1 - ay * ay))
			local poly = {}
			for _, p in ipairs(G2.circle(r, 12)) do
				table.insert(poly, { tx + p[1], tz + p[2] })
			end
			return { poly = poly, lo = ty - tilt, hi = ty + tilt }
		end
		-- lying down: walk along the top line
		local ux, uy, uz = -ax * ay, 1 - ay * ay, -az * ay
		local um = sqrt(ux * ux + uy * uy + uz * uz)
		ux, uy, uz = ux / um * r, uy / um * r, uz / um * r
		local x1, y1, z1 = cfPoint(c, -hx, 0, 0)
		local x2, y2, z2 = cfPoint(c, hx, 0, 0)
		x1, y1, z1, x2, y2, z2 = x1 + ux, y1 + uy, z1 + uz, x2 + ux, y2 + uy, z2 + uz
		local dx, dz = x2 - x1, z2 - z1
		local dl = sqrt(dx * dx + dz * dz)
		local px, pz = 0, 0
		if dl > 1e-9 then
			px, pz = -dz / dl * r * 0.5, dx / dl * r * 0.5
		end
		local poly = G2.hull({ { x1 + px, z1 + pz }, { x1 - px, z1 - pz }, { x2 + px, z2 + pz }, { x2 - px, z2 - pz } })
		return { poly = poly, lo = math.min(y1, y2), hi = math.max(y1, y2) }
	end
	-- world-up component of each face normal (columns of the rotation)
	local nx, ny, nz = c[7], c[8], c[9]
	if kind == "wedge" then
		local sl = sqrt(hy * hy + hz * hz)
		local cands = {
			{ -ny, { { -hx, -hy, -hz }, { hx, -hy, -hz }, { -hx, -hy, hz }, { hx, -hy, hz } } }, -- bottom
			{ nz, { { -hx, -hy, hz }, { hx, -hy, hz }, { -hx, hy, hz }, { hx, hy, hz } } }, -- back
			{ nx, { { hx, -hy, -hz }, { hx, -hy, hz }, { hx, hy, hz } } }, -- right side
			{ -nx, { { -hx, -hy, -hz }, { -hx, -hy, hz }, { -hx, hy, hz } } }, -- left side
			{ (ny * hz - nz * hy) / sl, { { -hx, -hy, -hz }, { hx, -hy, -hz }, { -hx, hy, hz }, { hx, hy, hz } } }, -- slope
		}
		local best = cands[1]
		for _, cand in ipairs(cands) do
			if cand[1] > best[1] then
				best = cand
			end
		end
		return corners(best[2])
	end
	-- box / truss / corner wedge: the most upward-facing face
	local faces = {
		{ nx, 1, hx },
		{ -nx, 1, -hx },
		{ ny, 2, hy },
		{ -ny, 2, -hy },
		{ nz, 3, hz },
		{ -nz, 3, -hz },
	}
	local best = faces[1]
	for _, f in ipairs(faces) do
		if f[1] > best[1] then
			best = f
		end
	end
	local axis, value = best[2], best[3]
	local list = {}
	local h = { hx, hy, hz }
	local o1, o2 = (axis % 3) + 1, ((axis + 1) % 3) + 1
	for _, s1 in ipairs({ -1, 1 }) do
		for _, s2 in ipairs({ -1, 1 }) do
			local p = { 0, 0, 0 }
			p[axis] = value
			p[o1] = s1 * h[o1]
			p[o2] = s2 * h[o2]
			table.insert(list, p)
		end
	end
	return corners(list)
end

------------------------------------------------------------------------
-- Motion: every pose a part can be in (Spin / Move / Swing on it or an ancestor model)
------------------------------------------------------------------------
local Motion = {}

-- animated things affecting this part, innermost first: { {tag, inst}, ... }
function Motion.sources(part, sectionModel)
	local list = {}
	local cur = part
	while cur do
		local d = U.data(cur)
		for _, tag in ipairs(ANIM_TAGS) do
			if d.tags[tag] then
				table.insert(list, { tag = tag, inst = cur })
			end
		end
		if cur == sectionModel then
			break
		end
		cur = d.parent
	end
	return list
end

local function vecAttr(inst, name)
	local v = U.attr(inst, name)
	if typeof(v) == "Vector3" then
		return v
	end
	return Vector3.zero
end
local function numAttr(inst, name)
	local v = U.attr(inst, name)
	if type(v) == "number" then
		return v
	end
	return 0
end

-- list of world transforms for one animation source; mode = "bounds" or "reach"
function Motion.transforms(src, mode: string)
	local inst, tag = src.inst, src.tag
	local out = {}
	local closed = false
	local function rotAbout(px, py, pz, axis, ang)
		local R = Mock.axisAngle(axis.X, axis.Y, axis.Z, ang)
		return cfMul(cfMul(Mock.cf(px, py, pz, 1, 0, 0, 0, 1, 0, 0, 0, 1), R), Mock.cf(-px, -py, -pz, 1, 0, 0, 0, 1, 0, 0, 0, 1))
	end
	if tag == "Spin" then
		local speed = numAttr(inst, "SpinSpeed")
		local axis = vecAttr(inst, "SpinAxis")
		local base = inst:IsA("Model") and inst:GetPivot() or (U.data(inst).props.CFrame or CFrame.identity)
		if speed == 0 or not U.finite(speed) or axis.Magnitude < 1e-9 or axis.Magnitude ~= axis.Magnitude then
			return { CFrame.identity }, false
		end
		local n = (mode == "bounds") and K.SPIN_SAMPLES or K.REACH_SPIN
		for i = 0, n - 1 do
			table.insert(out, rotAbout(base.X, base.Y, base.Z, axis, 2 * math.pi * i / n))
		end
		closed = true
	elseif tag == "Swing" then
		local A = math.rad(abs(numAttr(inst, "SwingAngle")))
		local axis = vecAttr(inst, "SwingAxis")
		local p = vecAttr(inst, "SwingPivot")
		if A == 0 or not U.finite(A) or axis.Magnitude < 1e-9 or axis.Magnitude ~= axis.Magnitude then
			return { CFrame.identity }, false
		end
		local n = (mode == "bounds") and math.max(25, math.ceil(math.deg(2 * A) / 2) + 1) or 9
		for i = 0, n - 1 do
			table.insert(out, rotAbout(p.X, p.Y, p.Z, axis, -A + 2 * A * i / (n - 1)))
		end
	elseif tag == "Move" then
		local off = vecAttr(inst, "MoveOffset")
		local n = (mode == "bounds") and 2 or 5
		for i = 0, n - 1 do
			local s = i / (n - 1)
			table.insert(out, Mock.cf(off.X * s, off.Y * s, off.Z * s, 1, 0, 0, 0, 1, 0, 0, 0, 1))
		end
	end
	return out, closed
end

-- all local-space poses (CFrames) of a part, and whether they form a loop
function Motion.poses(part, info, mode: string)
	local base = U.data(part).props.CFrame or CFrame.identity
	local transforms, closed = { CFrame.identity }, false
	for _, src in ipairs(info.sources) do
		local list, cl = Motion.transforms(src, mode)
		if #info.sources > 1 then
			-- combined motions: thin out the samples so the grid stays small
			local thin = {}
			local step = math.max(1, floor(#list / 12))
			for i = 1, #list, step do
				table.insert(thin, list[i])
			end
			if thin[#thin] ~= list[#list] then
				table.insert(thin, list[#list])
			end
			list, cl = thin, false
		end
		local nextT = {}
		for _, outer in ipairs(list) do
			for _, inner in ipairs(transforms) do
				table.insert(nextT, cfMul(outer, inner))
			end
		end
		transforms, closed = nextT, cl and #info.sources == 1
	end
	local poses = {}
	for i, T in ipairs(transforms) do
		poses[i] = cfMul(info.originInv, cfMul(T, base))
	end
	return poses, closed
end

------------------------------------------------------------------------
-- Reachability (rough jump physics, see tests/README.md)
------------------------------------------------------------------------
local Reach = {}

function Reach.maxRise(v0: number): number
	return v0 * v0 / (2 * K.GRAVITY) - 0.7
end
-- how far you can travel sideways while landing dy higher (nil if you can't reach that height)
function Reach.maxGap(v0: number, dy: number, k: number): number?
	local disc = v0 * v0 - 2 * K.GRAVITY * dy
	if disc < 0 then
		return nil
	end
	local t = (v0 + sqrt(disc)) / K.GRAVITY
	return K.WALK * t * k + 1.5
end

function Reach.dist(A, B, limit: number): number
	if A.x0 - B.x1 > limit or B.x0 - A.x1 > limit or A.z0 - B.z1 > limit or B.z0 - A.z1 > limit then
		return huge
	end
	local best = huge
	for _, fa in ipairs(A.faces) do
		for _, fb in ipairs(B.faces) do
			-- cheap box test first: the polygons can't be closer than their boxes
			local dx = math.max(0, fb.x0 - fa.x1, fa.x0 - fb.x1)
			local dz = math.max(0, fb.z0 - fa.z1, fa.z0 - fb.z1)
			local boxD = sqrt(dx * dx + dz * dz)
			if boxD < best and (boxD <= limit or limit == huge) then
				local d = G2.polyPoly(fa.poly, fb.poly)
				if d < best then
					best = d
					if best <= limit then
						return best
					end
				end
			end
		end
	end
	return best
end

-- can a player standing on A get onto B? returns ok, and a reason text when not
function Reach.edge(A, B, k: number): (boolean, string?)
	local v0 = A.v0
	local maxRise = Reach.maxRise(v0)
	if B.truss then
		if A.hi >= B.lo - 4 and A.hi <= B.hi then
			local d = Reach.dist(A, B, 3)
			if d <= 3 then
				return true
			end
		end
		local dy = B.hi - A.hi
		if dy > maxRise then
			return false, fmt("ladder bottom y=%s is out of reach and its top is %s higher (max %s)", U.n1(B.lo), U.n1(dy), U.n1(maxRise))
		end
		local g = Reach.maxGap(v0, dy, k) :: number
		local d = Reach.dist(A, B, g)
		if d <= g then
			return true
		end
		return false, fmt("too far from the ladder: gap %s (need <= 3 to grab it)", U.n1(d))
	end
	local dy = B.lo - A.hi
	if dy > maxRise then
		return false, fmt("rise %s is higher than a jump (max %s)", U.n1(dy), U.n1(maxRise))
	end
	local g = Reach.maxGap(v0, dy, k) :: number
	local d = Reach.dist(A, B, g)
	if d <= g then
		return true
	end
	return false, fmt("gap %s is too wide for a rise of %s (max %s)", d == huge and ">" .. U.n1(g) or U.n1(d), U.n1(dy), U.n1(g))
end

function Reach.node(name: string, faces, extra)
	local node = extra or {}
	node.name = name
	node.faces = faces
	local lo, hi = huge, -huge
	local x0, x1, z0, z1 = huge, -huge, huge, -huge
	for _, f in ipairs(faces) do
		lo, hi = math.min(lo, f.lo), math.max(hi, f.hi)
		local a, b, c, d = G2.box(f.poly)
		f.x0, f.x1, f.z0, f.z1 = a, b, c, d
		x0, x1, z0, z1 = math.min(x0, a), math.max(x1, b), math.min(z0, c), math.max(z1, d)
	end
	node.lo = node.lo or lo
	node.hi = node.hi or hi
	node.x0, node.x1, node.z0, node.z1 = x0, x1, z0, z1
	node.v0 = node.v0 or K.V0
	return node
end

-- breadth-first search from the entry plate; returns result table
function Reach.run(nodes, height: number, difficulty: number)
	local k = (difficulty >= 3) and 0.95 or 0.8
	local start = Reach.node("entry plate", { { poly = G2.circle(6, 24), lo = 0, hi = 0 } })
	local goal = Reach.node("exit plate", { { poly = G2.circle(6, 24), lo = height, hi = height } })
	local all = { start }
	for _, n in ipairs(nodes) do
		table.insert(all, n)
	end
	table.insert(all, goal)
	local reached = { [start] = true }
	local queue = { start }
	local head = 1
	local goalReached = false
	while head <= #queue do
		local A = queue[head]
		head += 1
		for _, B in ipairs(all) do
			if not reached[B] and Reach.edge(A, B, k) then
				reached[B] = true
				B.from = A
				table.insert(queue, B)
				if B == goal then
					goalReached = true
				end
			end
		end
	end
	local highest, highestNode = 0, start
	for _, n in ipairs(all) do
		if reached[n] and n ~= goal and n.hi > highest then
			highest, highestNode = n.hi, n
		end
	end
	return { reached = reached, goalReached = goalReached, highest = goalReached and height or highest, highestNode = highestNode, all = all, goal = goal, start = start, k = k }
end

-- explain why the climb stops: the closest misses just above the highest reached point
function Reach.explain(res): { string }
	local lines = {}
	local hn = res.highestNode
	table.insert(lines, fmt("highest reachable surface: %s (top y=%s)", hn.name, U.n1(hn.hi)))
	local cands = {}
	for _, B in ipairs(res.all) do
		if not res.reached[B] and B.lo > res.highest - 1 then
			table.insert(cands, B)
		end
	end
	table.sort(cands, function(a, b)
		return a.lo < b.lo
	end)
	for i = 1, math.min(3, #cands) do
		local B = cands[i]
		local bestA, bestWhy, bestScore = nil, nil, huge
		for A in pairs(res.reached) do
			local ok, why = Reach.edge(A, B, res.k)
			if not ok then
				-- prefer tries that are only a little too high, then the closest ones
				local score = math.max(0, B.lo - A.hi - Reach.maxRise(A.v0)) * 2 + abs(math.min(0, B.lo - A.hi)) + Reach.dist(A, B, huge)
				if score < bestScore then
					bestA, bestWhy, bestScore = A, why, score
				end
			end
		end
		if bestA then
			table.insert(lines, fmt("next unreachable: %s (y=%s) - best try from %s (y=%s): %s", B.name, U.n1(B.lo), bestA.name, U.n1(bestA.hi), bestWhy or "?"))
		end
	end
	return lines
end

------------------------------------------------------------------------
-- ctx proxy: checks every ctx call's arguments and opts (catches opts typos like "Colour")
------------------------------------------------------------------------
local CtxCheck = {}

local CTX_SPEC = {
	CF = { "x:n", "y:n", "z:n", "yaw:n?" },
	Pos = { "x:n", "y:n", "z:n" },
	Polar = { "radius:n", "angleDeg:n" },
	Block = { "x:n", "y:n", "z:n", "sx:+", "sy:+", "sz:+", "opts:opts" },
	Platform = { "x:n", "y:n", "z:n", "sx:+", "sz:+", "opts:opts" },
	Disc = { "x:n", "y:n", "z:n", "diameter:+", "opts:opts" },
	Ball = { "x:n", "y:n", "z:n", "diameter:+", "opts:opts" },
	Cylinder = { "x:n", "y:n", "z:n", "length:+", "diameter:+", "opts:opts" },
	Beam = { "a:V3", "b:V3", "width:+", "thickness:+", "opts:opts" },
	Wedge = { "x:n", "y:n", "z:n", "sx:+", "sy:+", "sz:+", "opts:opts" },
	Truss = { "x:n", "y:n", "z:n", "height:+", "opts:opts" },
	Group = { "name:s", "x:n", "y:n", "z:n" },
	Kill = { "target:target", "keepLook:b?" },
	Spin = { "target:target", "degPerSec:n", "axis:V3?" },
	Move = { "target:target", "offset:V3", "period:+", "phase:n?" },
	Swing = { "target:target", "pivot:V3", "axis:V3", "amplitudeDeg:n", "period:+", "phase:n?" },
	Cycle = { "part:part", "mode:mode", "onTime:n0", "offTime:n0", "phase:n?" },
	Melt = { "part:part", "delay:n0?", "respawn:n0?" },
	Bounce = { "part:part", "power:+?" },
	Conveyor = { "part:part", "velocity:V3" },
	Slippery = { "part:part" },
	Random = { "min:n", "max:n" },
	RandomInt = { "min:n", "max:n" },
	Chance = { "p:n" },
}
local OPT_KINDS = {
	Yaw = "n", Pitch = "n", Roll = "n", Color = "Color3", Material = "Material", Name = "s",
	Transparency = "01", CanCollide = "b", Parent = "inst", Thickness = "+", Reflectance = "n", Round = "b",
}

local function checkValue(kind: string, v: any, sectionModel): string?
	local optional = string.sub(kind, -1) == "?"
	if optional then
		kind = string.sub(kind, 1, -2)
		if v == nil then
			return nil
		end
	end
	if kind == "n" or kind == "+" or kind == "n0" or kind == "01" then
		if type(v) ~= "number" then
			return "must be a number, got " .. typeof(v)
		end
		if not U.finite(v) then
			return "must be a real number, got " .. tostring(v)
		end
		if kind == "+" and v <= 0 then
			return "must be bigger than 0, got " .. tostring(v)
		end
		if kind == "n0" and v < 0 then
			return "must not be negative, got " .. tostring(v)
		end
		if kind == "01" and (v < 0 or v > 1) then
			return "must be between 0 and 1, got " .. tostring(v)
		end
	elseif kind == "s" then
		if type(v) ~= "string" then
			return "must be a string, got " .. typeof(v)
		end
	elseif kind == "b" then
		if type(v) ~= "boolean" then
			return "must be true/false, got " .. typeof(v)
		end
	elseif kind == "V3" then
		if typeof(v) ~= "Vector3" then
			return "must be a Vector3, got " .. typeof(v)
		end
		if not (U.finite(v.X) and U.finite(v.Y) and U.finite(v.Z)) then
			return "must not contain NaN/inf, got " .. tostring(v)
		end
	elseif kind == "Color3" then
		if typeof(v) ~= "Color3" then
			return "must be a Color3, got " .. typeof(v)
		end
	elseif kind == "Material" then
		if typeof(v) ~= "EnumItem" or tostring(v.EnumType) ~= "Material" then
			return "must be an Enum.Material item, got " .. tostring(v)
		end
	elseif kind == "mode" then
		if v ~= "Hazard" and v ~= "Vanish" then
			return "must be \"Hazard\" or \"Vanish\", got " .. tostring(v)
		end
	elseif kind == "inst" or kind == "target" or kind == "part" then
		if not Mock.isInstance(v) then
			return "must be an Instance, got " .. typeof(v)
		end
		if kind == "part" and not v:IsA("BasePart") then
			return "must be a BasePart, got a " .. v.ClassName
		end
		if kind == "target" and not (v:IsA("BasePart") or v:IsA("Model")) then
			return "must be a BasePart or a Model (from ctx:Group), got a " .. v.ClassName
		end
		if v ~= sectionModel and not v:IsDescendantOf(sectionModel) then
			return fmt("must belong to this section (it is %s)", v.Parent and Mock.fullName(v) or "not parented")
		end
	elseif kind == "opts" then
		if type(v) ~= "table" then
			return "must be a table of options, got " .. typeof(v)
		end
		for key, val in pairs(v) do
			local okind = OPT_KINDS[key]
			if not okind then
				local hint = ""
				for real in pairs(OPT_KINDS) do
					if type(key) == "string" and string.lower(real) == string.lower(key) then
						hint = " (did you mean " .. real .. "?)"
					end
				end
				if key == "Colour" then
					hint = " (did you mean Color?)"
				end
				return fmt("unknown option %q%s - allowed: Yaw Pitch Roll Color Material Name Transparency CanCollide Parent Thickness Reflectance Round", tostring(key), hint)
			end
			local e = checkValue(okind, val, sectionModel)
			if e then
				return "option " .. key .. " " .. e
			end
		end
	end
	return nil
end

function CtxCheck.wrap(real, sectionModel)
	local proxy = {}
	local cache = {}
	setmetatable(proxy, {
		__index = function(_, key)
			local cached = cache[key]
			if cached then
				return cached
			end
			local spec = CTX_SPEC[key]
			local member = real[key]
			if type(member) == "function" then
				local fn = function(self, ...)
					if self ~= proxy then
						error(fmt("call ctx:%s(...) with a colon, not ctx.%s(...)", tostring(key), tostring(key)), 2)
					end
					if spec then
						local n = select("#", ...)
						if n > #spec then
							error(fmt("ctx:%s got %d arguments but takes at most %d", key, n, #spec), 2)
						end
						for i, s in ipairs(spec) do
							local pname, kind = string.match(s, "^(%w+):(.+)$")
							if kind == "opts" then
								kind = "opts?"
							end
							local e = checkValue(kind :: string, (select(i, ...)), sectionModel)
							if e then
								error(fmt("ctx:%s argument #%d (%s) %s", key, i, pname :: string, e), 2)
							end
						end
					end
					return member(real, ...)
				end
				cache[key] = fn
				return fn
			end
			local v = rawget(real, key)
			if v ~= nil then
				return v
			end
			error(fmt("ctx has no member %q (see the Ctx API table in docs/ARCHITECTURE.md section 3.2)", tostring(key)), 2)
		end,
		__newindex = function(_, key)
			error(fmt("ctx.%s = ... : sections must not change ctx", tostring(key)), 2)
		end,
	})
	return proxy
end

------------------------------------------------------------------------
-- Checking one build
------------------------------------------------------------------------
local Check = {}

-- a short readable description of a part, in section-local coordinates
function Check.describe(part, info)
	local d = U.data(part)
	local c = d.props.CFrame or CFrame.identity
	local x, y, z = cfPoint(info.originInv, c[1], c[2], c[3])
	return fmt("%s %q #%d at local (%s, %s, %s)", d.cls.Name, d.props.Name, info.index[part] or 0, U.n1(x), U.n1(y), U.n1(z))
end

function Check.build(def, combo, report)
	local height = def.Height
	local root = Instance.new("Folder")
	root.Name = "Tower"
	root.Parent = workspace
	Mock.startBuildLog()
	local model
	local errInfo
	local wrapped = {
		Name = def.Name,
		Creator = def.Creator,
		Difficulty = def.Difficulty,
		Height = def.Height,
		Colors = def.Colors,
		Build = function(realCtx)
			return def.Build(CtxCheck.wrap(realCtx, realCtx.Model))
		end,
	}
	local ok = xpcall(function()
		model = TowerSections.Build(wrapped, { Parent = root, BaseY = combo.baseY, Rotation = combo.rot, Seed = combo.seed })
	end, function(e)
		errInfo = { msg = tostring(e), tb = debug.traceback() }
		return e
	end)
	local created, notes = Mock.buildLog()
	for _, n in ipairs(notes) do
		report.warn(n)
	end
	if not ok then
		Check.reportError(def, errInfo, report)
		root:Destroy()
		return nil
	end
	local stats = Check.model(def, combo, model, created, report)
	root:Destroy()
	return stats
end

function Check.reportError(def, errInfo, report)
	local msg = U.mapText(errInfo.msg)
	local lines = {}
	local buildLine = debug.info(def.Build, "l")
	local buildModuleLine = U.moduleLine(buildLine)
	local firstLine
	for line in string.gmatch(errInfo.tb, "[^\n]+") do
		local L = tonumber(string.match(line, "%.luau?:(%d+)"))
		if L and U.moduleLine(L) then
			table.insert(lines, "      at " .. U.mapLine(L))
			firstLine = firstLine or L
		end
	end
	local where = ""
	local errL = tonumber(string.match(errInfo.msg, "%.luau?:(%d+)"))
	local useL = (errL and U.moduleLine(errL)) and errL or firstLine
	if useL and buildModuleLine then
		local ml = U.moduleLine(useL) :: number
		if ml >= buildModuleLine then
			where = fmt(" [%d lines below this section's 'Build = function' line, which is TowerSections.lua:%d]", ml - buildModuleLine, buildModuleLine)
		end
	end
	report.fail("Build error: " .. msg .. where, lines)
end

function Check.model(def, combo, model, created, report)
	local height = def.Height
	local origin = CFrame.new(0, combo.baseY, 0) * CFrame.Angles(0, combo.rot, 0)
	local originInv = origin:Inverse()
	local all = Mock.descendants(model)
	local parts = {}
	local index = {}
	for _, inst in ipairs(all) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
			index[inst] = #parts
		end
	end
	local stats = { parts = #parts, reach = 0 }

	-- part count
	if #parts > K.MAX_PARTS then
		report.fail(fmt("too many parts: %d (max %d)", #parts, K.MAX_PARTS))
	elseif #parts < K.MIN_PARTS then
		report.fail(fmt("too few parts: %d (min %d) - make it look like its food!", #parts, K.MIN_PARTS))
	elseif #parts < 25 or #parts > 70 then
		report.warn(fmt("part count %d is outside the 25..70 sweet spot", #parts))
	end

	-- instances made during Build but not put inside the section
	for _, inst in ipairs(created) do
		local d = U.data(inst)
		if not d.destroyed and inst ~= model and not inst:IsDescendantOf(model) then
			if d.parent == nil then
				report.warn(fmt("%s %q was created but never parented (Parent = nil), so it does not appear", d.cls.Name, d.props.Name))
			else
				report.fail(fmt("%s %q was parented outside the section (%s) - put everything in the section model (default) or a ctx:Group", d.cls.Name, d.props.Name, Mock.fullName(inst)))
			end
		end
	end

	-- tags & attributes sanity
	local animated = {}
	for _, inst in ipairs({ model, table.unpack(all) }) do
		local d = U.data(inst)
		for _, tag in ipairs(d.tagOrder) do
			if not KNOWN_TAGS[tag] then
				report.warn(fmt("%s %q has unknown tag %q", d.cls.Name, d.props.Name, tag))
			end
		end
		local anim = d.tags.Spin or d.tags.Move or d.tags.Swing
		if anim then
			table.insert(animated, inst)
			if not (inst:IsA("BasePart") or inst:IsA("Model")) then
				report.fail(fmt("%s %q is animated but is not a BasePart or Model", d.cls.Name, d.props.Name))
			end
			if inst:IsA("Model") and U.attr(inst, "GroupPivot") == nil then
				report.warn(fmt("Model %q is animated but was not made with ctx:Group (its pivot will be the bounding-box centre)", d.props.Name))
			end
			if inst:IsA("Model") and #inst:GetDescendants() == 0 then
				report.warn(fmt("animated Model %q is empty", d.props.Name))
			end
		end
		if d.tags.Spin then
			local s = U.attr(inst, "SpinSpeed")
			if not U.finite(s) then
				report.fail(fmt("%q: SpinSpeed is %s", d.props.Name, tostring(s)))
			elseif abs(s) > 240 then
				report.warn(fmt("%q spins very fast (%s deg/s)", d.props.Name, U.n1(s)))
			end
			local a = U.attr(inst, "SpinAxis")
			if typeof(a) ~= "Vector3" or not U.finite(a.X) or not U.finite(a.Y) or not U.finite(a.Z) then
				report.fail(fmt("%q: SpinAxis is invalid (%s) - did you pass a zero axis?", d.props.Name, tostring(a)))
			end
		end
		if d.tags.Move then
			local p = U.attr(inst, "MovePeriod")
			local o = U.attr(inst, "MoveOffset")
			if not U.finite(p) or p <= 0 then
				report.fail(fmt("%q: MovePeriod must be > 0 (got %s)", d.props.Name, tostring(p)))
			elseif typeof(o) == "Vector3" and math.pi * o.Magnitude / p > 30 then
				report.warn(fmt("%q moves very fast (top speed %s studs/s)", d.props.Name, U.n1(math.pi * o.Magnitude / p)))
			end
		end
		if d.tags.Swing then
			local p = U.attr(inst, "SwingPeriod")
			if not U.finite(p) or p <= 0 then
				report.fail(fmt("%q: SwingPeriod must be > 0 (got %s)", d.props.Name, tostring(p)))
			end
			local a = U.attr(inst, "SwingAxis")
			if typeof(a) ~= "Vector3" or not U.finite(a.X) then
				report.fail(fmt("%q: SwingAxis is invalid (%s)", d.props.Name, tostring(a)))
			end
		end
		if d.tags.Cycle then
			local on, off = U.attr(inst, "CycleOn"), U.attr(inst, "CycleOff")
			if not (U.finite(on) and U.finite(off)) or on < 0 or off < 0 or on + off <= 0 then
				report.fail(fmt("%q: Cycle times must be >= 0 and not both 0 (on=%s off=%s)", d.props.Name, tostring(on), tostring(off)))
			end
		end
		if d.tags.Bounce then
			local p = U.attr(inst, "BouncePower")
			if not U.finite(p) or p <= 0 then
				report.fail(fmt("%q: BouncePower must be > 0 (got %s)", d.props.Name, tostring(p)))
			elseif p > 150 then
				report.warn(fmt("%q: BouncePower %s is huge (default 80)", d.props.Name, U.n1(p)))
			end
		end
		if d.tags.Conveyor then
			local v = U.attr(inst, "ConveyorVelocity")
			if typeof(v) ~= "Vector3" or not U.finite(v.X) then
				report.fail(fmt("%q: ConveyorVelocity is invalid", d.props.Name))
			elseif v.Magnitude > 40 then
				report.warn(fmt("%q: conveyor is very fast (%s studs/s)", d.props.Name, U.n1(v.Magnitude)))
			end
		end
	end
	-- animated things must not be inside other animated things
	for _, inst in ipairs(animated) do
		local cur = U.data(inst).parent
		while cur and cur ~= model.Parent do
			if table.find(animated, cur) then
				report.fail(fmt("animated %q is inside animated %q - animated groups must not be nested", inst.Name, cur.Name))
				break
			end
			cur = U.data(cur).parent
		end
	end

	-- per-part checks
	local info = { originInv = originInv, index = index }
	local colorCount, colorTotal, distinct = {}, 0, 0
	local nodes = {}
	local exitCandidates = 0
	local function zoneLabel(z)
		return z == 1 and "launch space above the entry plate (radius < 7.5, y 0..6)" or fmt("space around/below the exit plate (radius < 7.5, y %s..%s)", U.n1(height - 7), U.n1(height))
	end
	for _, part in ipairs(parts) do
		local d = U.data(part)
		local props = d.props
		local kind = G3.kind(part)
		local size = part.Size
		local c = props.CFrame or CFrame.identity
		info.sources = Motion.sources(part, model)
		local moving = #info.sources > 0
		local desc = Check.describe(part, info)
		local motionText = moving and (" while it " .. string.lower(info.sources[1].tag) .. "s") or ""
		if #info.sources > 1 then
			report.warn(fmt("%s has %d animations at once (%s + %s); how they combine depends on the client", desc, #info.sources, info.sources[1].tag, info.sources[2].tag))
		end

		-- broken numbers
		local bad = false
		for i = 1, 12 do
			if not U.finite(c[i]) then
				bad = true
			end
		end
		if bad or not (U.finite(size.X) and U.finite(size.Y) and U.finite(size.Z)) then
			report.fail(fmt("%s has a NaN/inf CFrame or Size (division by zero?)", desc))
			continue
		end
		if math.min(size.X, size.Y, size.Z) < 0.05 then
			report.warn(fmt("%s is tiny (Size %s)", desc, tostring(size)))
		end
		if props.Anchored ~= true then
			report.fail(fmt("%s is not Anchored", desc))
		end
		if kind == "cylinder" and abs(size.Y - size.Z) > 1e-6 then
			report.warn(fmt("%s is a cylinder with different Y and Z sizes (Roblox uses the smaller one)", desc))
		end
		local collidable = props.CanCollide ~= false
		local isKill, isCycle = d.tags.Kill == true, d.tags.Cycle == true
		local transparency = props.Transparency or 0
		if collidable and transparency >= 0.95 and not isCycle then
			report.warn(fmt("%s is invisible but solid (Transparency %s)", desc, U.n1(transparency)))
		end
		if isKill and not isCycle then
			-- colours are stored as 8-bit, so compare loosely
			local mat = props.Material
			local col = props.Color or Color3.new()
			local close = abs(col.R - DANGER.R) < 0.01 and abs(col.G - DANGER.G) < 0.01 and abs(col.B - DANGER.B) < 0.01
			if not (mat and mat.Name == "Neon" and close) then
				report.warn(fmt("%s is a Kill part without the default deadly look (Neon + Danger red), rule 6", desc))
			end
		end
		if not isKill and transparency < 0.95 then
			local col = props.Color or Color3.new()
			local key = col:ToHex()
			if not colorCount[key] then
				distinct += 1
			end
			colorCount[key] = (colorCount[key] or 0) + 1
			colorTotal += 1
		end

		-- bounds (whole motion)
		local poses, closed = Motion.poses(part, info, "bounds")
		local maxR, minY, maxY = 0, huge, -huge
		local bx0, bx1, bz0, bz1 = huge, -huge, huge, -huge
		for _, pose in ipairs(poses) do
			local r, y0, y1, x0, x1, z0, z1 = G3.extentOf(kind, pose, size)
			maxR, minY, maxY = math.max(maxR, r), math.min(minY, y0), math.max(maxY, y1)
			bx0, bx1, bz0, bz1 = math.min(bx0, x0), math.max(bx1, x1), math.min(bz0, z0), math.max(bz1, z1)
		end
		if maxR > K.USABLE + K.BOUND_TOL then
			report.fail(fmt("%s reaches radius %s%s (must stay within %d)", desc, U.n1(maxR), motionText, K.USABLE))
		end
		if minY < -K.BOUND_TOL then
			report.fail(fmt("%s goes below the section floor: lowest y=%s%s (must be >= 0)", desc, U.n1(minY), motionText))
		end
		if maxY > height + K.BOUND_TOL then
			report.fail(fmt("%s goes above the section top: highest y=%s%s (Height is %d)", desc, U.n1(maxY), motionText, height))
		end

		-- keep-out zones (solid or deadly things only)
		if collidable or isKill or isCycle then
			local zones = { { 0.05, 6 }, { height - 7, height - 0.05 } }
			local nearAxis = (bx0 < K.KEEP_R and bx1 > -K.KEEP_R and bz0 < K.KEEP_R and bz1 > -K.KEEP_R)
			for zi, zone in ipairs(zones) do
				if nearAxis and minY < zone[2] and maxY > zone[1] then
					-- (cylinders use circumscribed rings so curved parts are never under-estimated)
					local ks = {}
					for i, pose in ipairs(poses) do
						ks[i] = G3.solid(kind, pose, size, 32, 1 / math.cos(math.pi / 32))
					end
					local hit
					local n = #ks
					for i = 1, n do
						local j = i + 1
						if j > n then
							j = closed and 1 or i
						end
						local r, hx, hz, hy = G3.zoneHit(ks[i], ks[j], zone[1], zone[2], K.KEEP_R)
						if r then
							hit = { r, hx, hz, hy }
							break
						end
					end
					if hit then
						local what = isKill and "deadly " or (isCycle and "cycling " or "solid ")
						report.fail(fmt("%s is a %spart inside the keep-out %s: comes within radius %s at about (%s, %s, %s)%s", desc, what, zoneLabel(zi), U.n1(hit[1]), U.n1(hit[2]), U.n1(hit[4]), U.n1(hit[3]), motionText))
					end
				end
			end
		end

		-- standable surface for the reachability search
		if collidable and not isKill then
			local rposes = Motion.poses(part, info, "reach")
			local faces = {}
			for i, pose in ipairs(rposes) do
				faces[i] = G3.walkFace(kind, pose, size)
			end
			local lx, ly, lz = cfPoint(originInv, c[1], c[2], c[3])
			local node = Reach.node(fmt("%q #%d at (%s, %s, %s)", props.Name, index[part], U.n1(lx), U.n1(ly), U.n1(lz)), faces)
			if kind == "truss" and abs(c[8]) > 0.9 then
				node.truss = true
				node.lo = minY
				node.hi = maxY
			end
			if d.tags.Bounce then
				local p = U.attr(part, "BouncePower")
				if U.finite(p) and p > 0 then
					node.v0 = p
				end
			end
			node.hazard = isCycle and U.attr(part, "CycleMode") == "Hazard"
			table.insert(nodes, node)
			-- rule 4: a safe last platform near the exit plate
			if not node.hazard then
				for _, f in ipairs(faces) do
					local rr = G2.pointPoly(f.poly, 0, 0)
					if f.hi >= height - 4.5 - 0.1 and f.hi <= height - 1.5 + 0.1 and rr >= 7.0 - 0.05 and rr <= 10.5 + 0.1 then
						node.exitPad = true
						exitCandidates += 1
						break
					end
				end
			end
		end
	end

	-- looks: lots of one colour?
	if colorTotal >= 20 then
		local top, topKey = 0, ""
		for key, n in pairs(colorCount) do
			if n > top then
				top, topKey = n, key
			end
		end
		if distinct < 3 then
			report.warn(fmt("only %d different colours - use several colours per food object (rule 6)", distinct))
		elseif top / colorTotal > 0.75 then
			report.warn(fmt("%d%% of the parts are the same colour (#%s) - mix in more colours (rule 6)", floor(top / colorTotal * 100 + 0.5), topKey))
		end
	end

	-- reachability
	local res = Reach.run(nodes, height, def.Difficulty)
	stats.reach = res.highest
	if not res.goalReached then
		report.fail(fmt("the exit plate (y=%d) can't be reached by jumping - highest reachable surface is y=%s", height, U.n1(res.highest)), Reach.explain(res))
	end
	if exitCandidates == 0 then
		report.fail(fmt("no safe last platform near the exit: need a solid, non-deadly surface with top y in %s..%s whose nearest edge is 7.5..10.5 from the axis (rule 4)", U.n1(height - 4.5), U.n1(height - 1.5)))
	else
		local any = false
		for _, n in ipairs(nodes) do
			if n.exitPad and res.reached[n] then
				any = true
			end
		end
		if not any and res.goalReached then
			report.warn("the last platform near the exit (rule 4) exists but the search could not reach it")
		end
	end
	return stats
end

------------------------------------------------------------------------
-- Self-test of the fake Roblox maths (fails loudly if the mocks are wrong)
------------------------------------------------------------------------
local function selfTest(): number
	local fails = {}
	local count = 0
	local function ok(name: string, cond: any)
		count += 1
		if not cond then
			table.insert(fails, name)
		end
	end
	local function near(a: number, b: number, eps: number?): boolean
		return abs(a - b) <= (eps or 1e-6)
	end
	local function vnear(a, b, eps: number?): boolean
		return (a - b).Magnitude <= (eps or 1e-6)
	end
	local function cfnear(a, b, eps: number?): boolean
		local A, B = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			if not near(A[i], B[i], eps or 1e-6) then
				return false
			end
		end
		return true
	end
	local function errors(name: string, fn, needle: string?)
		local good, e = pcall(fn)
		ok(name, not good and (needle == nil or string.find(tostring(e), needle, 1, true) ~= nil))
	end
	local rad = math.rad
	local V = Vector3.new

	-- Vector3
	ok("v3 add", V(1, 2, 3) + V(4, 5, 6) == V(5, 7, 9))
	ok("v3 sub", V(1, 2, 3) - V(4, 5, 6) == V(-3, -3, -3))
	ok("v3 scalar mul both sides", V(1, 2, 3) * 2 == V(2, 4, 6) and 2 * V(1, 2, 3) == V(2, 4, 6))
	ok("v3 div", V(2, 4, 6) / 2 == V(1, 2, 3) and V(2, 4, 6) / V(2, 4, 3) == V(1, 1, 2))
	ok("v3 unm", -V(1, -2, 3) == V(-1, 2, -3))
	ok("v3 cross", V(1, 0, 0):Cross(V(0, 1, 0)) == V(0, 0, 1))
	ok("v3 dot", V(1, 2, 3):Dot(V(4, 5, 6)) == 32)
	ok("v3 magnitude/unit", near(V(3, 4, 0).Magnitude, 5) and vnear(V(3, 4, 0).Unit, V(0.6, 0.8, 0)))
	ok("v3 lerp", V(0, 0, 0):Lerp(V(10, 20, 30), 0.5) == V(5, 10, 15))
	ok("v3 min/max/abs", V(1, 5, 3):Min(V(2, 4, 6)) == V(1, 4, 3) and V(1, 5, 3):Max(V(2, 4, 6)) == V(2, 5, 6) and V(-1, 2, -3):Abs() == V(1, 2, 3))
	ok("v3 fuzzy", V(1, 2, 3):FuzzyEq(V(1, 2, 3 + 1e-7)) and not V(1, 2, 3):FuzzyEq(V(1, 2, 3.1)))
	ok("v3 constants", Vector3.zero == V(0, 0, 0) and Vector3.one == V(1, 1, 1) and Vector3.yAxis == V(0, 1, 0))
	ok("v3 defaults", V() == Vector3.zero and V(1) == V(1, 0, 0))
	ok("v3 tostring", tostring(V(1, 2.5, -3)) == "1, 2.5, -3")
	errors("v3 read-only", function()
		local v = V(1, 2, 3);
		(v :: any).X = 5
	end)
	errors("v3 + number", function()
		return (V(1, 2, 3) :: any) + 1
	end)
	errors("v3 bad member", function()
		return (V() :: any).Magnitud
	end)

	-- CFrame basics
	local I = CFrame.new()
	ok("cf identity vectors", I.LookVector == V(0, 0, -1) and I.RightVector == V(1, 0, 0) and I.UpVector == V(0, 1, 0))
	ok("cf.Angles Y90 * X = -Z", vnear(CFrame.Angles(0, rad(90), 0) * V(1, 0, 0), V(0, 0, -1)))
	ok("cf.Angles X90 * Y = Z", vnear(CFrame.Angles(rad(90), 0, 0) * V(0, 1, 0), V(0, 0, 1)))
	ok("cf.Angles Z90 * X = Y", vnear(CFrame.Angles(0, 0, rad(90)) * V(1, 0, 0), V(0, 1, 0)))
	local a, b, c = 0.3, -0.7, 1.1
	ok("Angles = Rx*Ry*Rz", cfnear(CFrame.Angles(a, b, c), CFrame.Angles(a, 0, 0) * CFrame.Angles(0, b, 0) * CFrame.Angles(0, 0, c)))
	ok("fromEulerAnglesXYZ = Angles", cfnear(CFrame.fromEulerAnglesXYZ(a, b, c), CFrame.Angles(a, b, c)))
	ok("YXZ = Ry*Rx*Rz", cfnear(CFrame.fromEulerAnglesYXZ(a, b, c), CFrame.Angles(0, b, 0) * CFrame.Angles(a, 0, 0) * CFrame.Angles(0, 0, c)))
	ok("fromOrientation = YXZ", cfnear(CFrame.fromOrientation(a, b, c), CFrame.fromEulerAnglesYXZ(a, b, c)))
	local ex, ey, ez = CFrame.Angles(a, b, c):ToEulerAnglesXYZ()
	ok("ToEulerAnglesXYZ round trip", near(ex, a) and near(ey, b) and near(ez, c))
	local ox, oy, oz = CFrame.fromOrientation(a, b, c):ToOrientation()
	ok("ToOrientation round trip", near(ox, a) and near(oy, b) and near(oz, c))
	ok("fromAxisAngle Y = Angles Y", cfnear(CFrame.fromAxisAngle(V(0, 1, 0), 0.8), CFrame.Angles(0, 0.8, 0)))
	ok("fromAxisAngle X = Angles X", cfnear(CFrame.fromAxisAngle(V(2, 0, 0), -0.4), CFrame.Angles(-0.4, 0, 0)))
	local axis = V(1, 2, 3).Unit
	ok("fromAxisAngle keeps its axis", vnear(CFrame.fromAxisAngle(axis, 1.3) * axis, axis))
	local cf1 = CFrame.new(1, 2, 3) * CFrame.Angles(0.4, 1.2, -0.5)
	local cf2 = CFrame.new(-4, 0.5, 9) * CFrame.Angles(-1, 0.2, 2.5)
	local p = V(0.3, -2, 7)
	ok("cf * cf * v associative", vnear((cf1 * cf2) * p, cf1 * (cf2 * p)))
	ok("cf inverse round trip", cfnear(cf1 * cf1:Inverse(), I) and vnear(cf1:Inverse() * (cf1 * p), p))
	ok("PointToObjectSpace(PointToWorldSpace)", vnear(cf1:PointToObjectSpace(cf1:PointToWorldSpace(p)), p))
	ok("PointToWorldSpace = cf * v", vnear(cf1:PointToWorldSpace(p), cf1 * p))
	ok("ToObjectSpace = inv * cf", cfnear(cf1:ToObjectSpace(cf2), cf1:Inverse() * cf2))
	ok("ToWorldSpace = cf * cf", cfnear(cf1:ToWorldSpace(cf2), cf1 * cf2))
	ok("VectorToWorldSpace ignores position", vnear(cf1:VectorToWorldSpace(p), (cf1 - cf1.Position) * p) and vnear(cf1:VectorToObjectSpace(cf1:VectorToWorldSpace(p)), p))
	ok("cf + v / cf - v", (CFrame.new(1, 2, 3) + V(1, 1, 1)).Position == V(2, 3, 4) and (CFrame.new(1, 2, 3) - V(1, 1, 1)).Position == V(0, 1, 2))
	ok("cf X/Y/Z", CFrame.new(1, 2, 3).X == 1 and CFrame.new(1, 2, 3).Y == 2 and CFrame.new(1, 2, 3).Z == 3)
	local comps = { CFrame.new(1, 2, 3):GetComponents() }
	ok("GetComponents", #comps == 12 and comps[1] == 1 and comps[4] == 1 and comps[8] == 1 and comps[12] == 1 and comps[5] == 0)
	ok("12-number constructor", cfnear(CFrame.new(cf1:GetComponents()), cf1))
	local th = 0.9
	ok("quaternion constructor", cfnear(CFrame.new(0, 0, 0, 0, math.sin(th / 2), 0, math.cos(th / 2)), CFrame.Angles(0, th, 0)))
	local at, target = V(1, 2, 3), V(-4, 6, 10)
	local la = CFrame.lookAt(at, target)
	ok("lookAt LookVector points at target", vnear(la.LookVector, (target - at).Unit) and la.Position == at)
	ok("lookAt is upright", near(la.RightVector.Y, 0) and la.UpVector.Y > 0)
	ok("lookAt +X: right = +Z", vnear(CFrame.lookAt(V(), V(10, 0, 0)).RightVector, V(0, 0, 1)))
	ok("CFrame.new(pos, lookAt) = lookAt", cfnear(CFrame.new(at, target), la))
	ok("lookAt straight up is valid", vnear(CFrame.lookAt(V(), V(0, 5, 0)).LookVector, V(0, 1, 0)))
	ok("rotation is orthonormal", near(la.RightVector:Dot(la.UpVector), 0) and near(la.RightVector:Cross(la.UpVector):Dot(-la.LookVector), 1))
	ok("XVector is the first row", vnear(cf1.XVector, V(cf1.RightVector.X, cf1.UpVector.X, -cf1.LookVector.X)))
	local fm = CFrame.fromMatrix(V(1, 1, 1), V(0, 0, -1), V(0, 1, 0))
	-- Z column = X cross Y = (0,0,-1) x (0,1,0) = (1,0,0), so LookVector (-Z) = (-1,0,0)
	ok("fromMatrix columns", vnear(fm.RightVector, V(0, 0, -1)) and vnear(fm.UpVector, V(0, 1, 0)) and vnear(fm.LookVector, V(-1, 0, 0)) and fm.Position == V(1, 1, 1))
	ok("Lerp ends", cfnear(cf1:Lerp(cf2, 0), cf1) and cfnear(cf1:Lerp(cf2, 1), cf2))
	ok("Lerp half rotation", cfnear(CFrame.new():Lerp(CFrame.Angles(0, 1, 0), 0.5), CFrame.Angles(0, 0.5, 0)))
	ok("Rotation property", cfnear(cf1.Rotation, cf1 - cf1.Position))
	ok("CFrame.identity", CFrame.identity == CFrame.new())
	errors("cf read-only", function()
		(cf1 :: any).Position = V()
	end)
	errors("cf bad member", function()
		return (cf1 :: any).LookVectr
	end)
	errors("CFrame.Angels typo", function()
		return (CFrame :: any).Angels(0, 0, 0)
	end)

	-- Color3
	local col = Color3.fromRGB(255, 128, 0)
	ok("fromRGB", near(col.R, 1) and near(col.G, 128 / 255) and near(col.B, 0))
	ok("fromHex", Color3.fromHex("#FF8000") == col and Color3.fromHex("ff8000") == col)
	ok("ToHex", col:ToHex() == "FF8000")
	ok("fromHSV", Color3.fromHSV(0, 1, 1) == Color3.new(1, 0, 0) and Color3.fromHSV(1 / 3, 1, 1):ToHex() == "00FF00")
	ok("Color3 Lerp", Color3.new(0, 0, 0):Lerp(Color3.new(1, 1, 1), 0.5) == Color3.new(0.5, 0.5, 0.5))
	errors("Color3 read-only", function()
		(col :: any).R = 0
	end)

	-- Random
	local r1, r2 = Random.new(42), Random.new(42)
	local same, inRange, seen = true, true, {}
	for _ = 1, 2000 do
		local x, y = r1:NextNumber(), r2:NextNumber()
		if x ~= y then
			same = false
		end
		local n = r1:NextInteger(1, 6)
		r2:NextInteger(1, 6)
		seen[n] = true
		if n < 1 or n > 6 or x < 0 or x >= 1 then
			inRange = false
		end
		local z = r1:NextNumber(2, 3)
		r2:NextNumber(2, 3)
		if z < 2 or z > 3 then
			inRange = false
		end
	end
	ok("Random deterministic", same)
	ok("Random ranges", inRange and seen[1] and seen[6])
	ok("Random different seeds differ", Random.new(1):NextNumber() ~= Random.new(2):NextNumber())
	errors("NextInteger empty interval", function()
		return Random.new(1):NextInteger(5, 1)
	end)

	-- Enum
	ok("Enum item", Enum.Material.Neon.Name == "Neon" and typeof(Enum.Material.Neon) == "EnumItem" and Enum.Material.Neon == Enum.Material.Neon)
	errors("Enum item typo", function()
		return (Enum.Material :: any).Neonn
	end, "Neonn")
	errors("Enum typo", function()
		return (Enum :: any).Materal
	end, "Materal")

	-- Instances
	local part = Instance.new("Part")
	ok("part defaults", part.Anchored == false and part.CanCollide == true and part.Size == V(4, 1, 2) and part.Name == "Part" and part.ClassName == "Part")
	ok("IsA", part:IsA("BasePart") and part:IsA("Instance") and part:IsA("Part") and not part:IsA("Model"))
	ok("WedgePart is a BasePart", Instance.new("WedgePart"):IsA("BasePart") and Instance.new("TrussPart"):IsA("BasePart") and Instance.new("CornerWedgePart"):IsA("BasePart"))
	ok("typeof Instance", typeof(part) == "Instance")
	errors("unknown property write", function()
		(part :: any).Colour = Color3.new()
	end, "Colour is not a valid member")
	errors("unknown property read", function()
		return (part :: any).Colr
	end, "Colr")
	errors("nil Color", function()
		(part :: any).Color = nil
	end, "Color3 expected, got nil")
	errors("wrong type", function()
		(part :: any).Size = 5
	end, "Vector3 expected")
	errors("read-only property", function()
		(part :: any).ClassName = "X"
	end)
	errors("bad enum value", function()
		(part :: any).Material = Enum.PartType.Ball
	end)
	part.Material = "Neon" :: any -- Roblox converts enum names
	ok("enum by name", part.Material == Enum.Material.Neon)
	part.CFrame = CFrame.new(1, 2, 3) * CFrame.fromOrientation(rad(10), rad(20), rad(30))
	ok("Orientation from CFrame", vnear(part.Orientation, V(10, 20, 30), 1e-4))
	part.Position = V(5, 6, 7)
	ok("Position keeps rotation", vnear(part.Orientation, V(10, 20, 30), 1e-4) and part.CFrame.Position == V(5, 6, 7))
	part.Shape = Enum.PartType.Ball
	ok("Ball forces round size", part.Size.X == part.Size.Y and part.Size.Y == part.Size.Z)
	errors("Shape on WedgePart", function()
		(Instance.new("WedgePart") :: any).Shape = Enum.PartType.Ball
	end)
	errors("attribute table", function()
		part:SetAttribute("Bad", {} :: any)
	end)
	errors("attribute instance", function()
		part:SetAttribute("Bad", part :: any)
	end)
	part:SetAttribute("Good", V(1, 2, 3))
	part:SetAttribute("Pivot", CFrame.new())
	ok("attributes", part:GetAttribute("Good") == V(1, 2, 3) and part:GetAttributes().Pivot ~= nil and part:GetAttribute("Missing") == nil)
	errors("unknown class", function()
		Instance.new("Prat")
	end)
	errors("events are blocked", function()
		part.Touched:Connect(function() end)
	end)
	local m = Instance.new("Model")
	local f = Instance.new("Folder")
	f.Parent = m
	part.Parent = f
	ok("hierarchy", part:IsDescendantOf(m) and m:FindFirstChild("Folder") == f and m:FindFirstChild("Part", true) == part and #m:GetDescendants() == 2 and m:FindFirstChildWhichIsA("BasePart", true) == part and f:FindFirstChildOfClass("Part") == part)
	ok("child by name", (m :: any).Folder == f)
	errors("circular parent", function()
		m.Parent = part
	end)
	local cs = game:GetService("CollectionService")
	cs:AddTag(part, "Kill")
	ok("tags", part:HasTag("Kill") and cs:HasTag(part, "Kill") and #cs:GetTagged("Kill") == 0)
	m.Parent = workspace
	ok("GetTagged only in DataModel", #cs:GetTagged("Kill") == 1)
	local p2 = Instance.new("Part")
	p2.CFrame = CFrame.new(10, 0, 0)
	p2.Parent = m
	m.WorldPivot = CFrame.new(10, 0, 0)
	m:PivotTo(CFrame.new(10, 5, 0) * CFrame.Angles(0, rad(90), 0))
	ok("Model PivotTo moves parts", vnear(p2.Position, V(10, 5, 0)) and vnear(m:GetPivot().Position, V(10, 5, 0)))
	m:Destroy()
	ok("Destroy", part.Parent == nil and not part:IsDescendantOf(workspace) and #cs:GetTagged("Kill") == 0)
	errors("parent locked after Destroy", function()
		m.Parent = workspace
	end, "locked")
	local t = Instance.new("TrussPart")
	ok("truss default size", t.Size == V(2, 2, 2))

	-- the real toolkit + the harness geometry agree
	local probe = {
		Name = "Probe",
		Creator = "Harness",
		Difficulty = 1,
		Height = 30,
		Colors = { Main = Color3.new(1, 0, 0), Accent = Color3.new(0, 1, 0) },
		Build = function(ctx)
			ctx:Platform(10, 5, 0, 4, 6, { Name = "Plat" })
			ctx:Disc(-10, 7, 0, 6, { Name = "Disc" })
			ctx:Block(0, 15, 12, 2, 2, 2, { Name = "Block", Yaw = 45 })
			ctx:Truss(0, 2, -12, 7, { Name = "Truss" })
			ctx:Beam(V(12, 10, 0), V(18, 10, 0), 2, 1, { Name = "Beam" })
			ctx:Ball(0, 20, -15, 4, { Name = "Ball" })
			local g = ctx:Group("Spinner", 15, 25, 0)
			ctx:Block(20, 25, 0, 2, 1, 2, { Name = "Arm", Parent = g })
			ctx:Spin(g, 30)
		end,
	}
	local root = Instance.new("Folder")
	root.Parent = workspace
	local rot = rad(70)
	local model = TowerSections.Build(probe, { Parent = root, BaseY = 100, Rotation = rot, Seed = 1 })
	local originInv = (CFrame.new(0, 100, 0) * CFrame.Angles(0, rot, 0)):Inverse()
	local function faceOf(name)
		local pt = model:FindFirstChild(name, true) :: BasePart
		local pose = originInv * pt.CFrame
		return G3.walkFace(G3.kind(pt), pose, pt.Size), pt, pose
	end
	local fPlat = faceOf("Plat")
	ok("Platform top at y", near(fPlat.hi, 5) and near(fPlat.lo, 5))
	local fx0, fx1, fz0, fz1 = G2.box(fPlat.poly)
	ok("Platform footprint", near(fx0, 8) and near(fx1, 12) and near(fz0, -3) and near(fz1, 3))
	local fDisc, disc, discPose = faceOf("Disc")
	ok("Disc top at y", near(fDisc.hi, 7) and G3.kind(disc) == "cylinder")
	local dr, dlo, dhi = G3.extent(G3.solid("cylinder", discPose, disc.Size, 64, 1))
	ok("Disc extent", near(dr, 13, 1e-3) and near(dlo, 6) and near(dhi, 7))
	local fTruss, _, trussPose = faceOf("Truss")
	local tr, tlo, thi = G3.extent(G3.solid("truss", trussPose, (model:FindFirstChild("Truss", true) :: BasePart).Size, 8, 1))
	ok("Truss bottom at y, height rounded up to 8", near(tlo, 2) and near(thi, 10) and near(fTruss.hi, 10))
	local fBeam = faceOf("Beam")
	local bx0, bx1 = G2.box(fBeam.poly)
	ok("Beam runs from a to b", near(bx0, 12) and near(bx1, 18) and near(fBeam.hi, 10.5))
	local _, ball, ballPose = faceOf("Ball")
	local br, blo, bhi = G3.extent(G3.solid("ball", ballPose, ball.Size, 8, 1))
	ok("Ball extent", near(br, 17) and near(blo, 18) and near(bhi, 22))
	local fBlock = faceOf("Block")
	local kx0, kx1 = G2.box(fBlock.poly)
	ok("Yawed block footprint is a diamond", near(kx1 - kx0, 2 * sqrt(2), 1e-6) and near(fBlock.hi, 16))
	-- spinning arm sweeps a full circle around the group pivot (radius 5 + corner)
	local arm = model:FindFirstChild("Arm", true) :: BasePart
	local armInfo = { originInv = originInv, index = {}, sources = Motion.sources(arm, model) }
	ok("Spin source found", #armInfo.sources == 1 and armInfo.sources[1].tag == "Spin")
	local poses, closed = Motion.poses(arm, armInfo, "bounds")
	local maxX, minX = -huge, huge
	for _, pose in ipairs(poses) do
		local _, _, _, x0, x1 = G3.extent(G3.solid("box", pose, arm.Size, 8, 1))
		maxX, minX = math.max(maxX, x1), math.min(minX, x0)
	end
	ok("Spin envelope", closed and #poses == K.SPIN_SAMPLES and near(maxX, 15 + sqrt(6 * 6 + 1), 0.01) and near(minX, 15 - sqrt(6 * 6 + 1), 0.01))
	-- the fast extent agrees with the full solid
	local agree = true
	local odd = CFrame.new(3, 7, -9) * CFrame.Angles(0.3, 1.1, -0.6)
	for _, kind in ipairs({ "box", "cylinder", "ball", "wedge" }) do
		local A = { G3.extentOf(kind, odd, V(3, 2, 5)) }
		local B = { G3.extent(G3.solid(kind, odd, V(3, 2, 5), 64, 1)) }
		for j = 1, 7 do
			if not near(A[j], B[j], 1e-9) then
				agree = false
			end
		end
	end
	ok("extentOf = extent(solid)", agree)
	-- keep-out maths
	local slab = G3.solid("box", CFrame.new(0, 3, 0), V(2, 1, 2), 8, 1)
	ok("zoneHit inside", G3.zoneHit(slab, slab, 0.05, 6, 7.5) ~= nil)
	local farSlab = G3.solid("box", CFrame.new(12, 3, 0), V(2, 1, 2), 8, 1)
	ok("zoneHit outside", G3.zoneHit(farSlab, farSlab, 0.05, 6, 7.5) == nil)
	local passing = G3.solid("box", CFrame.new(-20, 3, 0), V(1, 1, 1), 8, 1)
	local passed = G3.solid("box", CFrame.new(20, 3, 0), V(1, 1, 1), 8, 1)
	ok("zoneHit swept move", G3.zoneHit(passing, passed, 0.05, 6, 7.5) ~= nil)
	local bigFloor = G3.solid("box", CFrame.new(0, 3, 0), V(40, 1, 40), 8, 1)
	ok("zoneHit huge slab covering the zone", G3.zoneHit(bigFloor, bigFloor, 0.05, 6, 7.5) ~= nil)
	-- jump physics
	ok("jump v0", near(K.V0, 53.15, 0.01) and near(Reach.maxRise(K.V0), 6.5, 1e-6))
	ok("flat jump gap", near(Reach.maxGap(K.V0, 0, 0.8) :: number, 16 * (2 * K.V0 / K.GRAVITY) * 0.8 + 1.5, 1e-9))
	root:Destroy()

	if #fails > 0 then
		print("MOCK SELF-TEST FAILED (" .. #fails .. " of " .. count .. "):")
		for _, n in ipairs(fails) do
			print("   - " .. n)
		end
		error("mock self-test failed - the harness can't be trusted, fix tests/mocks.luau first")
	end
	return count
end

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------
local COMBOS = {}
do
	local rots = { 0, 90, 180, 270, 37, 123, 200, 311, 45, 135, 225, 315 }
	local seeds = { 1, 2, 3, 4, 5, 6, 7, 8, 42, 99, 1234, 2026 }
	for i = 1, #rots do
		table.insert(COMBOS, { seed = seeds[i], rot = math.rad(rots[i]), rotDeg = rots[i], baseY = 100 })
	end
	table.insert(COMBOS, { seed = 11, rot = math.rad(10), rotDeg = 10, baseY = 12 })
	table.insert(COMBOS, { seed = 12, rot = math.rad(250), rotDeg = 250, baseY = 300 })
end

local function checkMeta(def, index: number, names, report): boolean
	if type(def) ~= "table" then
		report.fail(fmt("TowerSections.List[%d] is a %s, not a section table", index, typeof(def)))
		return false
	end
	local fatal = false
	local ALLOWED = { Name = true, Creator = true, Difficulty = true, Height = true, Colors = true, Build = true }
	for k in pairs(def) do
		if not ALLOWED[k] then
			report.warn(fmt("unknown field %q in the section table (typo? allowed: Name Creator Difficulty Height Colors Build)", tostring(k)))
		end
	end
	if type(def.Name) ~= "string" or def.Name == "" then
		report.fail("Name must be a non-empty string")
		fatal = true
	else
		local key = string.lower(def.Name)
		if names[key] then
			report.fail(fmt("Name %q is used by more than one section", def.Name))
		end
		names[key] = true
		if #def.Name > 26 then
			report.warn(fmt("Name %q is long for the wall sign (%d letters)", def.Name, #def.Name))
		end
	end
	if type(def.Creator) ~= "string" or def.Creator == "" then
		report.fail("Creator must be a non-empty string")
	end
	if def.Difficulty ~= 1 and def.Difficulty ~= 2 and def.Difficulty ~= 3 then
		report.fail(fmt("Difficulty must be 1, 2 or 3 (got %s)", tostring(def.Difficulty)))
		fatal = true
	end
	if type(def.Height) ~= "number" or def.Height % 2 ~= 0 or def.Height < 24 or def.Height > 44 then
		report.fail(fmt("Height must be an even number from 24 to 44 (got %s)", tostring(def.Height)))
		fatal = true
	end
	if type(def.Colors) ~= "table" or typeof(def.Colors.Main) ~= "Color3" or typeof(def.Colors.Accent) ~= "Color3" then
		report.fail("Colors must be { Main = Color3, Accent = Color3 }")
		fatal = true
	end
	if type(def.Build) ~= "function" then
		report.fail("Build must be a function")
		fatal = true
	end
	return not fatal
end

local function newReport()
	local r = { fails = {}, failSeen = {}, warns = {}, warnSeen = {}, combo = "" }
	function r.fail(msg: string, details: { string }?)
		local key = msg
		if r.failSeen[key] then
			r.failSeen[key].count += 1
			return
		end
		local entry = { msg = msg, details = details, combo = r.combo, count = 1 }
		r.failSeen[key] = entry
		table.insert(r.fails, entry)
	end
	function r.warn(msg: string)
		if r.warnSeen[msg] then
			return
		end
		r.warnSeen[msg] = true
		table.insert(r.warns, msg)
	end
	return r
end

local function shortReason(msg: string): string
	local s = string.gsub(msg, "%s*%b[]", "")
	if #s > 90 then
		s = string.sub(s, 1, 87) .. "..."
	end
	return s
end

local function main()
	local selfCount = selfTest()
	print(fmt("mock self-test: %d checks OK", selfCount))
	local list = TowerSections.List
	if type(list) ~= "table" or #list == 0 then
		print("No sections in TowerSections.List - nothing to test (add fragments to build/sections/).")
		return
	end
	local names = {}
	local passed, failed, warnCount = 0, 0, 0
	local MAX_SHOWN = 8
	for i, def in ipairs(list) do
		local report = newReport()
		local label = (type(def) == "table" and type(def.Name) == "string") and def.Name or ("#" .. i)
		local minParts, maxParts, minReach = huge, -huge, huge
		if checkMeta(def, i, names, report) then
			for _, combo in ipairs(COMBOS) do
				report.combo = fmt("seed %d, rotation %d deg, BaseY %d", combo.seed, combo.rotDeg, combo.baseY)
				local stats = Check.build(def, combo, report)
				if stats then
					minParts, maxParts = math.min(minParts, stats.parts), math.max(maxParts, stats.parts)
					minReach = math.min(minReach, stats.reach)
				end
			end
		end
		local partsText = (minParts == huge) and "?" or ((minParts == maxParts) and tostring(minParts) or (minParts .. ".." .. maxParts))
		local reachText = (minReach == huge) and "?" or (U.n1(minReach):gsub("%.0$", ""))
		if #report.fails == 0 then
			passed += 1
			print(fmt("PASS %s parts=%s reach=%s/%s", label, partsText, reachText, tostring(def.Height)))
		else
			failed += 1
			local reasons = {}
			for j = 1, math.min(3, #report.fails) do
				table.insert(reasons, shortReason(report.fails[j].msg))
			end
			print(fmt("FAIL %s: %s%s", label, table.concat(reasons, "; "), #report.fails > 3 and fmt(" (+%d more)", #report.fails - 3) or ""))
			print(fmt("     parts=%s reach=%s/%s", partsText, reachText, tostring(def.Height)))
			for j, e in ipairs(report.fails) do
				if j > MAX_SHOWN then
					print(fmt("     ... and %d more problems", #report.fails - MAX_SHOWN))
					break
				end
				local times = (e.count > 1) and fmt(" (in %d builds)", e.count) or ""
				print(fmt("   - %s%s", e.msg, times))
				if e.combo ~= "" then
					print("       first seen with " .. e.combo)
				end
				for _, dline in ipairs(e.details or {}) do
					print("       " .. dline)
				end
			end
		end
		for j, w in ipairs(report.warns) do
			if j > MAX_SHOWN then
				print(fmt("WARN %s: ... and %d more warnings", label, #report.warns - MAX_SHOWN))
				break
			end
			print(fmt("WARN %s: %s", label, w))
		end
		warnCount += #report.warns
	end
	print(fmt("Summary: %d sections, %d passed, %d failed, %d warnings", passed + failed, passed, failed, warnCount))
	if failed > 0 then
		-- (this text can show up ABOVE the report when output is piped; the FAIL lines are the real info)
		error(fmt("section harness failed: %d section(s) FAIL - see the FAIL lines in the harness output", failed), 0)
	end
end

main()
