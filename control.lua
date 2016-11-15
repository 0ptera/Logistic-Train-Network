--require "lib"
require "config"
require "interface"

-- signal names
MINDELIVERYSIZE = "min-delivery-size"
MAXTRAINLENGTH = "max-train-length"

-- Events

script.on_init(function()
  onLoad()
end)

script.on_load(function()
  onLoad()
end)

function onLoad ()
	if global.LogisticTrainStops ~= nil then
		script.on_event(defines.events.on_tick, tickTrainStops) --subscribe ticker when train stops exist    
    for stopID, stop in pairs(global.LogisticTrainStops) do --outputs are not stored in save
      UpdateStopOutput(stop)
    end
	end
  

end

script.on_configuration_changed(function()
  global.Dispatcher = global.Dispatcher or {}
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.Storage = global.Dispatcher.Storage or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}
  
  global.LogisticTrainStops = global.LogisticTrainStops or {}

  global.log_level = global.log_level or 2 -- 4: prints everything, 3: prints extended messages, 2: prints all Scheduler messages, 1 prints only important messages, 0: off
  global.log_output = global.log_output or {console = 'console'} -- console or log or both
end)



script.on_event(defines.events.on_built_entity, function(event)
	if (event.created_entity.name == "logistic-train-stop") then
		CreateStop(event.created_entity)
	end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
	if (event.created_entity.name == "logistic-train-stop") then
		CreateStop(event.created_entity)
	end
end)


script.on_event(defines.events.on_preplayer_mined_item, function(event)
  if (event.entity.name == "logistic-train-stop") then
    RemoveStop(event.entity)
  end
end)

script.on_event(defines.events.on_robot_pre_mined, function(event)
  if (event.entity.name == "logistic-train-stop") then
    RemoveStop(event.entity)
  end
end)

script.on_event(defines.events.on_entity_died, function(event)
  if (event.entity.name == "logistic-train-stop") then
    RemoveStop(event.entity)
  end
end)

function CreateStop(logisticTrainStop)
  if global.LogisticTrainStops[logisticTrainStop.unit_number] then
    if global.log_level >= 1 then printmsg("Error(CreateStop): Duplicated unit_number "..logisticTrainStop.unit_number) end
    return
  end
  
  --printmsg("Stop created at "..logisticTrainStop.position.x.."/"..logisticTrainStop.position.y..", orientation "..logisticTrainStop.direction)
  if logisticTrainStop.direction == 0 then --SN
    posIn = {logisticTrainStop.position.x, logisticTrainStop.position.y}
    posOut = {logisticTrainStop.position.x, logisticTrainStop.position.y-1}
    rot = 2
  elseif logisticTrainStop.direction == 2 then --EW
    posIn = {logisticTrainStop.position.x-1, logisticTrainStop.position.y}
    posOut = {logisticTrainStop.position.x, logisticTrainStop.position.y}
    rot = 4
  elseif logisticTrainStop.direction == 4 then --NS
    posIn = {logisticTrainStop.position.x-1, logisticTrainStop.position.y-1}
    posOut = {logisticTrainStop.position.x-1, logisticTrainStop.position.y}
    rot = 6
  elseif logisticTrainStop.direction == 6 then --WE
    posIn = {logisticTrainStop.position.x, logisticTrainStop.position.y-1}
    posOut = {logisticTrainStop.position.x-1, logisticTrainStop.position.y-1}
    rot = 0
  else --invalid orientation
    if global.log_level >= 1 then printmsg("Error(CreateStop): invalid Train Stop Orientation "..logisticTrainStop.direction) end
    logisticTrainStop.destroy()
    return
  end
  local input = logisticTrainStop.surface.create_entity
  {
    name = "logistic-train-stop-input",

    position = posIn,
    force = logisticTrainStop.force
  }  
  input.operable = false -- disable gui
  input.minable = false
  input.destructible = false -- don't bother checking if alive  
    
  local output = logisticTrainStop.surface.create_entity
  {
    name = "logistic-train-stop-output",
    position = posOut,
    direction = rot,
    force = logisticTrainStop.force
  }  
  output.operable = false -- disable gui
  output.minable = false
  output.destructible = false -- don't bother checking if alive
  
  global.LogisticTrainStops[logisticTrainStop.unit_number] = {
    entity = logisticTrainStop,
    input = input,
    output = output,
    isDepot = false,
    parkedTrain = nil,
    parkedTrainID = nil
  }
  
  count = 0
  for id, stop in pairs (global.LogisticTrainStops) do --can not get size with #
    count = count+1
  end
  if count == 1 then
    script.on_event(defines.events.on_tick, tickTrainStops) --subscribe ticker on first created train stop
    if global.log_level >= 4 then printmsg("on_tick subscribed") end
  end
