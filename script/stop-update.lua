--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]


-- return true if stop, output, lamp are on same logic network
local function detectShortCircuit(checkStop)
  local scdetected = false
  local networks = {}
  local entities = {checkStop.entity, checkStop.output, checkStop.input}

  for k, entity in pairs(entities) do
    local greenWire = entity.get_circuit_network(defines.wire_type.green)
    if greenWire then
      if networks[greenWire.network_id] then
        scdetected = true
      else
        networks[greenWire.network_id] = entity.unit_number
      end
    end
    local redWire =  entity.get_circuit_network(defines.wire_type.red)
    if redWire then
      if networks[redWire.network_id] then
        scdetected = true
      else
        networks[redWire.network_id] = entity.unit_number
      end
    end
  end

  return scdetected
end

local function remove_available_train(trainID)
  if debug_log then log("(UpdateStop) removing available train "..tostring(trainID).." from depot." ) end
  global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[trainID].capacity
  global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[trainID].fluid_capacity
  global.Dispatcher.availableTrains[trainID] = nil
end

-- update stop input signals
function UpdateStop(stopID)
  local stop = global.LogisticTrainStops[stopID]
  global.Dispatcher.Requests_by_Stop[stopID] = nil

  -- remove invalid stops
  if not stop or not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lampControl.valid then
    if message_level >= 1 then printmsg({"ltn-message.error-invalid-stop", stopID}) end
    if debug_log then log("(UpdateStop) Removing invalid stop: "..stopID) end
    if stop.entity.valid then
      Station_removeStopEntity(stop.entity)
    else
      for i = 1, #globals.LogisticStations do
        local station = globals.LogisticStations[i]
        Station_removeStopFromStation(station, stopID)
      end
    end
    return
  end

  -- set stop.station if missing
  if not stop.station then
    if debug_log then log("(UpdateStop) Adding stop to station: " .. stop.entity.backer_name .. " + " .. stop.entity.unit_number) end
    stop.station = Station_addStopEntity(stop.entity)
  end

  -- remove invalid trains
  if stop.parkedTrain and not stop.parkedTrain.valid then
    Station_removeTrain(stop.station, stop.parkedTrainID)
    stop.parkedTrain = nil
    stop.parkedTrainID = nil
  end

  -- remove invalid activeDeliveries -- shouldn't be necessary
  local station = stop.station
  if Station_isMaster(station, stop) then
    for trainID, _ in pairs(station.pendingTrains) do
      if not global.Dispatcher.Deliveries[trainID] then
        if message_level >= 1 then printmsg({"ltn-message.error-invalid-delivery", stop.entity.backer_name}) end
        if debug_log then log("(UpdateStop) Removing invalid delivery from stop '"..stop.entity.backer_name.."': "..nextDelivery) end
        Station_removeTrain(station, trainID)
      end
    end
    for trainID, _ in pairs(station.parkedTrains) do
      if not global.Dispatcher.Deliveries[trainID] then
        if message_level >= 1 then printmsg({"ltn-message.error-invalid-delivery", stop.entity.backer_name}) end
        if debug_log then log("(UpdateStop) Removing invalid delivery from stop '"..stop.entity.backer_name.."': "..nextDelivery) end
        Station_removeTrain(station, trainID)
      end
    end
  end

  -- reset stop parameters in case something goes wrong
  stop.minTraincars = 0
  stop.maxTraincars = 0
  stop.trainLimit = 0
  stop.requestThreshold = min_requested
  stop.requestPriority = 0
  stop.noWarnings = false
  stop.provideThreshold = min_provided
  stop.providePriority = 0
  stop.lockedSlots = 0

  -- add missing stops to name list
  if not global.LogisticStations[stop.entity.backer_name] then
    stop.station = Station_addStopEntity(stop.entity)
    if message_level >= 1 then printmsg({"ltn-message.error-missing-stop-name", stop.entity.backer_name}) end
    if debug_log then log("(UpdateStop) Missing stop name '"..tostring(stop.entity.backer_name).."' added to global.TrainStations") end
    return
  end

  -- finalize error code and reset check if master stop
  if Station_isMaster(station, stopID) then
    if station.ltnStopCount ~= Station_numStops(station) then
      -- not all stops for this station are LTN stops
      station.finishedErrorCode = 4
    end
    -- finalize error code
    station.finishedErrorCode = station.errorCode
    -- reset variables for check
    station.ltnStopCount = 0
    station.errorCode = 0
    local wire = stop.entity.get_circuit_network(defines.wire_type.green)
    station.greenNetworkID = wire and wire.network_id
    wire = stop.entity.get_circuit_network(defines.wire_type.red)
    station.redNetworkID = wire and wire.network_id
    station.isDepot = stop.isDepot
  end

  -- skip deactivated stops
  local stopCB = stop.entity.get_control_behavior()
  if stopCB and stopCB.disabled then
    if stop.parkedTrainID and global.Dispatcher.availableTrains[stop.parkedTrainID] then
      remove_available_train(stop.parkedTrainID)
    end
    setLamp(stop, ErrorCodes[1], 2)
    if debug_log then log("(UpdateStop) Circuit deactivated stop: "..stop.entity.backer_name.."("..stop.entity.unit_number..")") end
    return
  end

  -- skip short circuited stops
  if detectShortCircuit(stop) then
    if stop.parkedTrainID and global.Dispatcher.availableTrains[stop.parkedTrainID] then
      remove_available_train(stop.parkedTrainID)
    end
    setLamp(stop, ErrorCodes[1], 1)
    if debug_log then log("(UpdateStop) Short circuit error: "..stop.entity.backer_name.."("..stop.entity.unit_number..")") end
    return
  end

  -- initialize control signal values to defaults
  local isDepot = false
  local network_id = -1
  local minTraincars = 0
  local maxTraincars = 0
  local trainLimit = 0
  local requestThreshold = min_requested
  local requestStackThreshold = 0
  local requestPriority = 0
  local noWarnings = false
  local provideThreshold = min_provided
  local provideStackThreshold = 0
  local providePriority = 0
  local lockedSlots = 0

  -- get circuit values 0.16.24
  local signals = stop.input.get_merged_signals()
  if not signals then return end -- either lamp and lampctrl are not connected or lampctrl has no output signal

  -- log(stop.entity.backer_name.."("..stop.entity.unit_number..") signals: "..serpent.block(signals))

  local signals_filtered = {}
  local signal_type_virtual = "virtual"
  local abs = math.abs

  for _,v in pairs(signals) do
      if v.signal.type ~= signal_type_virtual then
        -- add item and fluid signals to new array
        signals_filtered[#signals_filtered+1] = v
      elseif ControlSignals[v.signal.name] then
        -- read out control signals
        if v.signal.name == ISDEPOT and v.count > 0 then
          isDepot = true
        elseif v.signal.name == NETWORKID then
          network_id = v.count
        elseif v.signal.name == MINTRAINLENGTH and v.count > 0 then
          minTraincars = v.count
        elseif v.signal.name == MAXTRAINLENGTH and v.count > 0 then
          maxTraincars = v.count
        elseif v.signal.name == MAXTRAINS and v.count > 0 then
          trainLimit = v.count
        elseif v.signal.name == REQUESTED_THRESHOLD then
          requestThreshold = abs(v.count)
        elseif v.signal.name == REQUESTED_STACK_THRESHOLD then
          requestStackThreshold = abs(v.count)
        elseif v.signal.name == REQUESTED_PRIORITY then
          requestPriority = v.count
        elseif v.signal.name == NOWARN and v.count > 0 then
          noWarnings = true
        elseif v.signal.name == PROVIDED_THRESHOLD then
           provideThreshold = abs(v.count)
        elseif v.signal.name == PROVIDED_STACK_THRESHOLD then
           provideStackThreshold = abs(v.count)
        elseif v.signal.name == PROVIDED_PRIORITY then
          providePriority = v.count
        elseif v.signal.name == LOCKEDSLOTS and v.count > 0 then
          lockedSlots = v.count
        end
      end
  end
  local network_id_string = format("0x%x", band(network_id))

  -- log(stop.entity.backer_name.."("..stop.entity.unit_number..") filtered signals: "..serpent.block(signals_filtered))
  -- log("Control Signals: isDepot:"..tostring(isDepot).." network_id:"..network_id.." network_id_string:"..network_id_string
  -- .." minTraincars:"..minTraincars.." maxTraincars:"..maxTraincars.." trainLimit:"..trainLimit
  -- .." requestThreshold:"..requestThreshold.." requestPriority:"..requestPriority.." noWarnings:"..tostring(noWarnings)
  -- .." provideThreshold:"..provideThreshold.." providePriority:"..providePriority.." lockedSlots:"..lockedSlots)

  -- update error code for station
  stop.isDepot = isDepot
  if not Station_isMaster(station, stopID) then
    if isDepot ~= station.isDepot then
      -- depot and non-depot don't mix
      station.errorCode = 2
      station.finishedErrorCode = 2
    end
    if not isDepot then
      -- non-depot stops must be connected by wire
      local wire = stop.entity.get_circuit_network(defines.wire_type.green)
      if station.greenNetworkID ~= (wire and wire.network_id) then
        station.greenNetworkID = nil
      end
      wire = stop.entity.get_circuit_network(defines.wire_type.red)
      if station.redNetworkID ~= (wire and wire.network_id) then
        station.redNetworkID = nil
      end
      if (station.greenNetworkID == nil) and (station.redNetworkID == nil) then
        station.errorCode = 3
        station.finishedErrorCode = 3
      end
    end
  end

  --update lamp colors
  SetStopLamp(stop)

  -- skip stops with errors
  if station.finishedErrorCode ~= 0 then
    return
  end

  -- check if it's a depot
  if isDepot then
    stop.isDepot = true
    stop.network_id = network_id

    -- add parked train to available trains
    if stop.parkedTrainID and stop.parkedTrain.valid then
      if global.Dispatcher.Deliveries[stop.parkedTrainID] then
        if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} is depot with train.id "..stop.parkedTrainID.." assigned to delivery" ) end
      else
        if not global.Dispatcher.availableTrains[stop.parkedTrainID] then
          -- create new available train
          local loco = get_main_locomotive(stop.parkedTrain)
          if loco then
            local capacity, fluid_capacity = GetTrainCapacity(stop.parkedTrain)
            global.Dispatcher.availableTrains[stop.parkedTrainID] = {train = stop.parkedTrain, force = loco.force.name, network_id = network_id, capacity = capacity, fluid_capacity = fluid_capacity}
            global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity + capacity
            global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity + fluid_capacity
          end
        else
          -- update network id
          global.Dispatcher.availableTrains[stop.parkedTrainID].network_id = network_id
        end
        if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} is depot with available train.id "..stop.parkedTrainID ) end
      end
    else
      if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} is empty depot.") end
    end

  -- not a depot -> update cached data in dispatcher
  else
    stop.isDepot = false
    if stop.parkedTrainID and global.Dispatcher.availableTrains[stop.parkedTrainID] then
      remove_available_train(stop.parkedTrainID)
    end

    -- global.Dispatcher.Provided_by_Stop[stopID] = {} -- Provided_by_Stop = {[stopID], {[item], count} }
    -- global.Dispatcher.Requests_by_Stop[stopID] = {} -- Requests_by_Stop = {[stopID], {[item], count} }

    for i = 1, #signals_filtered, 1 do
      local signal_type = signals_filtered[i].signal.type
      local signal_name = signals_filtered[i].signal.name
      local item = signal_type..","..signal_name
      local count = signals_filtered[i].count

      for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
        local deliverycount = delivery.shipment[item]
        if deliverycount then
          if Station_isParked(station, trainID) then
            local stopEntity = global.StoppedTrains[trainID]
            local trainStop = global.LogisticTrainStops[stopEntity.stopID]
            -- calculate items +- train inventory
            local traincount = 0
            if signal_type == "fluid" then
              traincount = trainStop.parkedTrain.get_fluid_count(signal_name)
            else
              traincount = trainStop.parkedTrain.get_item_count(signal_name)
            end

            if delivery.to == stop.entity.backer_name then
              local newcount = count + traincount
              if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
              if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} updating requested count with train inventory: "..item.." "..count.."+"..traincount.."="..newcount) end
              count = newcount
            elseif delivery.from == stop.entity.backer_name then
              if traincount <= deliverycount then
                local newcount = count - (deliverycount - traincount)
                if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
                if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} updating provided count with train inventory: "..item.." "..count.."-"..deliverycount - traincount.."="..newcount) end
                count = newcount
              else --train loaded more than delivery
                if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} updating delivery count with overloaded train inventory: "..item.." "..traincount) end
                -- update delivery to new size
                global.Dispatcher.Deliveries[trainID].shipment[item] = traincount
              end
            end

          else
            -- calculate items +- deliveries
            if delivery.to == stop.entity.backer_name then
              local newcount = count + deliverycount
              if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
              if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} updating requested count with delivery: "..item.." "..count.."+"..deliverycount.."="..newcount) end
              count = newcount
            elseif delivery.from == stop.entity.backer_name and not delivery.pickupDone then
              local newcount = count - deliverycount
              if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
              if debug_log then log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} updating provided count with delivery: "..item.." "..count.."-"..deliverycount.."="..newcount) end
              count = newcount
            end

          end
        end
      end -- for delivery

      local useProvideStackThreshold = false
      local useRequestStackThreshold = false
      local stack_count = 0

      if signal_type == "item" then
        useProvideStackThreshold = provideStackThreshold > 0
        useRequestStackThreshold = requestStackThreshold > 0
        if game.item_prototypes[signal_name] then
          stack_count = count / game.item_prototypes[signal_name].stack_size
        end
      end

      -- update Dispatcher Storage
      -- Providers are used when above Provider Threshold
      -- Requests are handled when above Requester Threshold
      if (useProvideStackThreshold and stack_count >= provideStackThreshold) or
        (not useProvideStackThreshold and count >= provideThreshold) then
        global.Dispatcher.Provided[item] = global.Dispatcher.Provided[item] or {}
        global.Dispatcher.Provided[item][stopID] = count
        global.Dispatcher.Provided_by_Stop[stopID] = global.Dispatcher.Provided_by_Stop[stopID] or {}
        global.Dispatcher.Provided_by_Stop[stopID][item] = count
        if debug_log then
          local trainsEnRoute = "";
          for k,_ in pairs(stop.station.pendingTrains) do
            trainsEnRoute=trainsEnRoute.." "..k
          end
          log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} provides "..item.." "..count.."("..provideThreshold..")".." stacks: "..stack_count.."("..provideStackThreshold..")"..", priority: "..providePriority..", min length: "..minTraincars..", max length: "..maxTraincars..", trains en route: "..trainsEnRoute)
        end
      elseif (useRequestStackThreshold and stack_count*-1 >= requestStackThreshold) or
        (not useRequestStackThreshold and count*-1 >= requestThreshold) then
        count = count * -1
        local ageIndex = item..","..stopID
        global.Dispatcher.RequestAge[ageIndex] = global.Dispatcher.RequestAge[ageIndex] or game.tick
        global.Dispatcher.Requests[#global.Dispatcher.Requests+1] = {age = global.Dispatcher.RequestAge[ageIndex], stopID = stopID, priority = requestPriority, item = item, count = count}
        global.Dispatcher.Requests_by_Stop[stopID] = global.Dispatcher.Requests_by_Stop[stopID] or {}
        global.Dispatcher.Requests_by_Stop[stopID][item] = count
        if debug_log then
          local trainsEnRoute = "";
          for k,_ in pairs(stop.station.pendingTrains) do
            trainsEnRoute=trainsEnRoute.." "..k
          end
          log("(UpdateStop) "..stop.entity.backer_name.."("..stop.entity.unit_number..") {"..network_id_string.."} requests "..item.." "..count.."("..requestThreshold..")".." stacks: "..tostring(stack_count*-1).."("..requestStackThreshold..")"..", priority: "..requestPriority..", min length: "..minTraincars..", max length: "..maxTraincars..", age: "..global.Dispatcher.RequestAge[ageIndex].."/"..game.tick..", trains en route: "..trainsEnRoute)
        end
      end

    end -- for circuitValues

    stop.network_id = network_id
    stop.provideThreshold = provideThreshold
    stop.provideStackThreshold = provideStackThreshold
    stop.providePriority = providePriority
    stop.requestThreshold = requestThreshold
    stop.requestStackThreshold = requestStackThreshold
    stop.requestPriority = requestPriority
    stop.minTraincars = minTraincars
    stop.maxTraincars = maxTraincars
    stop.trainLimit = trainLimit
    stop.lockedSlots = lockedSlots
    stop.noWarnings = noWarnings
  end
end



function setLamp(trainStop, color, count)
  -- skip invalid stops and colors
  if trainStop and trainStop.lampControl.valid and ColorLookup[color] then
    trainStop.lampControl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name=ColorLookup[color]}, count = count }}}
    return true
  end
  return false
