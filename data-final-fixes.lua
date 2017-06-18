local lococount = 0
for _, loco in pairs(data.raw["locomotive"]) do
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
  lococount=lococount+1
end
-- log("[LTN] "..lococount.." locomotives added")

wagoncount = 0
for _, wagon in pairs(data.raw["cargo-wagon"]) do
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
  wagoncount=wagoncount+1
end
for _, wagon in pairs(data.raw["fluid-wagon"]) do
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
  wagoncount=wagoncount+1
end
-- log("[LTN] "..wagoncount.." wagons added")

-- sum items, fluids and train composition signals for number of slots required in stop output
-- items may be are generated after this so additional safeguard in updating the output needs to be taken
-- turns out there are a lot of specialized types that act as items
local itemtypes =
{
  "item",
  "item-with-entity-data",  -- 0.13
  "item-with-label",        -- 0.13
  "module",
  "tool",                   -- science packs
  "armor",
  "gun",
  "ammo",
  "capsule",
  "repair-tool",
  "mining-tool",
  "selection-tool",
  "blueprint",
  "blueprint-book",
  "rail-planner",           -- no idea what that even is
}
local itemcount = 0
for _, itemtype in pairs(itemtypes) do
  for _, v in pairs(data.raw[itemtype]) do
    -- log("item type: "..v.type..", name: "..v.name)
    itemcount = itemcount + 1
  end
end
local fluidcount = 0
for _, v in pairs(data.raw["fluid"]) do
  fluidcount = fluidcount + 1
end
data.raw["constant-combinator"]["logistic-train-stop-output"].item_slot_count = lococount + wagoncount + itemcount + fluidcount
log("[LTN] found "..tostring(itemcount).." items, "..tostring(fluidcount).." fluids, "..tostring(lococount).." locomotives, "..tostring(wagoncount).." wagons")
