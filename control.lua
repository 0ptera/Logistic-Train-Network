--require "lib"
require "config"
require "interface"

MOD_NAME = "LogisticTrainNetwork"
MINDELIVERYSIZE = "min-delivery-size"
MAXTRAINLENGTH = "max-train-length"

ErrorCodes = {
  "red",    -- circuit/signal error
  "pink"    -- read error
}
-- Events

script.on_init(function()
  onLoad()
  initialize()
end)

script.on_load(function()
  onLoad()

end)

function onLoad ()
	if global.LogisticTrainStops ~= nil then
		script.on_event(defines.events.on_tick, ticker) --subscribe ticker when train stops exist    
    for stopID, stop in pairs(global.LogisticTrainStops) do --outputs are not stored in save
      UpdateStopOutput(stop)
    end
	end
end

script.on_configuration_changed(function(data)
  -- initialize  
  initialize()
  
end)

function initialize()
  global.log_level = global.log_level or 2 -- 4: everything, 3: scheduler messages, 2: basic messages, 1 errors only, 0: off
  global.log_output = global.log_output or {console = 'console'} -- console or log or both
  
  global.Dispatcher = global.Dispatcher or {}
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.Storage = global.Dispatcher.Storage or {}
  global.Dispatcher.Orders = global.Dispatcher.Orders or {}
  -- update to 0.4.2
  for i=#global.Dispatcher.Orders, 1, -1 do
    if not global.Dispatcher.Orders[i].toID or not global.Dispatcher.Orders[i].fromID then
      table.remove(global.Dispatcher.Orders, i)
    end
  end  
  
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}
  -- update to 0.4
  for trainID, delivery in pairs(global.Dispatcher.Deliveries) do
    if delivery.shipment == nil then
      if delivery.item and delivery.count then
        global.Dispatcher.Deliveries[trainID].shipment = {[delivery.item] = delivery.count}
      else
        global.Dispatcher.Deliveries[trainID].shipment = {}
      end
    end
  end

  global.LogisticTrainStops = global.LogisticTrainStops or {}
  for stopID, stop in pairs (global.LogisticTrainStops) do
    global.LogisticTrainStops[stopID].activeDeliveries = global.LogisticTrainStops[stopID].activeDeliveries or 0
    global.LogisticTrainStops[stopID].errorCode = global.LogisticTrainStops[stopID].errorCode or 0
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
    UpdateStop(stopID)
  end
  
  -- check if RailTanker is installed
  if game.item_prototypes["rail-tanker"] then
    global.useRailTanker = true
    printmsg("RailTanker found, enabling fluid deliveries")
  else
    global.useRailTanker = false
  end
end


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


script.on_event(defines.events.on_train_changed_state, function(event)
  local trainID = GetTrainID(event.train)
  local trainName = GetTrainName(event.train)
  if not trainID then --train has no locomotive
    return
  end
  
  if event.train.state == defines.train_state.wait_station and event.train.station ~= nil and event.train.station.name == "logistic-train-stop" then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stopID == event.train.station.unit_number then -- add train to station
        stop.parkedTrain = event.train
        --global.LogisticTrainStops[stopID].parkedTrain = event.train
        stop.parkedTrainID = trainID
        --global.LogisticTrainStops[stopID].parkedTrainID = trainID
        if global.log_level >= 3 then printmsg("Train "..trainName.." arrived at ".. stop.entity.backer_name) end
        
        if stop.isDepot then
          -- remove delivery
          removeDelivery(trainID)
          -- make train available for new deliveries
          global.Dispatcher.availableTrains[trainID] = event.train
          -- reset schedule
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "circuit", "=", {{type="virtual", name="signal-green", count=1}})
          event.train.schedule = schedule          
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
              -- ToDO: update to loaded inventory
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
  
end)

