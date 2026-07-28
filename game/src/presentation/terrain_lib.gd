extends RefCounted
## Ground that is actually ground (playtest: "the terrain is completely
## flat everywhere, and has a singular texture throughout").
##
## Two things fix that, and neither needs an artist:
##
## 1. RELIEF. `height_at()` is a cheap deterministic height field — a
##    few sine octaves, no noise resource, no seed to lose. Everything
##    that stands on the ground asks it where the ground is, so men,
##    walls, trees and the camera all agree. New England is drumlin
##    country: long low swells, not mountains.
##
## 2. COVER, not colour. A pasture in April is not one green. It is
##    winter-killed grass going green in patches, mud where feet and
##    hooves have been, bare earth on the ridges the wind scours, and
##    moss in the hollows that hold water. The mesh carries that as
##    vertex colour — free at runtime, and it varies at every scale
##    because it is driven by the same height field.
##
## Use via preload:
##   const TerrainLib := preload("res://src/presentation/terrain_lib.gd")

# The palette of a New England field, mid-April.
const GRASS_NEW := Color(0.27, 0.33, 0.17)      # what has come back
const GRASS_DEAD := Color(0.40, 0.37, 0.22)     # last year's, still lying
const EARTH := Color(0.29, 0.23, 0.16)          # scoured ridge, cart rut
const MUD := Color(0.21, 0.17, 0.13)            # the hollows, and the road
const MOSS := Color(0.20, 0.28, 0.16)
const SNOW_PACK := Color(0.62, 0.64, 0.70)      # town snow, trampled grey


## The land itself. Long swells crossing at an angle, a finer ripple on
## top, and a gentle fall toward the edges so the field does not read as
## a tabletop. `relief` scales the whole thing (towns want less).
static func height_at(x: float, z: float, relief := 1.0) -> float:
	var h := sin(x * 0.021 + 1.3) * cos(z * 0.017 - 0.4) * 2.6      # the swells
	h += sin(x * 0.058 - 0.7) * 0.55                                # a ridge line
	h += cos(z * 0.047 + 2.1) * 0.65
	h += sin((x + z) * 0.11) * 0.22                                 # the ripple
	return h * relief


## The normal of that surface, by finite difference — used for slope
## shading and for standing things upright-ish on a hillside.
static func normal_at(x: float, z: float, relief := 1.0) -> Vector3:
	var e := 0.75
	var hx := height_at(x + e, z, relief) - height_at(x - e, z, relief)
	var hz := height_at(x, z + e, relief) - height_at(x, z - e, relief)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


static func _hash01(x: int) -> float:
	var h := (x * 2654435761) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1103515245) & 0x7FFFFFFF
	return float(h % 10000) / 10000.0


## What is growing (or not) at a point — the blend that keeps the ground
## from being one colour. Driven by slope, height and a coarse patch
## noise, so it reads at 5 yards and at 200.
static func cover_at(x: float, z: float, kind: String, relief := 1.0) -> Color:
	if kind == "snow":
		var trample := 0.5 + 0.5 * sin(x * 0.09) * cos(z * 0.11)
		return SNOW_PACK.lerp(MUD, clampf(trample * 0.5, 0.0, 0.45))
	var n := normal_at(x, z, relief)
	var slope := 1.0 - n.y                       # 0 flat, ~0.3 steep here
	var h := height_at(x, z, relief)
	# Coarse patches: where the field was grazed, where it lay wet.
	var patch := sin(x * 0.037 + 2.2) * cos(z * 0.041 - 1.1)
	var wet := clampf(-h * 0.35 + patch * 0.4, 0.0, 1.0)
	var c := GRASS_DEAD.lerp(GRASS_NEW, clampf(0.35 + patch * 0.5, 0.0, 1.0))
	c = c.lerp(MOSS, wet * 0.45)                 # hollows hold water
	c = c.lerp(EARTH, clampf(slope * 3.2, 0.0, 0.7))   # the wind scours ridges
	# A fine grain so no two square yards match.
	var grain := _hash01(int(x * 3.0) * 7919 + int(z * 3.0) * 104729)
	return c.darkened((grain - 0.5) * 0.14)


## Build the ground as a real mesh: a displaced grid carrying its cover
## in vertex colours. `extent` is (width, depth) in yards.
static func build_ground(parent: Node3D, extent: Vector2, kind := "field",
		relief := 1.0, step := 6.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(extent.x / step)
	var nz := int(extent.y / step)
	var x0 := -extent.x / 2.0
	var z0 := -extent.y / 2.0
	for iz in nz:
		for ix in nx:
			var ax := x0 + float(ix) * step
			var az := z0 + float(iz) * step
			var bx := ax + step
			var bz := az + step
			var corners := [Vector2(ax, az), Vector2(bx, az), Vector2(bx, bz), Vector2(ax, bz)]
			var pts: Array[Vector3] = []
			var cols: Array[Color] = []
			var norms: Array[Vector3] = []
			for c in corners:
				pts.append(Vector3(c.x, height_at(c.x, c.y, relief), c.y))
				cols.append(cover_at(c.x, c.y, kind, relief))
				norms.append(normal_at(c.x, c.y, relief))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					st.set_color(cols[k])
					st.set_normal(norms[k])
					st.add_vertex(pts[k])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.specular = 0.05                    # earth does not shine
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Loose scatter — stones, tussocks, a fallen branch. Small things at
## ground level are what stop a field reading as a shaded plane.
static func scatter(parent: Node3D, extent: Vector2, count: int, relief := 1.0,
		seed_v := 3) -> void:
	var stone := BoxMesh.new()
	stone.size = Vector3(0.7, 0.4, 0.55)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.36, 0.35, 0.33)
	smat.roughness = 0.98
	stone.material = smat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stone
	mm.instance_count = count
	for i in count:
		var hx := _hash01(seed_v + i * 7919)
		var hz := _hash01(seed_v + i * 104729 + 13)
		var hs := _hash01(seed_v + i * 15485863 + 7)
		var x := (hx - 0.5) * extent.x
		var z := (hz - 0.5) * extent.y
		var s := 0.5 + hs * 1.5
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.rotated(Vector3.UP, hx * TAU).scaled(
				Vector3(s, s * (0.5 + hz * 0.6), s)),
			Vector3(x, height_at(x, z, relief) + 0.1 * s, z)))
		var v := 0.8 + hs * 0.45
		mm.set_instance_color(i, Color(v, v, v))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
