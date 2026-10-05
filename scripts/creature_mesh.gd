extends RefCounted
# Generador de mallas organicas para las criaturas.
# En vez de pegar esferas, cada parte del cuerpo es una piel continua que se
# "extruye" a lo largo de una columna curva, con secciones ovaladas de radio variable
# (lomo, panza y costado por separado). Sale de estudiar los modelos de referencia
# (tools/hots_study.py): masas musculares que se afinan, cuernos y garras curvos.
#
# La columna vive en el plano XY (el plano de la vista de costado) y la criatura es
# simetrica en Z. Cada anillo de control es [x, y, arriba, abajo, costado].

const EPS := 0.0001


# opts:
#   seg   lados de cada seccion (16)        sub   anillos interpolados por tramo (5)
#   z     desplazamiento lateral            u     Vector2: rango de UV.x a lo largo (rayas)
#   tip   Vector2: rango de UV2.x (cuanto se tiñe hacia el color de las extremidades)
#   colors [base, punta]: color por vertice a lo largo (cuernos, garras)
static func loft(rings: Array, opts: Dictionary = {}) -> ArrayMesh:
	var seg: int = opts.get("seg", 16)
	var sub: int = opts.get("sub", 5)
	var z0: float = opts.get("z", 0.0)
	var u_range: Vector2 = opts.get("u", Vector2(0.0, 1.0))
	var tip_range: Vector2 = opts.get("tip", Vector2.ZERO)
	var colors: Array = opts.get("colors", [Color.WHITE, Color.WHITE])

	# Catmull-Rom sobre los anillos de control: pocas medidas, forma suave.
	var pts: Array = []
	var n := rings.size()
	for i in n - 1:
		var p0: Array = rings[max(i - 1, 0)]
		var p1: Array = rings[i]
		var p2: Array = rings[i + 1]
		var p3: Array = rings[min(i + 2, n - 1)]
		for s in sub:
			pts.append(_catmull(p0, p1, p2, p3, float(s) / sub))
	pts.append(rings[n - 1].duplicate())
	var m := pts.size()

	var lengths := PackedFloat32Array()
	lengths.resize(m)
	var total := 0.0
	for i in range(1, m):
		total += Vector2(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]).length()
		lengths[i] = total
	total = maxf(total, EPS)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var prev_up := Vector2.ZERO
	var tangents: Array[Vector2] = []
	for i in m:
		var a: Array = pts[max(i - 1, 0)]
		var b: Array = pts[min(i + 1, m - 1)]
		var t := Vector2(b[0] - a[0], b[1] - a[1])
		t = t.normalized() if t.length() > EPS else Vector2.RIGHT
		tangents.append(t)
		# "arriba" de la seccion: perpendicular a la columna, sin dar vueltas de un anillo al otro.
		var up := Vector2(-t.y, t.x)
		if i == 0:
			if (absf(up.y) > 0.3 and up.y < 0.0) or (absf(up.y) <= 0.3 and up.x < 0.0):
				up = -up
		elif up.dot(prev_up) < 0.0:
			up = -up
		prev_up = up
		var ds := maxf(lengths[min(i + 1, m - 1)] - lengths[max(i - 1, 0)], EPS)
		var slope: float = ((b[2] + b[3] + b[4]) - (a[2] + a[3] + a[4])) / 3.0 / ds
		var s := lengths[i] / total
		var c: Array = pts[i]
		for j in seg + 1:
			var ang := TAU * j / seg
			var ca := cos(ang)
			var sa := sin(ang)
			var r_v: float = maxf(c[2] if ca >= 0.0 else c[3], 0.0)
			var r_s: float = maxf(c[4], 0.0)
			verts.append(Vector3(c[0] + up.x * ca * r_v, c[1] + up.y * ca * r_v, z0 + sa * r_s))
			var nr := Vector3(up.x, up.y, 0.0) * (ca / maxf(r_v, 0.01)) + Vector3(0.0, 0.0, sa / maxf(r_s, 0.01))
			nr = nr.normalized() - Vector3(t.x, t.y, 0.0) * slope
			normals.append(nr.normalized())
			uvs.append(Vector2(lerpf(u_range.x, u_range.y, s), float(j) / seg))
			uv2s.append(Vector2(lerpf(tip_range.x, tip_range.y, s), 0.0))
			cols.append(colors[0].lerp(colors[1], s))

	var row := seg + 1
	for i in m - 1:
		for j in seg:
			var q := i * row + j
			indices.append_array(PackedInt32Array([q, q + row, q + 1, q + 1, q + row, q + row + 1]))

	# Tapas en los extremos que no terminan en punta.
	for end in [0, m - 1]:
		var c: Array = pts[end]
		if maxf(c[2], maxf(c[3], c[4])) < 0.012:
			continue
		var dir := -1.0 if end == 0 else 1.0
		var center := verts.size()
		verts.append(Vector3(c[0], c[1], z0))
		normals.append(Vector3(tangents[end].x, tangents[end].y, 0.0) * dir)
		uvs.append(uvs[end * row])
		uv2s.append(uv2s[end * row])
		cols.append(cols[end * row])
		for j in seg:
			var q: int = end * row + j
			if end == 0:
				indices.append_array(PackedInt32Array([center, q, q + 1]))
			else:
				indices.append_array(PackedInt32Array([center, q + 1, q]))

	indices = _fix_winding(verts, normals, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Cuerno, garra, pua o pluma: cono que se curva. bend > 0 lo dobla hacia atras (-X local).
# flat < 1 lo aplana de costado (plumas, placas).
static func spike(length: float, radius: float, bend: float = 0.0, flat: float = 1.0, colors: Array = []) -> ArrayMesh:
	var rings := []
	for i in 5:
		var s := i / 4.0
		var r := radius * pow(1.0 - s, 0.8)
		rings.append([-bend * length * s * s, length * s, r, r, r * flat])
	return loft(rings, {"seg": 10, "sub": 3, "colors": colors if not colors.is_empty() else [Color(0.45, 0.4, 0.38), Color.WHITE]})


# Membrana plana (alas): abanico de triangulos desde el primer punto. Se dibuja de los dos lados.
static func membrane(points: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	for i in points.size():
		verts.append(points[i])
		normals.append(Vector3(0.0, 0.0, 1.0))
		# mas oscura cerca del cuerpo, clara en el borde
		cols.append(Color(0.55, 0.55, 0.55) if i == 0 else Color.WHITE)
	for i in range(1, points.size() - 1):
		indices.append_array(PackedInt32Array([0, i, i + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Ala de insecto: contorno redondeado con borde oscuro. outline son Vector2 en orden,
# sin incluir el arranque (hub). El color por vertice va de claro adentro a oscuro en el borde.
static func wing(hub: Vector2, outline: Array, border: float = 0.2) -> ArrayMesh:
	var pts: Array[Vector2] = []
	var n := outline.size()
	for i in n - 1:
		var p0: Vector2 = outline[max(i - 1, 0)]
		var p1: Vector2 = outline[i]
		var p2: Vector2 = outline[i + 1]
		var p3: Vector2 = outline[min(i + 2, n - 1)]
		for s in 4:
			var t := s / 4.0
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	pts.append(outline[n - 1])
	var m := pts.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	verts.append(Vector3(hub.x, hub.y, 0.0))
	cols.append(Color(0.6, 0.6, 0.6))
	for p in pts:
		var inner := hub + (p - hub) * (1.0 - border)
		verts.append(Vector3(inner.x, inner.y, 0.0))
		cols.append(Color.WHITE)
	for p in pts:
		verts.append(Vector3(p.x, p.y, 0.0))
		cols.append(Color(0.12, 0.12, 0.14))
	for i in verts.size():
		normals.append(Vector3(0.0, 0.0, 1.0))
	for i in m - 1:
		var a := 1 + i
		var b := 1 + m + i
		indices.append_array(PackedInt32Array([0, a, a + 1, a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _catmull(p0: Array, p1: Array, p2: Array, p3: Array, t: float) -> Array:
	var out := []
	var t2 := t * t
	var t3 := t2 * t
	for k in 5:
		var v: float = 0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * t + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * t2 + (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * t3)
		# los radios no pueden pasarse a negativo por el rebote de la curva
		out.append(v if k < 2 else maxf(v, 0.0))
	return out


# Godot toma como cara frontal la de sentido horario. Se mira un triangulo y, si quedo
# al reves respecto de las normales, se invierten todos.
static func _fix_winding(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> PackedInt32Array:
	var vote := 0.0
	for i in range(0, indices.size(), 3):
		var a := verts[indices[i]]
		var face := (verts[indices[i + 1]] - a).cross(verts[indices[i + 2]] - a)
		vote += face.dot(normals[indices[i]])
	if vote > 0.0:
		for i in range(0, indices.size(), 3):
			var tmp := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = tmp
	return indices