end

function RemoveStop(logisticTrainStop)
  global.LogisticTrainStops[logisticTrainStop.unit_number].input.destroy()
  global.LogisticTrainStops[logisticTrainStop.unit_number].output.destroy()
  global.LogisticTrainStops[logisticTrainStop.unit_number] = nil
  --printmsg("Stop "..logisticTrainStop.unit_number.."removed")
  
  count = 0
  for id, stop in pairs (global.LogisticTrainStops) do --can not get size with #
    count = count+1
  end
  if count == 0 then
    script.on_event(defines.events.on_tick, nil) --unsubscribe ticker on last removed train stop
    if  global.log_level >= 4 then printmsg("on_tick unsubscribed") end
  end
end


script.on_event(defines.events.on_train_changed_state, function(event)
  local trainID = GetTrainID(event.train)
  if event.train.state == defines.train_state.wait_station and event.train.station ~= nil and event.train.station.name == "logistic-train-stop" then -- add train to station
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stopID == event.train.station.unit_number then
        stop.parkedTrain = event.train
        stop.parkedTrainID = trainID
        if global.log_level >= 3 then printmsg("TrainID "..trainID.." arrived at ".. stop.entity.backer_name) end
        UpdateStopOutput(stop)
        
        if stop.isDepot then          
          global.Dispatcher.availableTrains[trainID] = event.train
          -- assume delivery is complete
          global.Dispatcher.Deliveries[trainID] = nil
          -- reset schedule
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "circuit", {type="virtual",name="signal-green"}, "=", 1)          
          event.train.schedule = schedule
          
          -- TODO set lamp to blue
          
        end
        
        UpdateStopOutput(stop)
        return
      end
    end
  else --remove train from station
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stop.parkedTrainID == trainID then
        stop.parkedTrain = nil
        stop.parkedTrainID = nil
        if global.log_level >= 3 then printmsg("TrainID "..trainID.." left ".. stop.entity.backer_name) end
        
        if stop.isDepot then
          global.Dispatcher.availableTrains[trainID] = nil
          
          -- TODO set lamp to nothing
          
        end
        
        UpdateStopOutput(stop)
        return
      end
    end
  end
  
end)

