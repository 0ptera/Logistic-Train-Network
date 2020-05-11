--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]


-- update stop output when train enters stop
function TrainArrives(train)
  local stopID = train.station.unit_number
  local stop = global.LogisticTrainStops[stopID]
  if stop then
    -- assign main loco name and force
    local loco = Get_Main_Locomotive(train)
    local trainForce = nil
    local trainName = nil
    if loco then
      trainName = loco.backer_name
      trainForce = loco.force
    end

    -- add train to global.StoppedTrains
    global.StoppedTrains[train.id] = {
      train = train,
      name = trainName,
      force = trainForce,
      stopID = stopID,
    }

    -- add train to global.LogisticTrainStops
    stop.parked_train = train
    stop.parked_train_id = train.id

    if message_level >= 3 then printmsg({"ltn-message.train-arrived", tostring(trainName), stop.entity.backer_name}, trainForce, false) end
    if debug_log then log("Train ["..train.id.."] "..tostring(trainName).." arrived at LTN-stop ["..stopID.."] "..stop.entity.backer_name) end

    local frontDistance = Get_Distance(train.front_stock.position, train.station.position)
    local backDistance = Get_Distance(train.back_stock.position, train.station.position)
    if debug_log then log("Front Stock Distance: "..frontDistance..", Back Stock Distance: "..backDistance) end
    if frontDistance > backDistance then
      stop.parked_train_faces_stop = false
    else
      stop.parked_train_faces_stop = true
    end

    if stop.error_code == 0 then
      if stop.is_depot then
        -- remove delivery
        RemoveDelivery(train.id)

        -- make train available for new deliveries
        local capacity, fluid_capacity = GetTrainCapacity(train)
        global.Dispatcher.availableTrains[train.id] = {
          train = train,
          surface = loco.surface,
          force = trainForce,
          depot_priority = stop.depot_priority,
          network_id = stop.network_id,
          capacity = capacity,
          fluid_capacity = fluid_capacity
        }
        global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity + capacity
        global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity + fluid_capacity
        -- log("added available train "..train.id..", inventory: "..tostring(global.Dispatcher.availableTrains[train.id].capacity)..", fluid capacity: "..tostring(global.Dispatcher.availableTrains[train.id].fluid_capacity))
        -- reset schedule
        local schedule = {current = 1, records = {}}
        schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "inactivity", depot_inactivity)
        train.schedule = schedule
        setLamp(stop, "blue", 1)

        -- reset filters and bars
        if reset_filters and train.cargo_wagons then
        for n,wagon in pairs(train.cargo_wagons) do
          local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
          if inventory then
            if inventory.is_filtered() then
              log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory).." filtered slots.")
              for slotIndex=1, #inventory, 1 do
                inventory.set_filter(slotIndex, nil)
              end
            end
            if inventory.supports_bar and #inventory - inventory.get_bar() > 0 then
              log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory - inventory.get_bar()).." locked slots.")
              inventory.set_bar()
            end
          end
        end
        end

      else -- stop is no Depot
        -- set lamp to blue for LTN controlled trains
        for i=1, #stop.active_deliveries, 1 do
          if stop.active_deliveries[i] == train.id then
            setLamp(stop, "blue", #stop.active_deliveries)
            break
          end
        end
      end
    end

    UpdateStopOutput(stop)
  end
end

-- update stop output when train leaves stop
-- when called from on_train_created stoppedTrain.train will be invalid
function TrainLeaves(trainID)
  local stoppedTrain = global.StoppedTrains[trainID] -- checked before every call of TrainLeaves
  local stopID = stoppedTrain.stopID
  local stop = global.LogisticTrainStops[stopID]
  if not stop then
    -- stop became invalid
    if debug_log then log("(TrainLeaves) StopID: "..tostring(stopID).." wasn't found in global.LogisticTrainStops") end
    global.StoppedTrains[trainID] = nil
    return
  end

  -- train was stopped at LTN depot
  if stop.is_depot then
    if global.Dispatcher.availableTrains[trainID] then -- trains are normally removed when deliveries are created
      global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[trainID].capacity
      global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[trainID].fluid_capacity
      global.Dispatcher.availableTrains[trainID] = nil
    end
    if stop.error_code == 0 then
      setLamp(stop, "green", 1)
    end

  -- train was stopped at LTN stop
  else
    -- remove delivery from stop
    for i=#stop.active_deliveries, 1, -1 do
      if stop.active_deliveries[i] == trainID then
        table.remove(stop.active_deliveries, i)
      end
    end

    local delivery = global.Dispatcher.Deliveries[trainID]
    if stoppedTrain.train.valid and delivery then
      if delivery.from_id == stop.entity.unit_number then
        -- update delivery counts to train inventory
        local actual_shipment = {}
        local train_items = stoppedTrain.train.get_contents()
        local train_fluids = stoppedTrain.train.get_fluid_contents()
        for name, count in pairs(train_items) do
          actual_shipment["item,"..name] = count
        end
        for name, count in pairs(train_fluids) do
          actual_shipment["fluid,"..name] = count
        end
        delivery.pickupDone = true -- remove reservations from this delivery
        script.raise_event(on_delivery_pickup_complete_event, {train_id = trainID, planned_shipment = delivery.shipment, actual_shipment = actual_shipment})
        delivery.shipment = actual_shipment

      elseif delivery.to_id == stop.entity.unit_number then
        -- signal completed delivery and remove it
        script.raise_event(on_delivery_completed_event, {train_id = trainID, shipment = delivery.shipment})
        global.Dispatcher.Deliveries[trainID] = nil

        -- reset schedule when ltn-dispatcher-early-schedule-reset is active
        if requester_delivery_reset then
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(stoppedTrain.train.schedule.records[1].station, "inactivity", depot_inactivity)
          stoppedTrain.train.schedule = schedule
        end
      end
    end
    if stop.error_code == 0 then
      if #stop.active_deliveries > 0 then
        setLamp(stop, "yellow", #stop.active_deliveries)
      else
        setLamp(stop, "green", 1)
      end
    end
  end

  -- remove train reference
  stop.parked_train = nil
  stop.parked_train_id = nil
  if message_level >= 3 then printmsg({"ltn-message.train-left", tostring(stoppedTrain.name), stop.entity.backer_name}, stoppedTrain.force) end
  if debug_log then log("Train ["..trainID.."] "..tostring(stoppedTrain.trainName).." left LTN-stop ["..stopID.."] "..stop.entity.backer_name) end
  UpdateStopOutput(stop)

  global.StoppedTrains[trainID] = nil
end


function OnTrainStateChanged(event)
  -- log("(OnTrainStateChanged) Train name: "..tostring(Get_Train_Name(event.train))..", train.id:"..tostring(event.train.id).." stop: "..tostring(event.train.station and event.train.station.backer_name)..", state: "..tostring(event.old_state).." > "..tostring(event.train.state))
  local train = event.train
  if train.state == defines.train_state.wait_station and train.station ~= nil and ltn_stop_entity_names[train.station.name] then
    TrainArrives(train)
  elseif event.old_state == defines.train_state.wait_station and global.StoppedTrains[train.id] then -- update to 0.16
    TrainLeaves(train.id)
  end
end

-- updates or removes delivery references
local function update_delivery(old_train_id, new_train)
  local delivery = global.Dispatcher.Deliveries[old_train_id]

  -- expanded RemoveDelivery(old_train_id) to also update
  for stopID, stop in pairs(global.LogisticTrainStops) do
    if not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lamp_control.valid then
      RemoveStop(stopID)
    else
      for i=#stop.active_deliveries, 1, -1 do --trainID should be unique => checking matching stop name not required
        if stop.active_deliveries[i] == old_train_id then
          if delivery then
            stop.active_deliveries[i] = new_train.id -- update train id if delivery exists
          else
            table.remove(stop.active_deliveries, i) -- otherwise remove entry
            if #stop.active_deliveries > 0 then
              setLamp(stop, "yellow", #stop.active_deliveries)
            else
              setLamp(stop, "green", 1)
            end
          end
        end
      end
    end
  end

  -- copy global.Dispatcher.Deliveries[old_train_id] to new_train.id and change attached train in delivery
  if delivery then
    delivery.train = new_train
    global.Dispatcher.Deliveries[new_train.id] = delivery
  end

  if global.StoppedTrains[old_train_id] then
    TrainLeaves(old_train_id) -- removal only, new train is added when on_train_state_changed fires with wait_station afterwards
  end
  global.Dispatcher.Deliveries[old_train_id] = nil
end

function OnTrainCreated(event)
  -- log("(on_train_created) Train name: "..tostring(Get_Train_Name(event.train))..", train.id:"..tostring(event.train.id)..", .old_train_id_1:"..tostring(event.old_train_id_1)..", .old_train_id_2:"..tostring(event.old_train_id_2)..", state: "..tostring(event.train.state))
  -- on_train_created always sets train.state to 9 manual, scripts have to set the train back to its former state.

  if event.old_train_id_1 then
    update_delivery(event.old_train_id_1, event.train)
  end

  if event.old_train_id_2 then
    update_delivery(event.old_train_id_2, event.train)
  end
end