end


function UpdateStopOutput(trainStop)
  -- skip invalid stop outputs
  if not trainStop.output.valid then
    return
  end

  local signals = {}
  local index = 0

  if trainStop.parkedTrain and trainStop.parkedTrain.valid then
    -- get train composition
    local carriages = trainStop.parkedTrain.carriages
    local carriagesDec = {}
    local inventory = trainStop.parkedTrain.get_contents() or {}
    local fluidInventory = trainStop.parkedTrain.get_fluid_contents() or {}

    if #carriages < 32 then --prevent circuit network integer overflow error
      if trainStop.parkedTrainFacesStop then --train faces forwards >> iterate normal
        for i=1, #carriages do
          local name = carriages[i].name
          if carriagesDec[name] then
            carriagesDec[name] = carriagesDec[name] + 2^(i-1)
          else
            carriagesDec[name] = 2^(i-1)
          end
        end
      else --train faces backwards >> iterate backwards
        n = 0
        for i=#carriages, 1, -1 do
          local name = carriages[i].name
          if carriagesDec[name] then
            carriagesDec[name] = carriagesDec[name] + 2^n
          else
            carriagesDec[name] = 2^n
          end
          n=n+1
        end
      end

      for k ,v in pairs (carriagesDec) do
        index = index+1
        table.insert(signals, {index = index, signal = {type="virtual",name="LTN-"..k}, count = v })
      end
    end

    if not trainStop.isDepot then
      -- Update normal stations
      local loadingList = {}
      local fluidLoadingList = {}
      local conditions = trainStop.parkedTrain.schedule.records[trainStop.parkedTrain.schedule.current].wait_conditions
      if conditions ~= nil then
        for _, c in pairs(conditions) do
          if c.condition and c.condition.first_signal then -- loading without mods can make first signal nil?
            if c.type == "item_count" then
              if (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
                inventory[c.condition.first_signal.name] = nil
              elseif c.condition.comparator == "≥" then --train expects to be loaded to x of this item
                inventory[c.condition.first_signal.name] = c.condition.constant
              elseif c.condition.comparator == ">" then --train expects to be loaded to x of this item
                inventory[c.condition.first_signal.name] = c.condition.constant + 1
              end
            elseif c.type == "fluid_count" then
              if (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this fluid
                fluidInventory[c.condition.first_signal.name] = -1
              elseif c.condition.comparator == "≥" then --train expects to be loaded to x of this fluid
                fluidInventory[c.condition.first_signal.name] = c.condition.constant
              elseif c.condition.comparator == ">" then --train expects to be loaded to x of this fluid
                fluidInventory[c.condition.first_signal.name] = c.condition.constant + 1
              end
            end
          end
        end
      end

      -- output expected inventory contents
      for k,v in pairs(inventory) do
        index = index+1
        table.insert(signals, {index = index, signal = {type="item", name=k}, count = v})
      end
      for k,v in pairs(fluidInventory) do
        index = index+1
        table.insert(signals, {index = index, signal = {type="fluid", name=k}, count = v})
      end

    end -- not trainStop.isDepot

  end
  -- will reset if called with no parked train
  if index > 0 then
    -- log("[LTN] "..trainStop.entity.backer_name.."("..trainStop.entity.unit_number..") displaying "..#signals.."/"..tostring(trainStop.output.get_control_behavior().signals_count).." signals.")

    while #signals > trainStop.output.get_control_behavior().signals_count do
      -- log("[LTN] removing signal "..tostring(signals[#signals].signal.name))
      table.remove(signals)
    end
    if index ~= #signals then
      if message_level >= 1 then printmsg({"ltn-message.error-stop-output-truncated", tostring(trainStop.entity.backer_name), tostring(trainStop.parkedTrain), trainStop.output.get_control_behavior().signals_count, index-#signals}, trainStop.entity.force) end
      if debug_log then log("(UpdateStopOutput) Inventory of train "..tostring(trainStop.parkedTrain.id).." at stop "..trainStop.entity.backer_name.."("..trainStop.entity.unit_number..") exceeds stop output limit of "..trainStop.output.get_control_behavior().signals_count.." by "..index-#signals.." signals.") end
    end
    trainStop.output.get_control_behavior().parameters = {parameters=signals}
    if debug_log then log("(UpdateStopOutput) Updating signals for "..trainStop.entity.backer_name.."("..trainStop.entity.unit_number.."): train "..tostring(trainStop.parkedTrain.id)..": "..index.." signals") end
  else
    trainStop.output.get_control_behavior().parameters = nil
    if debug_log then log("(UpdateStopOutput) Resetting signals for "..trainStop.entity.backer_name.."("..trainStop.entity.unit_number..").") end
  end
end

function SetStopLamp(stop)
  local station = stop.station
  if station.finishedErrorCode ~= 0 then
    setLamp(stop, ErrorCodes[station.finishedErrorCode], station.finishedErrorCode)
    -- remove parked train from dispatcher (if this is/was a depot)
    if stop.parkedTrainID and global.Dispatcher.availableTrains[stop.parkedTrainID] then
      remove_available_train(stop.parkedTrainID)
    end
    if debug_log then log("(SetStopLamp) Stop with error "..station.finishedErrorCode..": "..stop.entity.backer_name.."("..stop.entity.unit_number..")") end
  else
    if stop.isDepot then
      if stop.parkedTrainID and stop.parkedTrain.valid then
        if global.Dispatcher.Deliveries[stop.parkedTrainID] then
          setLamp(stop, "yellow", 1)
        else
          setLamp(stop, "blue", 1)
        end
      else
        setLamp(stop, "green", 1)
      end
    else
      local trainCount = Station_pendingCount(station)
      if stop.parkedTrainID and stop.parkedTrain.valid then
        setLamp(stop, "blue", trainCount + 1)
      else
        if trainCount == 0 then
          setLamp(stop, "green", Station_numStops(station) - Station_trainCount(station))
        else
          setLamp(stop, "yellow", trainCount)
        end
      end
    end
  end
end
