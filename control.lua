require "config"
require "interface"

MOD_NAME = "LogisticTrainNetwork"
MINDELIVERYSIZE = "min-delivery-size"
MAXTRAINLENGTH = "max-train-length"
PRIORITY = "stop-priority"

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
  global.log_level = global.log_level or 2 -- 4: everything, 3: scheduler messages, 2: basic messages, 1 errors only, 0: off
  global.log_output = global.log_output or "both" -- console or log or both
  
  -- check if RailTanker is installed
  if game.active_mods["RailTanker"] then
    global.useRailTanker = true
  else
    global.useRailTanker = false
  end
  
  -- update to 0.4.5
  if type(global.log_output) ~= "string" then
    global.log_output = "both"
  end
  
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
  
  global.Dispatcher = global.Dispatcher or {}
  
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  
  --update to 0.5.0
  global.Dispatcher.Storage = nil
  global.Dispatcher.Requested = global.Dispatcher.Requested or {}
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}
  
  -- update 0.4.4
  global.Dispatcher.Orders = nil
  global.Dispatcher.OrderAge = global.Dispatcher.OrderAge or {}
  
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}
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
		CreateStop(entity)
	end
  if entity.type == "locomotive" or entity.type == "cargo-wagon" then
    entity.train.manual_mode = true
    UpdateStopParkedTrain(entity.train)
    --entity.train.manual_mode = false 
  end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  local entity = event.created_entity
	if entity.name == "logistic-train-stop" then
		CreateStop(entity)
	end
end)