function tickTrainStops(event)
  -- Station update
  if global.LogisticTrainStops ~= nil and game.tick % station_update_interval == 0 then
    for stopID, stop in pairs(global.LogisticTrainStops) do                
      if string.lower(stop.entity.backer_name) == "depot" then
        stop.isDepot = true
      else
        stop.isDepot = false
      end
        
      -- update input signals of stop
      local circuitValues = GetCircuitValues(stop.input)
      local requested = {}
      local provided = {}
      if circuitValues then
        minDelivery = min_delivery_size
        maxTraincars = 0
        for item, count in pairs (circuitValues) do
          if item == "virtual,"..MINDELIVERYSIZE and count > 0 then -- overwrite default min-delivery-size
            minDelivery = count
            circuitValues[item] = nil
          elseif item == "virtual,"..MAXTRAINLENGTH and count > 0 then -- set max-train-length
            maxTraincars = count
            circuitValues[item] = nil            
          else
            for trainID, delivery in pairs (global.Dispatcher.Deliveries) do -- calculate items + deliveries
              if delivery.item == item and delivery.to == stop.entity.backer_name then
                 count = count + delivery.count                 
                 circuitValues[item] = count              
              end
            end
            if count < 0 then
              requested[item] = count * -1
            else
              provided[item] = count
            end
          end  
        end
        global.Dispatcher.Storage[stopID] = global.Dispatcher.Storage[stopID] or {}
        global.Dispatcher.Storage[stopID].lastUpdate = game.tick
        global.Dispatcher.Storage[stopID].minDelivery = minDelivery
        global.Dispatcher.Storage[stopID].maxTraincars = maxTraincars
        global.Dispatcher.Storage[stopID].provided = provided
        global.Dispatcher.Storage[stopID].requested = requested
      end  
    end
  end -- Station Update 

  -- Dispatcher update
  if global.LogisticTrainStops ~= nil and game.tick % dispatcher_update_interval == 0 then
    -- clean up deliveries in case train was destroyed or removed
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
      if not delivery.train or not delivery.train.valid then
        global.Dispatcher.Deliveries[trainID] = nil
      elseif game.tick-delivery.started > delivery_timeout then
        if global.log_level >= 1 then printmsg("Delivery: ".. delivery.count .."  ".. delivery.item.." from "..delivery.from.." to "..delivery.to.." running for "..game.tick-delivery.started.." ticks deleted after time out.") end
        global.Dispatcher.Deliveries[trainID] = nil
      end
    end  

    -- update storage and requests
    for stopID, storage in pairs (global.Dispatcher.Storage) do
      if storage.lastUpdate and storage.lastUpdate > (game.tick - dispatcher_update_interval * 10) -- remove stops without data
        and global.LogisticTrainStops[stopID] and global.LogisticTrainStops[stopID].entity.backer_name and storage.requested and storage.minDelivery then 
        RequestHandler(global.LogisticTrainStops[stopID].entity.backer_name ,storage.requested, storage.minDelivery, storage.maxTraincars)         
      else
        if global.LogisticTrainStops[stopID] and global.LogisticTrainStops[stopID].entity.backer_name then
          if global.log_level >= 3 then printmsg("Removed old storage data: "..global.LogisticTrainStops[stopID].entity.backer_name) end
        else
          if global.log_level >= 3 then printmsg("Removed old storage data: invalid stopID") end
        end
        global.Dispatcher.Storage[stopID] = nil      
      end
    end   
    
  end -- Dispatcher Update
end

-- Logic

