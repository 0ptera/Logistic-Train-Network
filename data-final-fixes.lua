--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

optera_lib = optera_lib or {}

local icon_encoded_position = { { icon = "__LogisticTrainNetwork__/graphics/icons/encoded-position.png", icon_size = 32, tint = {r=1, g=1, b=1, a=1} } }

local lococount = 0
for _, loco in pairs(data.raw["locomotive"]) do
  lococount=lococount+1
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..loco.name,
    icons = optera_lib.create_icons(loco, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-u"..string.format("%02d", lococount),
    localised_name = {"virtual-signal-name.LTN-locomotive", {"entity-name." .. loco.name}}
  }
  data:extend({signal})
end

wagoncount = 0
for _, wagon in pairs(data.raw["cargo-wagon"]) do
  wagoncount=wagoncount+1
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icons = optera_lib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-v"..string.format("%02d", wagoncount),
    localised_name = {"virtual-signal-name.LTN-wagon", {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
end
for _, wagon in pairs(data.raw["fluid-wagon"]) do
  wagoncount=wagoncount+1
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icons = optera_lib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-v"..string.format("%02d", wagoncount),
    localised_name = {"virtual-signal-name.LTN-wagon", {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
end
for _, wagon in pairs(data.raw["artillery-wagon"]) do
  wagoncount=wagoncount+1
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icons = optera_lib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-v"..string.format("%02d", wagoncount),
    localised_name = {"virtual-signal-name.LTN-wagon", {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
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

data.raw["constant-combinator"]["logistic-train-stop-output"].item_slot_count = lococount + wagoncount + itemcount + fluidcount
log("[LTN] found "..tostring(itemcount).." items, "..tostring(fluidcount).." fluids, "..tostring(lococount).." locomotives, "..tostring(wagoncount).." wagons")

