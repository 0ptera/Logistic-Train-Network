--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local flib = require('__flib__.data-util')

local icon_encoded_position = { { icon = "__LogisticTrainNetwork__/graphics/icons/encoded-position.png", icon_size = 64, tint = {r=1, g=1, b=1, a=1} } }

local function create_signal(prototype, order)
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..prototype.name,
    icons = flib.create_icons(prototype, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal",
    order = order,
    localised_name = {"virtual-signal-name.ltn-position", prototype.localised_name or {"entity-name." .. prototype.name}}
  }
  data:extend({signal})
end

local lococount = 0
for _, loco in pairs(data.raw["locomotive"]) do
  lococount=lococount+1
  create_signal(loco, "a"..string.format("%02d", lococount))
end

local wagoncount = 0
for _, wagon in pairs(data.raw["cargo-wagon"]) do
  wagoncount=wagoncount+1
  create_signal(wagon, "b"..string.format("%02d", wagoncount))
end

local wagoncount_fluid = 0
for _, wagon in pairs(data.raw["fluid-wagon"]) do
  wagoncount_fluid=wagoncount_fluid+1
  create_signal(wagon, "c"..string.format("%02d", wagoncount_fluid))
end

local wagoncount_artillery = 0
for _, wagon in pairs(data.raw["artillery-wagon"]) do
  wagoncount_artillery=wagoncount_artillery+1
  create_signal(wagon, "d"..string.format("%02d", wagoncount_artillery))
end

-- sum items, fluids and train composition signals for number of slots required in stop output
-- badly written mods may generate prototypes in final-fixes after this so additional safeguard in updating the output needs to be taken
-- turns out there are a lot of specialized types that act as items
local itemcount = 0
local fluidcount = 0
for type, type_data in pairs(data.raw) do
  for item_name, item in pairs(type_data) do
    if item.stack_size then
      itemcount = itemcount + 1
    end
    if type == "fluid" then
      fluidcount = fluidcount + 1
    end
  end
end

data.raw["constant-combinator"]["logistic-train-stop-output"].item_slot_count = 4 + lococount + wagoncount + wagoncount_fluid + wagoncount_artillery + itemcount + fluidcount
log(string.format("[LTN] found %d items, %d fluids, %d locomotives, %d cargo wagons, %d fluid wagons, %d artillery wagons.", itemcount, fluidcount, lococount, wagoncount, wagoncount_fluid, wagoncount_artillery))
