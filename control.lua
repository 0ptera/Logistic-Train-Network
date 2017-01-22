require "config"
require "interface"

MOD_NAME = "LogisticTrainNetwork"
MINDELIVERYSIZE = "min-delivery-size"
MAXTRAINLENGTH = "max-train-length"
PRIORITY = "stop-priority"
ISDEPOT = "ltn-depot"

ErrorCodes = {
  "red",    -- circuit/signal error
  "pink"    -- duplicate stop name
}

-- Events

script.on_load(function()
	if global.LogisticTrainStops ~= nil and next(global.LogisticTrainStops) ~= nil then
		script.on_event(defines.events.on_tick, ticker) --subscribe ticker when train stops exist
    for stopID, stop in pairs(global.LogisticTrainStops) do --outputs are not stored in save
      UpdateStopOutput(stop)
    end
	end
  log("[LTN] on_load: complete")
  if global.useRailTanker then
    log("[LTN] fluid deliveries enabled")
  end
end)

script.on_init(function()
  initialize()
  local version = game.active_mods[MOD_NAME] or 0
  log("[LTN] on_init: ".. MOD_NAME.." "..version.." initialized.")
  if global.useRailTanker then
    log("[LTN] Rail Tanker "..game.active_mods["RailTanker"].." found, fluid deliveries enabled.")
  end
end)

script.on_configuration_changed(function(data)
  initialize()
  local loadmsg = MOD_NAME.." "..game.active_mods[MOD_NAME].." initialized."
  if data and data.mod_changes[MOD_NAME] then
    if data.mod_changes[MOD_NAME].old_version and data.mod_changes[MOD_NAME].new_version then
      loadmsg = MOD_NAME.." version changed from "..data.mod_changes[MOD_NAME].old_version.." to "..data.mod_changes[MOD_NAME].new_version.."."
    end
  end
  log("[LTN] on_configuration_changed: "..loadmsg)
  if global.useRailTanker then
    log("[LTN] Rail Tanker "..game.active_mods["RailTanker"].." found, fluid deliveries enabled.")
  end
end)

function initialize()
  -- check if RailTanker is installed
  if game.active_mods["RailTanker"] then
    global.useRailTanker = true
  else
    global.useRailTanker = false
  end

  -- initialize logger
  global.log_level = nil
  global.log_output = nil

  -- initialize stops
  global.LogisticTrainStops = global.LogisticTrainStops or {}
  if next(global.LogisticTrainStops) ~= nil then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].activeDeliveries = global.LogisticTrainStops[stopID].activeDeliveries or 0
      global.LogisticTrainStops[stopID].errorCode = global.LogisticTrainStops[stopID].errorCode or 0
      -- update to 0.3.8
      if stop.lampControl == nil then
        local lampctrl = stop.entity.surface.create_entity
        {
          name = "logistic-train-stop-lamp-control",
          position = stop.input.position,
          force = stop.entity.force
        }
        lampctrl.operable = false -- disable gui
        lampctrl.minable = false
        lampctrl.destructible = false -- don't bother checking if alive
        lampctrl.connect_neighbour({target_entity=stop.input, wire=defines.wire_type.green})
        lampctrl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-white"}, count = 1 }}}
        global.LogisticTrainStops[stopID].lampControl = lampctrl
        global.LogisticTrainStops[stopID].input.operable = false
        global.LogisticTrainStops[stopID].input.get_or_create_control_behavior().use_colors = true
        global.LogisticTrainStops[stopID].input.get_or_create_control_behavior().circuit_condition = {condition = {comperator=">",first_signal={type="virtual",name="signal-anything"}}}
      end

      UpdateStopOutput(stop) --make sure output is set
      --UpdateStop(stopID)
    end
    script.on_event(defines.events.on_tick, ticker) --subscribe ticker when train stops exist
  end

  -- initialize Dispatcher
  global.Dispatcher = global.Dispatcher or {}
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}

  --update to 0.5.0
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}

  -- update to 0.6.0
  global.Dispatcher.Requests = global.Dispatcher.Requests or {}
  global.Dispatcher.RequestAge = global.Dispatcher.RequestAge or {}

  -- clean obsolete global
  global.Dispatcher.Requested = nil
  global.Dispatcher.Orders = nil
  global.Dispatcher.OrderAge = nil
  global.Dispatcher.Storage = nil

  -- update to 0.4
  for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
    if delivery.shipment == nil then
      if delivery.item and delivery.count then
        global.Dispatcher.Deliveries[trainID].shipment = {[delivery.item] = delivery.count}
      else
        global.Dispatcher.Deliveries[trainID].shipment = {}
      end
    end
  end

end

script.on_event(defines.events.on_built_entity, function(event)
  local entity = event.created_entity
	if entity.name == "logistic-train-stop" then
    printmsg("Built Entity "..entity.name)
		CreateStop(entity)
    return
	end

  -- handle adding carriages to parked trains
  if entity.type == "locomotive" or entity.type == "cargo-wagon" then
    entity.train.manual_mode = true
    UpdateStopParkedTrain(entity.train)
    --entity.train.manual_mode = false
    return
  end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  local entity = event.created_entity
	if entity.name == "logistic-train-stop" then
    printmsg("Robots built Entity "..entity.name)
		CreateStop(entity)
	end
end)


