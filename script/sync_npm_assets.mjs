import { copyFileSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")

const assets = [
  [
    "node_modules/echarts/dist/echarts.esm.min.js",
    "app/assets/npm/echarts.esm.min.js"
  ],
  [
    "node_modules/@sjmc11/tourguidejs/dist/tour.js",
    "app/assets/npm/tour.js"
  ],
  [
    "node_modules/@sjmc11/tourguidejs/dist/css/tour.min.css",
    "app/assets/npm/css/tour.min.css"
  ]
]

for (const [source, destination] of assets) {
  const sourcePath = join(root, source)
  const destinationPath = join(root, destination)

  mkdirSync(dirname(destinationPath), { recursive: true })
  copyFileSync(sourcePath, destinationPath)
}
