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
    local stop_name = stop.entity.backer_name
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

    local frontDistance = Get_Distance(train.front_stock.position, train.station.position)
    local backDistance = Get_Distance(train.back_stock.position, train.station.position)
    if frontDistance > backDistance then
      stop.parked_train_faces_stop = false
    else
      stop.parked_train_faces_stop = true
    end
    local is_provider = false

    -- if message_level >= 3 then printmsg({"ltn-message.train-arrived", tostring(trainName), stop_name}, trainForce, false) end
    if message_level >= 3 then printmsg({"ltn-message.train-arrived", Make_Train_RichText(train, nil), format("[train-stop=%d]", stopID)}, trainForce, false) end
    if debug_log then log(format("(TrainArrives) Train [%d] \"%s\": arrived at LTN-stop [%d] \"%s\"; train_faces_stop: %s", train.id, trainName, stopID, stop_name, stop.parked_train_faces_stop )) end

    if stop.error_code == 0 then
      if stop.is_depot then
        local delivery = global.Dispatcher.Deliveries[train.id]
        if delivery then
          -- delivery should have been removed when leaving requester. Handle like delivery timeout.
          if message_level >= 1 then
            printmsg({
              "ltn-message.delivery-removed-depot",
              Make_Stop_RichText(from_entity) or delivery.from,
              Make_Stop_RichText(to_entity) or delivery.to
            }, delivery.force, false)
          end
          if debug_log then log(format("(TrainArrives) Train [%d] \"%s\": Entered Depot with active Delivery. Failing Delivery and reseting train.", train.id, trainName)) end
          script.raise_event(on_delivery_failed_event, {train_id = train.id, shipment = delivery.shipment})
          RemoveDelivery(train.id)
        end

        -- clean fluid residue
        local train_items = train.get_contents()
        local train_fluids = train.get_fluid_contents()
        if table_size(train_fluids) > 0 and depot_fluid_cleaning > 0 then
          -- cleaning per wagon
          for i, wagon in pairs(train.fluid_wagons) do
            for fluid, count in pairs(wagon.get_fluid_contents()) do
              if count <= depot_fluid_cleaning then
                local removed = wagon.remove_fluid({name=fluid, amount=count})
                if debug_log then log(format("(TrainArrives) Train \"%s\"[%d]: Depot fluid removal %s %f/%f", trainName, i, fluid, removed, count)) end
              end
            end
          end
          -- cleaning whole train doesn't work in 1.1.26
          -- for fluid, count in pairs(train_fluids) do
          --   if count <= depot_fluid_cleaning then
          --     local removed = train.remove_fluid({name=fluid, amount=count})
          --     log(format("Train %s: removed %s %f/%f", trainName, fluid, removed, count))
          --   end
          -- end
          train_fluids = train.get_fluid_contents()
        end

        -- check for leftover cargo
        if table_size(train_items) > 0 then
          create_alert(stop.entity, "cargo-warning", {"ltn-message.depot_left_over_cargo", trainName, stop_name}, trainForce)
        end
        if table_size(train_fluids) > 0 then
          create_alert(stop.entity, "cargo-warning", {"ltn-message.depot_left_over_cargo", trainName, stop_name}, trainForce)
        end

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
        schedule.records[1] = NewScheduleRecord(stop_name, "inactivity", depot_inactivity)
        train.schedule = schedule

        -- reset filters and bars
        if depot_reset_filters and train.cargo_wagons then
          for n,wagon in pairs(train.cargo_wagons) do
            local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
            if inventory then
              if inventory.is_filtered() then
                -- log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory).." filtered slots.")
                for slotIndex=1, #inventory, 1 do
                  inventory.set_filter(slotIndex, nil)
                end
              end
              if inventory.supports_bar and #inventory - inventory.get_bar() > 0 then
                -- log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory - inventory.get_bar()).." locked slots.")
                inventory.set_bar()
              end
            end
          end
        end

        setLamp(stop, "blue", 1)

      else -- stop is no Depot
        -- check requester for incorrect shipment
        local delivery = global.Dispatcher.Deliveries[train.id]
        if delivery then
          is_provider = delivery.from_id == stop.entity.unit_number
          if delivery.to_id == stop.entity.unit_number then
            local requester_unscheduled_cargo = false
            local unscheduled_load = {}
            local train_items = train.get_contents()
            for name, count in pairs(train_items) do
              local typed_name = "item,"..name
              if not delivery.shipment[typed_name] then
                requester_unscheduled_cargo = true
                unscheduled_load[typed_name] = count
              end
            end
            local train_fluids = train.get_fluid_contents()
            for name, count in pairs(train_fluids) do
              local typed_name = "fluid,"..name
              if not delivery.shipment[typed_name] then
                requester_unscheduled_cargo = true
                unscheduled_load[typed_name] = count
              end
            end
            if requester_unscheduled_cargo then
              create_alert(stop.entity, "cargo-alert", {"ltn-message.requester_unscheduled_cargo", trainName, stop_name}, trainForce)
              script.raise_event(on_requester_unscheduled_cargo_alert, {train = train, station = stop.entity, planned_shipment = delivery.shipment, unscheduled_load = unscheduled_load})
            end
          end
        end

        -- set lamp to blue for LTN controlled trains
        for i=1, #stop.active_deliveries, 1 do
          if stop.active_deliveries[i] == train.id then
            setLamp(stop, "blue", #stop.active_deliveries)
            break
          end
        end
      end
    end

    UpdateStopOutput(stop, is_provider and not(provider_show_existing_cargo) )
  end
end

-- update stop output when train leaves stop
-- when called from on_train_created stoppedTrain.train will be invalid
function TrainLeaves(trainID)
  local stoppedTrain = global.StoppedTrains[trainID] -- checked before every call of TrainLeaves
  local train = stoppedTrain.train
  local stopID = stoppedTrain.stopID
  local stop = global.LogisticTrainStops[stopID]
  if not stop then
    -- stop became invalid
    if debug_log then log(format("(TrainLeaves) Error: StopID [%d] wasn't found in global.LogisticTrainStops", stopID )) end
    global.StoppedTrains[trainID] = nil
    return
  end
  local stop_name = stop.entity.backer_name

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
    if debug_log then log(format("(TrainLeaves) Train [%d] \"%s\": left Depot [%d] \"%s\".", trainID, stoppedTrain.name, stopID, stop.entity.backer_name )) end

  -- train was stopped at LTN stop
  else
    -- remove delivery from stop
    for i=#stop.active_deliveries, 1, -1 do
      if stop.active_deliveries[i] == trainID then
        table.remove(stop.active_deliveries, i)
      end
    end

    local delivery = global.Dispatcher.Deliveries[trainID]
    if train.valid and delivery then
      if delivery.from_id == stop.entity.unit_number then
        -- update delivery counts to train inventory
        local actual_load = {}
        local unscheduled_load = {}
        local provider_unscheduled_cargo = false
        local provider_missing_cargo = false
        local train_items = train.get_contents()
        for name, count in pairs(train_items) do
          local typed_name = "item,"..name
          local planned_count = delivery.shipment[typed_name]
          if planned_count then
            actual_load[typed_name] = count -- update shipment to actual inventory
            if count < planned_count then
              -- underloaded
              provider_missing_cargo = true
            end
          else
            -- loaded wrong items
            unscheduled_load[typed_name] = count
            provider_unscheduled_cargo = true
          end
        end
        local train_fluids = train.get_fluid_contents()
        for name, count in pairs(train_fluids) do
          local typed_name = "fluid,"..name
          local planned_count = delivery.shipment[typed_name]
          if planned_count then
            actual_load[typed_name] = count -- update shipment actual inventory
            if planned_count-count > 0.1 then -- prevent lsb errors
              -- underloaded
              provider_missing_cargo = true
            end
          else
            -- loaded wrong fluids
            unscheduled_load[typed_name] = count
            provider_unscheduled_cargo = true
          end
        end
        delivery.pickupDone = true -- remove reservations from this delivery
        if debug_log then log(format("(TrainLeaves) Train [%d] \"%s\": left Provider [%d] \"%s\"; cargo: %s; unscheduled: %s ", trainID, stoppedTrain.name, stopID, stop.entity.backer_name, serpent.line(actual_load), serpent.line(unscheduled_load) )) end
        global.StoppedTrains[trainID] = nil

        if provider_missing_cargo then
          create_alert(stop.entity, "cargo-alert", {"ltn-message.provider_missing_cargo", stoppedTrain.name, stop_name}, stoppedTrain.force)
          script.raise_event(on_provider_missing_cargo_alert, {
            train = train,
            station = stop.entity,
            planned_shipment = delivery.shipment,
            actual_shipment = actual_load
          })
        end
        if provider_unscheduled_cargo then
          create_alert(stop.entity, "cargo-alert", {"ltn-message.provider_unscheduled_cargo", stoppedTrain.name, stop_name}, stoppedTrain.force)
          script.raise_event(on_provider_unscheduled_cargo_alert, {
            train = train,
            station = stop.entity,
            planned_shipment = delivery.shipment,
            unscheduled_load = unscheduled_load
          })
        end
        script.raise_event(on_delivery_pickup_complete_event, {
          train_id = trainID,
          train = train,
          planned_shipment = delivery.shipment,
          actual_shipment = actual_load
        })
        delivery.shipment = actual_load

      elseif delivery.to_id == stop.entity.unit_number then
        -- reset schedule before API events
        if requester_delivery_reset then
          local schedule = {current = 1, records = {}}
          schedule.records[1] = NewScheduleRecord(train.schedule.records[1].station, "inactivity", depot_inactivity)
          train.schedule = schedule
        end

        local remaining_load = {}
        local requester_left_over_cargo = false
        local train_items = train.get_contents()
        for name, count in pairs(train_items) do
          -- not fully unloaded
          local typed_name = "item,"..name
          requester_left_over_cargo = true
          remaining_load[typed_name] = count
        end
        local train_fluids = train.get_fluid_contents()
        for name, count in pairs(train_fluids) do
          -- not fully unloaded
          local typed_name = "fluid,"..name
          requester_left_over_cargo = true
          remaining_load[typed_name] = count
        end

        if debug_log then log(format("(TrainLeaves) Train [%d] \"%s\": left Requester [%d] \"%s\" with left over cargo: %s", trainID, stoppedTrain.name, stopID, stop.entity.backer_name, serpent.line(remaining_load))) end
        -- signal completed delivery and remove it
        if requester_left_over_cargo then
          create_alert(stop.entity, "cargo-alert", {"ltn-message.requester_left_over_cargo", stoppedTrain.name, stop_name}, stoppedTrain.force)
          script.raise_event(on_requester_remaining_cargo_alert, {
            train = train,
            station = stop.entity,
            remaining_load = remaining_load
          })
        end
        script.raise_event(on_delivery_completed_event, {
          train_id = trainID,
          train = train,
          shipment = delivery.shipment})
        RemoveDelivery(trainID)
      else
        if debug_log then log(format("(TrainLeaves) Train [%d] \"%s\": left LTN-stop [%d] \"%s\".", trainID, stoppedTrain.name, stopID, stop.entity.backer_name)) end
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
  -- if message_level >= 3 then printmsg({"ltn-message.train-left", tostring(stoppedTrain.name), stop.entity.backer_name}, stoppedTrain.force) end
  if message_level >= 3 then printmsg({"ltn-message.train-left", Make_Train_RichText(train, stoppedTrain.name), format("[train-stop=%d]", stopID)}, stoppedTrain.force, false) end
  UpdateStopOutput(stop)

  global.StoppedTrains[trainID] = nil
end

-- local reverse_defines = require('__flib__.reverse-defines')

function OnTrainStateChanged(event)
  -- log(game.tick.." (OnTrainStateChanged) Train name: "..tostring(Get_Train_Name(event.train))..", train.id:"..tostring(event.train.id).." stop: "..tostring(event.train.station and event.train.station.backer_name)..", state: "..reverse_defines.train_state[event.old_state].." > "..reverse_defines.train_state[event.train.state] )
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

  return delivery
end

---Finds the next logistic stop in the schedule of the given train. Returns nil if the train is not executing a delivery or has no further logistic stops in its schedule.
---@param train LuaTrain
---@param schedule_index integer? the index in the schedule to search from, `schedule.current` if omitted. Starts from the next position if the train is currently stopping at that station.
---@return integer? schedule_index the index of next logistic stop in the schedule or nil
---@return integer? id the unit_number of the logistic stop
---@return "provider"|"requester"|nil type
function GetNextLogisticStop(train, schedule_index)
  if not (train and train.valid) then
    if debug_log then log("(GetNextLogisticStop) train not valid") end
    return
  end

  if not train.schedule then
    if debug_log then log("(GetNextLogisticStop) train [%d] has no schedule.", train.id) end
    return
  end

  local delivery = global.Dispatcher.Deliveries[train.id]
  if not delivery then
    if debug_log then log("(GetNextLogisticStop) train [%d] not found in deliveries.", train.id) end
    return
  end

  -- Comparing stop names is not enough to find the provider and the requester,
  -- they might share names with each other or another stop in the schedule.
  -- So use a heuristic that also looks at the wait conditions
  local item, _ = next(delivery.shipment)
  local itype, iname = match(item, match_string)
  local records = train.schedule.records

  local record_index = schedule_index or train.schedule.current or 2 -- defaulting to 1 is pointless because that's the depot
  if (train.state == defines.train_state.wait_station) then
    record_index = record_index + 1
  end

  local function get_wait_count_comparator(record)
    if record.wait_conditions then
      for _, wait_condition in pairs(record.wait_conditions) do
        local condition = wait_condition.condition
        if condition and condition.constant and (wait_condition.type == "item_count" or wait_condition.type == "fluid_count") then
          local signal = condition.first_signal
          return signal and signal.type == itype and signal.name == iname and condition.comparator
        end
      end
    end
  end

  local record = records[record_index]
  while record do
    if record.station == delivery.from and get_wait_count_comparator(record) == "≥" then
      return record_index, delivery.from_id, "provider"
    end
    if record.station == delivery.to and get_wait_count_comparator(record) == "=" then
      return record_index, delivery.to_id, "requester"
    end

    record_index = record_index + 1
    record = records[record_index]
  end
end

local temp_wait_condition = {{type = "time", compare_type = "and", ticks = 0}}

---Ensures the next logistic stop in the schedule has a temporary stop if is on the same surface as the train.
---@param train LuaTrain
---@param schedule_index integer? the index in the schedule to search from, `schedule.current` if omitted. Starts from the next index if the train is currently stopping at that station.
---@return integer? stop_position index of created or existing temporary stop for next found logistic stop that was handled, nil if there is no further logistic stop or the next logistic stop is not on the same surface.
function GetOrCreateNextTempStop(train, schedule_index)
  local stop_schedule_index, stop_id = GetNextLogisticStop(train, schedule_index)
  if not stop_schedule_index then return end

  --unlike ProcessDelivery we need to consider that the stop entity might be gone
  local stop = global.LogisticTrainStops[stop_id]
  if not stop or not stop.entity.valid then
    if debug_log then log(format("(UpdateSchedule) skipping stop [%d] for train [%d], stop-entity not valid", stop_id, train.id)) end
    return
  end

  local rail = stop.entity.connected_rail
  local rail_direction = stop.entity.connected_rail_direction
  if not rail or not rail_direction then
    if debug_log then log(format("(UpdateSchedule) skipping stop [%d] for train [%d], not connected to a rail", stop_id, train.id)) end
    return
  end

  -- the engine does not allow temp_stops on different surfaces
  -- locomotive might not work here, a new train on another surface could still be incomplete
  if train.carriages[1].surface ~= stop.entity.surface then
    if debug_log then log(format("(UpdateSchedule) stop [%d] is on a different surface than train [%d]", stop_id, train.id)) end
    return
  end

  -- insert temp stop in schedule
  local schedule = train.schedule
  local previous_record = schedule.records[stop_schedule_index-1]
  if previous_record and previous_record.temporary then return stop_schedule_index-1 end -- schedule already up-to-date for stop_position

  if debug_log then log(format("(UpdateSchedule) adding new temp-stop before stop [%d] at rail [%d] to train [%d] ", stop_id, rail.unit_number, train.id)) end
  table.insert(schedule.records, stop_schedule_index, {
    wait_conditions = temp_wait_condition,
    rail = rail,
    rail_direction = rail_direction,
    temporary = true,
  })
  train.schedule = schedule
  return stop_schedule_index
end

---reassigns an existing delivery from one train to another
---@param old_train_id integer
---@param new_train LuaTrain
---@return boolean reassigned true if the old train was executing a delivery, false otherwise
function ReassignDelivery(old_train_id, new_train)
  -- check if delivery exists for given train id
  if not (old_train_id and global.Dispatcher.Deliveries[old_train_id]) then
    if debug_log then log(format("(ReassignDelivery) train [%d] not found in deliveries.", old_train_id)) end
    return false
  end
  -- check if new train is valid
  if not (new_train and new_train.valid and new_train.object_name == "LuaTrain") then
    if debug_log then log("(ReassignDelivery) Received new_train was invalid.") end
    return false
  end

  local delivery = update_delivery(old_train_id, new_train)
  return delivery and true
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
