from PIL import Image
from pathlib import Path

SOURCE = Path(r"C:/Users/wyeeb/.openclaude/image-cache/389f5d16-8e37-4688-874d-bafae64090b3/7.png")
ROOT = Path(r"F:/OC/Projetos/SteamAchievementsAPK/android/app/src/main/res")
OUT_ROOT_ICON = Path(r"F:/OC/Projetos/SteamAchievementsAPK/icon_preview_512.png")
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# The source image is the approved 12B preview. Crop only the launcher icon,
# excluding the outer screenshot background, then resize for Android densities.
source = Image.open(SOURCE).convert("RGBA")
# Crop bounds tuned for the approved 344x301 screenshot.
icon = source.crop((49, 20, 296, 267)).resize((512, 512), Image.Resampling.LANCZOS)

OUT_ROOT_ICON.parent.mkdir(parents=True, exist_ok=True)
icon.save(OUT_ROOT_ICON)

for folder, size in SIZES.items():
    out = ROOT / folder / "ic_launcher.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    icon.resize((size, size), Image.Resampling.LANCZOS).save(out)

print(f"Generated icons from {SOURCE}")
print(f"Preview: {OUT_ROOT_ICON}")
