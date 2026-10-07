# Section test harness

Nobody can run Roblox in our build container, so `tools/check.sh` runs every tower
section in a **fake Roblox** and checks the section rules from `docs/ARCHITECTURE.md` §5.

```
tools/check.sh                          # all fragments in build/sections/*.lua
tools/check.sh build/sections/mine.lua  # just your fragment(s)
```

The type check runs first (`=== Type check ===`), then `=== Section harness ===`.
Your section must end with **zero type errors and a PASS line**.

## Files

| File | What it is |
|---|---|
| `tests/mocks.luau` | Fake Roblox: `Vector3`, `CFrame`, `Color3`, `Enum`, `Random`, `Instance.new`, `CollectionService`, `game`, `workspace`… The property/enum lists at the bottom are generated from `.tools/globalTypes.d.luau`. |
| `tests/section_checks.luau` | The checks. Starts with a self-test of the fake maths (it refuses to run if the mocks are wrong). |
| `tests/fixtures/good_*.lua` | Sections that must **PASS**. |
| `tests/fixtures/bad_*.lua` | Sections that must **FAIL**, each for the reason written above it. `bad_code.lua` also has one deliberate type error (`Colr`). |

If you change the harness, run `tools/check.sh tests/fixtures/*.lua`. Both `good_*` sections
must PASS, and every `Fixture ...` section in the `bad_*` files must FAIL for its stated reason.

## What is checked (per section)

1. **Metadata**: unique `Name`, a `Creator`, `Difficulty` 1/2/3, even `Height` 24..44,
   `Colors.Main` / `Colors.Accent` are `Color3`, and `Build` is a function. Unknown keys in the
   section table cause a WARN.
2. **It builds**: `TowerSections.Build` runs 14 times (12 seeds × rotations at BaseY 100, plus
   BaseY 12 and 300). Any error is a FAIL, with the line number.
   - Every `ctx:` call is checked: missing or NaN numbers, sizes ≤ 0, unknown `opts` keys
     (`Colour` → "did you mean Color?"), wrong value types, parts from another section.
   - Fake Roblox errors on wrong property names, `nil` for a `Color3`/`Vector3` property,
     writing read-only values (`v.X = 5`, `cf.Position = …`, `part.Mass = …`), Enum typos,
     bad attribute values, connecting events, and `wait()`/`task.*` inside Build.
3. **Part count**: FAIL above 120 or below 15. WARN outside 25..70.
4. **Anchored**: every part. Parts parented outside the section are a FAIL.
5. **Bounds**: every part's real shape (box corners, round cylinder ends, spheres) stays within
   radius **24** and between y = **0** and y = **Height**, with a tolerance of 0.05. This holds
   for its *whole motion* if it, or its group, has Spin, Move or Swing. Wedges are measured as
   their full box, which is a safe over-estimate.
6. **Keep-out**: nothing solid (`CanCollide`) and nothing deadly (`Kill`/`Cycle`) may come
   within radius **7.5** of the axis for y in 0..6 (above the entry plate) or Height-7..Height
   (around the exit plate). This uses the exact swept shape, including motion. Non-solid
   decorations are allowed there.
7. **Reachability** (rough jump physics: gravity 196.2, walk 16, jump height 7.2):
   - Every solid, non-Kill part's top surface is a place to stand. Hazard/Vanish/Melt parts count;
     moving parts count everywhere they go.
   - From a surface you can reach another if the rise is at most **6.5** and the horizontal gap
     is at most `16 · airtime · k + 1.5`, where k = 0.8 for difficulty 1–2 and 0.95 for 3.
   - Bounce pads jump with `BouncePower`.
   - Truss ladders can be grabbed from within 3 studs and climbed to the top.
   - FAIL if the exit plate can't be reached. The output then shows the highest reachable
     surface and the closest failed jumps.
   - Also FAIL if there is no safe last ledge (rule 4: top between Height-4.5 and Height-1.5,
     nearest edge 7.5–10.5 from the axis).

WARN lines are soft problems, such as:
- a Kill part without the Neon/red look
- one colour on more than 75% of the parts
- tiny or invisible solid parts
- truss sizes that aren't multiples of 2
- very fast movers
- `warn()` calls from your code
- a group pivot used before Build finished

## Reading the output

```
mock self-test: 123 checks OK
PASS Nugget Steps parts=44 reach=28/28
FAIL Fixture Bad Gap: the exit plate (y=30) can't be reached by jumping - highest reachable surface is y=12.0
     parts=31 reach=12/30
   - the exit plate (y=30) can't be reached by jumping - highest reachable surface is y=12.0 (in 14 builds)
       first seen with seed 1, rotation 0 deg, BaseY 100
       highest reachable surface: "Step4" #13 at (-10.3, 11.5, 3.8) (top y=12.0)
       next unreachable: "Step7" #20 at (1.9, 19.0, -10.8) (y=19.5) - best try from "Step4" ...: rise 7.5 is higher than a jump (max 6.5)
WARN Nugget Steps: part count 22 is outside the 25..70 sweet spot
Summary: 5 sections, 4 passed, 1 failed, 1 warnings
```

- `parts=` is the part count (a range if it changes with the seed). `reach=` is the highest
  reachable height out of `Height`, the worst over all builds.
- Parts are named like `Part "Step4" #13 at local (x, y, z)`. That is the part's `Name`
  (set it with `opts.Name`!), its number in build order, and its centre in **section-local**
  coordinates (the same numbers you pass to ctx).
- Error lines like `TowerSections.lua:374` use the same numbering as the type checker. The note
  `[3 lines below this section's 'Build = function' line]` helps you find the line in your
  fragment.
- When output is piped, the final `section harness failed` message can show up *above* the
  report. That's normal; read the FAIL lines.

