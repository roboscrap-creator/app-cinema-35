from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

def _carregar_fonte(tamanho):
    candidatos = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/system/fonts/Roboto-Bold.ttf",
    ]
    for c in candidatos:
        if os.path.exists(c):
            return ImageFont.truetype(c, tamanho)
    return ImageFont.load_default()

def criar_icone(tamanho, caminho):
    img = Image.new("RGBA", (tamanho, tamanho), (11, 13, 18, 255))
    glow = Image.new("RGBA", (tamanho, tamanho), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)

    pad = int(tamanho * 0.06)
    raio = int(tamanho * 0.22)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle(
        [pad, pad, tamanho - pad, tamanho - pad],
        radius=raio,
        fill=(15, 18, 26, 255),
        outline=(245, 184, 46, 220),
        width=max(2, tamanho // 42),
    )

    # Triangulo Modern Play dourado com brilho
    cx, cy = int(tamanho * 0.52), tamanho // 2
    r = int(tamanho * 0.29)
    tri = [
        (cx - int(r * 0.65), cy - int(r * 0.85)),
        (cx - int(r * 0.65), cy + int(r * 0.85)),
        (cx + int(r * 0.85), cy),
    ]
    gdraw.polygon(tri, outline=(245, 184, 46, 255), width=max(4, tamanho // 18))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(2, tamanho // 28)))
    img = Image.alpha_composite(img, glow)

    draw = ImageDraw.Draw(img)
    draw.polygon(tri, outline=(255, 223, 115, 255), width=max(2, tamanho // 28))

    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    img.save(caminho, "PNG")

def criar_banner_tv(caminho):
    w, h = 320, 180
    img = Image.new("RGBA", (w, h), (10, 12, 17, 255))
    draw = ImageDraw.Draw(img)

    # Gradiente sutil de fundo
    for y in range(h):
        c = int(10 + (y / h) * 8)
        draw.line([(0, y), (w, y)], fill=(c, c + 2, c + 7, 255))

    # Brilho radial dourado centralizado
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    cx, cy = w // 2, h // 2
    gdraw.ellipse([cx - 95, cy - 55, cx + 95, cy + 55], fill=(245, 184, 46, 42))

    # Triangulo Modern Play neon atras do texto CineMAX
    tri = [
        (cx - 28, cy - 56),
        (cx - 28, cy + 56),
        (cx + 68, cy),
    ]
    gdraw.polygon(tri, outline=(245, 184, 46, 255), width=7)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=6))
    img = Image.alpha_composite(img, glow)

    draw = ImageDraw.Draw(img)
    draw.polygon(tri, outline=(255, 226, 130, 255), width=3)

    # Tipografia Cine (dourado) + MAX (branco nitido)
    fonte = _carregar_fonte(40)
    txt_cine = "Cine"
    txt_max = "MAX"
    b_cine = draw.textbbox((0, 0), txt_cine, font=fonte)
    b_max = draw.textbbox((0, 0), txt_max, font=fonte)
    w_cine = b_cine[2] - b_cine[0]
    w_max = b_max[2] - b_max[0]
    h_txt = b_cine[3] - b_cine[1]

    x_inicio = (w - (w_cine + w_max + 2)) // 2
    y_inicio = (h - h_txt) // 2 - 4

    # Sombra suave atras das letras para leitura nitida sobre o triangulo
    draw.text((x_inicio + 2, y_inicio + 2), txt_cine, font=fonte, fill=(8, 10, 14, 220))
    draw.text((x_inicio + w_cine + 4, y_inicio + 2), txt_max, font=fonte, fill=(8, 10, 14, 220))

    draw.text((x_inicio, y_inicio), txt_cine, font=fonte, fill=(245, 184, 46, 255))
    draw.text((x_inicio + w_cine + 2, y_inicio), txt_max, font=fonte, fill=(255, 255, 255, 255))

    # Borda externa sutil
    draw.rounded_rectangle([2, 2, w - 3, h - 3], radius=14, outline=(245, 184, 46, 110), width=2)

    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    img.save(caminho, "PNG")

densidades = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for pasta, px in densidades.items():
    criar_icone(px, f"android/app/src/main/res/{pasta}/ic_launcher.png")
criar_banner_tv("android/app/src/main/res/drawable/tv_banner.png")
print("Icone e Banner Modern Play CineMax gerados!")
