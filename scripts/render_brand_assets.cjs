// Dev-only: KASATA_SHARP_MODULE may point at an installed sharp package.
// Master SVGs are the source of truth; no runtime asset dependencies are added.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require(process.env.KASATA_SHARP_MODULE || 'sharp');
const root = path.resolve(__dirname, '..');

async function raster(svg, destination, width, height = width) {
  await fs.mkdir(path.dirname(destination), { recursive: true });
  await sharp(svg).resize(width, height).png().toFile(destination);
}

async function main() {
  const icon = await fs.readFile(path.join(root, 'assets/images/sajia_app_icon.svg'));
  const launcher = await fs.readFile(path.join(root, 'assets/images/sajia_launcher_icon.svg'));
  const lockup = await fs.readFile(path.join(root, 'assets/images/sajia_logo_lockup.svg'));
  await raster(icon, path.join(root, 'assets/images/sajia_app_icon.png'), 1024);
  await raster(launcher, path.join(root, 'assets/images/sajia_launcher_icon.png'), 1024);
  await sharp(lockup).resize({ width: 1200 }).png().toFile(path.join(root, 'assets/images/sajia_logo_lockup.png'));
  for (const [density, size] of Object.entries({mdpi:48, hdpi:72, xhdpi:96, xxhdpi:144, xxxhdpi:192})) {
    await raster(launcher, path.join(root, 'android/app/src/main/res', 'mipmap-' + density, 'ic_launcher.png'), size);
  }
  for (const size of [192, 512]) {
    await raster(icon, path.join(root, 'web/icons/Icon-' + size + '.png'), size);
    await raster(launcher, path.join(root, 'web/icons/Icon-maskable-' + size + '.png'), size);
  }
  await raster(icon, path.join(root, 'web/favicon.png'), 32);
  await raster(icon, path.join(root, 'site/assets/sajia_app_icon.png'), 192);
  for (const platform of ['ios', 'macos']) {
    const folder = path.join(root, platform, 'Runner/Assets.xcassets/AppIcon.appiconset');
    const manifest = JSON.parse(await fs.readFile(path.join(folder, 'Contents.json'), 'utf8'));
    for (const image of manifest.images) {
      if (!image.filename) continue;
      const size = Math.round(parseFloat(image.size) * parseFloat(image.scale));
      await raster(launcher, path.join(folder, image.filename), size);
    }
  }
  const png = await sharp(icon).resize(256, 256).png().toBuffer();
  const ico = Buffer.alloc(22);
  ico.writeUInt16LE(1, 2);
  ico.writeUInt16LE(1, 4);
  ico.writeUInt16LE(1, 10);
  ico.writeUInt16LE(32, 12);
  ico.writeUInt32LE(png.length, 14);
  ico.writeUInt32LE(22, 18);
  await fs.writeFile(path.join(root, 'windows/runner/resources/app_icon.ico'), Buffer.concat([ico, png]));
  await fs.copyFile(path.join(root, 'assets/images/sajia_app_icon.svg'), path.join(root, 'lib/files/app_icon.svg'));
  console.log('Brand assets rendered from master SVGs.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
