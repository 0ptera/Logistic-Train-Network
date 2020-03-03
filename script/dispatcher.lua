--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]


-- update global.Dispatcher.Deliveries.force when forces are removed/merged
script.on_event(defines.events.on_forces_merging, function(event)
  for _, delivery in pairs(global.Dispatcher.Deliveries) do
    if delivery.force == event.source then
      delivery.force = event.destination
    end
  end
end)


---------------------------------- MAIN LOOP ----------------------------------

function OnTick(event)
  local tick = event.tick
  -- log("DEBUG: (OnTick) "..tick.." global.tick_state: "..tostring(global.tick_state).." global.tick_stop_index: "..tostring(global.tick_stop_index).." global.tick_request_index: "..tostring(global.tick_request_index) )

  if global.tick_state == 1 then -- update stops
    for i = 1, dispatcher_updates_per_tick, 1 do
      -- reset on invalid index
      if global.tick_stop_index and not global.LogisticTrainStops[global.tick_stop_index] then
        global.tick_state = 0
        if message_level >= 1 then printmsg({"ltn-message.error-invalid-stop-index", global.tick_stop_index}, nil, false) end
        log("(OnTick) Invalid global.tick_stop_index "..tostring(global.tick_stop_index).." in global.LogisticTrainStops. Removing stop and starting over.")
        RemoveStop(global.tick_stop_index)
        return
      end

      local stopID, stop = next(global.LogisticTrainStops, global.tick_stop_index)
      if stopID then
        global.tick_stop_index = stopID
        if debug_log then log("(OnTick) "..tick.." updating stopID "..tostring(stopID)) end
        UpdateStop(stopID, stop)
      else -- stop updates complete, moving on
        global.tick_stop_index = nil
        global.tick_state = 2
        return
      end
    end

  elseif global.tick_state == 2 then -- clean up and sort lists
    global.tick_state = 3

    -- remove messages older than message_filter_age from messageBuffer
    for bufferedMsg, v in pairs(global.messageBuffer) do
      if (tick - v.tick) > message_filter_age then
        global.messageBuffer[bufferedMsg] = nil
      end
    end

    --clean up deliveries in case train was destroyed or removed
    local activeDeliveryTrains = ""
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
      if not(delivery.train and delivery.train.valid) then
        if message_level >= 1 then printmsg({"ltn-message.delivery-removed-train-invalid", delivery.from, delivery.to}, delivery.force, false) end
        if debug_log then log("(OnTick) Delivery from "..delivery.from.." to "..delivery.to.." removed. Train no longer valid.") end

        script.raise_event(on_delivery_failed_event, {train_id = trainID, shipment = delivery.shipment})
        RemoveDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if message_level >= 1 then printmsg({"ltn-message.delivery-removed-timeout", delivery.from, delivery.to, tick-delivery.started}, delivery.force, false) end
        if debug_log then log("(OnTick) Delivery from "..delivery.from.." to "..delivery.to.." removed. Timed out after "..tick-delivery.started.."/"..delivery_timeout.." ticks.") end

        script.raise_event(on_delivery_failed_event, {train_id = trainID, shipment = delivery.shipment})
        RemoveDelivery(trainID)
      else
        activeDeliveryTrains = activeDeliveryTrains.." "..trainID
      end
    end
    if debug_log then log("(OnTick) Trains on deliveries"..activeDeliveryTrains) end


    -- remove no longer active requests from global.Dispatcher.RequestAge[stopID]
    local newRequestAge = {}
    for _,request in pairs (global.Dispatcher.Requests) do
      local ageIndex = request.item..","..request.stopID
      local age = global.Dispatcher.RequestAge[ageIndex]
      if age then
        newRequestAge[ageIndex] = age
      end
    end
    global.Dispatcher.RequestAge = newRequestAge

    -- sort requests by priority and age
    sort(global.Dispatcher.Requests, function(a, b)
        if a.priority ~= b.priority then
          return a.priority > b.priority
        else
          return a.age < b.age
        end
      end)

  elseif global.tick_state == 3 then -- parse requests and dispatch trains
    if dispatcher_enabled then
      if debug_log then log("(OnTick) Available train capacity: "..global.Dispatcher.availableTrains_total_capacity.." item stacks, "..global.Dispatcher.availableTrains_total_fluid_capacity.. " fluid capacity.") end
      for i = 1, dispatcher_updates_per_tick, 1 do
        -- reset on invalid index
        if global.tick_request_index and not global.Dispatcher.Requests[global.tick_request_index] then
          global.tick_state = 0
          if message_level >= 1 then printmsg({"ltn-message.error-invalid-request-index", global.tick_request_index}, nil, false) end
          log("(OnTick) Invalid global.tick_request_index "..tostring(global.tick_request_index).." in global.Dispatcher.Requests. Starting over.")
          return
        end

        local request_index, request = next(global.Dispatcher.Requests, global.tick_request_index)
        if request_index and request then
          global.tick_request_index = request_index
          if debug_log then log("(OnTick) "..tick.." parsing request "..tostring(request_index).."/"..tostring(#global.Dispatcher.Requests) ) end
          ProcessRequest(request_index, request)
        else -- request updates complete, moving on
          global.tick_request_index = nil
          global.tick_state = 4
          return
        end
      end
    else
      if message_level >= 1 then printmsg({"ltn-message.warning-dispatcher-disabled"}, nil, true) end
      if debug_log then log("(OnTick) Dispatcher disabled.") end
      global.tick_request_index = nil
      global.tick_state = 4
      return
    end

  elseif global.tick_state == 4 then -- raise API events
    global.tick_state = 0
    -- raise events for mod API
    script.raise_event(on_stops_updated_event,
      {
        logistic_train_stops = global.LogisticTrainStops,
      })
    script.raise_event(on_dispatcher_updated_event,
      {
        update_interval = tick - global.tick_interval_start,
        provided_by_stop = global.Dispatcher.Provided_by_Stop,
        requests_by_stop = global.Dispatcher.Requests_by_Stop,
        deliveries = global.Dispatcher.Deliveries,
        available_trains = global.Dispatcher.availableTrains,
      })

  else -- reset
    global.tick_stop_index = nil
    global.tick_request_index = nil

    global.tick_state = 1
    global.tick_interval_start = tick
    -- clear Dispatcher.Storage
    global.Dispatcher.Provided = {}
    global.Dispatcher.Requests = {}
    global.Dispatcher.Provided_by_Stop = {}
    global.Dispatcher.Requests_by_Stop = {}
  end
end


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

-- ensures removal of trainID from global.Dispatcher.Deliveries and stop.activeDeliveries
function RemoveDelivery(trainID)
  for stopID, stop in pairs(global.LogisticTrainStops) do
    if not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lampControl.valid then
      RemoveStop(stopID)
    else
      for i=#stop.activeDeliveries, 1, -1 do --trainID should be unique => checking matching stop name not required
        if stop.activeDeliveries[i] == trainID then
          table.remove(stop.activeDeliveries, i)
          if #stop.activeDeliveries > 0 then
            setLamp(stop, "yellow", #stop.activeDeliveries)
          else
            setLamp(stop, "green", 1)
          end
        end
      end
    end
  end
  global.Dispatcher.Deliveries[trainID] = nil
end


-- NewScheduleRecord: returns new schedule_record
local condition_circuit_red = {type = "circuit", compare_type = "and", condition = {comparator = "=", first_signal = {type = "virtual", name = "signal-red"}, constant = 0} }
local condition_circuit_green = {type = "circuit", compare_type = "or", condition = {comparator = "≥", first_signal = {type = "virtual", name = "signal-green"}, constant = 1} }
local condition_wait_empty = {type = "empty", compare_type = "and" }
local condition_finish_loading = {type = "inactivity", compare_type = "and", ticks = 120 }
-- local condition_stop_timeout -- set in settings.lua to capture changes

function NewScheduleRecord(stationName, condType, condComp, itemlist, countOverride)
  local record = {station = stationName, wait_conditions = {}}

  if condType == "item_count" then
    local waitEmpty = false
    -- write itemlist to conditions
    for i=1, #itemlist do
      local condFluid = nil
      if itemlist[i].type == "fluid" then
        condFluid = "fluid_count"
        -- workaround for leaving with fluid residue, can time out trains
        if condComp == "=" and countOverride == 0 then
          waitEmpty = true
        end
      end

      -- make > into >=
      if condComp == ">" then
        countOverride = itemlist[i].count - 1
      end

      -- itemlist = {first_signal.type, first_signal.name, constant}
      local cond = {comparator = condComp, first_signal = {type = itemlist[i].type, name = itemlist[i].name}, constant = countOverride or itemlist[i].count}
      record.wait_conditions[#record.wait_conditions+1] = {type = condFluid or condType, compare_type = "and", condition = cond }
    end

    if waitEmpty then
      record.wait_conditions[#record.wait_conditions+1] = condition_wait_empty
    elseif finish_loading then -- let inserter/pumps finish
      record.wait_conditions[#record.wait_conditions+1] = condition_finish_loading
    end

    -- with circuit control enabled keep trains waiting until red = 0 and force them out with green ≥ 1
    if schedule_cc then
      record.wait_conditions[#record.wait_conditions+1] = condition_circuit_red
      record.wait_conditions[#record.wait_conditions+1] = condition_circuit_green
    end

    if stop_timeout > 0 then -- send stuck trains away when stop_timeout is set
      record.wait_conditions[#record.wait_conditions+1] = condition_stop_timeout
      -- should it also wait for red = 0?
      if schedule_cc then
        record.wait_conditions[#record.wait_conditions+1] = condition_circuit_red
      end
    end
  elseif condType == "inactivity" then
    record.wait_conditions[#record.wait_conditions+1] = {type = condType, compare_type = "and", ticks = condComp }
    -- with circuit control enabled keep trains waiting until red = 0 and force them out with green ≥ 1
    if schedule_cc then
      record.wait_conditions[#record.wait_conditions+1] = condition_circuit_red
      record.wait_conditions[#record.wait_conditions+1] = condition_circuit_green
    end
  end
  return record
end


---- ProcessRequest ----

-- return a list ordered priority > #activeDeliveries > item-count of {entity, network_id, priority, activeDeliveryCount, item, count, provideThreshold, provideStackThreshold, minTraincars, maxTraincars, lockedSlots}
local function getProviders(requestStation, item, req_count, min_length, max_length)
  local stations = {}
  local providers = global.Dispatcher.Provided[item]
  if not providers then
    return nil
  end
  local toID = requestStation.entity.unit_number
  local force = requestStation.entity.force
  local surface = requestStation.entity.surface

  for stopID, count in pairs (providers) do
    local stop = global.LogisticTrainStops[stopID]
    if stop and stop.entity.valid then
      local matched_networks = band(requestStation.network_id, stop.network_id)
      -- log("DEBUG: comparing 0x"..string.format("%x", band(requestStation.network_id)).." & 0x"..string.format("%x", band(stop.network_id)).." = 0x"..string.format("%x", band(matched_networks)) )

      if stop.entity.force == force
      and stop.entity.surface == surface
      and matched_networks ~= 0
      -- and count >= stop.provideThreshold
      and (stop.minTraincars == 0 or max_length == 0 or stop.minTraincars <= max_length)
      and (stop.maxTraincars == 0 or min_length == 0 or stop.maxTraincars >= min_length) then --check if provider can actually service trains from requester
        local activeDeliveryCount = #stop.activeDeliveries
        local from_network_id_string = format("0x%x", band(stop.network_id))
        if activeDeliveryCount and (stop.trainLimit == 0 or activeDeliveryCount < stop.trainLimit) then
          if debug_log then log("found "..count.."("..tostring(stop.provideThreshold)..")".."/"..req_count.." ".. item.." at "..stop.entity.backer_name.." {"..from_network_id_string.."}, priority: "..stop.providePriority..", active Deliveries: "..activeDeliveryCount.." minTraincars: "..stop.minTraincars..", maxTraincars: "..stop.maxTraincars..", locked Slots: "..stop.lockedSlots) end
          stations[#stations +1] = {
            entity = stop.entity,
            network_id = matched_networks,
            priority = stop.providePriority,
            activeDeliveryCount = activeDeliveryCount,
            item = item,
            count = count,
            provideThreshold = stop.provideThreshold,
            provideStackThreshold = stop.provideStackThreshold,
            minTraincars = stop.minTraincars,
            maxTraincars = stop.maxTraincars,
            lockedSlots = stop.lockedSlots,
          }
        end
      end
    end
  end
  -- sort best matching station to the top
  sort(stations, function(a, b)
      if a.priority ~= b.priority then --sort by priority, will result in train queues if trainlimit is not set
        return a.priority > b.priority
      elseif a.activeDeliveryCount ~= b.activeDeliveryCount then --sort by #deliveries
        return a.activeDeliveryCount < b.activeDeliveryCount
      else
        return a.count > b.count --finally sort by item count
      end
    end)
  return stations
end

local function getStationDistance(stationA, stationB)
  local stationPair = stationA.unit_number..","..stationB.unit_number
  if global.StopDistances[stationPair] then
    --log(stationPair.." found, distance: "..global.StopDistances[stationPair])
    return global.StopDistances[stationPair]
  else
    local dist = get_distance(stationA.position, stationB.position)
    global.StopDistances[stationPair] = dist
    --log(stationPair.." calculated, distance: "..dist)
    return dist
  end
end

-- returns: available train with smallest suitable inventory or largest available inventory
--          capacity of train - locked slots of provider
-- if minTraincars is set, number of locos + wagons has to be bigger
-- if maxTraincars is set, number of locos + wagons has to be smaller
local function getFreeTrain(nextStop, minTraincars, maxTraincars, type, size)
  local result_train = nil
  local result_train_capacity = nil
  if minTraincars == nil or minTraincars < 0 then minTraincars = 0 end
  if maxTraincars == nil or maxTraincars < 0 then maxTraincars = 0 end
  local largestInventory = 0
  local smallestInventory = 0
  local minDistance = 0
  for trainID, trainData in pairs (global.Dispatcher.availableTrains) do
    if trainData.train.valid and trainData.train.station and trainData.train.station.valid then
      local depot_network_id_string -- filled only when debug_log is enabled
      local dest_network_id_string  -- filled only when debug_log is enabled
      local inventorySize = trainData.capacity - (nextStop.lockedSlots * #trainData.train.cargo_wagons) -- subtract locked slots from every cargo wagon
      if type == "fluid" then
        inventorySize = trainData.fluid_capacity
      end

      if debug_log then
        depot_network_id_string = format("0x%x", band(trainData.network_id) )
        dest_network_id_string = format("0x%x", band(nextStop.network_id) )
        log("checking train "..tostring(get_train_name(trainData.train)).." ,force "..tostring(trainData.force.name).."/"..tostring(nextStop.entity.force.name)..", network "..depot_network_id_string.."/"..dest_network_id_string..", length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..getStationDistance(trainData.train.station, nextStop.entity))
      end

      if trainData.force == nextStop.entity.force -- forces match
      and trainData.surface == nextStop.entity.surface
      and btest(trainData.network_id, nextStop.network_id) -- depot is in the same network as requester and provider
      and (minTraincars == 0 or #trainData.train.carriages >= minTraincars) and (maxTraincars == 0 or #trainData.train.carriages <= maxTraincars) then -- train length fits
        local distance = getStationDistance(trainData.train.station, nextStop.entity)
        if inventorySize >= size then
          -- train can be used for whole delivery
          if inventorySize < smallestInventory or (inventorySize == smallestInventory and distance < minDistance) or smallestInventory == 0 then
            minDistance = distance
            smallestInventory = inventorySize
            result_train = trainData.train
            result_train_capacity = inventorySize
            if debug_log then log("(getFreeTrain) found train "..tostring(get_train_name(trainData.train)).." {"..depot_network_id_string.."}, length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
          end
        elseif smallestInventory == 0 and inventorySize > 0 then
          -- train can be used for partial delivery, use only when no trains for whole delivery available
          if inventorySize > largestInventory or (inventorySize == largestInventory and distance < minDistance) or largestInventory == 0 then
            minDistance = distance
            largestInventory = inventorySize
            result_train = trainData.train
            result_train_capacity = inventorySize
            if debug_log then log("(getFreeTrain) largest available train "..tostring(get_train_name(trainData.train)).." {"..depot_network_id_string.."}, length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
          end
        end

      end
    else
      -- remove invalid train from global.Dispatcher.availableTrains
      global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[trainID].capacity
      global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[trainID].fluid_capacity
      global.Dispatcher.availableTrains[trainID] = nil
    end
  end

  return result_train, result_train_capacity
end

-- parse single request from global.Dispatcher.Request={stopID, item, age, count}
-- returns created delivery ID or nil
function ProcessRequest(reqIndex, request)
  -- ensure validity of request stop
  local toID = request.stopID
  local requestStation = global.LogisticTrainStops[toID]

  if not requestStation or not (requestStation.entity and requestStation.entity.valid) then
    -- goto skipRequestItem -- station was removed since request was generated
    return nil
  end

  local to = requestStation.entity.backer_name
  local to_network_id_string = format("0x%x", band(requestStation.network_id))
  local item = request.item
  local count = request.count

  local maxTraincars = requestStation.maxTraincars
  local minTraincars = requestStation.minTraincars
  local requestForce = requestStation.entity.force

  if debug_log then log("request "..reqIndex.."/"..#global.Dispatcher.Requests..": "..count.."("..requestStation.requestThreshold..")".." "..item.." to "..requestStation.entity.backer_name.." {"..to_network_id_string.."} priority: "..request.priority.." min length: "..minTraincars.." max length: "..maxTraincars ) end

  if not( global.Dispatcher.Requests_by_Stop[toID] and global.Dispatcher.Requests_by_Stop[toID][item] ) then
    if debug_log then log("Skipping request "..requestStation.entity.backer_name..": "..item..". Item has already been processed.") end
    -- goto skipRequestItem -- item has been processed already
    return nil
  end

  if requestStation.trainLimit > 0 and #requestStation.activeDeliveries >= requestStation.trainLimit then
    if debug_log then log(requestStation.entity.backer_name.." Request station train limit reached: "..#requestStation.activeDeliveries.."("..requestStation.trainLimit..")" ) end
    -- goto skipRequestItem -- reached train limit
    return nil
  end

  -- find providers for requested item
  local itype, iname = match(item, match_string)
  if not (itype and iname and (game.item_prototypes[iname] or game.fluid_prototypes[iname])) then
    if message_level >= 1 then printmsg({"ltn-message.error-parse-item", item}, requestForce) end
    if debug_log then log("(ProcessRequests) could not parse "..item) end
    -- goto skipRequestItem
    return nil
  end

  local localname
  if itype == "fluid" then
    localname = game.fluid_prototypes[iname].localised_name
    -- skip if no trains are available
    if (global.Dispatcher.availableTrains_total_fluid_capacity or 0) == 0 then
      if message_level >= 2 then printmsg({"ltn-message.empty-depot-fluid"}, requestForce, true) end
      if debug_log then log("Skipping request "..to.." {"..to_network_id_string.."}: "..item..". No trains available.") end
      script.raise_event(on_dispatcher_no_train_found_event, {to = to, to_id = toID, network_id = requestStation.network_id, item = item})
      return nil
    end
  else
    localname = game.item_prototypes[iname].localised_name
    -- skip if no trains are available
    if (global.Dispatcher.availableTrains_total_capacity or 0) == 0 then
      if message_level >= 2 then printmsg({"ltn-message.empty-depot-item"}, requestForce, true) end
      if debug_log then log("Skipping request "..to.." {"..to_network_id_string.."}: "..item..". No trains available.") end
      script.raise_event(on_dispatcher_no_train_found_event, {to = to, to_id = toID, network_id = requestStation.network_id, item = item})
      return nil
    end
  end

  -- get providers ordered by priority
  local providers = getProviders(requestStation, item, count, minTraincars, maxTraincars)
  if not providers or #providers < 1 then
    if requestStation.noWarnings == false and message_level >= 1 then printmsg({"ltn-message.no-provider-found", localname, to_network_id_string}, requestForce, true) end
    if debug_log then log("No station supplying "..item.." found.") end
    -- goto skipRequestItem
    return nil
  end

  local providerData = providers[1] -- only one delivery/request is created so use only the best provider
  local fromID = providerData.entity.unit_number
  local from = providerData.entity.backer_name
  local matched_network_id_string = format("0x%x", band(providerData.network_id))

  if message_level >= 3 then printmsg({"ltn-message.provider-found", from, tostring(providerData.priority), tostring(providerData.activeDeliveryCount), providerData.count, localname}, requestForce, true) end
  -- if debug_log then
    -- for n, provider in pairs (providers) do
      -- log("Provider["..n.."] "..provider.entity.backer_name..": Priority "..tostring(provider.priority)..", "..tostring(provider.activeDeliveryCount).." deliveries, "..tostring(provider.count).." "..item.." available.")
    -- end
  -- end

  -- limit deliverySize to count at provider
  local deliverySize = count
  if count > providerData.count then
    deliverySize = providerData.count
  end

  local stacks = deliverySize -- for fluids stack = tanker capacity
  if itype ~= "fluid" then
    stacks = ceil(deliverySize / game.item_prototypes[iname].stack_size) -- calculate amount of stacks item count will occupy
  end

  -- maxTraincars = shortest set max-train-length
  if providerData.maxTraincars > 0 and (providerData.maxTraincars < requestStation.maxTraincars or requestStation.maxTraincars == 0) then
    maxTraincars = providerData.maxTraincars
  end
  -- minTraincars = longest set min-train-length
  if providerData.minTraincars > 0 and (providerData.minTraincars > requestStation.minTraincars or requestStation.minTraincars == 0) then
    minTraincars = providerData.minTraincars
  end

  global.Dispatcher.Requests_by_Stop[toID][item] = nil -- remove before merge so it's not added twice
  local loadingList = { {type=itype, name=iname, localname=localname, count=deliverySize, stacks=stacks} }
  local totalStacks = stacks
  if debug_log then log("created new order "..from.." >> "..to..": "..deliverySize.." "..item.." in "..stacks.."/"..totalStacks.." stacks, min length: "..minTraincars.." max length: "..maxTraincars) end

  -- find possible mergable items, fluids can't be merged in a sane way
  if itype ~= "fluid" then
    for merge_item, merge_count_req in pairs(global.Dispatcher.Requests_by_Stop[toID]) do
      local merge_type, merge_name = match(merge_item, match_string)
      if merge_type and merge_name and game.item_prototypes[merge_name] then
        local merge_localname = game.item_prototypes[merge_name].localised_name
        -- get current provider for requested item
        if global.Dispatcher.Provided[merge_item] and global.Dispatcher.Provided[merge_item][fromID] then
          -- set delivery Size and stacks
          local merge_count_prov = global.Dispatcher.Provided[merge_item][fromID]
          local merge_deliverySize = merge_count_req
          if merge_count_req > merge_count_prov then
            merge_deliverySize = merge_count_prov
          end
          local merge_stacks =  ceil(merge_deliverySize / game.item_prototypes[merge_name].stack_size) -- calculate amount of stacks item count will occupy

          -- add to loading list
          loadingList[#loadingList+1] = {type=merge_type, name=merge_name, localname=merge_localname, count=merge_deliverySize, stacks=merge_stacks}
          totalStacks = totalStacks + merge_stacks
          -- order.totalStacks = order.totalStacks + merge_stacks
          -- order.loadingList[#order.loadingList+1] = loadingList
          if debug_log then log("inserted into order "..from.." >> "..to..": "..merge_deliverySize.." "..merge_item.." in "..merge_stacks.."/"..totalStacks.." stacks.") end
        end
      end
    end
  end

  -- find train
  local selectedTrain, trainInventorySize = getFreeTrain(providerData, minTraincars, maxTraincars, loadingList[1].type, totalStacks)
  if not selectedTrain or not trainInventorySize then
    if message_level >= 2 then printmsg({"ltn-message.no-train-found", from, to, matched_network_id_string, tostring(minTraincars), tostring(maxTraincars) }, requestForce, true) end
    if debug_log then log("No train with "..tostring(minTraincars).." <= length <= "..tostring(maxTraincars).." to transport "..tostring(totalStacks).." stacks from "..from.." to "..to.." in network "..matched_network_id_string.." found in Depot.") end
    script.raise_event(on_dispatcher_no_train_found_event, { to = to, to_id = toID, from = from, from_id = fromID, network_id = requestStation.network_id, minTraincars = minTraincars, maxTraincars = maxTraincars, shipment = loadingList,
    })
    global.Dispatcher.Requests_by_Stop[toID][item] = count -- add removed item back to list of requested items.
    return nil
  end

  if message_level >= 3 then printmsg({"ltn-message.train-found", from, to, matched_network_id_string, tostring(trainInventorySize), tostring(totalStacks) }, requestForce) end
  if debug_log then log("Train to transport "..tostring(trainInventorySize).."/"..tostring(totalStacks).." stacks from "..from.." to "..to.." in network "..matched_network_id_string.." found in Depot.") end

  -- recalculate delivery amount to fit in train
  if trainInventorySize < totalStacks then
    -- recalculate partial shipment
    if loadingList[1].type == "fluid" then
      -- fluids are simple
      loadingList[1].count = trainInventorySize
    else
      -- items need a bit more math
      for i=#loadingList, 1, -1 do
        if totalStacks - loadingList[i].stacks < trainInventorySize then
          -- remove stacks until it fits in train
          loadingList[i].stacks = loadingList[i].stacks - (totalStacks - trainInventorySize)
          totalStacks = trainInventorySize
          local newcount = loadingList[i].stacks * game.item_prototypes[loadingList[i].name].stack_size
          loadingList[i].count = newcount
          break
        else
          -- remove item and try again
          totalStacks = totalStacks - loadingList[i].stacks
          table.remove(loadingList, i)
        end
      end
    end
  end

  -- create delivery
  if message_level >= 2 then
    if #loadingList == 1 then
      printmsg({"ltn-message.creating-delivery", from, to, loadingList[1].count, loadingList[1].localname}, requestForce)
    else
      printmsg({"ltn-message.creating-delivery-merged", from, to, totalStacks}, requestForce)
    end
  end

  -- create schedule
  -- local selectedTrain = global.Dispatcher.availableTrains[trainID].train
  local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]
  local schedule = {current = 1, records = {}}
  schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "inactivity", depot_inactivity)
  schedule.records[2] = NewScheduleRecord(from, "item_count", "≥", loadingList)
  schedule.records[3] = NewScheduleRecord(to, "item_count", "=", loadingList, 0)
  -- log("DEBUG: schedule = "..serpent.block(schedule))
  selectedTrain.schedule = schedule


  local shipment = {}
  if debug_log then log("Creating Delivery: "..totalStacks.." stacks, "..from.." >> "..to) end
  for i=1, #loadingList do
    local loadingListItem = loadingList[i].type..","..loadingList[i].name
    -- store Delivery
    shipment[loadingListItem] = loadingList[i].count

    -- subtract Delivery from Provided items and check thresholds
    global.Dispatcher.Provided[loadingListItem][fromID] = global.Dispatcher.Provided[loadingListItem][fromID] - loadingList[i].count
    local new_provided = global.Dispatcher.Provided[loadingListItem][fromID] - loadingList[i].count
    local new_provided_stacks = 0
    local useProvideStackThreshold = false
    if loadingList[i].type == "item" then
      if game.item_prototypes[loadingList[i].name] then
        new_provided_stacks = new_provided / game.item_prototypes[loadingList[i].name].stack_size
      end
      useProvideStackThreshold = providerData.provideStackThreshold > 0
    end

    if (useProvideStackThreshold and new_provided_stacks >= providerData.provideStackThreshold) or
      (not useProvideStackThreshold and new_provided >= providerData.provideThreshold) then
      global.Dispatcher.Provided[loadingListItem][fromID] = new_provided
      global.Dispatcher.Provided_by_Stop[fromID][loadingListItem] = new_provided
    else
      global.Dispatcher.Provided[loadingListItem][fromID] = nil
      global.Dispatcher.Provided_by_Stop[fromID][loadingListItem] = nil
    end

    -- remove Request and reset age
    global.Dispatcher.Requests_by_Stop[toID][loadingListItem] = nil
    global.Dispatcher.RequestAge[loadingListItem..","..toID] = nil

    if debug_log then log("  "..loadingListItem..", "..loadingList[i].count.." in "..loadingList[i].stacks.." stacks ") end
  end
  global.Dispatcher.Deliveries[selectedTrain.id] = {
    force = requestForce,
    train = selectedTrain,
    started = game.tick,
    from = from,
    from_id = fromID,
    to = to,
    to_id = toID,
    -- networkID = providerData.network_id,
    network_id = providerData.network_id,
    shipment = shipment}
  global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[selectedTrain.id].capacity
  global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[selectedTrain.id].fluid_capacity
  global.Dispatcher.availableTrains[selectedTrain.id] = nil

  -- train is no longer available => set depot to yellow
  setLamp(depot, "yellow", 1)

  -- update delivery count and lamps on stations
  -- trains will pick a stop by their own logic so we have to parse by name
  for stopID, stop in pairs (global.LogisticTrainStops) do
    if stop.entity.backer_name == from or stop.entity.backer_name == to then
      table.insert(global.LogisticTrainStops[stopID].activeDeliveries, selectedTrain.id)
      -- only update blue lamp count, otherwise change to yellow
      local current_signal = stop.lampControl.get_control_behavior().get_signal(1)
      if current_signal and current_signal.signal.name == "signal-blue" then
        setLamp(stop, "blue", #stop.activeDeliveries)
      else
        setLamp(stop, "yellow", #stop.activeDeliveries)
      end
    end
  end

  -- return train ID = delivery ID
  return selectedTrain.id
end


