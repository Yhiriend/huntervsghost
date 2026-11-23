class_name House
extends Node3D
## Raíz de la casa. Al arrancar genera la malla de navegación de la IA a partir de la geometría
## (paredes, muebles y armarios). Las puertas se excluyen: la IA planifica como si estuvieran
## abiertas y las abre al llegar.

signal navigation_ready

const AGENT_RADIUS := 0.5
const AGENT_HEIGHT := 1.5

var nav_ready: bool = false

var _region: NavigationRegion3D


func _ready() -> void:
	add_to_group("house")
	_region = NavigationRegion3D.new()
	_region.name = "Navigation"
	add_child(_region)
	_bake()


func _make_navigation_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = 0.25
	return mesh


## La geometría fuente se construye a mano (caras de colisión de los CSG + cajas de los armarios):
## no depende del renderizador y las puertas quedan fuera automáticamente.
func _bake() -> void:
	var source := NavigationMeshSourceGeometryData3D.new()
	for child in get_children():
		var csg := child as CSGShape3D
		if csg == null or not csg.is_root_shape():
			continue
		# CSG construye su geometría de forma diferida (tarda un par de frames).
		var faces := PackedVector3Array()
		for attempt in 30:
			var shape := csg.bake_collision_shape() if csg.get_meshes().size() > 0 else null
			if shape:
				faces = shape.get_faces()
			if not faces.is_empty():
				break
			await get_tree().physics_frame
		if faces.is_empty():
			push_error("House: la geometría CSG '%s' no está lista; la IA no podrá navegar." % csg.name)
			continue
		source.add_faces(faces, csg.global_transform)
	for node in get_tree().get_nodes_in_group("hiding_spots"):
		var spot := node as HidingSpot
		var box := BoxMesh.new()
		box.size = HidingSpot.SIZE
		var offset := Transform3D(Basis(), Vector3(0.0, HidingSpot.SIZE.y * 0.5, 0.0))
		source.add_mesh_array(box.get_mesh_arrays(), spot.global_transform * offset)

	var mesh := _make_navigation_mesh()
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_region.navigation_mesh = mesh
	# La malla llega al servidor de navegación unos frames después. En Godot 4.7 el primer envío
	# a veces se pierde: se reenvía hasta que la región responde a consultas.
	var probe := Vector3.ZERO
	for attempt in 60:
		await get_tree().physics_frame
		if not NavigationServer3D.region_get_closest_point(_region.get_rid(), probe).is_zero_approx():
			break
		if attempt % 3 == 2:
			NavigationServer3D.region_set_navigation_mesh(_region.get_rid(), mesh)
	# Un frame más para que el mapa (no solo la región) esté sincronizado.
	await get_tree().physics_frame
	print_verbose("House: navegación lista (%d polígonos)." % mesh.get_polygon_count())
	nav_ready = true
	navigation_ready.emit()
