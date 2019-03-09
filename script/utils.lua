--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
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


function GetMainLocomotive(train)
  if train.valid and train.locomotives and (#train.locomotives.front_movers > 0 or #train.locomotives.back_movers > 0) then
    return train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
  end
end

function GetTrainID(train)
  local loco = GetMainLocomotive(train)
  return loco and loco.unit_number
end

function GetTrainName(train)
  local loco = GetMainLocomotive(train)
  return loco and loco.backer_name
end

--local square = math.sqrt
function GetDistance(a, b)
  local x, y = a.x-b.x, a.y-b.y
  --return square(x*x+y*y) -- sqrt shouldn't be necessary for comparing distances
  return (x*x+y*y)
end
