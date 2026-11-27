"""Riguea y anima los modelos de los personajes (no traen esqueleto) y los exporta a GLB.

Uso (desde la raíz del proyecto):
  "C:/Program Files/Blender Foundation/Blender 5.0/blender.exe" -b --factory-startup -P tools/rig_characters.py

Modelos de origen: pack "100 Avatars R1" (Polygonal Mind, CC0), en pose T, mirando a +X y de ~4,4 m.
Salida en assets/characters/: hunter.glb (Alien) y prey.glb (Ghost Character).

Cada modelo se escala a 1,6 m (la altura de la cápsula del juego) y se gira para que en Godot mire
a -Z, el "frente" de los personajes. El esqueleto es humanoide simple (15 huesos) y el pesado es
automático. Animaciones: Idle, Walk, Run (en bucle), Netted (bucle, solo Presa) y Shoot (Cazador).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSETS = r"D:/proyectos-godot/colleccion de assets/100 Avatars R1-glb"
TARGET_HEIGHT = 1.6
FPS = 30

# Puntos de referencia medidos en las coordenadas originales (Z arriba, mirando a +X, brazos en Y).
MODELS = {
	"hunter": {
		"src": "Alien.glb",
		"neck": 3.20, "crotch": 1.50, "knee": 0.78, "ankle": 0.16,
		"shoulder_y": 0.45, "aim": True,
	},
	"prey": {
		"src": "Ghost Character.glb",
		"neck": 3.40, "crotch": 1.40, "knee": 0.68, "ankle": 0.16,
		"shoulder_y": 0.55, "aim": False,
	},
}

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def measure(verts, m):
	"""Completa los puntos de referencia que se pueden sacar de la malla."""
	arm = [v for v in verts if abs(v.y) > 1.0]
	m["arm_z"] = sum(v.z for v in arm) / len(arm)
	m["arm_tip"] = max(abs(v.y) for v in verts)
	legs = [v for v in verts if m["crotch"] * 0.25 < v.z < m["crotch"] * 0.8]
	m["leg_y"] = sum(abs(v.y) for v in legs) / len(legs)
	feet = [v for v in verts if v.z < m["ankle"]]
	m["toe_x"] = max(v.x for v in feet)
	m["head_top"] = max(v.z for v in verts)


def _seg_dist(p, a, b):
	ab = b - a
	t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
	return (a + ab * t - p).length


def _unify_seam_weights(mesh):
	"""Los vértices duplicados en las costuras de UV (misma posición) reciben pesos distintos
	y la malla se abre al animar: se les da a todos la media."""
	groups = {}
	for v in mesh.data.vertices:
		groups.setdefault(tuple(round(c, 4) for c in v.co), []).append(v)
	names = {g.index: g.name for g in mesh.vertex_groups}
	for verts in groups.values():
		if len(verts) < 2:
			continue
		acc = {}
		for v in verts:
			for g in v.groups:
				acc[g.group] = acc.get(g.group, 0.0) + g.weight / len(verts)
		for v in verts:
			for gi in [g.group for g in v.groups]:
				mesh.vertex_groups[names[gi]].remove([v.index])
			for gi, w in acc.items():
				mesh.vertex_groups[names[gi]].add([v.index], w, "REPLACE")


def build(name, m):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.scene.render.fps = FPS
	bpy.ops.import_scene.gltf(filepath=os.path.join(ASSETS, m["src"]))
	mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
	# Quitar los nodos vacíos de la importación y aplicar la transformación a la malla.
	bpy.ops.object.select_all(action="DESELECT")
	mesh.select_set(True)
	bpy.context.view_layer.objects.active = mesh
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
	for o in list(bpy.context.scene.objects):
		if o != mesh:
			bpy.data.objects.remove(o)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	# La importación deja una shape key con las coordenadas originales: el exportador y la
	# deformación la usarían en vez de la malla transformada.
	if mesh.data.shape_keys:
		mesh.shape_key_clear()
	mesh.data.validate()
	measure([v.co.copy() for v in mesh.data.vertices], m)

	# Girar +90° en Z (mirar a +Y en Blender = -Z en Godot) y escalar a la altura objetivo.
	s = TARGET_HEIGHT / m["head_top"]
	xf = Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Scale(s, 4)
	mesh.data.transform(xf)
	mesh.data.update()
	mesh.name = name

	def T(x, y, z):
		return xf @ Vector((x, y, z))

	# --- Esqueleto -------------------------------------------------------------------------
	arm_data = bpy.data.armatures.new(name + "_rig")
	arm = bpy.data.objects.new("Armature", arm_data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	eb = arm_data.edit_bones

	def bone(bname, head, tail, parent=None, roll_axis=Y):
		b = eb.new(bname)
		b.head, b.tail = head, tail
		b.align_roll(xf.to_3x3() @ roll_axis)
		if parent:
			b.parent = eb[parent]
			b.use_connect = False
		return b

	c, n, top = m["crotch"], m["neck"], m["head_top"]
	chest_z = m["arm_z"] - (m["arm_z"] - c) * 0.35
	bone("Hips", T(0, 0, c), T(0, 0, c + (chest_z - c) * 0.5), roll_axis=Z)
	bone("Spine", T(0, 0, c + (chest_z - c) * 0.5), T(0, 0, chest_z), "Hips", roll_axis=Z)
	bone("Chest", T(0, 0, chest_z), T(0, 0, n), "Spine", roll_axis=Z)
	bone("Head", T(0, 0, n), T(0, 0, top), "Chest", roll_axis=Z)
	sy, tip, az = m["shoulder_y"], m["arm_tip"], m["arm_z"]
	elbow, wrist = sy + (tip - sy) * 0.45, sy + (tip - sy) * 0.82
	ly, k, a = m["leg_y"], m["knee"], m["ankle"]
	# Lado L = +Y original (izquierda del personaje), R = -Y.
	for side, sg in (("L", 1), ("R", -1)):
		bone("UpperArm." + side, T(0, sg * sy, az), T(0, sg * elbow, az), "Chest", roll_axis=Z)
		bone("LowerArm." + side, T(0, sg * elbow, az), T(0, sg * wrist, az), "UpperArm." + side, roll_axis=Z)
		bone("Hand." + side, T(0, sg * wrist, az), T(0, sg * tip, az), "LowerArm." + side, roll_axis=Z)
		bone("UpperLeg." + side, T(0, sg * ly, c), T(0.02, sg * ly, k), "Hips", roll_axis=X)
		bone("LowerLeg." + side, T(0.02, sg * ly, k), T(0, sg * ly, a), "UpperLeg." + side, roll_axis=X)
		bone("Foot." + side, T(0, sg * ly, a), T(m["toe_x"], sg * ly, 0.0), "LowerLeg." + side, roll_axis=Z)
	bpy.ops.object.mode_set(mode="OBJECT")

	# --- Pesado automático -----------------------------------------------------------------
	bpy.ops.object.select_all(action="DESELECT")
	mesh.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.parent_set(type="ARMATURE_AUTO")
	# El calor de huesos deja sin peso las piezas sueltas (ojos, detalles de la cara):
	# esas van enteras al hueso más cercano.
	unweighted = [v for v in mesh.data.vertices if not any(g.weight > 0.0 for g in v.groups)]
	print(f"[{name}] vértices sin peso tras el pesado automático: {len(unweighted)}/{len(mesh.data.vertices)}")
	segs = [(b.name, b.head_local, b.tail_local) for b in arm.data.bones]
	for v in unweighted:
		best = min(segs, key=lambda s: _seg_dist(v.co, s[1], s[2]))[0]
		mesh.vertex_groups[best].add([v.index], 1.0, "REPLACE")
	_unify_seam_weights(mesh)

	make_animations(arm, m)
	out = os.path.join(ROOT, "assets", "characters", name + ".glb")
	os.makedirs(os.path.dirname(out), exist_ok=True)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(
		filepath=out, export_format="GLB", use_selection=False,
		export_animation_mode="ACTIONS", export_force_sampling=True,
		export_frame_range=False, export_anim_single_armature=True,
		export_yup=True, export_apply=False,
	)
	print(f"[{name}] exportado: {out}")


# --- Animación ---------------------------------------------------------------------------
# Ejes tras el giro (Blender): el personaje mira a +Y, su derecha es +X, arriba +Z.
#   Rx(+) lleva una pierna hacia delante; Ry(-) baja el brazo izquierdo, Ry(+) el derecho.


def q(axis, deg):
	return Quaternion(axis, math.radians(deg))


class Poser:
	def __init__(self, arm):
		self.arm = arm
		self.rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}

	def rot(self, bname, world_q):
		"""Rotación expresada en el espacio del armature en reposo -> espacio local del hueso."""
		r = self.rest[bname]
		pb = self.arm.pose.bones[bname]
		pb.rotation_mode = "QUATERNION"
		pb.rotation_quaternion = r.inverted() @ world_q @ r

	def loc(self, bname, world_v):
		self.arm.pose.bones[bname].location = self.rest[bname].inverted() @ world_v

	def key(self, frame):
		for pb in self.arm.pose.bones:
			pb.keyframe_insert("rotation_quaternion", frame=frame)
			if pb.name == "Hips":
				pb.keyframe_insert("location", frame=frame)

	def reset(self):
		for pb in self.arm.pose.bones:
			pb.rotation_mode = "QUATERNION"
			pb.rotation_quaternion = Quaternion()
			pb.location = Vector()


def arms_down(p, m, l_swing=0.0, r_swing=0.0, l_elbow=8.0, r_elbow=8.0, down=78.0):
	p.rot("UpperArm.L", q(X, l_swing) @ q(Y, -down))
	p.rot("LowerArm.L", q(X, l_elbow))
	if m["aim"]:
		aim(p, r_swing)
	else:
		p.rot("UpperArm.R", q(X, r_swing) @ q(Y, down))
		p.rot("LowerArm.R", q(X, r_elbow))


def aim(p, recoil=0.0):
	"""Cazador: brazo derecho al frente, con el lanzador en la mano."""
	p.rot("UpperArm.R", q(X, recoil - 8.0) @ q(Z, 80.0))
	p.rot("LowerArm.R", q(Z, 10.0))


def legs(p, thigh_l, thigh_r, knee_l, knee_r):
	p.rot("UpperLeg.L", q(X, thigh_l))
	p.rot("UpperLeg.R", q(X, thigh_r))
	p.rot("LowerLeg.L", q(X, -knee_l))
	p.rot("LowerLeg.R", q(X, -knee_r))
	p.rot("Foot.L", q(X, -0.4 * thigh_l + 0.5 * knee_l))
	p.rot("Foot.R", q(X, -0.4 * thigh_r + 0.5 * knee_r))


def new_action(arm, name):
	act = bpy.data.actions.new(name)
	act.use_fake_user = True
	arm.animation_data_create()
	arm.animation_data.action = act
	return act


def loop_action(arm, p, m, name, frames, pose_fn):
	new_action(arm, name)
	for f in range(frames + 1):
		p.reset()
		pose_fn(2.0 * math.pi * f / frames, f)
		p.key(f)


def make_animations(arm, m):
	p = Poser(arm)
	h = TARGET_HEIGHT

	def idle(t, _f):
		arms_down(p, m, l_swing=2 * math.sin(t), r_swing=2 * math.sin(t), down=76 + 3 * math.sin(t))
		p.rot("Chest", q(X, 2.0 * math.sin(t)))
		p.rot("Head", q(Z, 4.0 * math.sin(t * 0.5 + 1.0)))
		p.loc("Hips", Z * (0.006 * h * math.sin(t)))
		legs(p, 0, 0, 0, 0)

	def gait(amp_leg, amp_knee, amp_arm, lean, bob, elbow):
		def fn(t, _f):
			s, co = math.sin(t), math.cos(t)
			legs(p, amp_leg * s, -amp_leg * s,
				5 + amp_knee * max(0.0, co), 5 + amp_knee * max(0.0, -co))
			arms_down(p, m, l_swing=-amp_arm * s, r_swing=amp_arm * s, l_elbow=elbow, r_elbow=elbow)
			p.rot("Spine", q(X, -lean) @ q(Z, 5.0 * s))
			p.rot("Chest", q(Z, -3.0 * s))
			p.loc("Hips", Z * (bob * h * (math.cos(2 * t) - 1.0)))
		return fn

	loop_action(arm, p, m, "Idle", 60, idle)
	loop_action(arm, p, m, "Walk", 32, gait(28, 40, 22, 3, 0.012, 12))
	loop_action(arm, p, m, "Run", 20, gait(45, 75, 45, 12, 0.025, 70))

	if m["aim"]:
		new_action(arm, "Shoot")
		for f, recoil in ((0, 0), (2, 28), (5, 12), (10, 0)):
			p.reset()
			arms_down(p, m)
			aim(p, recoil)
			p.rot("Spine", q(X, recoil * 0.25))
			legs(p, 0, 0, 0, 0)
			p.key(f)
	else:
		def netted(t, _f):
			s = math.sin(t)
			p.rot("UpperArm.L", q(X, 15 * s) @ q(Y, 35 + 15 * math.sin(2 * t)))
			p.rot("UpperArm.R", q(X, -15 * s) @ q(Y, -35 - 15 * math.sin(2 * t + 1)))
			p.rot("LowerArm.L", q(X, 30))
			p.rot("LowerArm.R", q(X, 30))
			p.rot("Spine", q(Z, 12 * s) @ q(X, -5))
			p.rot("Head", q(Z, -15 * s))
			legs(p, 10 * s, -10 * s, 25, 25)
			p.loc("Hips", Z * (-0.03 * h))
		loop_action(arm, p, m, "Netted", 16, netted)

	arm.animation_data.action = bpy.data.actions["Idle"]
	p.reset()


if __name__ == "__main__":
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	for key, model in MODELS.items():
		if not argv or key in argv:
			build(key, dict(model))