--Parse Requests for a given station
function RequestHandler(requestStation, requests, minDelivery, maxTraincars)
  for item, count in pairs (requests) do

    if count < minDelivery then -- don't deliver anything below delivery size
      goto continueParseRequests
    end
       
    itype, iname = item:match("([^,]+),([^,]+)")
    if not (itype and iname) then
      if global.log_level >= 1 then printmsg("Error(RequestHandler): could not parse item "..item) end
      goto continueParseRequests
    end   

    -- find best supplier
    local pickupStation = GetStationItemMax(item, 1)        
    if not pickupStation then
      if global.log_level >= 2 then printmsg("Warning: no station supplying "..item.." found") end
      goto continueParseRequests
    end
    deliverySize = math.min(count, pickupStation.count)
        --maxTraincars = math.min(maxTraincars, pickupStation.maxTraincars)
    if pickupStation.maxTraincars > 0 and (maxTraincars <= 0 or (maxTraincars > 0 and pickupStation.maxTraincars < maxTraincars)) then
      maxTraincars = pickupStation.maxTraincars
    end
          
    -- get train with fitting cargo type (item/fluid) and inventory size
    local train = GetFreeTrain(itype, iname, deliverySize, minDelivery, maxTraincars)      
    if not train then   
      if global.log_level >= 4 then printmsg("No train with length "..maxTraincars.." to transport "..deliverySize.." ".. item.." found in Depot") end
      goto continueParseRequests
    end        
    local deliverySize = math.min(deliverySize, train.inventorySize)
    
    -- if deliverySize < minDelivery then -- train inventory size could drop below minDelivery
      -- --if global.log_level >= 4 then printmsg("Rejected Delivery: delivery size ".. deliverySize.." < selected min delivery size "..minDelivery) end
      -- goto continueParseRequests
    -- end

    if global.log_level >= 2 then printmsg("Creating Delivery: ".. deliverySize .."  ".. item.." from "..pickupStation.name.." to "..requestStation) end
    
    -- use Rail Tanker fake items instead of fluids 
    if game.item_prototypes["rail-tanker"] and itype == "fluid" then
      if game.item_prototypes[iname .. "-in-tanker"] then
        iname = iname .. "-in-tanker"
        itype = "item"
      else
        printmsg("Error(RequestHandler): couldn't get RailTanker fake item")
      end
    end
          
    -- generate schedule
    local ItemSignalID = {type=itype, name=iname}
    local selectedTrain = global.Dispatcher.availableTrains[train.id]
    local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]
    local schedule = {current = 1, records = {}}
    schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "circuit", {type="virtual",name="signal-green"}, "=", 1)      
    schedule.records[2] = NewScheduleRecord(pickupStation.name, "item_count", ItemSignalID, ">", deliverySize-1) 
    schedule.records[3] = NewScheduleRecord(requestStation, "item_count", ItemSignalID, "=", 0) 
    selectedTrain.schedule = schedule   
    -- send green to selectedTrain (needs output connected to station)          
    depot.output.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-green"}, count = 1 }}}
    -- store delivery
    global.Dispatcher.Deliveries[train.id] = {train=selectedTrain, started=game.tick, item=item, count=deliverySize, from=pickupStation.name, to=requestStation}
    global.Dispatcher.availableTrains[train.id] = nil
    ::continueParseRequests:: -- use goto since lua doesn't know continue
  end
end

--return name of station with highest count of item or nil
function GetStationItemMax(item, min_count ) 
  local currentStation = nil
  local currentMax = min_count
  for stopID, storage in pairs (global.Dispatcher.Storage) do    
    for k, v in pairs (storage.provided) do      
      if k == item and v > currentMax then
        local ltStop = global.LogisticTrainStops[stopID]
        if ltStop then
          if global.log_level >= 4 then printmsg("found ".. v .."  ".. k.." at "..ltStop.entity.backer_name) end
          currentMax = v
          currentStation = {name=ltStop.entity.backer_name, count=v, maxTraincars=global.Dispatcher.Storage[stopID].maxTraincars}
        else
          if global.log_level >= 1 then printmsg("Error(GetStationItemMax): "..stopID.." no such unit_number") end
        end
      end
    end --for k, v in pairs (storage.provided) do      
  end
  return currentStation
end

