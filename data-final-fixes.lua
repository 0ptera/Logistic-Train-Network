--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local optera_lib = require("__OpteraLib__.data.utilities")

local icon_encoded_position = { { icon = "__LogisticTrainNetwork__/graphics/icons/encoded-position.png", icon_size = 32, tint = {r=1, g=1, b=1, a=1} } }

local lococount = 0
for _, loco in pairs(data.raw["locomotive"]) do
  lococount=lococount+1
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..loco.name,
    icons = optera_lib.create_icons(loco, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal-locomotive",
    order = "b"..string.format("%02d", lococount),
    localised_name = {"virtual-signal-name.ltn-position", loco.localised_name or {"entity-name." .. loco.name}}
  }
  data:extend({signal})
end

local wagoncount = 0
for _, wagon in pairs(data.raw["cargo-wagon"]) do
  wagoncount=wagoncount+1
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..wagon.name,
    icons = optera_lib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal-cargo-wagon",
    order = "b"..string.format("%02d", wagoncount),
    localised_name = {"virtual-signal-name.ltn-position", wagon.localised_name or {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
end

local wagoncount_fluid = 0
for _, wagon in pairs(data.raw["fluid-wagon"]) do
  wagoncount_fluid=wagoncount_fluid+1
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..wagon.name,
    icons = optera_lib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal-fluid-wagon",
    order = "b"..string.format("%02d", wagoncount_fluid),
    localised_name = {"virtual-signal-name.ltn-position", wagon.localised_name or {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
end

local wagoncount_artillery = 0
for _, wagon in pairs(data.raw["artillery-wagon"]) do
  wagoncount_artillery=wagoncount_artillery+1
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..wagon.name,
    icons = optera_lib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal-artillery-wagon",
    order = "b"..string.format("%02d", wagoncount_artillery),
    localised_name = {"virtual-signal-name.ltn-position", wagon.localised_name or {"entity-name." .. wagon.name}}
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

data.raw["constant-combinator"]["logistic-train-stop-output"].item_slot_count = 4 + lococount + wagoncount + wagoncount_fluid + wagoncount_artillery + itemcount + fluidcount
log("[LTN] found "..tostring(itemcount).." items, "..tostring(fluidcount).." fluids, "..tostring(lococount).." locomotives, "..tostring(wagoncount + wagoncount_fluid + wagoncount_artillery).." wagons")

