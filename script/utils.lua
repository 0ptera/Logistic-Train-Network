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
  local artillery = 0
  if train and train.valid then
    for _,wagon in pairs(train.cargo_wagons) do
      local capacity = global.WagonCapacity[wagon.name] or getCargoWagonCapacity(wagon)
      inventorySize = inventorySize + capacity
    end
    for _,wagon in pairs(train.fluid_wagons) do
      local capacity = global.WagonCapacity[wagon.name] or getFluidWagonCapacity(wagon)
      fluidCapacity = fluidCapacity + capacity
    end
    for _,carriage in pairs(train.carriages) do
      if carriage.type == "artillery-wagon" then
        artillery = 1
      end
    end
  end
  return inventorySize, fluidCapacity, artillery
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

-- returns 1 if the train counts for the virtual signal
function GetTrainSignalCount(train, signal)
  -- log("(GetTrainSignalCount) for train "..train.id.." and signal "..signal..")")
  locomotives = {}
  cargo = {}
  fluid = {}
  artillery = {}
  -- summarize train composition
  for _,carriage in pairs(train.carriages) do
    local proto = carriage.prototype
    if carriage.type == "locomotive" then
      locomotives[proto.name] = true
    elseif carriage.type == "cargo-wagon" then
      cargo[proto.name] = true
    elseif carriage.type == "fluid-wagon" then
      fluid[proto.name] = true
    elseif carriage.type == "artillery-wagon" then
      artillery[proto.name] = true
    end
  end
  -- split signal name into parts
  local t = global.TrainSignals[signal]
  local train_type = t.type
  local loco_type = t.locomotive
  local wagon_type = t.wagon
  --log("(GetTrainSignalCount) train_type = "..train_type..", loco_type = "..loco_type..", wagon_type = "..wagon_type)
  -- match locomotive
  if (loco_type ~= "any") and (locomotives[loco_type] == nil) then
    -- train doesn't have the right locmotive
    return 0
  end
  -- match type of train
  local wagons
  if train_type == "cargo" then
    wagons = cargo
  elseif train_type == "fluid" then
    wagons = fluid
  elseif train_type == "artillery" then
    wagons = artillery
  else
     -- no idea what train type that is
     return 0
  end
  -- match wagon
  if (wagon_type == "any") or wagons[wagon_type] then
    return 1
  end
  return 0
end