script.on_event(defines.events.on_preplayer_mined_item, function(event)
  local entity = event.entity
  if entity.name == "logistic-train-stop" then
    RemoveStop(entity)
    return
  end

  -- handle removing carriages from parked trains
  if entity.type == "locomotive" or entity.type == "cargo-wagon" then
    entity.train.manual_mode = true
    UpdateStopParkedTrain(entity.train)
    --entity.train.manual_mode = false
    return
  end
end)

script.on_event(defines.events.on_robot_pre_mined, function(event)
  local entity = event.entity
  if entity.name == "logistic-train-stop" then
    RemoveStop(entity)
  end
end)

script.on_event(defines.events.on_entity_died, function(event)
  local entity = event.entity
  if entity.name == "logistic-train-stop" then
    RemoveStop(entity)
    return
  end

  -- handle removing carriages from parked trains
  if entity.type == "locomotive" or entity.type == "cargo-wagon" then
    entity.train.manual_mode = true
    UpdateStopParkedTrain(entity.train)
    --entity.train.manual_mode = false
    return
  end
end)

script.on_event(defines.events.on_train_changed_state, function(event)
  UpdateStopParkedTrain(event.train)
end)


function ticker(event)
  local tick = game.tick

  -- exit when there are no logistic train stops
  local next = next
  if global.LogisticTrainStops == nil or next(global.LogisticTrainStops) == nil then
    script.on_event(defines.events.on_tick, nil)
    if log_level >= 4 then printmsg("no LogisticTrainStops, unsubscribed from on_tick") end
    return
  end

  if tick % dispatcher_update_interval == 0 then
    -- clear Dispatcher.Storage
    global.Dispatcher.Provided = {}
    global.Dispatcher.Requests = {}

    -- update LogisticTrainStops
    for stopID, stop in pairs(global.LogisticTrainStops) do
      UpdateStop(stopID)
    end

    --clean up deliveries in case train was destroyed or removed
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
      if not delivery.train or not delivery.train.valid then
        if log_level >= 2 then printmsg("Delivery from "..delivery.from.." to "..delivery.to.." removed. Train no longer valid.") end
        removeDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if log_level >= 2 then printmsg("Delivery from "..delivery.from.." to "..delivery.to.." running for "..tick-delivery.started.." ticks removed after time out.") end
        removeDelivery(trainID)
      end
    end

    -- sort requests by age
    local sort = table.sort
    sort(global.Dispatcher.Requests, function(a, b)
        return a.age < b.age
      end)

    -- remove no longer active requests from global.Dispatcher.RequestAge[stopID]
    local newRequestAge = {}
    for _,request in pairs (global.Dispatcher.Requests) do
      local age = global.Dispatcher.RequestAge[request.stopID]
      if age then
        newRequestAge[request.stopID] = age
      end
    end
    global.Dispatcher.RequestAge = newRequestAge


    -- find best provider, merge shipments, find train, generate delivery, reset age
    for reqIndex, request in pairs (global.Dispatcher.Requests) do

      local delivery = ProcessRequest(request)
      if delivery then
        break
      end

    end

  end -- dispatcher update


end


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