function ticker(event)
  local tick = game.tick
  -- exit when there are no logistic train stops 
  local next = next
  if global.LogisticTrainStops == nil or next(global.LogisticTrainStops) == nil then
    script.on_event(defines.events.on_tick, nil)
    return
  end
  
  ---- update LogisticTrainStops ----
  if tick % station_update_interval == 0 then
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
        if global.log_level >= 2 then printmsg("Delivery from "..delivery.from.." to "..delivery.to.." running for "..game.tick-delivery.started.." ticks removed after time out.") end
        removeDelivery(trainID)
      end
    end
  
    -- remove invalid stations from storage
    CleanDispatcherStorage()
    
    ---- all actual Dispatcher logic -----
    
    -- create/update orders
    UpdateOrders()
    AddNewOrders()
    
    -- send orders to available train
    ProcessOrders()  
    
  end -- dispatcher update
end    


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

-- cleans Dispatcher.Storage from invalid stations
function CleanDispatcherStorage()
  local oldStorage = global.Dispatcher.Storage
  local newStorage = {}
  for stopID, storage in pairs (oldStorage) do
    local stop = global.LogisticTrainStops[stopID]
    
    -- copy valid storage data
    if stop and  stop.entity.valid and storage.lastUpdate and storage.lastUpdate > (game.tick - dispatcher_update_interval * 10) then
      newStorage[stopID] = oldStorage[stopID] 
    else
      if stop and stop.entity.backer_name then
        if global.log_level >= 3 then printmsg("Removed old Dispatcher storage data: "..stop.entity.backer_name) end
      else
        if global.log_level >= 3 then printmsg("Removed old Dispatcher storage data: invalid stopID") end
      end
    end
  end
  global.Dispatcher.Storage = newStorage
end

