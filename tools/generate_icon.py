"""Genera los iconos del launcher de Android y el icono del proyecto.

Uso: python tools/generate_icon.py
Salida en icons/:
  icon_background_432.png  fondo del icono adaptativo
  icon_foreground_432.png  primer plano del icono adaptativo (dentro de la zona segura)
  icon_monochrome_432.png  silueta para los iconos temáticos de Android 13+
  icon_192.png             icono clásico (Android antiguo)
  icon_1024.png            icono del proyecto / ventana

Paleta del GDD: azul oscuro y violeta de fondo, luz amarilla cálida,
una cápsula mitad Cazador (naranja) y mitad Presa (celeste) dentro de una mira blanca.
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4  # supermuestreo para bordes suaves
OUT = os.path.join(os.path.dirname(__file__), "..", "icons")

NAVY = (22, 28, 56)
VIOLET = (52, 32, 88)
WARM = (255, 204, 102)
CYAN = (120, 220, 255)
CYAN_DARK = (60, 150, 210)
ORANGE = (255, 138, 40)
ORANGE_DARK = (200, 90, 20)
EYE = (20, 30, 60)
WHITE = (255, 255, 255)


def background(size):
	s = size * SS
	img = Image.new("RGBA", (s, s))
	px = img.load()
	for y in range(s):
		t = y / (s - 1)
		c = tuple(int(NAVY[i] + (VIOLET[i] - NAVY[i]) * t) for i in range(3))
		for x in range(s):
			px[x, y] = c + (255,)
	# Luz cálida de habitación detrás del personaje.
	glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	d = ImageDraw.Draw(glow)
	cx, cy, r = s * 0.5, s * 0.44, s * 0.34
	d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WARM + (110,))
	glow = glow.filter(ImageFilter.GaussianBlur(s * 0.12))
	img = Image.alpha_composite(img, glow)
	return img.resize((size, size), Image.LANCZOS)


def capsule(d, cx, top, w, h, fill):
	r = w / 2
	d.rounded_rectangle((cx - r, top, cx + r, top + h), radius=r, fill=fill)


def foreground(size, mono=False):
	"""Una cápsula partida en dos: mitad Cazador (naranja, con el lanzador) y mitad Presa
	(celeste), dentro de una mira blanca. Cabe en la zona segura (círculo de r=144)."""
	s = size * SS
	u = s / 432.0  # unidades del lienzo de 432
	img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	cx, top, w, h = 216 * u, 104 * u, 148 * u, 224 * u
	gap = 8 * u  # separación entre las dos mitades

	# Cápsula completa como máscara; cada mitad se recorta de ella.
	body = Image.new("L", (s, s), 0)
	capsule(ImageDraw.Draw(body), cx, top, w, h, 255)
	inner = Image.new("L", (s, s), 0)
	capsule(ImageDraw.Draw(inner), cx, top + 4 * u, w - 14 * u, h - 14 * u, 255)
	left = Image.new("L", (s, s), 0)
	ImageDraw.Draw(left).rectangle((0, 0, cx - gap / 2, s), fill=255)
	right = Image.new("L", (s, s), 0)
	ImageDraw.Draw(right).rectangle((cx + gap / 2, 0, s, s), fill=255)

	if not mono:
		halo = Image.new("RGBA", (s, s), WHITE + (0,))
		halo.putalpha(body.filter(ImageFilter.GaussianBlur(14 * u)).point(lambda v: v * 0.45))
		img = Image.alpha_composite(img, halo)

	def half(side, dark, light):
		layer = Image.new("RGBA", (s, s), dark + (0,))
		layer.putalpha(ImageChops.multiply(body, side))
		hl = Image.new("RGBA", (s, s), light + (0,))
		hl.putalpha(ImageChops.multiply(inner, side))
		return Image.alpha_composite(layer, hl)

	if mono:
		sil = Image.new("RGBA", (s, s), WHITE + (0,))
		sil.putalpha(ImageChops.add(ImageChops.multiply(body, left), ImageChops.multiply(body, right)))
		img = Image.alpha_composite(img, sil)
	else:
		img = Image.alpha_composite(img, half(left, ORANGE_DARK, ORANGE))
		img = Image.alpha_composite(img, half(right, CYAN_DARK, CYAN))

	d = ImageDraw.Draw(img)
	# Lanzador del Cazador: el "morro" de la cápsula naranja, como en el juego.
	d.rounded_rectangle((cx - w / 2 - 34 * u, top + 104 * u, cx - w / 2 + 10 * u, top + 128 * u),
		radius=7 * u, fill=WHITE if mono else ORANGE_DARK)
	# Ojos: uno en cada mitad. El del Cazador entornado, el de la Presa abierto.
	clear = (0, 0, 0, 0)
	d.rounded_rectangle((cx - 46 * u, top + 70 * u, cx - 16 * u, top + 86 * u), radius=8 * u, fill=clear if mono else EYE)
	d.ellipse((cx + 16 * u, top + 60 * u, cx + 46 * u, top + 96 * u), fill=clear if mono else EYE)

	# Mira blanca: aro con cuatro marcas, partida donde cruzan las marcas.
	r, lw = 132 * u, int(9 * u)
	d.ellipse((cx - r, 216 * u - r, cx + r, 216 * u + r), outline=WHITE, width=lw)
	cy = 216 * u
	for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
		a, b = r - 26 * u, r + 10 * u
		d.line((cx + dx * a, cy + dy * a, cx + dx * b, cy + dy * b), fill=WHITE, width=lw)
	return img.resize((size, size), Image.LANCZOS)


def monochrome():
	return foreground(432, mono=True)


def flat(size, rounded=True):
	"""Fondo + primer plano ampliado (sin el margen de la zona segura)."""
	big = 432
	bg = background(big)
	fg = foreground(big)
	comp = Image.alpha_composite(bg, fg)
	crop = int(big * 0.17)  # el adaptativo reserva ~1/6 por lado
	comp = comp.crop((crop, crop, big - crop, big - crop)).resize((size * SS, size * SS), Image.LANCZOS)
	if rounded:
		mask = Image.new("L", comp.size, 0)
		ImageDraw.Draw(mask).rounded_rectangle((0, 0, comp.size[0] - 1, comp.size[1] - 1), radius=comp.size[0] * 0.22, fill=255)
		comp.putalpha(mask)
	return comp.resize((size, size), Image.LANCZOS)


def main():
	os.makedirs(OUT, exist_ok=True)
	fg = foreground(432)
	background(432).save(os.path.join(OUT, "icon_background_432.png"))
	fg.save(os.path.join(OUT, "icon_foreground_432.png"))
	monochrome().save(os.path.join(OUT, "icon_monochrome_432.png"))
	flat(192).save(os.path.join(OUT, "icon_192.png"))
	flat(1024).save(os.path.join(OUT, "icon_1024.png"))
	print("Iconos generados en", os.path.abspath(OUT))


if __name__ == "__main__":
	main()
