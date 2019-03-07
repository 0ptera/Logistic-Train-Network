--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]


-- update global.Dispatcher.Deliveries.force when forces are removed/merged
script.on_event(defines.events.on_forces_merging, function(event)
  for _, delivery in pairs(global.Dispatcher.Deliveries) do
    if delivery.force.name == event.source.name then
      delivery.force = event.destination
    end
  end
end)


---------------------------------- MAIN LOOP ----------------------------------

-- recalculate update interval based on stops-per-tick setting
function ResetUpdateInterval()
  local new_update_interval = ceil(#StopIDList/dispatcher_max_stops_per_tick) + 3 -- n-3 ticks for stop Updates, 3 ticks for dispatcher
  if new_update_interval < 60 then  -- limit fastest possible update interval to 60 ticks
    global.Dispatcher.UpdateInterval = 60
    global.Dispatcher.UpdateStopsPerTick = ceil(#StopIDList/57)
  else
    global.Dispatcher.UpdateInterval = new_update_interval
    global.Dispatcher.UpdateStopsPerTick = dispatcher_max_stops_per_tick
  end
  if debug_log then log("(ResetUpdateInterval) UpdateInterval = "..global.Dispatcher.UpdateInterval..", UpdateStopsPerTick = "..global.Dispatcher.UpdateStopsPerTick..", #StopIDList = "..#StopIDList) end
end


function OnTick(event)
  -- exit when there are no logistic train stops
  local tick = event.tick
  global.tickCount = global.tickCount or 1

  if global.tickCount == 1 then

    -- stopsPerTick = ceil(#StopIDList/(global.Dispatcher.UpdateInterval - 3)) -- n-3 ticks for stop Updates, 3 ticks for dispatcher
    -- ResetUpdateInterval()
    global.stopIdStartIndex = 1

    -- clear Dispatcher.Storage
    global.Dispatcher.Provided = {}
    global.Dispatcher.Requests = {}
    global.Dispatcher.Provided_by_Stop = {}
    global.Dispatcher.Requests_by_Stop = {}
  end

  -- ticks 1 - 57: update stops
  if global.tickCount < global.Dispatcher.UpdateInterval - 2 then
    local stopIdLastIndex = global.stopIdStartIndex + global.Dispatcher.UpdateStopsPerTick - 1
    if stopIdLastIndex > #StopIDList then
      stopIdLastIndex = #StopIDList
    end
    for i = global.stopIdStartIndex, stopIdLastIndex, 1 do
      local stopID = StopIDList[i]
      if debug_log then log("(OnTick) "..global.tickCount.."/"..tick.." updating stopID "..tostring(stopID)) end
      UpdateStop(stopID)
    end
    global.stopIdStartIndex = stopIdLastIndex + 1

  -- tick 58: clean up and sort lists
  elseif global.tickCount == global.Dispatcher.UpdateInterval - 2 then
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

        script.raise_event(on_delivery_failed_event, {delivery = delivery, trainID = trainID})
        RemoveDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if message_level >= 1 then printmsg({"ltn-message.delivery-removed-timeout", delivery.from, delivery.to, tick-delivery.started}, delivery.force, false) end
        if debug_log then log("(OnTick) Delivery from "..delivery.from.." to "..delivery.to.." removed. Timed out after "..tick-delivery.started.."/"..delivery_timeout.." ticks.") end

        script.raise_event(on_delivery_failed_event, {delivery = delivery, trainID = trainID})
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

  -- tick 59: parse requests and dispatch trains
  elseif global.tickCount == global.Dispatcher.UpdateInterval - 1 then
    if dispatcher_enabled then
      if debug_log then log("(OnTick) Available train capacity: "..global.Dispatcher.availableTrains_total_capacity.." item stacks, "..global.Dispatcher.availableTrains_total_fluid_capacity.. " fluid capacity.") end
      local created_deliveries = 0
      for reqIndex = 1, #global.Dispatcher.Requests, 1 do
      -- for reqIndex, request in pairs (global.Dispatcher.Requests) do
        local delivery_ID = ProcessRequest(reqIndex)
        if delivery_ID then
          created_deliveries = created_deliveries + 1
        end
      end
      if debug_log then log("(OnTick) Created "..created_deliveries.." deliveries this interval.") end
    else
      if message_level >= 1 then printmsg({"ltn-message.warning-dispatcher-disabled"}, nil, true) end
      if debug_log then log("(OnTick) Dispatcher disabled.") end
    end

  -- tick 60: reset
  else
    -- raise events for interface mods
    -- script.raise_event(on_stops_updated_event, {data = global.LogisticTrainStops})
    -- script.raise_event(on_dispatcher_updated_event, {data = global.Dispatcher}) -- sending whole dispatcher might not be ideal

    -- raise events for interface mods
    script.raise_event(on_stops_updated_event,
      {
        logistic_train_stops = global.LogisticTrainStops,
      })
    script.raise_event(on_dispatcher_updated_event,
      {
        update_interval = global.Dispatcher.UpdateInterval,
        provided_by_stop = global.Dispatcher.Provided_by_Stop,
        requests_by_stop = global.Dispatcher.Requests_by_Stop,
        deliveries = global.Dispatcher.Deliveries,
        available_trains = global.Dispatcher.availableTrains,
      })

    global.tickCount = 0 -- reset tick count
  end

  global.tickCount = global.tickCount + 1
end


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

-- ensures removal of trainID from global.Dispatcher.Deliveries and stop.activeDeliveries
function RemoveDelivery(trainID)
  for stopID, stop in pairs(global.LogisticTrainStops) do
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
  global.Dispatcher.Deliveries[trainID] = nil
end


-- NewScheduleRecord: returns new schedule_record
local condition_circuit_red = {type = "circuit", compare_type = "and", condition = {comparator = "=", first_signal = {type = "virtual", name = "signal-red"}, constant = 0} }
local condition_circuit_green = {type = "circuit", compare_type = "or", condition = {comparator = "≥", first_signal = {type = "virtual", name = "signal-green"}, constant = 1} }
local condition_wait_empty = {type = "empty", compare_type = "and" }
local condition_finish_loading = {type = "inactivity", compare_type = "and", ticks = 120 }
local condition_stop_timeout = {type = "time", compare_type = "or", ticks = stop_timeout }

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


-- ProcessRequest

-- return all stations providing item, ordered by priority and item-count
local function getProviders(requestStation, item, req_count, min_length, max_length)
  local stations = {}
  local providers = global.Dispatcher.Provided[item]
  if not providers then
    return nil
  end
  local toID = requestStation.entity.unit_number
  local force = requestStation.entity.force

  for stopID, count in pairs (providers) do
    local stop = global.LogisticTrainStops[stopID]
    if stop then
      local matched_networks = band(requestStation.network_id, stop.network_id)
      -- log("DEBUG: comparing 0x"..string.format("%x", band(requestStation.network_id)).." & 0x"..string.format("%x", band(stop.network_id)).." = 0x"..string.format("%x", band(matched_networks)) )

      if stop.entity.force.name == force.name
      and matched_networks ~= 0
      and count >= stop.minProvided
      and (stop.minTraincars == 0 or max_length == 0 or stop.minTraincars <= max_length)
      and (stop.maxTraincars == 0 or min_length == 0 or stop.maxTraincars >= min_length) then --check if provider can actually service trains from requester
        local activeDeliveryCount = #stop.activeDeliveries
        local from_network_id_string = format("0x%x", band(stop.network_id))
        if activeDeliveryCount and (stop.trainLimit == 0 or activeDeliveryCount < stop.trainLimit) then
          if debug_log then log("found "..count.."("..tostring(stop.minProvided)..")".."/"..req_count.." ".. item.." at "..stop.entity.backer_name.." {"..from_network_id_string.."}, priority: "..stop.providePriority..", active Deliveries: "..activeDeliveryCount.." minTraincars: "..stop.minTraincars..", maxTraincars: "..stop.maxTraincars..", locked Slots: "..stop.lockedSlots) end
          stations[#stations +1] = {entity = stop.entity, network_id = matched_networks, priority = stop.providePriority, activeDeliveryCount = activeDeliveryCount, item = item, count = count, minTraincars = stop.minTraincars, maxTraincars = stop.maxTraincars, lockedSlots = stop.lockedSlots}
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
    local dist = GetDistance(stationA.position, stationB.position)
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
        log("checking train "..tostring(GetTrainName(trainData.train)).." ,force "..trainData.force.."/"..nextStop.entity.force.name..", network "..depot_network_id_string.."/"..dest_network_id_string..", length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..getStationDistance(trainData.train.station, nextStop.entity))
      end

      if trainData.force == nextStop.entity.force.name -- forces match
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
            if debug_log then log("(getFreeTrain) found train "..tostring(GetTrainName(trainData.train)).." {"..depot_network_id_string.."}, length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
          end
        elseif smallestInventory == 0 and inventorySize > 0 then
          -- train can be used for partial delivery, use only when no trains for whole delivery available
          if inventorySize > largestInventory or (inventorySize == largestInventory and distance < minDistance) or largestInventory == 0 then
            minDistance = distance
            largestInventory = inventorySize
            result_train = trainData.train
            result_train_capacity = inventorySize
            if debug_log then log("(getFreeTrain) largest available train "..tostring(GetTrainName(trainData.train)).." {"..depot_network_id_string.."}, length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
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
function ProcessRequest(reqIndex)
  local request = global.Dispatcher.Requests[reqIndex]

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

  local minRequested = requestStation.minRequested
  local maxTraincars = requestStation.maxTraincars
  local minTraincars = requestStation.minTraincars
  local requestForce = requestStation.entity.force

  if debug_log then log("request "..reqIndex.."/"..#global.Dispatcher.Requests..": "..count.."("..minRequested..")".." "..item.." to "..requestStation.entity.backer_name.." {"..to_network_id_string.."} priority: "..request.priority.." min length: "..minTraincars.." max length: "..maxTraincars ) end

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
      if debug_log then log("Skipping request "..requestStation.entity.backer_name.." {"..to_network_id_string.."}: "..item..". No trains available.") end
      return nil
    end
  else
    localname = game.item_prototypes[iname].localised_name
    -- skip if no trains are available
    if (global.Dispatcher.availableTrains_total_capacity or 0) == 0 then
      if message_level >= 2 then printmsg({"ltn-message.empty-depot-item"}, requestForce, true) end
      if debug_log then log("Skipping request "..requestStation.entity.backer_name.." {"..to_network_id_string.."}: "..item..". No trains available.") end
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

  local providerStation = providers[1] -- only one delivery/request is created so use only the best provider
  local fromID = providerStation.entity.unit_number
  local from = providerStation.entity.backer_name
  local matched_network_id_string = format("0x%x", band(providerStation.network_id))

  if message_level >= 3 then printmsg({"ltn-message.provider-found", from, tostring(providerStation.priority), tostring(providerStation.activeDeliveryCount), providerStation.count, localname}, requestForce, true) end
  -- if debug_log then
    -- for n, provider in pairs (providers) do
      -- log("Provider["..n.."] "..provider.entity.backer_name..": Priority "..tostring(provider.priority)..", "..tostring(provider.activeDeliveryCount).." deliveries, "..tostring(provider.count).." "..item.." available.")
    -- end
  -- end

  -- limit deliverySize to count at provider
  local deliverySize = count
  if count > providerStation.count then
    deliverySize = providerStation.count
  end

  local stacks = deliverySize -- for fluids stack = tanker capacity
  if itype ~= "fluid" then
    stacks = ceil(deliverySize / game.item_prototypes[iname].stack_size) -- calculate amount of stacks item count will occupy
  end

  -- maxTraincars = shortest set max-train-length
  if providerStation.maxTraincars > 0 and (providerStation.maxTraincars < requestStation.maxTraincars or requestStation.maxTraincars == 0) then
    maxTraincars = providerStation.maxTraincars
  end
  -- minTraincars = longest set min-train-length
  if providerStation.minTraincars > 0 and (providerStation.minTraincars > requestStation.minTraincars or requestStation.minTraincars == 0) then
    minTraincars = providerStation.minTraincars
  end

  global.Dispatcher.Requests_by_Stop[toID][item] = nil -- remove before merge so it's not added twice
  local loadingList = { {type=itype, name=iname, localname=localname, count=deliverySize, stacks=stacks} }
  local totalStacks = stacks
  -- local order = {toID=toID, fromID=fromID, minTraincars=minTraincars, maxTraincars=maxTraincars, totalStacks=stacks, lockedSlots=providerStation.lockedSlots, loadingList={loadingList} } -- orders as intermediate step are no longer required
  if debug_log then log("created new order "..from.." >> "..to..": "..deliverySize.." "..item.." in "..stacks.."/"..totalStacks.." stacks, min length: "..minTraincars.." max length: "..maxTraincars) end

  -- find possible mergable items, fluids can't be merged in a sane way
  if itype ~= "fluid" then
    for merge_item, merge_count_req in pairs(global.Dispatcher.Requests_by_Stop[toID]) do
      local merge_type, merge_name = match(merge_item, match_string)
      if merge_type and merge_name and game.item_prototypes[merge_name] then --type=="item"?
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
  local selectedTrain, trainInventorySize = getFreeTrain(providerStation, minTraincars, maxTraincars, loadingList[1].type, totalStacks)
  if not selectedTrain or not trainInventorySize then
    if message_level >= 2 then printmsg({"ltn-message.no-train-found", from, to, matched_network_id_string, tostring(minTraincars), tostring(maxTraincars) }, requestForce, true) end
    if debug_log then log("No train with "..tostring(minTraincars).." <= length <= "..tostring(maxTraincars).." to transport "..tostring(totalStacks).." stacks from "..from.." to "..to.." in network "..matched_network_id_string.." found in Depot.") end
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
  selectedTrain.schedule = schedule


  local shipment = {}
  if debug_log then log("Creating Delivery: "..totalStacks.." stacks, "..from.." >> "..to) end
  for i=1, #loadingList do
    local loadingListItem = loadingList[i].type..","..loadingList[i].name
    -- store Delivery
    shipment[loadingListItem] = loadingList[i].count

    -- remove Delivery from Provided items
    global.Dispatcher.Provided[loadingListItem][fromID] = global.Dispatcher.Provided[loadingListItem][fromID] - loadingList[i].count

    -- remove Request and reset age
    global.Dispatcher.Requests_by_Stop[toID][loadingListItem] = nil
    global.Dispatcher.RequestAge[loadingListItem..","..toID] = nil

    if debug_log then log("  "..loadingListItem..", "..loadingList[i].count.." in "..loadingList[i].stacks.." stacks ") end
  end
  global.Dispatcher.Deliveries[selectedTrain.id] = {force=requestForce, train=selectedTrain, started=game.tick, from=from, to=to, networkID=providerStation.network_id, shipment=shipment}
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

  -- return train ID / delivery ID
  return selectedTrain.id
end