-- creates a single delivery from a given request
-- returns generated delivery or nil
function ProcessRequest(request)
  local match = string.match
  local ceil = math.ceil
  local stopID = request.stopID
  local requestStation = global.LogisticTrainStops[stopID]
  local minDelivery = requestStation.minDelivery
  local orders = {}
  local deliveries = nil

  -- find providers for requested items
  for item, count in pairs (request.itemlist) do
    -- split merged key into type & name
    local itype, iname = match(item, "([^,]+),([^,]+)")
    if not (itype and iname) then
      if log_level >= 1 then printmsg("Error(ProcessRequest): could not parse item "..item) end
      goto skipRequestItem
    end

    -- ignore fluids without rail tanker
    if itype == "fluid" and not global.useRailTanker then
      if log_level >= 3 then printmsg("Notice: fluid transport requires Rail Tanker") end
      goto skipRequestItem
    end

     -- get providers ordered by priority
    local providers = GetStations(requestStation.entity.force, item, minDelivery)
    if not providers or #providers < 1 then
      if log_level >= 3 then printmsg("Notice: no station supplying "..item.." found") end
      goto skipRequestItem
    end

    -- only one delivery is created so use only the best provider
    local providerStation = providers[1]

    -- set count to availability of highest priority provider
    local deliverySize = count
    if count > providerStation.count then
      deliverySize = providerStation.count
    end
    local stacks = deliverySize -- for fluids stack = count
    if itype == "item" then
      stacks = ceil(deliverySize / game.item_prototypes[iname].stack_size) -- calculate amount of stacks item count will occupy
    end

    -- maxTraincars = shortest set max-train-length
    local maxTraincars = requestStation.maxTraincars
    if providerStation.maxTraincars > 0 and providerStation.maxTraincars < requestStation.maxTraincars then
      maxTraincars = providerStation.maxTraincars
    end

    -- merge into existing shipments
    local to = requestStation.entity.backer_name
    local from = providerStation.entity.backer_name
    local toID = requestStation.entity.unit_number
    local fromID = providerStation.entity.unit_number
    local insertnew = true
    local loadingList = {type=itype, name=iname, count=deliverySize, stacks=stacks}

    -- try inserting into existing order
    for i=1, #orders do
      if orders[i].fromID == fromID and itype == "item" and orders[i].loadingList[1].type == "item" then
        orders[i].loadingList[#orders[i].loadingList+1] = loadingList
        orders[i].totalStacks = orders[i].totalStacks + stacks
        insertnew = false
        if log_level >= 3 then  printmsg("inserted into order "..i.."/"..#orders.." "..from.." >> "..to..": "..deliverySize.." in "..stacks.." stacks "..itype..","..iname.." maxLength: "..maxTraincars) end
        break
      end
    end
    -- create new order for fluids and different provider-requester pairs
    if insertnew then
      orders[#orders+1] = {toID=toID, fromID=fromID, minDelivery=minDelivery, maxTraincars=maxTraincars, shipmentCount=1, totalStacks=stacks, loadingList={loadingList} }
      if log_level >= 3 then  printmsg("added new order "..#orders.." "..from.." >> "..to..": "..deliverySize.." in "..stacks.." stacks "..itype..","..iname.." maxLength: "..maxTraincars) end
    end

    ::skipRequestItem:: -- use goto since lua doesn't know continue
  end -- find providers for requested items


  -- find trains for orders
  for orderIndex=1, #orders do
    local loadingList = orders[orderIndex].loadingList
    local totalStacks = orders[orderIndex].totalStacks
    local maxTraincars = orders[orderIndex].maxTraincars

    -- get station names
    local toStop = global.LogisticTrainStops[orders[orderIndex].toID]
    local fromStop = global.LogisticTrainStops[orders[orderIndex].fromID]
    if not toStop or not fromStop then
      if log_level >= 1 then printmsg("Error: Couldn't get provider or requester stop") end
      goto skipOrder
    end
    local to = toStop.entity.backer_name
    local from = fromStop.entity.backer_name

    -- find train
    local train = GetFreeTrain(toStop.entity.force, loadingList[1].type, totalStacks, maxTraincars)
    if not train then
      if maxTraincars > 0 then
        if log_level >= 3 then printmsg("No train with length "..maxTraincars.." to transport "..totalStacks.."stacks found in Depot") end
      else
        if log_level >= 3 then printmsg("No train to transport "..totalStacks.." stacks found in Depot") end
      end
      goto skipOrder
    end
    if log_level >= 3 then printmsg("Train with "..train.inventorySize.."/"..totalStacks.." found in Depot") end

    -- recalculate delivery amount to fit in train
    if train.inventorySize < totalStacks then
      -- recalculate partial shipment
      if loadingList[1].type == "fluid" then
        -- fluids are simple
        loadingList[1].count = train.inventorySize
      else
        -- items need a bit more math
        for i=#loadingList, 1, -1 do
          if totalStacks - loadingList[i].stacks < train.inventorySize then
            -- remove stacks until it fits in train
            loadingList[i].stacks = loadingList[i].stacks - (totalStacks - train.inventorySize)
            totalStacks = train.inventorySize
            local newcount = loadingList[i].stacks * game.item_prototypes[loadingList[i].name].stack_size
            loadingList[i].count = newcount
            break
          else
            -- remove item and try again
            totalStacks = totalStacks - loadingList[i].stacks
            table.remove(loadingList[i])
          end
        end
      end
    end

    if log_level >= 2 then
      if #loadingList == 1 then
        printmsg("Creating Delivery: ".. loadingList[1].count .."  ".. loadingList[1].name..", "..from.." >> "..to)
      else
        printmsg("Creating merged Delivery: "..totalStacks.." stacks total, "..from.." >> "..to)
      end
    elseif log_level >= 4 then
      for i=1, #loadingList do
        printmsg("Creating Delivery: "..loadingList[i].count.." in "..loadingList[i].stacks.." stacks "..loadingList[i].type..","..loadingList[i].name..", "..from.." >> "..to)
      end
    end

    -- create schedule
    local selectedTrain = global.Dispatcher.availableTrains[train.id]
    local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]
    local schedule = {current = 1, records = {}}
    schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "inactivity", 120)
    schedule.records[2] = NewScheduleRecord(from, "item_count", ">", loadingList)
    schedule.records[3] = NewScheduleRecord(to, "item_count", "=", loadingList, 0)
    selectedTrain.schedule = schedule

    -- store delivery
    local delivery = {}
    for i=1, #loadingList do
      delivery[loadingList[i].type..","..loadingList[i].name] = loadingList[i].count
    end
    global.Dispatcher.Deliveries[train.id] = {train=selectedTrain, started=game.tick, from=from, to=to, shipment=delivery}
    global.Dispatcher.availableTrains[train.id] = nil

    -- move Request to the back of the queue
    global.Dispatcher.RequestAge[orders[orderIndex].toID] = nil

    -- set lamps on stations to yellow
    -- trains will pick a stop by their own logic so we have to parse by name
    for stopID, stop in pairs (global.LogisticTrainStops) do
      if stop.entity.backer_name == from or stop.entity.backer_name == to then
        global.LogisticTrainStops[stopID].activeDeliveries = stop.activeDeliveries + 1
      end
    end

    -- stop after first delivery was created
    do return delivery end -- eplicit block needed ... lua really sucks ...

    ::skipOrder:: -- use goto since lua doesn't know continue
  end --for orders

  return nil
end

-- return all stations providing item, ordered by priority and item-count
function GetStations(force, item, min_count)
  local stations = {}
  local providers = global.Dispatcher.Provided[item]
  if not providers then
    return nil
  end
  -- get all providing stations
  for stopID, count in pairs (providers) do
  if not(stopID == "sumCount" or stopID == "sumStops") then --skip sumCount, sumStops
    local stop = global.LogisticTrainStops[stopID]
    if stop and stop.entity.force.name == force.name then
      if count > 0 and (use_Best_Effort or count > min_count) then
        if log_level >= 4 then printmsg("(GetStations): found ".. count .."/"..min_count.." ".. item.." at "..stop.entity.backer_name.." priority: "..stop.priority.." maxTraincars: "..stop.maxTraincars) end
        stations[#stations +1] = {entity = stop.entity, priority = stop.priority, item = item, count = count, maxTraincars = stop.maxTraincars}
      end
    end
  end
  end
  -- sort by priority and count
  local sort = table.sort
  sort(stations, function(a, b)
      if a.priority ~= b.priority then
          return a.priority > b.priority
      end

      return a.count > b.count
    end)
  return stations
end

-- return available train with smallest suitable inventory or largest available inventory
-- if maxTraincars is set, number of locos + wagons has to be smaller
function GetFreeTrain(force, type, size, maxTraincars)
  local train = nil
  local largestInventory = 0
  local smallestInventory = 0
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    if DispTrain.valid and DispTrain.station then
      local locomotive = GetMainLocomotive(DispTrain)
      if locomotive.force.name == force.name then
        local inventorySize = 0
        if maxTraincars == nil or maxTraincars <= 0 or #DispTrain.carriages <= maxTraincars then -- train length fits
          -- get total inventory of train for requested item type
          inventorySize = GetInventorySize(DispTrain, type)

          if inventorySize >= size then
            -- train can be used for delivery
            if inventorySize < smallestInventory or smallestInventory == 0 then
              smallestInventory = inventorySize
              train = {id=DispTrainKey, inventorySize=inventorySize}
            end
          elseif smallestInventory == 0 and inventorySize > 0 and (inventorySize > largestInventory or largestInventory == 0) then
            -- store as biggest available train
            largestInventory = inventorySize
            train = {id=DispTrainKey, inventorySize=inventorySize}
          end
        end
      end
    else
      -- remove invalid train
      global.Dispatcher.availableTrains[DispTrainKey] = nil
    end
  end
  return train
end

function GetInventorySize(train, type)
  local inventorySize = 0
  if not train.valid then
    return inventorySize
  end

  for _,wagon in pairs (train.cargo_wagons) do
    -- RailTanker
    if type == "fluid" and global.useRailTanker and wagon.name == "rail-tanker" then
      inventorySize = inventorySize + 2500
    -- normal cargo wagons
    elseif type == "item" and wagon.name ~= "rail-tanker" then
      local slots = #wagon.get_inventory(defines.inventory.cargo_wagon)
      if slots then
        inventorySize = inventorySize + slots
      else
        if log_level >= 1 then printmsg("Error(GetInventorySize): Could not read inventory size of ".. wagon.name) end
      end
    end
  end
  return inventorySize
end

-- return new schedule_record
-- itemlist = {first_signal.type, first_signal.name, constant}
function NewScheduleRecord(stationName, condType, condComp, itemlist, countOverride)
  local record = {station = stationName, wait_conditions = {}}

  if condType == "item_count" then
    -- write itemlist to conditions
    for i=1, #itemlist do
      --convert to RT fake item if needed
      local rtname = nil
      local rttype = nil
      if itemlist[i].type == "fluid" and global.useRailTanker then
        rtname = itemlist[i].name .. "-in-tanker"
        rttype = "item"
        if not game.item_prototypes[rtname] then
          if log_level >= 1 then printmsg("Error(NewScheduleRecord): couldn't get RailTanker fake item") end
          return nil
        end
      end

      -- make > into >=
      if condComp == ">" then
        countOverride = itemlist[i].count - 1
      end

      local cond = {comparator = condComp, first_signal = {type = rttype or itemlist[i].type, name = rtname or itemlist[i].name}, constant = countOverride or itemlist[i].count}
      record.wait_conditions[#record.wait_conditions+1] = {type = condType, compare_type = "and", condition = cond }
    end

    -- if stop_timeout is set add inactivity condition
    if stop_timeout > 0 then
      record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "or", ticks = stop_timeout } -- send stuck trains away
    end
  elseif condType == "inactivity" then
    record.wait_conditions[#record.wait_conditions+1] = {type = condType, compare_type = "and", ticks = condComp } -- 1s inactivity allowing trains to be refuelled in depot
  end
  return record
end

function removeDelivery(trainID)
  if global.Dispatcher.Deliveries[trainID] then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if global.Dispatcher.Deliveries[trainID].from == stop.entity.backer_name or global.Dispatcher.Deliveries[trainID].to == stop.entity.backer_name then
        if stop.activeDeliveries > 0 then
          global.LogisticTrainStops[stopID].activeDeliveries = stop.activeDeliveries - 1
        end
      end
    end
    global.Dispatcher.Deliveries[trainID] = nil
  end
end


------------------------------------- STOP FUNCTIONS -------------------------------------

function CreateStop(entity)
  if global.LogisticTrainStops[entity.unit_number] then
    if log_level >= 1 then printmsg("Error(CreateStop): Duplicated unit_number "..entity.unit_number) end
    return
  end

  --log("Stop created at "..entity.position.x.."/"..entity.position.y..", orientation "..entity.direction)
  if entity.direction == 0 then --SN
    posIn = {entity.position.x, entity.position.y-1}
    posOut = {entity.position.x-1, entity.position.y-1}
    rot = 0
  elseif entity.direction == 2 then --EW
    posIn = {entity.position.x, entity.position.y}
    posOut = {entity.position.x, entity.position.y-1}
    rot = 2
  elseif entity.direction == 4 then --NS
    posIn = {entity.position.x-1, entity.position.y}
    posOut = {entity.position.x, entity.position.y}
    rot = 4
  elseif entity.direction == 6 then --WE
    posIn = {entity.position.x-1, entity.position.y-1}
    posOut = {entity.position.x-1, entity.position.y}
    rot = 6
  else --invalid orientation
    if log_level >= 1 then printmsg("Error(CreateStop): invalid Train Stop Orientation "..entity.direction) end
    entity.destroy()
    return
  end

  local lampctrl = entity.surface.create_entity
  {
    name = "logistic-train-stop-lamp-control",
    position = posIn,
    force = entity.force
  }
  lampctrl.operable = false -- disable gui
  lampctrl.minable = false
  lampctrl.destructible = false -- don't bother checking if alive
  lampctrl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-white"}, count = 1 }}}

  local input, output
  -- revive ghosts (should preserve connections)
  --local ghosts = entity.surface.find_entities_filtered{area={{entity.position.x-2, entity.position.y-2},{entity.position.x+2, entity.position.y+2}} , name="entity-ghost"}
  local ghosts = entity.surface.find_entities_filtered{area={{entity.position.x-2, entity.position.y-2},{entity.position.x+2, entity.position.y+2}} }
  for _,ghost in pairs (ghosts) do
    if ghost.name == "entity-ghost" and ghost.ghost_name == "logistic-train-stop-input" then
      _, input = ghost.revive()
    elseif ghost.name == "entity-ghost" and ghost.ghost_name == "logistic-train-stop-output" then
      _, output = ghost.revive()
    -- something has built I/O already (e.g.) Creative Mode Instant Blueprint
    elseif ghost.name == "logistic-train-stop-input" then
      input = ghost
    elseif ghost.name == "logistic-train-stop-output" then
      output = ghost
    end
  end

  if input == nil then -- create new
    input = entity.surface.create_entity
    {
      name = "logistic-train-stop-input",

      position = posIn,
      force = entity.force
    }
  end
  input.operable = false -- disable gui
  input.minable = false
  input.destructible = false -- don't bother checking if alive
  input.connect_neighbour({target_entity=lampctrl, wire=defines.wire_type.green})
  input.get_or_create_control_behavior().use_colors = true
  input.get_or_create_control_behavior().circuit_condition = {condition = {comperator=">",first_signal={type="virtual",name="signal-anything"}}}

  if output == nil then -- create new
    output = entity.surface.create_entity
    {
      name = "logistic-train-stop-output",
      position = posOut,
      direction = rot,
      force = entity.force
    }
  end
  output.operable = false -- disable gui
  output.minable = false
  output.destructible = false -- don't bother checking if alive

  global.LogisticTrainStops[entity.unit_number] = {
    entity = entity,
    input = input,
    output = output,
    lampControl = lampctrl,
    isDepot = false,
    activeDeliveries = 0, --#deliveries to/from stop
    errorCode = 0,        --key to errorCodes table
    parkedTrain = nil,
    parkedTrainID = nil
  }

  UpdateStopOutput(global.LogisticTrainStops[entity.unit_number])

  count = 0
  for id, stop in pairs (global.LogisticTrainStops) do --can not get size with #
    count = count+1
  end
  if count == 1 then
    script.on_event(defines.events.on_tick, ticker) --subscribe ticker on first created train stop
    if log_level >= 4 then printmsg("on_tick subscribed") end
  end
end

function RemoveStop(entity)
  local stopID = entity.unit_number
  local stop = global.LogisticTrainStops[stopID]

  -- remove available train
  if stop.isDepot and stop.parkedTrainID then
    global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
  end

  -- destroy entities
  global.LogisticTrainStops[stopID].input.destroy()
  global.LogisticTrainStops[stopID].output.destroy()
  global.LogisticTrainStops[stopID] = nil

  count = 0
  for id, stop in pairs (global.LogisticTrainStops) do --can not get size with #
    count = count+1
  end
  if count == 0 then
    script.on_event(defines.events.on_tick, nil) --unsubscribe ticker on last removed train stop
    if  log_level >= 4 then printmsg("on_tick unsubscribed") end
  end
end

-- update stop output when train enters/leaves
function UpdateStopParkedTrain(train)
  local trainID = GetTrainID(train)
  local trainName = GetTrainName(train)

  if not trainID then --train has no locomotive
    if log_level >= 1 then printmsg("Error (UpdateStopParkedTrain): couldn't assign train id") end
    --TODO: Update all stops?
    return
  end

  if train.valid and train.manual_mode == false and train.state == defines.train_state.wait_station and train.station ~= nil and train.station.name == "logistic-train-stop" then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stopID == train.station.unit_number then -- add train to station
        stop.parkedTrain = train
        --global.LogisticTrainStops[stopID].parkedTrain = event.train
        stop.parkedTrainID = trainID
        --global.LogisticTrainStops[stopID].parkedTrainID = trainID
        if log_level >= 3 then printmsg("Train "..trainName.." arrived at ".. stop.entity.backer_name) end

        if stop.isDepot then
          -- remove delivery
          removeDelivery(trainID)

          -- make train available for new deliveries
          global.Dispatcher.availableTrains[trainID] = train

          -- reset schedule
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "inactivity", 300)
          train.schedule = schedule
          if stop.errorCode == 0 then
            setLamp(stopID, "blue")
          end
        end

        UpdateStopOutput(stop)
        return
      end
    end
  else --remove train from station
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stop.parkedTrainID == trainID then
        -- remove train reference
        stop.parkedTrain = nil
        --global.LogisticTrainStops[stopID].parkedTrain = nil
        stop.parkedTrainID = nil
        --global.LogisticTrainStops[stopID].parkedTrainID = nil
        if log_level >= 3 then printmsg("Train "..trainName.." left ".. stop.entity.backer_name) end

        if stop.isDepot then
          global.Dispatcher.availableTrains[trainID] = nil
          if stop.errorCode == 0 then
            setLamp(stopID, "green")
          end
        else
          if global.Dispatcher.Deliveries[trainID] then
            if global.Dispatcher.Deliveries[trainID].from == stop.entity.backer_name then
              -- TODO: update to loaded inventory
              if stop.activeDeliveries > 0 then
                global.LogisticTrainStops[stopID].activeDeliveries = stop.activeDeliveries - 1
              end
            elseif global.Dispatcher.Deliveries[trainID].to == stop.entity.backer_name then
              if stop.activeDeliveries > 0 then
                global.LogisticTrainStops[stopID].activeDeliveries = stop.activeDeliveries - 1
              end
                -- Delivery complete > remove
                global.Dispatcher.Deliveries[trainID] = nil
            end
          end

        end

        UpdateStopOutput(stop)
        return
      end
    end
  end
end

-- update stop input signals
function UpdateStop(stopID)
  local stop = global.LogisticTrainStops[stopID]
  local match = string.match
  local lower = string.lower

  -- remove invalid stops
  if not (stop.entity and stop.entity.valid) or
    not (stop.input and stop.input.valid) or
    not (stop.output and stop.output.valid) or
    not (stop.lampControl and stop.lampControl.valid) then

    global.LogisticTrainStops[stopID] = nil
    return
  end

  -- remove invalid trains
  if stop.parkedTrain and not stop.parkedTrain.valid then
    global.LogisticTrainStops[stopID].parkedTrain = nil
    global.LogisticTrainStops[stopID].parkedTrainID = nil
  end

  -- TODO: check if input and output are connected through LuaCircuitNetwork

  -- get circuit values
  local circuitValues = GetCircuitValues(stop.input)
  if not circuitValues then
    return
  end
  
  local colorSignals = { -- lookup table for color signals
    ["virtual,signal-red"] = true,
    ["virtual,signal-green"] = true,
    ["virtual,signal-blue"] = true,
    ["virtual,signal-yellow"] = true,
    ["virtual,signal-pink"] = true,
    ["virtual,signal-cyan"] = true,
    ["virtual,signal-white"] = true,
    ["virtual,signal-grey"] = true,
    ["virtual,signal-black"] = true
  }

  -- read configuration signals and remove them from the signal list (should leave only item and fluid signal types)
  local isDepot = circuitValues["virtual,"..ISDEPOT] or 0
  circuitValues["virtual,"..ISDEPOT] = nil
  local minDelivery = circuitValues["virtual,"..MINDELIVERYSIZE] or min_delivery_size
  circuitValues["virtual,"..MINDELIVERYSIZE] = nil
  local maxTraincars = circuitValues["virtual,"..MAXTRAINLENGTH] or 0
  circuitValues["virtual,"..MAXTRAINLENGTH] = nil
  local priority = circuitValues["virtual,"..PRIORITY] or 0
  circuitValues["virtual,"..PRIORITY] = nil

  -- check if it's a depot
  if isDepot > 0 then
    stop.isDepot = true

    -- reset duplicate name error
    if stop.errorCode == 2 then
      stop.errorCode = 0
    end

    -- add parked train to available trains
    if stop.parkedTrainID and stop.parkedTrain.valid and not global.Dispatcher.Deliveries[stop.parkedTrainID] then
      global.Dispatcher.availableTrains[stop.parkedTrainID] = stop.parkedTrain
    end

    -- update input signals of depot
    local colorCount = 0
    for item, count in pairs (circuitValues) do
      if colorSignals[item] then
        colorCount = colorCount + count
      end
    end

    if colorCount ~= 1 then
      -- signal error
      global.LogisticTrainStops[stopID].errorCode = 1
      setLamp(stopID, ErrorCodes[1])
    else
      -- signal error fixed, depots ignore all other errors
      global.LogisticTrainStops[stopID].errorCode = 0

      global.LogisticTrainStops[stopID].minDelivery = nil
      global.LogisticTrainStops[stopID].maxTraincars = maxTraincars
      global.LogisticTrainStops[stopID].priority = 0
      if stop.parkedTrain then
        setLamp(stopID, "blue")
      else
        setLamp(stopID, "green")
      end
    end

  elseif isUniqueStopName(stop) then
    stop.isDepot = false

    -- reset duplicate name error
    if stop.errorCode == 2 then
      stop.errorCode = 0
    end

    -- remove parked train from available trains
    if stop.parkedTrainID then
      global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
    end

    -- update input signals of stop
    local colorCount = 0
    local deliverycount = 0
    local requestItems = {}
    global.Dispatcher.RequestAge[stopID] = global.Dispatcher.RequestAge[stopID] or game.tick

    for item, count in pairs (circuitValues) do
      if colorSignals[item] then
        colorCount = colorCount + count
      else       
        for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
          if stop.parkedTrain and stop.parkedTrainID == trainID then
            -- calculate items +- train inventory
            local itype, iname = match(item, "([^,]+),([^,]+)")
            if itype and (itype == "item" or itype == "fluid") and iname then
              --use RT fake item
              if itype == "fluid" then
                iname = iname .. "-in-tanker"
              end

              local traincount = stop.parkedTrain.get_item_count(iname)
              if delivery.to == stop.entity.backer_name then
                if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating requested with train inventory: "..item.." "..count.." + "..traincount) end
                count = count + traincount
                deliverycount = deliverycount + 1
              elseif delivery.from == stop.entity.backer_name then
                if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating provided with train inventory: "..item.." "..count.." - "..traincount) end
                count = count - traincount
                deliverycount = deliverycount + 1
                if count < 0 then count = 0 end --make sure we don't turn it into a request
              end
            end

          else
            -- calculate items +- deliveries
            local traincount = delivery.shipment[item]
            if traincount then
              if delivery.to == stop.entity.backer_name then
                if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating requested with delivery: "..item.." "..count.." + "..traincount) end
                count = count + traincount
                deliverycount = deliverycount + 1
              elseif delivery.from == stop.entity.backer_name then
                if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." updating provided with delivery: "..item.." "..count.." - "..traincount) end
                count = count - traincount
                deliverycount = deliverycount + 1
                if count < 0 then count = 0 end --make sure we don't turn it into a request
              end
            end

          end
        end -- for delivery

        -- update Dispatcher Storage
        if count > 0 then
           local provided = global.Dispatcher.Provided[item] or {}
          provided[stopID] = count
          if provided.sumCount then
            provided.sumCount = provided.sumCount + count
          else
            provided.sumCount = count
          end
          if provided.sumStops then
            provided.sumStops = provided.sumStops + 1
          else
            provided.sumStops = 1
          end
          global.Dispatcher.Provided[item] = provided
          if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." provides "..item.." "..count) end
        elseif count*-1 >= minDelivery then
          count = count * -1
          requestItems[item] = count
          if log_level >= 4 then printmsg("(UpdateStop) "..stop.entity.backer_name.." requested "..item.." "..count..", age: "..global.Dispatcher.RequestAge[stopID].."/"..game.tick) end
        end

      end
    end -- for circuitValues

    if colorCount ~= 1 then
      -- signal error
      global.LogisticTrainStops[stopID].errorCode = 1
      setLamp(stopID, ErrorCodes[1])
    elseif stop.errorCode <= 1 then
      --signal error fixed
      global.LogisticTrainStops[stopID].errorCode = 0

      global.LogisticTrainStops[stopID].minDelivery = minDelivery
      global.LogisticTrainStops[stopID].maxTraincars = maxTraincars
      global.LogisticTrainStops[stopID].priority = priority

      -- create Requests {stopID, age, itemlist={[item], count}}
      global.Dispatcher.Requests[#global.Dispatcher.Requests+1] = {age = global.Dispatcher.RequestAge[stopID], stopID = stopID, itemlist = requestItems}

      -- reset delivery counter in case train became invalid during delivery
      -- only reset when 0 so provider can be cleared once train leaves
      if deliverycount == 0 then
        stop.activeDeliveries = 0
      end

      if stop.activeDeliveries > 0 then
        setLamp(stopID, "yellow")
      else
        setLamp(stopID, "green")
      end

    end

  else
    -- duplicate stop name error
    global.LogisticTrainStops[stopID].errorCode = 2
    setLamp(stopID, ErrorCodes[2])
  end

end

function GetCircuitValues(entity)
  local greenWire = entity.get_circuit_network(defines.wire_type.green)
  local redWire =  entity.get_circuit_network(defines.wire_type.red)
  local items = {}
  local validSignals = {
    [MINDELIVERYSIZE] = true,
    [MAXTRAINLENGTH] = true,
    [PRIORITY] = true,
    [ISDEPOT] = true,
    ["signal-red"] = true,
    ["signal-green"] = true,
    ["signal-blue"] = true,
    ["signal-yellow"] = true,
    ["signal-pink"] = true,
    ["signal-cyan"] = true,
    ["signal-white"] = true,
    ["signal-grey"] = true,
    ["signal-black"] = true
  }
  if greenWire then
    for _, v in pairs (greenWire.signals) do
      if v.signal.type ~= "virtual" or validSignals[v.signal.name] then
        items[v.signal.type..","..v.signal.name] = v.count
      end
    end
  end
  if redWire then
    for _, v in pairs (redWire.signals) do
      if v.signal.type ~= "virtual" or validSignals[v.signal.name] then
        if items[v.signal.type..","..v.signal.name] ~= nil then
          items[v.signal.type..","..v.signal.name] = items[v.signal.type..","..v.signal.name] + v.count
        else
          items[v.signal.type..","..v.signal.name] = v.count
        end
      end
    end
  end
  return items
end

function setLamp(stopID, color)
  local colors = {
    red = "signal-red",
    green = "signal-green",
    blue = "signal-blue",
    yellow = "signal-yellow",
    pink = "signal-pink",
    cyan = "signal-cyan",
    white = "signal-white",
    grey = "signal-grey",
    black = "signal-black"
  }
  if colors[color] and global.LogisticTrainStops[stopID] then
    global.LogisticTrainStops[stopID].lampControl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name=colors[color]}, count = 1 }}}
    return true
  end
  return false
