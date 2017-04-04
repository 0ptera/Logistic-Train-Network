local i = 0
log("[LTN] generating virtual signals")
for k, loco in pairs(data.raw["locomotive"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..loco.name,
    icon = loco.icon,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-u",
    localised_name = {"virtual-signal-name.LTN-locomotive", {"entity-name." .. loco.name}}
  }
  data:extend({signal})
  i=i+1
end
log("[LTN] "..i.." locomotives added")
i = 0
for k, wagon in pairs(data.raw["cargo-wagon"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icon = wagon.icon,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-v",
    localised_name = {"virtual-signal-name.LTN-wagon", {"entity-name." .. wagon.name}}
  }

  local inventorySize = wagon.inventory_size
  if wagon.name == "rail-tanker" then
    signal.icon = "__LogisticTrainNetwork__/graphics/icons/rail-tanker.png" -- fix RailTanker 1.4.0 showing cargo-wagon icon on entity
    inventorySize = 2500
  end

  local inventory = {
    type = "flying-text",
    name = "ltn-inventories["..wagon.name.."]",
    time_to_live = 0,
    speed = 1,
    order = tostring(inventorySize)
  }

  data:extend({signal})
  data:extend({inventory})
  i=i+1
end
log("[LTN] "..i.." wagons added")