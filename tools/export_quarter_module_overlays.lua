-- Exports quarter-module hardware at its authored grid size. Each source
-- canvas is an odd number of 16px design cells; the center design cell is the
-- universal mount anchor and is centered on Base_Quarter's socket at runtime.
local source = app.activeSprite
if not source then
  error("Open Weapons_Tileset.aseprite before running this exporter")
end

local definitions = {
  {
    name = "thruster.png",
    canvas = Rectangle(64, 344, 48, 48),
    artwork = Rectangle(69, 346, 38, 38),
  },
  {
    name = "directional_shield.png",
    canvas = Rectangle(112, 344, 48, 48),
    artwork = Rectangle(112, 352, 48, 32),
  },
}

local source_image = Image(source.width, source.height, source.colorMode)
source_image:drawSprite(source, 1)
local source_directory = app.fs.filePath(source.filename)
local project_root = app.fs.filePath(app.fs.filePath(source_directory))
local output_directory = app.fs.joinPath(
  project_root,
  "assets",
  "sprites",
  "interiors",
  "rooms",
  "quarter",
  "overlays"
)

local exported_sprites = {}
for _, definition in ipairs(definitions) do
  local exported = Sprite(definition.canvas.width, definition.canvas.height, source.colorMode)
  local output_image = exported.cels[1].image
  -- Copy only the authored hardware. Checkerboard/guide pixels surrounding it
  -- must remain transparent in-game, especially after the canvas is rotated.
  local output_origin = Point(
    definition.artwork.x - definition.canvas.x,
    definition.artwork.y - definition.canvas.y
  )
  for y = 0, definition.artwork.height - 1 do
    for x = 0, definition.artwork.width - 1 do
      output_image:putPixel(
        output_origin.x + x,
        output_origin.y + y,
        source_image:getPixel(definition.artwork.x + x, definition.artwork.y + y)
      )
    end
  end
  exported:saveAs(app.fs.joinPath(output_directory, definition.name))
  table.insert(exported_sprites, exported)
  app.activeSprite = source
end
for _, exported in ipairs(exported_sprites) do
  exported:close()
end