script.on_event(defines.events.on_preplayer_mined_item, function(event)
  local entity = event.entity
  if entity.name == "logistic-train-stop" then
    RemoveStop(entity)
  end
  if entity.type == "locomotive" or entity.type == "cargo-wagon" then
    entity.train.manual_mode = true
    UpdateStopParkedTrain(entity.train)
    --entity.train.manual_mode = false
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
  end
  if entity.type == "locomotive" or entity.type == "cargo-wagon" then
    entity.train.manual_mode = true
    UpdateStopParkedTrain(entity.train)
    --entity.train.manual_mode = false
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
    if global.log_level >= 4 then printmsg("no LogisticTrainStops, unsubscribed from on_tick") end
    return
  end
  
  if tick % station_update_interval == 0 then
    -- clear Dispatcher.Storage
    global.Dispatcher.Provided = {}
    global.Dispatcher.Requested = {}
    
    -- update LogisticTrainStops
    for stopID, stop in pairs(global.LogisticTrainStops) do     
      UpdateStop(stopID)
    end   
  end
  
  if tick % dispatcher_update_interval == 0 then
    ---- clean up deliveries in case train was destroyed or removed ----
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do        
      if not delivery.train or not delivery.train.valid then
        if global.log_level >= 2 then printmsg("Delivery from "..delivery.from.." to "..delivery.to.." removed. Train no longer valid.") end
        removeDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if global.log_level >= 2 then printmsg("Delivery from "..delivery.from.." to "..delivery.to.." running for "..tick-delivery.started.." ticks removed after time out.") end
        removeDelivery(trainID)
      end
    end  
    
    -- remove no longer active requests from global.Dispatcher.OrderAge[toID][type][name] = age
    local newOrderAge = {}
    for stopID, requests in pairs (global.Dispatcher.OrderAge) do
      local stop = global.LogisticTrainStops[stopID]
      if stop and stop.entity.valid then
        for itype, names in pairs (requests) do
          if names then
            for iname, age in pairs (names) do
              local requesters = global.Dispatcher.Requested[itype..","..iname]
              if requesters and requesters[stopID] and requesters[stopID] >= stop.minDelivery then
                newOrderAge[stopID] = newOrderAge[stopID] or {}
                newOrderAge[stopID][itype] = newOrderAge[stopID][itype] or {}
                newOrderAge[stopID][itype][iname] = age
                if global.log_level >= 4 then printmsg("preserving Order, tick: "..newOrderAge[stopID][itype][iname]..", to: "..stopID..", "..itype..", "..iname) end
              end
            end
          end
        end
      end
    end
    global.Dispatcher.OrderAge = newOrderAge
    
    -- create orders {toID, fromID, age, minDelivery, maxTraincars, shipmentCount, shipment = {[type] = {[name] = count}}}  
    local orders = BuildOrders()
    
    -- sort orders by age
    local sort = table.sort
    sort(orders, function(a, b)
        return a.age < b.age
      end)
    
    -- send orders to available train
    ProcessOrders(orders)
    
  end -- dispatcher update
end    


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

-- creates and merges new orders from Dispatcher.Requested
function BuildOrders()
  local orders = {}
  for item, data in pairs (global.Dispatcher.Requested) do
    for stopID, count in pairs (data) do
    if not(stopID == "sumCount" or stopID == "sumStops") then --skip sumCount, sumStops 
      local requestStation = global.LogisticTrainStops[stopID]
      if not requestStation or requestStation.isDepot or requestStation.errorCode > 0 then
        if global.log_level >= 1 then printmsg("Error(BuildOrders): invalid request Stop ID: "..stopID) end
        goto skipRequestItem
      end
      local minDelivery = requestStation.minDelivery
      local match = string.match

      -- don't deliver anything below delivery size
      if count < minDelivery then
        goto skipRequestItem
      end 

      -- split merged key into type & name
      local itype, iname = match(item, "([^,]+),([^,]+)")
      if not (itype and iname) then
        if global.log_level >= 1 then printmsg("Error(BuildOrders): could not parse item "..item) end
        goto skipRequestItem
      end
        
      -- ignore fluids without rail tanker
      if itype == "fluid" and not global.useRailTanker then
        if global.log_level >= 3 then printmsg("Notice: fluid transport requires Rail Tanker") end
        goto skipRequestItem
      end        
        
      -- get providers ordered by priority
      local providers = GetStations(item, minDelivery)
      if not providers or #providers < 1 then
        if global.log_level >= 3 then printmsg("Notice: no station supplying "..item.." found") end
        goto skipRequestItem
      end
        
      -- prevent stop from hogging all available items
      local provided = global.Dispatcher.Provided[item]
      local requested = global.Dispatcher.Requested[item]
      if requested and provided then
        if provided.sumCount < requested.sumCount then
          local floor = math.floor
          local averageCount = floor(provided.sumCount / requested.sumStops)
          if count > averageCount then
            if averageCount > minDelivery or use_Best_Effort then
              count = averageCount
            else
              count = minDelivery
            end
          end
        end
      end
        
        -- create orders until request is fulfilled
      for i=1, #providers do
        local deliverySize = count
        if providers[i].count < count then
          deliverySize = providers[i].count
        end
        count = count - deliverySize
        
        -- maxTraincars = shortest set max-train-length
        local maxTraincars = requestStation.maxTraincars
        if providers[i].maxTraincars > 0 and providers[i].maxTraincars < requestStation.maxTraincars then
          maxTraincars = providers[i].maxTraincars
        end
        
        -- merge new order into existing orders        
        local to = requestStation.entity.backer_name
        local toID = requestStation.entity.unit_number
        local from = providers[i].entity.backer_name
        local fromID = providers[i].entity.unit_number
        local age = game.tick
        if global.Dispatcher.OrderAge[toID] and global.Dispatcher.OrderAge[toID][itype] and global.Dispatcher.OrderAge[toID][itype][iname] then            
          age = global.Dispatcher.OrderAge[toID][itype][iname]
        end
        
        local insertnew = true
        for j=1, #orders do
          -- insert/merge only items with same provider-requester pair into one order
          if orders[j].toID == toID and orders[j].fromID == fromID and itype == "item" and orders[j].shipment[itype] then
            if not orders[j].shipment[itype][iname] then 
              --add item to shipment
              orders[j].shipmentCount = orders[j].shipmentCount + 1
              global.Dispatcher.OrderAge[toID] = global.Dispatcher.OrderAge[toID] or {}
              global.Dispatcher.OrderAge[toID][itype] = global.Dispatcher.OrderAge[toID][itype] or {}
              global.Dispatcher.OrderAge[toID][itype][iname] = global.Dispatcher.OrderAge[toID][itype][iname] or age
            end            
            orders[j].shipment[itype][iname] = deliverySize
            -- update metadata in case it was changed
            
            orders[j].age = age
            orders[j].maxTraincars = maxTraincars
            orders[j].minDelivery = minDelivery 
            if global.log_level >= 3 then  printmsg("inserted into  order "..i.."/"..#orders.." tick: "..age.."/"..game.tick.." maxLength: "..maxTraincars.." "..from..">>"..to..": "..deliverySize.." "..itype..","..iname) end
            insertnew = false
            break
          end          
        end
        -- create new order for fluids and different provider-requester pairs
        if insertnew then
          orders[#orders+1] = {toID = toID, fromID = fromID, age = age, minDelivery = minDelivery, maxTraincars = maxTraincars, shipmentCount = 1, shipment = {[itype] = {[iname] = deliverySize}}}
          global.Dispatcher.OrderAge[toID] = global.Dispatcher.OrderAge[toID] or {}
          global.Dispatcher.OrderAge[toID][itype] = global.Dispatcher.OrderAge[toID][itype] or {}
          global.Dispatcher.OrderAge[toID][itype][iname] = global.Dispatcher.OrderAge[toID][itype][iname] or age
          if global.log_level >= 3 then  printmsg("added new order "..#orders.." tick: "..age.."/"..game.tick.." maxLength: "..maxTraincars.." "..from..">>"..to..": "..deliverySize.." "..itype..","..iname) end
        end                   
        
        -- prevent multiple orders for same items
        global.Dispatcher.Provided[item][fromID] = global.Dispatcher.Provided[item][fromID] - deliverySize        
        
        -- break if remaining request size is below min_delivery_size
        if count < minDelivery then            
          break
        end
      end --loop found providers

    end -- for stopID, count in pairs (data)
    ::skipRequestItem:: -- use goto since lua doesn't know continue
  end
  end --for item, data in pairs (global.Requested)
  return orders
end

-- checks trains available in depot and sends oldest order as schedule
function ProcessOrders(orders)
  local ceil = math.ceil
  for orderIndex=1, #orders do
    if global.log_level >= 3 then printmsg("processing "..orderIndex.."/"..#orders.." Orders") end
    local order = orders[orderIndex]
    local totalStacks = 0
    local totalCount = 0
    local loadingList = {}
    
    if order.shipment and order.shipmentCount > 0 then
    for itype, items in pairs (order.shipment) do
      if items then
      for name, count in pairs (items) do
        --if global.log_level >= 4 then printmsg("order List: "..itype.." "..name.." "..count) end
        -- calculate stacks needed, type is guaranteed to stay the same per order
        if itype == "item" then
          local addstacks = ceil(count / game.item_prototypes[name].stack_size)
          totalStacks = totalStacks + addstacks
          totalCount = totalCount + count
          loadingList[#loadingList+1] = {type=itype, name=name, count=count, stacks=addstacks}
        elseif itype == "fluid" and global.useRailTanker then
          totalCount = totalCount + count
          totalStacks = totalCount
          loadingList[#loadingList+1] = {type=itype, name=name, count=count, stacks=1}
        else
          -- either rail tanker was removed after the order was created or order got corrupted
          if global.log_level >= 1 then printmsg("Error(ProcessOrders): "..itype.."is no valid type") end
          goto skipOrder
        end        

      end
      end
    end -- for shipment.items
    else
      if global.log_level >= 3 then  printmsg("skipped empty shipment") end
      goto skipOrder
    end

    if loadingList == nil or #loadingList < 1 then
      if global.log_level >= 3 then  printmsg("couldn't create loadingList") end
      goto skipOrder
    end
    
    if global.log_level >= 3 then
    for i=1 ,#loadingList do
       printmsg("loading List: "..loadingList[i].type.." "..loadingList[i].name.." "..loadingList[i].count.." "..loadingList[i].stacks)
    end
    end

    -- get station names
    local toStop = global.LogisticTrainStops[order.toID]
    local fromStop = global.LogisticTrainStops[order.fromID]
    if not toStop or not  fromStop then
      if global.log_level >= 1 then printmsg("Error: Couldn't read station name") end
      goto skipOrder
    end  
    local to = toStop.entity.backer_name
    local from = fromStop.entity.backer_name
    
    -- find train
    local train = GetFreeTrain(loadingList[1].type, totalStacks, order.maxTraincars)
    if not train then
      if order.maxTraincars > 0 then
        if global.log_level >= 3 then printmsg("No train with length "..order.maxTraincars.." to transport "..totalStacks.." found in Depot") end
      else
        if global.log_level >= 3 then printmsg("No train to transport "..totalStacks.." found in Depot") end
      end
      goto skipOrder
    end

    if global.log_level >= 3 then printmsg("Train with "..train.inventorySize.."/"..totalStacks.." found in Depot") end
    
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
            totalCount = totalCount - loadingList[i].count + newcount
            loadingList[i].count = newcount
            break
          else
            -- remove item and try again
            totalStacks = totalStacks - loadingList[i].stacks
            totalCount = totalCount - loadingList[i].count            
            table.remove(loadingList[i])
          end
        end
      end
    end 
    
    if global.log_level >= 2 then 
      if #loadingList == 1 then
        printmsg("Creating Delivery: ".. loadingList[1].count .."  ".. loadingList[1].name..", from "..from.." to "..to) 
      else
        printmsg("Creating merged Delivery: "..totalStacks.." stacks total, from "..from.." to "..to) 
      end
    end
    
    -- create schedule
    local selectedTrain = global.Dispatcher.availableTrains[train.id]
    local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]    
    local schedule = {current = 1, records = {}}
    schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "circuit", "=", {{type="virtual", name="signal-green", count=1}})
    schedule.records[2] = NewScheduleRecord(from, "item_count", ">", loadingList)
    schedule.records[3] = NewScheduleRecord(to, "item_count", "=", loadingList, 0)
    selectedTrain.schedule = schedule   
        
    -- send go to selectedTrain (needs output connected to station)
    depot.output.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual", name="signal-green"}, count = 1 }}}      
    
    -- store delivery and reset order age
    local delivery = {}
    for i=1, #loadingList do
      delivery[loadingList[i].type..","..loadingList[i].name] = loadingList[i].count      
      global.Dispatcher.OrderAge[order.toID][loadingList[i].type][loadingList[i].name] = nil
    end
    global.Dispatcher.Deliveries[train.id] = {train=selectedTrain, started=game.tick, from=from, to=to, shipment=delivery}
    global.Dispatcher.availableTrains[train.id] = nil
    
    -- set lamps on stations to yellow 
    -- trains will pick a stop by their own logic so we have to parse by name
    for stopID, stop in pairs (global.LogisticTrainStops) do
      if stop.entity.backer_name == from or stop.entity.backer_name == to then
        global.LogisticTrainStops[stopID].activeDeliveries = stop.activeDeliveries + 1
      end
    end   

    ::skipOrder:: -- use goto since lua doesn't know continue
  end --for orders

end

-- return all stations providing item, ordered by priority and item-count
function GetStations(item, min_count) 
  local stations = {}
  local providers = global.Dispatcher.Provided[item]
  if not providers then
    return nil
  end
  -- get all providing stations
  for stopID, count in pairs (providers) do
  if not(stopID == "sumCount" or stopID == "sumStops") then --skip sumCount, sumStops
    local stop = global.LogisticTrainStops[stopID]    
    if stop then 
      if count > 0 and (use_Best_Effort or count > min_count) then
        if global.log_level >= 4 then printmsg("(GetStations): found ".. count .."/"..min_count.." ".. item.." at "..stop.entity.backer_name.." priority: "..stop.priority.." maxTraincars: "..stop.maxTraincars) end
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
function GetFreeTrain(type, size, maxTraincars)
  local train = nil
  local largestInventory = 0
  local smallestInventory = 0
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    local inventorySize = 0
    if DispTrain.valid and (maxTraincars == nil or maxTraincars <= 0 or #DispTrain.carriages <= maxTraincars) then -- train length fits
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
        if global.log_level >= 1 then printmsg("Error(GetInventorySize): Could not read inventory size of ".. wagon.name) end
      end
    end
  end         
  return inventorySize
end

-- return new schedule_record
-- itemlist = {first_signal.type, first_signal.name, constant}
function NewScheduleRecord(stationName, condType, condComp, itemlist, countOverride)
  local record = {station = stationName, wait_conditions = {}}
  for i=1, #itemlist do    
    --convert to RT fake item if needed
    local rtname = nil
    local rttype = nil
    if itemlist[i].type == "fluid" and global.useRailTanker then
      rtname = itemlist[i].name .. "-in-tanker"
      rttype = "item"
      if not game.item_prototypes[rtname] then
        if global.log_level >= 1 then printmsg("Error(NewScheduleRecord): couldn't get RailTanker fake item") end
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
  if condType == "circuit" then
    record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "and", ticks = 60 } -- 1s inactivity allowing trains to be refuelled in depot
  else
    if stop_timeout > 0 then
      record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "or", ticks = stop_timeout } -- send stuck trains away
    end
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

function CreateStop(logisticTrainStop)
  if global.LogisticTrainStops[logisticTrainStop.unit_number] then
    if global.log_level >= 1 then printmsg("Error(CreateStop): Duplicated unit_number "..logisticTrainStop.unit_number) end
    return
  end
  
  --printmsg("Stop created at "..logisticTrainStop.position.x.."/"..logisticTrainStop.position.y..", orientation "..logisticTrainStop.direction)
  if logisticTrainStop.direction == 0 then --SN
    posIn = {logisticTrainStop.position.x, logisticTrainStop.position.y-1}
    posOut = {logisticTrainStop.position.x-1, logisticTrainStop.position.y-1}
    rot = 0
  elseif logisticTrainStop.direction == 2 then --EW
    posIn = {logisticTrainStop.position.x, logisticTrainStop.position.y}
    posOut = {logisticTrainStop.position.x, logisticTrainStop.position.y-1}
    rot = 2
  elseif logisticTrainStop.direction == 4 then --NS
    posIn = {logisticTrainStop.position.x-1, logisticTrainStop.position.y}
    posOut = {logisticTrainStop.position.x, logisticTrainStop.position.y}
    rot = 4
  elseif logisticTrainStop.direction == 6 then --WE
    posIn = {logisticTrainStop.position.x-1, logisticTrainStop.position.y-1}
    posOut = {logisticTrainStop.position.x-1, logisticTrainStop.position.y}
    rot = 6
  else --invalid orientation
    if global.log_level >= 1 then printmsg("Error(CreateStop): invalid Train Stop Orientation "..logisticTrainStop.direction) end
    logisticTrainStop.destroy()
    return
  end

  local lampctrl = logisticTrainStop.surface.create_entity
  {
    name = "logistic-train-stop-lamp-control",
    position = posIn,
    force = logisticTrainStop.force
  }  
  lampctrl.operable = false -- disable gui
  lampctrl.minable = false
  lampctrl.destructible = false -- don't bother checking if alive
  lampctrl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name="signal-white"}, count = 1 }}}

  local input = logisticTrainStop.surface.create_entity
  {
    name = "logistic-train-stop-input",

    position = posIn,
    force = logisticTrainStop.force
  }  
  input.operable = false -- disable gui
  input.minable = false
  input.destructible = false -- don't bother checking if alive  
  input.connect_neighbour({target_entity=lampctrl, wire=defines.wire_type.green})
  input.get_or_create_control_behavior().use_colors = true
  input.get_or_create_control_behavior().circuit_condition = {condition = {comperator=">",first_signal={type="virtual",name="signal-anything"}}}
  
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
  output.connect_neighbour({target_entity=logisticTrainStop, wire=defines.wire_type.green})
  
  global.LogisticTrainStops[logisticTrainStop.unit_number] = {
    entity = logisticTrainStop,
    input = input,
    output = output,
    lampControl = lampctrl,
    isDepot = false,
    activeDeliveries = 0, --#deliveries to/from stop
    errorCode = 0,        --key to errorCodes table
    parkedTrain = nil,
    parkedTrainID = nil
  }
  
  UpdateStopOutput(global.LogisticTrainStops[logisticTrainStop.unit_number])
  
  count = 0
  for id, stop in pairs (global.LogisticTrainStops) do --can not get size with #
    count = count+1
  end
  if count == 1 then
    script.on_event(defines.events.on_tick, ticker) --subscribe ticker on first created train stop
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

