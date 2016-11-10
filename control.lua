require "lib"

update_interval = 60
min_delivery_size = 1000

-- Events

script.on_init(function()
	if global.LogisticTrainStops ~= nil then
		script.on_event(defines.events.on_tick, tickTrainStops) --subscribe ticker when train stops exist
	end  
end)

script.on_load(function()
	if global.LogisticTrainStops ~= nil then
		script.on_event(defines.events.on_tick, tickTrainStops) --subscribe ticker when train stops exist
	end  
end)

script.on_configuration_changed(function()
  global.Dispatcher = global.Dispatcher or {}
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.Storage = global.Dispatcher.Storage or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}
  
  global.LogisticTrainStops = global.LogisticTrainStops or {}
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
    printmsg("Error: Duplicated unit_number "..logisticTrainStop.unit_number)
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
    printmsg("invalid Train Stop Orientation "..logisticTrainStop.direction)
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
    printmsg("on_tick subscribed")
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
    printmsg("on_tick unsubscribed")
  end
end


script.on_event(defines.events.on_train_changed_state, function(event)
  local trainID = GetTrainID(event.train)
  if event.train.state == defines.train_state.wait_station and event.train.station ~= nil and event.train.station.name == "logistic-train-stop" then -- add train to station
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stopID == event.train.station.unit_number then
        stop.parkedTrain = event.train
        stop.parkedTrainID = trainID
        printmsg(trainID.." arrived at ".. stop.entity.backer_name)
        UpdateStopOutput(stop)
        
        if stop.isDepot then          
          global.Dispatcher.availableTrains[trainID] = event.train
          -- assume delivery is complete
          global.Dispatcher.Deliveries[trainID] = {}
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
        printmsg(trainID.." left ".. stop.entity.backer_name)
        
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
if global.LogisticTrainStops ~= nil and game.tick % update_interval == 0 then
  global.Dispatcher.Storage = {} --reset storage
  requests = {} --collect requests
  for stopID, stop in pairs(global.LogisticTrainStops) do          
    -- update depots by station name
    if string.lower(stop.entity.backer_name) == "depot" then
      stop.isDepot = true
    else
      stop.isDepot = false
    end
      
    -- update input signals of stop
    global.Dispatcher.Storage[stop.entity.backer_name] = GetCircuitValues(stop.input)
  
    if global.Dispatcher.Storage[stop.entity.backer_name] then
      for item, count in pairs (global.Dispatcher.Storage[stop.entity.backer_name]) do
        --printmsg(stop.entity.backer_name.." storage ".. item .."  "..count)        
        for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
          if delivery.item == item and delivery.to == stop.entity.backer_name then
            count = count + delivery.count
          end
        end
        if count < min_delivery_size * -1 then
          requests[stop.entity.backer_name] = requests[stop.entity.backer_name] or {}
          requests[stop.entity.backer_name][item] = count*-1
        end
      end  
    end  

  end --end update per stop
          
  -- Dispatcher
  if requests then
  for requestStation, req in pairs (requests) do
    if req then
    for item, count in pairs (req) do
      local TrainID = GetFreeTrain()      
      if TrainID then
         --find best supplier
        local pickupStation = GetStationItemMax(item, count)
        if pickupStation then
          -- generate schedule
          printmsg("Creating Delivery: ".. count .."  ".. item.." from "..pickupStation.." to "..requestStation)
          local train = global.Dispatcher.availableTrains[TrainID]
          local depot = global.LogisticTrainStops[train.station.unit_number]
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "circuit", {type="virtual",name="signal-green"}, "=", 1)      
          schedule.records[2] = NewScheduleRecord(pickupStation, "item_count", {type="item",name=item}, ">", count-1) 
          schedule.records[3] = NewScheduleRecord(requestStation, "item_count", {type="item",name=item}, "=", 0) 
          train.schedule = schedule   
          -- send green to train (needs output connected to station)          
          depot.output.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-green"}, count = 1 }}}
          -- store delivery
          global.Dispatcher.Deliveries[TrainID] = {item=item, count=count, from=pickupStation, to=requestStation}
        end
      end
    end
    end
  end
  end
end  
end

-- Logic

--return name of station with highest count of item or nil
function GetStationItemMax(item, min_count) 
  local currentStation = nil
  local currentMax = min_count
  for station, itemlist in pairs (global.Dispatcher.Storage) do
    --printmsg("checking ".. station .." for ".. item)
    for k, v in pairs (itemlist) do
      if k == item and v > currentMax then
        --printmsg("found ".. v .."  ".. k.." at "..station)
        currentMax = v
        currentStation = station
      end
    end
  end
  return currentStation
end

function GetFreeTrain()
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    if DispTrain.valid then
      return DispTrainKey
    end
  end
end

function GetCircuitValues(entity) 
  local greenWire = entity.get_circuit_network(defines.wire_type.green)
  local redWire =  entity.get_circuit_network(defines.wire_type.red)
  local items = {} 
  if greenWire then
    for _, v in pairs (greenWire.signals) do
      if v.signal.type == "item" then
        items[v.signal.name] = v.count
      end
    end
  end
  if redWire then
    for _, v in pairs (redWire.signals) do 
      if v.signal.type == "item" then
        if items[v.signal.name] ~= nil then
          items[v.signal.name] = items[v.signal.name] + v.count
        else
          items[v.signal.name] = v.count
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
  if trainStop.parkedTrain and trainStop.isDepot then
    table.insert(signals, {index = 1, signal = {type="virtual",name="signal-blue"}, count = 1 })
  elseif trainStop.parkedTrain then
    local conditions = trainStop.parkedTrain.schedule.records[trainStop.parkedTrain.schedule.current].wait_conditions
    if conditions ~= nil then 
      local i = 0
      for _, c in pairs(conditions) do
        if c.condition and c.condition.comparator and c.condition.first_signal and c.condition.constant then
          i=i+1
          if c.condition.comparator == ">" then --train expects to be loaded with x of this item
            table.insert(signals, {index = i, signal = c.condition.first_signal, count = c.condition.constant + 1 })
          elseif (c.condition.comparator == "<" and c.condition.constant == 1) or
                 (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
            table.insert(signals, {index = i, signal = c.condition.first_signal, count = trainStop.parkedTrain.get_item_count(c.condition.first_signal.name) * -1 })
          else --signal invalid
             table.insert(signals, {index = i, signal = {type="virtual",name="signal-red"}, count = 1 })
          end      
        end
      end
    end
    --printmsg(trainStop.id.." current schedule position:"..trainStop.parkedTrain.schedule.current.." found "..i.." signals")
  end
  params = {parameters=signals}
  trainStop.output.get_control_behavior().parameters = params	
end