## Regenerating the API data

The `API.CLASSES` / `API.ENUMS` / `API.ENUM_NAMES` / `API.CREATABLE` / `API.SERVICES` block at the
bottom of `tests/mocks.luau` comes from `.tools/globalTypes.d.luau`. If that file is updated,
regenerate the block:

1. Save the script below as `/tmp/gen_api.py`.
2. Run `python3 /tmp/gen_api.py .tools/globalTypes.d.luau > /tmp/api.luau`.
3. Replace the lines from `API.CLASSES = {` up to (not including) `buildMocks()` with `/tmp/api.luau`.

To mock another class, add it to `WANT` here **and** to `MOCKED_NEW` in `mocks.luau`.

<details><summary>gen_api.py</summary>

```python
import json, re, sys

lines = open(sys.argv[1]).read().split("\n")
meta = json.loads(lines[0][len("--#METADATA#"):])
classes, enums = {}, {}
decl = re.compile(r"^declare extern type (\w+)(?: extends (\w+))? with\s*(end)?\s*$")
i = 0
while i < len(lines):
    m = decl.match(lines[i])
    if not m:
        i += 1
        continue
    name, parent, oneline = m.group(1), m.group(2), m.group(3)
    body = []
    i += 1
    if not oneline:
        while i < len(lines) and lines[i] != "end":
            body.append(lines[i])
            i += 1
        i += 1
    if name.startswith("Enum"):
        if name.endswith("_INTERNAL"):
            enums[name[4:-9]] = [mm.group(1) for b in body for mm in [re.match(r"^\t(\w+): Enum\w+\s*$", b)] if mm]
        continue
    props, methods, events = {}, [], []
    for b in body:
        mm = re.match(r"^\t+function (\w+)\(", b)
        if mm:
            methods.append(mm.group(1))
            continue
        mm = re.match(r"^\t(\w+): (.+?)\s*$", b)
        if mm:
            (events.append(mm.group(1)) if mm.group(2).startswith("RBXScriptSignal") else props.__setitem__(mm.group(1), mm.group(2)))
    classes[name] = dict(parent=parent, props=props, methods=sorted(set(methods)), events=sorted(set(events)))

WANT = """Part WedgePart CornerWedgePart TrussPart Model Folder
PointLight SpotLight SurfaceLight ParticleEmitter Fire Smoke Sparkles Attachment
SurfaceGui BillboardGui TextLabel Frame ImageLabel UICorner UIStroke UIGradient UIListLayout UIPadding
UIAspectRatioConstraint UIScale Decal Texture Highlight Beam Trail SpecialMesh SelectionBox
Workspace CollectionService ReplicatedStorage ServerStorage ServerScriptService Lighting Players RunService
TweenService Debris DataModel""".split()
order = []
def add(c):
    if c is not None and c not in order:
        add(classes[c]["parent"])
        order.append(c)
for w in WANT:
    add(w)

VALUE_TYPES = {"number", "boolean", "string", "Vector3", "CFrame", "Color3", "UDim", "UDim2", "Vector2",
               "NumberRange", "NumberSequence", "ColorSequence", "PhysicalProperties", "BrickColor", "Font",
               "Rect", "ContentId", "ProtectedString", "Content", "Faces", "Axes"}
used = set()
out = ["API.CLASSES = {"]
for c in order:
    d, ps = classes[c], []
    for pn, pt in sorted(d["props"].items()):
        t = pt.replace(" ", "")
        opt = t.endswith("?")
        base = t[:-1] if opt else t
        if base.startswith("Enum") and base[4:] in enums:
            used.add(base[4:])
            t = "Enum." + base[4:] + ("?" if opt else "")
        elif not (base in VALUE_TYPES or base in classes):
            t = "any"
        ps.append(pn + ":" + t)
    out.append('\t{ "%s", %s, "%s", "%s", "%s" },' % (c, ('"%s"' % d["parent"]) if d["parent"] else "nil",
               " ".join(ps), " ".join(d["methods"]), " ".join(d["events"])))
out.append("}")
for e in ["Material", "PartType", "SurfaceType", "NormalId", "Font", "Style", "RotationOrder", "Axis",
          "EasingStyle", "EasingDirection", "FontWeight", "FontStyle", "ParticleOrientation",
          "ParticleEmitterShape", "ParticleEmitterShapeStyle", "ParticleEmitterShapeInOut",
          "TextXAlignment", "TextYAlignment", "SizeConstraint", "ZIndexBehavior", "SurfaceGuiSizingMode",
          "ApplyStrokeMode", "LineJoinMode", "HighlightDepthMode", "MeshType", "TextureMode", "AutomaticSize",
          "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "AspectType",
          "DominantAxis", "ModelStreamingMode", "CollisionFidelity", "RenderFidelity"]:
    if e in enums:
        used.add(e)
out.append("API.ENUMS = {")
out += ['\t%s = "%s",' % (e, " ".join(enums[e])) for e in sorted(used)]
out.append("}")
out.append('API.ENUM_NAMES = "%s"' % " ".join(sorted(enums)))
out.append('API.CREATABLE = "%s"' % " ".join(meta["CREATABLE_INSTANCES"]))
out.append('API.SERVICES = "%s"' % " ".join(meta["SERVICES"]))
print("\n".join(out))
```

</details>

## Known limits (it's a heuristic, not Roblox)

- Reachability is optimistic. It ignores Kill parts in the way, head bumps, timing of moving
  parts and sloped landings. A PASS means "probably beatable", so still play it in Studio.
- Collisions between moving parts and the stairs are not checked.
- Enum `Value` numbers in the fake are list positions, not Roblox's real numbers. Use the Enum
  items themselves.
- `Random` is deterministic but gives different numbers from Roblox's.
