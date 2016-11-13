for i, loco in pairs(data.raw["locomotive"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..loco.name,
    icon = loco.icon,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ba",
    localised_name = {"virtual-signal-name.LTN-locomotive", "#", {"entity-name." .. loco.name}}
  }
  data:extend({signal})
end

for i, wagon in pairs(data.raw["cargo-wagon"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..wagon.name,
    icon = wagon.icon,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-bb",
    localised_name = {"virtual-signal-name.LTN-wagon", "#", {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
end