-- update stop output when train enters/leaves
function UpdateStopParkedTrain(train)
  local trainID = GetTrainID(train)
  local trainName = GetTrainName(train)
  
  if not trainID then --train has no locomotive
    if global.log_level >= 1 then printmsg("Error (UpdateStopParkedTrain): couldn't assign train id") end
    --TODO: -Update all stops?
    return
  end
  
  if train.valid and train.manual_mode == false and train.state == defines.train_state.wait_station and train.station ~= nil and train.station.name == "logistic-train-stop" then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stopID == train.station.unit_number then -- add train to station
        stop.parkedTrain = train
        --global.LogisticTrainStops[stopID].parkedTrain = event.train
        stop.parkedTrainID = trainID
        --global.LogisticTrainStops[stopID].parkedTrainID = trainID
        if global.log_level >= 3 then printmsg("Train "..trainName.." arrived at ".. stop.entity.backer_name) end
        
        if stop.isDepot then
          -- remove delivery
          removeDelivery(trainID)
          
          -- make train available for new deliveries
          global.Dispatcher.availableTrains[trainID] = train          
          
          -- reset schedule
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "circuit", "=", {{type="virtual", name="signal-green", count=1}})
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
        if global.log_level >= 3 then printmsg("Train "..trainName.." left ".. stop.entity.backer_name) end
        
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

  -- check if it's a depot
  if lower(stop.entity.backer_name) == "depot" then
    -- update input signals of depot
    local circuitValues = GetCircuitValues(stop.input)
    if circuitValues then
      local maxTraincars = 0
      local colorCount = 0  
      for item, count in pairs (circuitValues) do
        if item == "virtual,"..MAXTRAINLENGTH and count > 0 then -- set max-train-length
          maxTraincars = count          
        elseif item == "virtual,signal-red" or item == "virtual,signal-green" or item == "virtual,signal-blue" or item == "virtual,signal-yellow" or item == "virtual,signal-pink" or item == "virtual,signal-cyan" or item == "virtual,signal-white" or item == "virtual,signal-grey" or item == "virtual,signal-black" then
          colorCount = colorCount + count
        end
      end
      
      global.LogisticTrainStops[stopID].isDepot = true
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
    end        
  elseif isUniqueStopName(stop) then
    -- reset duplicate name error
    if stop.errorCode == 2 then
      global.LogisticTrainStops[stopID].errorCode = 0
    end
    
    -- update input signals of stop
    local circuitValues = GetCircuitValues(stop.input)
    local requested = {}
    local provided = {}
    if circuitValues then
      local minDelivery = min_delivery_size
      local maxTraincars = 0
      local priority = 0
      local colorCount = 0       
      for item, count in pairs (circuitValues) do
        if item == "virtual,"..MINDELIVERYSIZE and count > 0 then -- overwrite default min-delivery-size
          minDelivery = count
        elseif item == "virtual,"..MAXTRAINLENGTH and count > 0 then -- set max-train-length
          maxTraincars = count
        elseif item == "virtual,"..PRIORITY and count > 0 then -- set max-train-length
          priority = count
        elseif item == "virtual,signal-red" or item == "virtual,signal-green" or item == "virtual,signal-blue" or item == "virtual,signal-yellow" or item == "virtual,signal-pink" or item == "virtual,signal-cyan" or item == "virtual,signal-white" or item == "virtual,signal-grey" or item == "virtual,signal-black" then
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
                  count = count + traincount             
                elseif delivery.from == stop.entity.backer_name then
                  count = count - traincount
                  if count < 0 then count = 0 end
                end
              end
                  
            else
              -- calculate items +- deliveries
              if delivery.shipment[item] then
                if delivery.to == stop.entity.backer_name then                              
                  count = count + delivery.shipment[item]                
                elseif delivery.from == stop.entity.backer_name then
                  count = count - delivery.shipment[item]
                  --make sure we don't turn it into a request
                  if count < 0 then count = 0 end
                end
              end
              
            end
          end -- for delivery
          if count < 0 then
            requested[item] = count * -1
          else
            provided[item] = count
          end
        end  
      end
      
      global.LogisticTrainStops[stopID].isDepot = false
      if colorCount ~= 1 then
        -- signal error
        global.LogisticTrainStops[stopID].errorCode = 1
        setLamp(stopID, ErrorCodes[1])               
      elseif stop.errorCode <= 1 then
        -- signal error fixed
        global.LogisticTrainStops[stopID].errorCode = 0

        global.LogisticTrainStops[stopID].minDelivery = minDelivery
        global.LogisticTrainStops[stopID].maxTraincars = maxTraincars
        global.LogisticTrainStops[stopID].priority = priority
        
        for k,v in pairs (provided) do
          global.Dispatcher.Provided[k] = global.Dispatcher.Provided[k] or {}
          global.Dispatcher.Provided[k][stopID] = v
          if global.Dispatcher.Provided[k].sumCount then
            global.Dispatcher.Provided[k].sumCount = global.Dispatcher.Provided[k].sumCount + v
          else
            global.Dispatcher.Provided[k].sumCount = v
          end
          if global.Dispatcher.Provided[k].sumStops then
            global.Dispatcher.Provided[k].sumStops = global.Dispatcher.Provided[k].sumStops + 1
          else
            global.Dispatcher.Provided[k].sumStops = 1
          end
        end      
        for k,v in pairs (requested) do
          global.Dispatcher.Requested[k] = global.Dispatcher.Requested[k] or {}
          global.Dispatcher.Requested[k][stopID] = v
          if global.Dispatcher.Requested[k].sumCount then
            global.Dispatcher.Requested[k].sumCount = global.Dispatcher.Requested[k].sumCount + v
          else
            global.Dispatcher.Requested[k].sumCount = v
          end
          if global.Dispatcher.Requested[k].sumStops then
            global.Dispatcher.Requested[k].sumStops = global.Dispatcher.Requested[k].sumStops + 1
          else
            global.Dispatcher.Requested[k].sumStops = 1
          end
        end
        
        if stop.activeDeliveries > 0 then
          setLamp(stopID, "yellow")
        else
          setLamp(stopID, "green")               
        end
        
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
  if greenWire then
    for _, v in pairs (greenWire.signals) do
      items[v.signal.type..","..v.signal.name] = v.count
    end
  end
  if redWire then
    for _, v in pairs (redWire.signals) do 
      if items[v.signal.type..","..v.signal.name] ~= nil then
        items[v.signal.type..","..v.signal.name] = items[v.signal.type..","..v.signal.name] + v.count
      else
        items[v.signal.type..","..v.signal.name] = v.count
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
    
	if trainStop.parkedTrain and trainStop.parkedTrain.valid then
    -- get train composition
    carriages = trainStop.parkedTrain.carriages
		carriagesBin = {}
		carriagesDec = {}
		for i=1, #carriages do
			local name = carriages[i].name
			if carriagesDec[name] then
				carriagesDec[name] = carriagesDec[name] + 2^(i-1)
			else
				carriagesDec[name] = 2^(i-1)
			end
		end
		index = 2
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


