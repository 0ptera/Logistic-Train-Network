local i = 0
log("[LTN] generating virtual signals")
for k, loco in pairs(data.raw["locomotive"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..loco.name,
    icon = "__base__/graphics/icons/diesel-locomotive.png", --fallback
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-u",
    localised_name = {"virtual-signal-name.LTN-locomotive", {"entity-name." .. loco.name}}
  }
  if loco.icon then
    signal.icon = loco.icon
  elseif loco.icons then
    signal.icon = nil
    signal.icons = loco.icons
  end
  data:extend({signal})
  i=i+1
end
log("[LTN] "..i.." locomotives added")
i = 0
for k, wagon in pairs(data.raw["cargo-wagon"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icon = "__base__/graphics/icons/cargo-wagon.png", --fallback
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-v",
    localised_name = {"virtual-signal-name.LTN-wagon", {"entity-name." .. wagon.name}}
  }
  if wagon.icon then
    signal.icon = wagon.icon
  elseif wagon.icons then
    signal.icon = nil
    signal.icons = wagon.icons
  end
  data:extend({signal})
  i=i+1
end
for k, wagon in pairs(data.raw["fluid-wagon"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icon = "__base__/graphics/icons/fluid-wagon.png", --fallback
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-v",
    localised_name = {"virtual-signal-name.LTN-wagon", {"entity-name." .. wagon.name}}
  }
  if wagon.icon then
    signal.icon = wagon.icon
  elseif wagon.icons then
    signal.icon = nil
    signal.icons = wagon.icons
  end
  data:extend({signal})
  i=i+1
end
log("[LTN] "..i.." wagons added")