-- return available train with smallest suitable inventory or largest available inventory 
-- inventory has to be between minSize and maxSize if set
function GetFreeTrain(type, name, count, minSize, maxTraincars)
  local train = nil
  local largestInventory = 0
  local smallestInventory = 0
  if type == "item" then
    stackSize = game.item_prototypes[name].stack_size
  end
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    local inventorySize = 0
    if DispTrain.valid then
      -- get total inventory of train for requested item type
      for _,wagon in pairs (DispTrain.cargo_wagons) do
        -- RailTanker
        if game.item_prototypes["rail-tanker"] and type == "fluid" and wagon.name == "rail-tanker" then
          inventorySize = inventorySize + 2500
        -- normal cargo wagons
        elseif type == "item" and wagon.name ~= "rail-tanker" then
          local slots = #wagon.get_inventory(defines.inventory.cargo_wagon)
          if slots then
            inventorySize = inventorySize + slots * stackSize
          else
            if global.log_level >= 1 then printmsg("Error(GetFreeTrain): Could not read inventory size of ".. wagon.name) end
          end
        end
      end
      
      if (minSize == nil or minSize <= 0 or inventorySize >= minSize) -- cargo space sufficient
      and (maxTraincars == nil or maxTraincars <= 0 or #DispTrain.carriages <= maxTraincars) then -- train length fits
        if inventorySize >= count then
          -- train can be used for delivery
          if inventorySize < smallestInventory or smallestInventory == 0 then
            smallestInventory = inventorySize
            train = {id=DispTrainKey, inventorySize=inventorySize}
          end
        elseif inventorySize > 0 and (inventorySize > largestInventory or largestInventory == 0) then
          -- store biggest available train
          largestInventory = inventorySize
          train = {id=DispTrainKey, inventorySize=inventorySize}
        end
      end
    end
  end
  return train
end

function GetCircuitValues(entity) 
  local greenWire = entity.get_circuit_network(defines.wire_type.green)
  local redWire =  entity.get_circuit_network(defines.wire_type.red)
  local items = {} 
  if greenWire then
    for _, v in pairs (greenWire.signals) do
      if v.signal.type == "item" or v.signal.type == "fluid" 
      or (v.signal.type == "virtual" and (v.signal.name == MINDELIVERYSIZE or v.signal.name == MAXTRAINLENGTH)) then
        items[v.signal.type..","..v.signal.name] = v.count
      end
    end
  end
  if redWire then
    for _, v in pairs (redWire.signals) do 
      if v.signal.type == "item" or v.signal.type == "fluid" 
      or (v.signal.type == "virtual" and (v.signal.name == MINDELIVERYSIZE or v.signal.name == MAXTRAINLENGTH)) then
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

function NewScheduleRecord(stationName, condType, condSignal, condComp, condConst)
  local cond = {comparator = condComp, first_signal = condSignal, constant = condConst}
  local record = {station = stationName, wait_conditions = {}}
  record.wait_conditions[1] = {type = condType, compare_type = "and", condition = cond }
  record.wait_conditions[2] = {type = "inactivity", compare_type = "and", ticks = 60 } -- prevent trains leaving too early
  return record
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

function UpdateStopOutput(trainStop)
  local signals = {}
  if trainStop.parkedTrain and trainStop.parkedTrain.valid then
    -- get train composition
    carriages = {}
    for _,carriage in pairs (trainStop.parkedTrain.carriages) do
      if carriages[carriage.name] ~= nil then
        carriages[carriage.name] = carriages[carriage.name] + 1
      else
        carriages[carriage.name] = 1
      end
    end
    i = 1
    for k ,v in pairs (carriages) do      
      table.insert(signals, {index = i, signal = {type="virtual",name="LTN-"..k}, count = v })
      i=i+1
    end
    
    
    if trainStop.isDepot then
      -- Update Depot
      table.insert(signals, {index = i, signal = {type="virtual",name="signal-blue"}, count = 1 })      
    else    
      -- Update normal stations
      local conditions = trainStop.parkedTrain.schedule.records[trainStop.parkedTrain.schedule.current].wait_conditions
      if conditions ~= nil then 
        for _, c in pairs(conditions) do
          if c.condition and c.condition.comparator and c.condition.first_signal and c.condition.constant then
            if c.condition.comparator == ">" then --train expects to be loaded with x of this item
              table.insert(signals, {index = i, signal = c.condition.first_signal, count = c.condition.constant + 1 })
            elseif (c.condition.comparator == "<" and c.condition.constant == 1) or
                   (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
              table.insert(signals, {index = i, signal = c.condition.first_signal, count = trainStop.parkedTrain.get_item_count(c.condition.first_signal.name) * -1 })
            else --signal invalid
               table.insert(signals, {index = i, signal = {type="virtual",name="signal-red"}, count = 1 })
            end  
            i=i+1            
          end
        end
      end       
    end
    
  end
  -- will reset if called with no parked train
  params = {parameters=signals}
  trainStop.output.get_control_behavior().parameters = params	
end
