import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const mapPath = path.join(root, "config", "streamline_icons.yml");
const iconsPath = path.join(root, "node_modules", "@iconify-json", "streamline-freehand", "icons.json");
const outputPath = path.join(root, "app", "assets", "images", "streamline-freehand.svg");

function readIconMap(filePath) {
  return fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .reduce((iconMap, line, index) => {
      const trimmed = line.replace(/\s+#.*$/, "").trim();
      if (!trimmed) return iconMap;

      const match = trimmed.match(/^([A-Za-z0-9_]+):\s*([A-Za-z0-9_-]+)$/);
      if (!match) {
        throw new Error(`Invalid icon map entry at ${filePath}:${index + 1}`);
      }

      iconMap[match[1]] = match[2];
      return iconMap;
    }, {});
}

function escapeAttribute(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

const iconMap = readIconMap(mapPath);
const collection = JSON.parse(fs.readFileSync(iconsPath, "utf8"));
const width = collection.width || 24;
const height = collection.height || 24;

const symbols = Object.entries(iconMap).map(([key, iconName]) => {
  const icon = collection.icons[iconName];
  if (!icon) {
    throw new Error(`Streamline icon "${iconName}" for "${key}" was not found`);
  }

  const viewBox = [
    icon.left || 0,
    icon.top || 0,
    icon.width || width,
    icon.height || height
  ].join(" ");

  return [
    `  <symbol id="streamline-${escapeAttribute(key.replaceAll("_", "-"))}" viewBox="${escapeAttribute(viewBox)}">`,
    `    ${icon.body}`,
    "  </symbol>"
  ].join("\n");
});

const sprite = [
  '<svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true">',
  "  <!-- Generated from @iconify-json/streamline-freehand. Streamline Freehand free icons are licensed under CC BY 4.0. -->",
  ...symbols,
  "</svg>",
  ""
].join("\n");

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, sprite);
console.log(`Generated ${symbols.length} Streamline icons at ${path.relative(root, outputPath)}`);
