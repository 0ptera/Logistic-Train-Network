for i, loco in pairs(data.raw["locomotive"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTV-"..loco.name,
    icon = loco.icon,
    subgroup = "virtual-signal",
    order = "l",
    localised_name = {"signal-name.LTV-locomotive", "#", {"entity-name." .. loco.name}}
  }
  data:extend({signal})
end

for i, wagon in pairs(data.raw["cargo-wagon"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTV-"..wagon.name,
    icon = wagon.icon,
    subgroup = "virtual-signal",
    order = "m",
    localised_name = {"signal-name.LTV-wagon", "#", {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
end