-- update existing orders to current available/requested items and clean out obsolete orders
function UpdateOrders()
  if not global.Dispatcher.Orders then return end

  for i=#global.Dispatcher.Orders, 1, -1 do
    if global.log_level >= 3 then printmsg("updating Order "..i.."/"..#global.Dispatcher.Orders) end
    local order = global.Dispatcher.Orders[i]
    local toID = order.toID
    local fromID = order.fromID
    local updateTimeout = game.tick - dispatcher_update_interval * 10
        
    if order.shipment and order.shipmentCount > 0 and -- shipment exists?
       global.LogisticTrainStops[toID].entity.valid and global.LogisticTrainStops[fromID].entity.valid and -- stations exist?
       global.Dispatcher.Storage[toID].lastUpdate > updateTimeout and global.Dispatcher.Storage[fromID].lastUpdate > updateTimeout then -- stations still updated?
      for type, items in pairs(order.shipment) do
        if items then
          for item, count in pairs (items) do       
            local requested = global.Dispatcher.Storage[toID].requested
            local provided = global.Dispatcher.Storage[fromID].provided
            local minDelivery = global.Dispatcher.Storage[toID].minDelivery
            local count = 0
            
            if requested[type..","..item] and provided[type..","..item] then -- items still requested and provided?
              if requested[type..","..item] > minDelivery then
                if requested[type..","..item] < provided[type..","..item] then
                  count = requested[type..","..item]                  
                elseif use_Best_Effort then
                  count = provided[type..","..item]
                end
              end
            end
            
            if count > 0 then
              -- update order & storage count
              global.Dispatcher.Storage[toID].requested[type..","..item] = requested[type..","..item] - count
              global.Dispatcher.Storage[fromID].provided[type..","..item] = provided[type..","..item] - count
              order.shipment[type][item] = count
              -- update metadata
              order.minDelivery = minDelivery
              if global.Dispatcher.Storage[toID].maxTraincars > global.Dispatcher.Storage[fromID].maxTraincars then
                order.maxTraincars = global.Dispatcher.Storage[fromID].maxTraincars
              else
                order.maxTraincars = global.Dispatcher.Storage[toID].maxTraincars
              end

            else
              -- remove item from shipment
              order.shipment[type][item] = nil
              order.shipmentCount = order.shipmentCount - 1
            end
            global.Dispatcher.Orders[i] = order
          end
        else
          if global.log_level >= 3 then printmsg("removed order: no items in shipment") end
          table.remove(global.Dispatcher.Orders, i)
        end
      end
    else
      if global.log_level >= 3 then printmsg("removed order: shipments "..order.shipmentCount.." < 1 or stations invalid") end
      table.remove(global.Dispatcher.Orders, i)
    end
  end
  
end

-- creates and merges new orders from Dispatcher.Storage.requested
function AddNewOrders()
  for stopID, storage in pairs (global.Dispatcher.Storage) do
    local requestStation = global.LogisticTrainStops[stopID]
    if storage.requested and requestStation.entity.backer_name ~= "Depot" then
      local maxTraincars = storage.maxTraincars or 0
      local minDelivery = storage.minDelivery
      local match = string.match
      for item, count in pairs (storage.requested) do
        
        -- don't deliver anything below delivery size
        if count < minDelivery then
          goto skipRequestItem
        end 
        
        -- split merged key into type & name
        local itype, iname = match(item, "([^,]+),([^,]+)")
        if not (itype and iname) then
          if global.log_level >= 1 then printmsg("Error(AddNewOrders): could not parse item "..item) end
          goto skipRequestItem
        end
        
        -- drop fluids without rail tanker
        if itype == "fluid" and not global.useRailTanker then
          if global.log_level >= 3 then printmsg("Notice: fluid transport requires Rail Tanker") end
          goto skipRequestItem
        end
        
        -- find best supplier
        local pickupStation = GetStationItemMax(item, minDelivery)        
        if not pickupStation then
          if global.log_level >= 3 then printmsg("Notice: no station supplying "..item.." found") end
          goto skipRequestItem
        end
        
        local deliverySize = count
        if pickupStation.count < count then
          deliverySize = pickupStation.count
        end
        
        -- maxTraincars = shortest set max-train-length
        if pickupStation.maxTraincars > 0 and (maxTraincars <= 0 or (maxTraincars > 0 and pickupStation.maxTraincars < maxTraincars)) then
          maxTraincars = pickupStation.maxTraincars
        end
        
        -- merge new order into existing orders        
        local to = requestStation.entity.backer_name
        local toID = requestStation.entity.unit_number
        local from = pickupStation.entity.backer_name
        local fromID = pickupStation.entity.unit_number
        local orders = global.Dispatcher.Orders or {}
        local insertnew = true
        for i=1, #orders do
          -- insert/merge only items with same provider-requester pair into one order
          if orders[i].toID == toID and orders[i].fromID == fromID and itype == "item" and orders[i].shipment[itype] then
            if not orders[i].shipment[itype][iname] then
              orders[i].shipmentCount = orders[i].shipmentCount + 1
            end
            orders[i].shipment[itype][iname] = deliverySize
            -- update metadata in case it was changed
            orders[i].age = game.tick
            orders[i].maxTraincars = maxTraincars
            orders[i].minDelivery = minDelivery 
            if global.log_level >= 3 then  printmsg("inserted into  order "..i.."/"..#orders.." "..from..">>"..to..": "..deliverySize.." "..itype..","..iname) end
            insertnew = false
            break
          end          
        end
        -- create new order for fluids and different provider-requester pairs
        if insertnew then
          orders[#orders+1] = {to = to, toID = toID, from = from, fromID = fromID, age = game.tick, minDelivery = minDelivery, maxTraincars = maxTraincars, shipmentCount = 1, shipment = {[itype] = {[iname] = deliverySize}}}
          if global.log_level >= 3 then  printmsg("added new order "..#orders.." "..from..">>"..to..": "..deliverySize.." "..itype..","..iname) end
        end
        
        global.Dispatcher.Orders = orders
        
        ::skipRequestItem:: -- continue with next item
      end  
    end
  end

end

-- checks trains available in depot and sends oldest order as schedule
function ProcessOrders()
  local ceil = math.ceil
  for orderIndex=1, #global.Dispatcher.Orders do
    if global.log_level >= 3 then printmsg("processing "..orderIndex.."/"..#global.Dispatcher.Orders.." Orders") end
    local order = global.Dispatcher.Orders[orderIndex]
    local totalStacks = 0
    local totalCount = 0
    local loadingList = {}
    
    if order.shipment and order.shipmentCount > 0 then
    for itype, items in pairs (order.shipment) do
      if items then
      for name, count in pairs (items) do      
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
          global.Dispatcher.Orders[orderIndex].shipment = nil --mark order for delete
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
    
    -- find train
    local train = GetFreeTrain(loadingList[1].type, totalStacks, order.maxTraincars)
    if not train then
      if order.maxTraincars > 0 then
        if global.log_level >= 4 then printmsg("No train with length "..order.maxTraincars.." to transport "..totalStacks.." found in Depot") end
      else
        if global.log_level >= 4 then printmsg("No train to transport "..totalStacks.." found in Depot") end
      end
      goto skipOrder
    end

    if global.log_level >= 3 then printmsg("Train with "..train.inventorySize.."/"..totalStacks.." found in Depot") end
    order.shipment = nil
    order.shipmentCount = 0
    if train.inventorySize < totalStacks then
      -- recalculate partial shipment    
      if loadingList[1].type == "fluid" then
        -- fluids are simple
        if loadingList[1].count - train.inventorySize > order.minDelivery then
          order.shipment = {}
          order.shipment["fluid"] = {[loadingList[1].name] = loadingList[1].count - train.inventorySize}
          order.shipmentCount = 1
        end
        loadingList[1].count = train.inventorySize
      else
        -- items on the other hand
        for i=#loadingList, 1, -1 do
          if totalStacks - loadingList[i].stacks < train.inventorySize then
            -- remove stacks until it fits in train
            loadingList[i].stacks = loadingList[i].stacks - (totalStacks - train.inventorySize)
            totalStacks = train.inventorySize
            local newcount = loadingList[i].stacks * game.item_prototypes[loadingList[i].name].stack_size
            totalCount = totalCount - loadingList[i].count + newcount
            if loadingList[i].count - newcount > order.minDelivery then
              order.shipment = {}
              order.shipment["item"] = {[loadingList[i].name] = loadingList[i].count - newcount}
              order.shipmentCount = order.shipmentCount + 1
            end
            loadingList[i].count = newcount
            break
          else
            -- remove item and try again
            totalStacks = totalStacks - loadingList[i].stacks
            totalCount = totalCount - loadingList[i].count
            order.shipment["item"] = {[loadingList[i].name] = loadingList[i].count}
            order.shipmentCount = order.shipmentCount + 1
            table.remove(loadingList[i])
          end
        end
      end
    end
    
    if global.log_level >= 2 then 
      if #loadingList == 1 then
        printmsg("Creating Delivery: ".. loadingList[1].count .."  ".. loadingList[1].name..", from "..order.from.." to "..order.to) 
      else
        printmsg("Creating merged Delivery: "..totalStacks.." stacks total, from "..order.from.." to "..order.to) 
      end
    end
    
    -- create schedule
    local selectedTrain = global.Dispatcher.availableTrains[train.id]
    local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]    
    local schedule = {current = 1, records = {}}
    schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "circuit", "=", {{type="virtual", name="signal-green", count=1}})
    schedule.records[2] = NewScheduleRecord(order.from, "item_count", ">", loadingList)
    schedule.records[3] = NewScheduleRecord(order.to, "item_count", "=", loadingList, 0)
    selectedTrain.schedule = schedule   
        
    -- send go to selectedTrain (needs output connected to station)
    depot.output.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual", name="signal-green"}, count = 1 }}}
    
    -- update order
    global.Dispatcher.Orders[orderIndex] = order
    
    -- store delivery
    local delivery = {}
    for i=1, #loadingList do
      delivery[loadingList[i].type..","..loadingList[i].name] = loadingList[i].count      
    end
    global.Dispatcher.Deliveries[train.id] = {train=selectedTrain, started=game.tick, from=order.from, to=order.to, shipment=delivery}
    global.Dispatcher.availableTrains[train.id] = nil
    
    -- set lamps on stations to yellow 
    -- trains will pick a stop by their own logic so we have to parse by name
    for stopID, stop in pairs (global.LogisticTrainStops) do
      if stop.entity.backer_name == order.from or stop.entity.backer_name == order.to then
        global.LogisticTrainStops[stopID].activeDeliveries = stop.activeDeliveries + 1
      end
    end   

    ::skipOrder:: -- use goto since lua doesn't know continue
  end --for orders
  
  -- cleanup of shipment=nil orders will be done before MergeOrders() next cycle
end

--return name of station with highest count of item or nil
function GetStationItemMax(item, min_count ) 
  local currentStation = nil
  local currentMax = min_count
  if use_Best_Effort then -- Best effort will ship below requested size
    currentMax = 1
  end
  for stopID, storage in pairs (global.Dispatcher.Storage) do    
    for k, v in pairs (storage.provided) do      
      if k == item and v > currentMax then
        local ltStop = global.LogisticTrainStops[stopID]
        if ltStop then
          if global.log_level >= 4 then printmsg("(GetStationItemMax): found ".. v .."/"..currentMax.." ".. k.." at "..ltStop.entity.backer_name) end
          currentMax = v
          currentStation = {entity=ltStop.entity, count=v, maxTraincars=global.Dispatcher.Storage[stopID].maxTraincars}
          -- subtract min_count from storage.provided so we don't request the same items multiple times
          global.Dispatcher.Storage[stopID].provided[k] = v - min_count
        else
          if global.log_level >= 1 then printmsg("Error(GetStationItemMax): "..stopID.." no such unit_number") end
        end
      end
    end --for k, v in pairs (storage.provided) do      
  end
  return currentStation
end

-- return available train with smallest suitable inventory or largest available inventory
-- if maxTraincars is set, number of locos + wagons has to be smaller
function GetFreeTrain(type, size, maxTraincars)
  local train = nil
  local largestInventory = 0
  local smallestInventory = 0
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    local inventorySize = 0
    if DispTrain.valid 
    and (maxTraincars == nil or maxTraincars <= 0 or #DispTrain.carriages <= maxTraincars) then -- train length fits
      -- get total inventory of train for requested item type
      for _,wagon in pairs (DispTrain.cargo_wagons) do
        -- RailTanker
        if type == "fluid" and global.useRailTanker and wagon.name == "rail-tanker" then
          inventorySize = inventorySize + 2500
        -- normal cargo wagons
        elseif type == "item" and wagon.name ~= "rail-tanker" then
          local slots = #wagon.get_inventory(defines.inventory.cargo_wagon)
          if slots then
            inventorySize = inventorySize + slots
          else
            if global.log_level >= 1 then printmsg("Error(GetFreeTrain): Could not read inventory size of ".. wagon.name) end
          end
        end
      end
      
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
        printmsg("Error(NewScheduleRecord): couldn't get RailTanker fake item")
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
    record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "and", ticks = 60 } -- prevent trains leaving depot instantly
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

function UpdateStop(stopID)
  local stop = global.LogisticTrainStops[stopID]
  local match = string.match
  local lower = string.lower
  
  -- remove invalid stops
  if not (stop.entity and stop.entity.valid) or
    not (stop.input and stop.input.valid) or
    not (stop.output and stop.output.valid) or
    not (stop.lampControl and stop.lampControl.valid) then
    
    global.Dispatcher.Storage[stopID] = nil  
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
      maxTraincars = 0
      colorCount = 0  
      for item, count in pairs (circuitValues) do
        if item == "virtual,"..MAXTRAINLENGTH and count > 0 then -- set max-train-length
          maxTraincars = count          
        elseif item == "virtual,signal-red" or item == "virtual,signal-green" or item == "virtual,signal-blue" or item == "virtual,signal-yellow" or item == "virtual,signal-pink" or item == "virtual,signal-cyan" or item == "virtual,signal-white" or item == "virtual,signal-grey" or item == "virtual,signal-black" then
          colorCount = colorCount + 1
        end
      end
      
      global.LogisticTrainStops[stopID].isDepot = true
      if colorCount ~= 1 then
        -- signal error
        global.LogisticTrainStops[stopID].errorCode = 1
        setLamp(stopID, ErrorCodes[1])
      elseif stop.errorCode <= 1 then
        -- signal error fixed
        global.LogisticTrainStops[stopID].errorCode = 0
        
        global.Dispatcher.Storage[stopID] = global.Dispatcher.Storage[stopID] or {}
        global.Dispatcher.Storage[stopID].lastUpdate = game.tick
        global.Dispatcher.Storage[stopID].maxTraincars = maxTraincars
        if stop.parkedTrain then
          setLamp(stopID, "blue")              
        else
          setLamp(stopID, "green")              
        end            
      end
    end        
  else   
    -- update input signals of stop
    local circuitValues = GetCircuitValues(stop.input)
    local requested = {}
    local provided = {}
    if circuitValues then
      minDelivery = min_delivery_size
      maxTraincars = 0
      colorCount = 0     
      for item, count in pairs (circuitValues) do
        if item == "virtual,"..MINDELIVERYSIZE and count > 0 then -- overwrite default min-delivery-size
          minDelivery = count
        elseif item == "virtual,"..MAXTRAINLENGTH and count > 0 then -- set max-train-length
          maxTraincars = count          
        elseif item == "virtual,signal-red" or item == "virtual,signal-green" or item == "virtual,signal-blue" or item == "virtual,signal-yellow" or item == "virtual,signal-pink" or item == "virtual,signal-cyan" or item == "virtual,signal-white" or item == "virtual,signal-grey" or item == "virtual,signal-black" then
          colorCount = colorCount + 1
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

        global.Dispatcher.Storage[stopID] = global.Dispatcher.Storage[stopID] or {}
        global.Dispatcher.Storage[stopID].lastUpdate = game.tick
        global.Dispatcher.Storage[stopID].minDelivery = minDelivery
        global.Dispatcher.Storage[stopID].maxTraincars = maxTraincars
        global.Dispatcher.Storage[stopID].provided = provided
        global.Dispatcher.Storage[stopID].requested = requested
        if stop.activeDeliveries > 0 then
          setLamp(stopID, "yellow")
        else
          setLamp(stopID, "green")               
        end
        
      end
    end 
  end

end

function GetCircuitValues(entity) 
  local greenWire = entity.get_circuit_network(defines.wire_type.green)
  local redWire =  entity.get_circuit_network(defines.wire_type.red)
  local items = {} 
  if greenWire then
    for _, v in pairs (greenWire.signals) do
      -- if v.signal.type == "item" or v.signal.type == "fluid" 
      -- or (v.signal.type == "virtual" and (v.signal.name == MINDELIVERYSIZE or v.signal.name == MAXTRAINLENGTH)) then
        items[v.signal.type..","..v.signal.name] = v.count
      --end
    end
  end
  if redWire then
    for _, v in pairs (redWire.signals) do 
      -- if v.signal.type == "item" or v.signal.type == "fluid" 
      -- or (v.signal.type == "virtual" and (v.signal.name == MINDELIVERYSIZE or v.signal.name == MAXTRAINLENGTH)) then
        if items[v.signal.type..","..v.signal.name] ~= nil then
          items[v.signal.type..","..v.signal.name] = items[v.signal.type..","..v.signal.name] + v.count
        else
          items[v.signal.type..","..v.signal.name] = v.count
        end
      -- end
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
  local signals = {{index = 1, signal = {type="virtual",name="signal-grey"}, count = 1 }} -- short circuit test signal
    
    -- prime error detection
    local readError = false
    if trainStop.errorCode == 2 then
      trainStop.errorCode = 0
    end

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
    i = 2
    for k ,v in pairs (carriages) do      
      table.insert(signals, {index = i, signal = {type="virtual",name="LTN-"..k}, count = v })
      i=i+1
    end

    if not trainStop.isDepot then
      -- Update normal stations
      local conditions = trainStop.parkedTrain.schedule.records[trainStop.parkedTrain.schedule.current].wait_conditions
      if conditions ~= nil then 
        for _, c in pairs(conditions) do
          if c.condition and c.condition.comparator and c.condition.first_signal and c.condition.constant then
            if c.condition.comparator == ">" then --train expects to be loaded with x of this item
              table.insert(signals, {index = i, signal = c.condition.first_signal, count = c.condition.constant + 1 })
               i=i+1
            elseif (c.condition.comparator == "<" and c.condition.constant == 1) or
                   (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
              table.insert(signals, {index = i, signal = c.condition.first_signal, count = trainStop.parkedTrain.get_item_count(c.condition.first_signal.name) * -1 })
               i=i+1
            else
               readError = true
            end
          end
        end
      end
      if readError and trainStop.errorCode == 0 then --signal invalid
        trainStop.errorCode = 2
        setLamp(trainStop.entity.unit_number, ErrorCodes[2])
      end
    end
    
  end
  -- will reset if called with no parked train
  trainStop.output.get_control_behavior().parameters = {parameters=signals}	
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


