--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 * Control stage utility functions
 *
 * See LICENSE.md in the project directory for license information.
--]]

--GetTrainCapacity(train)
local function getCargoWagonCapacity(entity)
  local capacity = entity.prototype.get_inventory_size(defines.inventory.cargo_wagon)
  -- log("(getCargoWagonCapacity) capacity for "..entity.name.." = "..capacity)
  global.WagonCapacity[entity.name] = capacity
  return capacity
end

local function getFluidWagonCapacity(entity)
  local capacity = 0
  for n=1, #entity.fluidbox do
    capacity = capacity + entity.fluidbox.get_capacity(n)
  end
  -- log("(getFluidWagonCapacity) capacity for "..entity.name.." = "..capacity)
  global.WagonCapacity[entity.name] = capacity
  return capacity
end

-- returns inventory and fluid capacity of a given train
function GetTrainCapacity(train)
  local inventorySize = 0
  local fluidCapacity = 0
  if train and train.valid then
    for _,wagon in pairs(train.cargo_wagons) do
      local capacity = global.WagonCapacity[wagon.name] or getCargoWagonCapacity(wagon)
      inventorySize = inventorySize + capacity
    end
    for _,wagon in pairs(train.fluid_wagons) do
      local capacity = global.WagonCapacity[wagon.name] or getFluidWagonCapacity(wagon)
      fluidCapacity = fluidCapacity + capacity
    end
  end
  return inventorySize, fluidCapacity
end

-- returns rich text string for train stops, or nil if entity is invalid
function Make_Stop_RichText(entity)
  if entity and entity.valid then
    if message_include_gps then
      return format("[train-stop=%d] [gps=%s,%s,%s]", entity.unit_number, entity.position["x"], entity.position["y"], entity.surface.name)
    else
      return format("[train-stop=%d]", entity.unit_number)
    end
  else
    return nil
  end
end

-- returns rich text string for trains, or nil if entity is invalid
function Make_Train_RichText(train, train_name)
  local loco = Get_Main_Locomotive(train)
  if loco and loco.valid then
    return format("[train=%d] %s", loco.unit_number, train_name)
  else
    return format("[train=] %s", train_name)
  end
end