local i = 0
log("[LTN] generating virtual signals")
for k, loco in pairs(data.raw["locomotive"]) do
  local signal = {
    type = "virtual-signal",
    name = "LTN-"..loco.name,
    icon = loco.icon,
    subgroup = "LTN-signal",
    order = "z[LTN-signal]-ba",
    localised_name = {"virtual-signal-name.LTN-locomotive", "#", {"entity-name." .. loco.name}}
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
    order = "z[LTN-signal]-bb",
    localised_name = {"virtual-signal-name.LTN-wagon", "#", {"entity-name." .. wagon.name}}
  }
  data:extend({signal})
  i=i+1
end
log("[LTN] "..i.." wagons added")