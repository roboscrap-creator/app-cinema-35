from PIL import Image, ImageDraw
import os

def criar_icone(tamanho, caminho):
    img = Image.new("RGBA", (tamanho, tamanho), (11, 13, 18, 255))
    draw = ImageDraw.Draw(img)

    # Fundo com borda dourada elegante
    pad = int(tamanho * 0.06)
    raio = int(tamanho * 0.22)
    draw.rounded_rectangle(
        [pad, pad, tamanho - pad, tamanho - pad],
        radius=raio,
        fill=(22, 26, 36, 255),
        outline=(245, 184, 46, 255),
        width=max(3, tamanho // 36),
    )

    # Emblema central dourado
    cx, cy = tamanho // 2, tamanho // 2
    r_inner = int(tamanho * 0.28)
    draw.ellipse(
        [cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner],
        fill=(245, 184, 46, 255),
    )

    # Triangulo Play escuro nitido no centro
    p1 = (cx - int(r_inner * 0.32), cy - int(r_inner * 0.46))
    p2 = (cx - int(r_inner * 0.32), cy + int(r_inner * 0.46))
    p3 = (cx + int(r_inner * 0.52), cy)
    draw.polygon([p1, p2, p3], fill=(11, 13, 18, 255))

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
print("Icone CineMax gerado!")
