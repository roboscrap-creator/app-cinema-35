from PIL import Image, ImageDraw, ImageFont
import os

def criar_icone(tamanho):
    img = Image.new("RGBA", (tamanho, tamanho), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pad = int(tamanho * 0.03)
    borda = max(3, int(tamanho * 0.035))

    # Círculo externo dourado e fundo azul-marinho escuro
    draw.ellipse([pad, pad, tamanho - pad, tamanho - pad], fill=(255, 196, 0, 255))
    draw.ellipse([pad + borda, pad + borda, tamanho - pad - borda, tamanho - pad - borda], fill=(12, 16, 62, 255))

    # Esfera brilhante estilo Play (ciano -> magenta) no topo direito
    cx, cy, r = int(tamanho * 0.63), int(tamanho * 0.35), int(tamanho * 0.145)
    for y in range(cy - r, cy + r):
        for x in range(cx - r, cx + r):
            dx, dy = x - cx, y - cy
            if dx*dx + dy*dy <= r*r:
                t = (dy + r) / (2.0 * r)
                cr = int(0 * (1 - t) + 230 * t)
                cg = int(215 * (1 - t) + 30 * t)
                cb = int(255 * (1 - t) + 245 * t)
                img.putpixel((x, y), (cr, cg, cb, 255))

    # Brilho branco na esfera e triângulo Play
    draw.ellipse([cx - int(r*0.55), cy - int(r*0.65), cx - int(r*0.1), cy - int(r*0.25)], fill=(255, 255, 255, 180))
    tri = [
        (cx - int(r * 0.28), cy - int(r * 0.38)),
        (cx - int(r * 0.28), cy + int(r * 0.38)),
        (cx + int(r * 0.42), cy)
    ]
    draw.polygon(tri, fill=(255, 255, 255, 255))

    # Fonte arredondada/negrito para escrever "Cinema"
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
    ]
    font_path = next((p for p in font_paths if os.path.exists(p)), None)
    f_size = int(tamanho * 0.22)
    font = ImageFont.truetype(font_path, f_size) if font_path else ImageFont.load_default()

    texto = "Cinema"
    bbox = draw.textbbox((0, 0), texto, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (tamanho - tw) // 2
    ty = int(tamanho * 0.50)

    # Sombra e texto dourado/laranja vibrante
    draw.text((tx + max(2, tamanho // 80), ty + max(2, tamanho // 80)), texto, font=font, fill=(140, 60, 0, 255))
    draw.text((tx, ty), texto, font=font, fill=(255, 198, 10, 255))

    return img

densidades = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for pasta, px in densidades.items():
    destino = f"android/app/src/main/res/{pasta}/ic_launcher.png"
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    criar_icone(px).save(destino)
    print(f"Icone gerado: {destino} ({px}x{px})")
