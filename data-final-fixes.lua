--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local flib = require('__flib__.data-util')

local icon_encoded_position = { { icon = "__LogisticTrainNetwork__/graphics/icons/encoded-position.png", icon_size = 64, tint = {r=1, g=1, b=1, a=1} } }
local icon_empty = { { icon = "__core__/graphics/empty.png", icon_size = 1, tint = {r=1, g=1, b=1, a=1} } }
local proto_empty = { icons =  icon_empty }

local function is_hidden(proto)
  if proto.flags then
    for _,flag in pairs(proto.flags) do
      if (flag == "hidden") then
        return true
      end
    end
  end
  return false
end

local function scaled_icon(icon, second)
   local size = icon.icon_size or 32
   local shift = icon.shift or {x = 0, y = 0}
   -- empty icon scales things up 32 times bigger and we want half size
   local scale = (icon.scale or 32 / size) / 64
   local dx
   if second then
     dx = 0.25
   else
     dx = -0.25
   end
   return {
     icon = icon.icon,
     icon_size = size,
     icon_mipmaps = icon.icon_mipmaps or 0,
     tint = icon.tint,
     scale = scale,
     -- empty icon scales things up 32 times bigger and we want half size
     shift = {
       x = shift.x / 64 + dx,
       y = shift.y / 64,
     },
   }
end

local function scale_icons(icons, proto, second)
  if proto.icon then
    local icon = {
       icon = proto.icon,
       icon_size = proto.icon_size,
       icon_mipmaps = proto.icon_mipmaps,
       tint = {r=1, g=1, b=1, a=1}
      }
    icons[#icons+1] = scaled_icon(icon, second)
  elseif proto.icons then
    for _, v in pairs(proto.icons) do
      icons[#icons+1] = scaled_icon(v, second)
    end
  end
end

local function train_signal(loco, wagon, order, suffix)
  local wagoncount = 0
  if not is_hidden(wagon) then
    wagoncount = wagoncount + 1
    -- scale icons
    local icons = {}
    scale_icons(icons, loco, false)
    scale_icons(icons, wagon, true)
    -- create signal
    local localised_name
    local loco_name = loco.localized_name or loco.name
    local wagon_name = wagon.localized_name or wagon.name

    if loco.type == "virtual-signal" then
      if wagon.type == "virtual-signal" then
        localised_name = {"virtual-signal-name.ltn-train-any-any", suffix}
      else
        localised_name = {"virtual-signal-name.ltn-train-any", wagon_name}
      end
    else
      if wagon.type == "virtual-signal" then
         localised_name = {"virtual-signal-name.ltn-train-any", loco_name}
      else
         localised_name = {"virtual-signal-name.ltn-train", loco_name, wagon_name}
      end
    end

    local signal = {
      type = "virtual-signal",
      name = "ltn-train-"..suffix.."-"..loco.name.."-"..wagon.name,
      icons = flib.create_icons(proto_empty, icons) or empty_icon,
      icon_size = nil,
      subgroup = "ltn-train-signal-"..suffix,
      order = order,
      localised_name = localised_name,
    }
    data:extend({signal})
  end
end

local function train_signals(loco, lococount)
  if not is_hidden(loco) then
    -- add cargo wagons to train  
    local wagoncount = 0
    for _, wagon in pairs(data.raw["cargo-wagon"]) do
      wagoncount = wagoncount + 1
      local order = "a-cargo-"..string.format("%02d", lococount)..string.format("%02d", wagoncount)
      train_signal(loco, wagon, order, "cargo")
    end
    if wagoncount > 1 then
      local order = "a-cargo-"..string.format("%02d", lococount).."00"
      train_signal(loco, data.raw["virtual-signal"]["ltn-position-any-cargo-wagon"], oder, "cargo")
    end
    -- add fluid wagons to train  
    wagoncount = 0
    for _, wagon in pairs(data.raw["fluid-wagon"]) do
      wagoncount = wagoncount + 1
      local order = "a-fluid-"..string.format("%02d", lococount)..string.format("%02d", wagoncount)
      train_signal(loco, wagon, order, "fluid")
    end
    if wagoncount > 1 then
      local order = "a-cargo-"..string.format("%02d", lococount).."00"
      train_signal(loco, data.raw["virtual-signal"]["ltn-position-any-fluid-wagon"], order, "fluid")
    end
    -- add fluid wagons to train  
    wagoncount = 0
    for _, wagon in pairs(data.raw["artillery-wagon"]) do
      wagoncount = wagoncount + 1
      local order = "a-artillery-"..string.format("%02d", lococount)..string.format("%02d", wagoncount)
      train_signal(loco, wagon, order, "artillery")
    end
    if wagoncount > 1 then
      local order = "a-artillery-"..string.format("%02d", lococount).."00"
      train_signal(loco, data.raw["virtual-signal"]["ltn-position-any-artillery-wagon"], order, "artillery")
    end
  end   
end

local lococount = 0
for _, loco in pairs(data.raw["locomotive"]) do
  lococount=lococount+1
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..loco.name,
    icons = flib.create_icons(loco, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal",
    order = "a"..string.format("%02d", lococount),
    localised_name = {"virtual-signal-name.ltn-position", loco.localised_name or {"entity-name." .. loco.name}}
  }
  data:extend({signal})
  train_signals(loco, lococount)
end
if lococount > 1 then
  train_signals(data.raw["virtual-signal"]["ltn-position-any-locomotive"], 0)
end

local wagoncount = 0
for _, wagon in pairs(data.raw["cargo-wagon"]) do
  wagoncount=wagoncount+1
  local signal = {
    type = "virtual-signal",
    name = "ltn-position-"..wagon.name,
    icons = flib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal",
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
    icons = flib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal",
    order = "c"..string.format("%02d", wagoncount_fluid),
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
    icons = flib.create_icons(wagon, icon_encoded_position) or icon_encoded_position,
    icon_size = nil,
    subgroup = "ltn-position-signal",
    order = "d"..string.format("%02d", wagoncount_artillery),
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

for _, loco in pairs(data.raw["locomotive"]) do
end