end

function UpdateStopOutput(trainStop)
	local index = 1
  local signals = {{index = index, signal = {type="virtual",name="signal-grey"}, count = 1 }} -- short circuit test signal
  index = index + 1

	if trainStop.parkedTrain and trainStop.parkedTrain.valid then
    -- get train composition
    local carriages = trainStop.parkedTrain.carriages
		local carriagesDec = {}
		for i=1, #carriages do
			local name = carriages[i].name
			if carriagesDec[name] then
				carriagesDec[name] = carriagesDec[name] + 2^(i-1)
			else
				carriagesDec[name] = 2^(i-1)
			end
		end
    for k ,v in pairs (carriagesDec) do
      table.insert(signals, {index = index, signal = {type="virtual",name="LTN-"..k}, count = v })
      index = index+1
    end

    if not trainStop.isDepot then
      -- Update normal stations
      local conditions = trainStop.parkedTrain.schedule.records[trainStop.parkedTrain.schedule.current].wait_conditions
      if conditions ~= nil then
        for _, c in pairs(conditions) do
          if c.condition and c.condition.comparator and c.condition.first_signal and c.condition.constant then
            if c.condition.comparator == ">" then --train expects to be loaded with x of this item
              table.insert(signals, {index = index, signal = c.condition.first_signal, count = c.condition.constant + 1 })
               index = index+1
            elseif (c.condition.comparator == "<" and c.condition.constant == 1) or
                   (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
              table.insert(signals, {index = index, signal = c.condition.first_signal, count = trainStop.parkedTrain.get_item_count(c.condition.first_signal.name) * -1 })
               index = index+1
            end
          end
        end
      end

    end

  end
  -- will reset if called with no parked train
  trainStop.output.get_control_behavior().parameters = {parameters=signals}
end

-- return true if stop backer_name is unique
function isUniqueStopName(checkStop)
  local checkName = checkStop.entity.backer_name
  local checkID = checkStop.entity.unit_number
  for stopID, stop in pairs (global.LogisticTrainStops) do
    if checkName == stop.entity.backer_name and checkID ~= stopID then
      return false
    end
  end
  return true
end

---------------------------------- HELPER FUNCTIONS ----------------------------------

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


