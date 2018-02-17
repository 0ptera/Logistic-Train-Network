require "interface"

local MOD_NAME = "LogisticTrainNetwork"

local ISDEPOT = "ltn-depot"
local NETWORKID = "ltn-network-id"
local MINTRAINLENGTH = "ltn-min-train-length"
local MAXTRAINLENGTH = "ltn-max-train-length"
local MAXTRAINS = "ltn-max-trains"
local MINREQUESTED = "ltn-requester-threshold"
local REQPRIORITY = "ltn-requester-priority"
local NOWARN = "ltn-disable-warnings"
local MINPROVIDED = "ltn-provider-threshold"
local PROVPRIORITY = "ltn-provider-priority"
local LOCKEDSLOTS = "ltn-locked-slots"

local ControlSignals = {
  [ISDEPOT] = true,
  [NETWORKID] = true,
  [MINTRAINLENGTH] = true,
  [MAXTRAINLENGTH] = true,
  [MAXTRAINS] = true,
  [MINREQUESTED] = true,
  [REQPRIORITY] = true,
  [NOWARN] = true,
  [MINPROVIDED] = true,
  [PROVPRIORITY] = true,
  [LOCKEDSLOTS] = true,
}

local dispatcher_update_interval = 60

local ErrorCodes = {
  [-1] = "white", -- not initialized
  [1] = "red",    -- circuit/signal error
  [2] = "pink",   -- duplicate stop name
}
local StopIDList = {} -- stopIDs list for on_tick updates
local stopsPerTick = 1 -- step width of StopIDList

local match = string.match
local ceil = math.ceil
local sort = table.sort

---- INITIALIZATION ----
do
local function initialize(oldVersion, newVersion)
  --log("oldVersion: "..tostring(oldVersion)..", newVersion: "..tostring(newVersion))
  ---- disable instant blueprint in creative mode
  if game.active_mods["creative-mode"] then
    remote.call("creative-mode", "exclude_from_instant_blueprint", "logistic-train-stop-input")
    remote.call("creative-mode", "exclude_from_instant_blueprint", "logistic-train-stop-output")
    remote.call("creative-mode", "exclude_from_instant_blueprint", "logistic-train-stop-lamp-control")
  end

  ---- initialize logger
  global.messageBuffer = {}

  ---- initialize global lookup tables
  global.stopIdStartIndex = global.stopIdStartIndex or 1 --start index for on_tick stop updates
  global.StopDistances = global.StopDistances or {} -- station distance lookup table
  global.WagonCapacity = { --preoccupy table with wagons to ignore at 0 capacity
    ["rail-tanker"] = 0
  }
  -- set in UpdateAllTrains
  global.StoppedTrains = global.StoppedTrains or {} -- trains stopped at LTN stops

  ---- initialize Dispatcher
  global.Dispatcher = global.Dispatcher or {}
  -- set in UpdateAllTrains
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity or 0
  global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity or 0
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}
  global.Dispatcher.Requests = global.Dispatcher.Requests or {}
  global.Dispatcher.Requests_by_Stop = global.Dispatcher.Requests_by_Stop or {}
  global.Dispatcher.RequestAge = global.Dispatcher.RequestAge or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}

  -- clean obsolete global
  global.Dispatcher.Requested = nil
  global.Dispatcher.Orders = nil
  global.Dispatcher.OrderAge = nil
  global.Dispatcher.Storage = nil
  global.useRailTanker = nil

   -- update to 1.4.0
  if oldVersion and oldVersion < "01.04.00" then
    global.Dispatcher.Requests = {} -- wipe existing requests
    global.Dispatcher.RequestAge = {}
  end

  -- update to 1.5.0
  if oldVersion and oldVersion < "01.05.00" then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].providePriority = global.LogisticTrainStops[stopID].priority or 0
      global.LogisticTrainStops[stopID].priority = nil
    end

    global.Dispatcher.Requests = {} -- wipe existing requests
  end

  -- update to 1.6.1 migrate locomotiveID to trainID
  if oldVersion and oldVersion < "01.06.01" then
    local locoID_to_trainID = {} -- id dictionary
    local new_availableTrains = {}
    local new_Deliveries = {}
    for _,surface in pairs(game.surfaces) do
      local trains = surface.get_trains()
      for _, train in pairs(trains) do
        -- build dictionary
        local loco = GetMainLocomotive(train)
        if loco then
          locoID_to_trainID[loco.unit_number] = train.id
        end

      end
    end
    -- log("locoID_to_trainID: "..serpent.block(locoID_to_trainID))

    for locoID, delivery in pairs(global.Dispatcher.Deliveries) do
      local trainID = locoID_to_trainID[locoID]
      if trainID then
        log("Migrating global.Dispatcher.Deliveries from ["..tostring(locoID).."] to ["..tostring(trainID).."]")
        new_Deliveries[trainID] = delivery
      end
    end
    -- log("new_Deliveries: "..serpent.dump(new_Deliveries))
    global.Dispatcher.Deliveries = new_Deliveries
  end

  ---- initialize stops
  global.LogisticTrainStops = global.LogisticTrainStops or {}

  if next(global.LogisticTrainStops) then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].errorCode = global.LogisticTrainStops[stopID].errorCode or -1

      -- update to 1.3.0
      global.LogisticTrainStops[stopID].minDelivery = nil
      global.LogisticTrainStops[stopID].ignoreMinDeliverySize = nil
      global.LogisticTrainStops[stopID].minRequested = global.LogisticTrainStops[stopID].minRequested or 0
      global.LogisticTrainStops[stopID].minProvided = global.LogisticTrainStops[stopID].minProvided or 0

      -- update to 1.5.0
      global.LogisticTrainStops[stopID].reqestPriority = global.LogisticTrainStops[stopID].reqestPriority or 0
      global.LogisticTrainStops[stopID].providePriority = global.LogisticTrainStops[stopID].providePriority or 0

      -- update to 1.7.0
      global.LogisticTrainStops[stopID].network_id = global.LogisticTrainStops[stopID].network_id or -1 --all bits set = any network
    end
  end

end

-- run every time the mod configuration is changed to catch stops from other mods
local function buildStopNameList()
  global.TrainStopNames = global.TrainStopNames or {} -- dictionary of all train stops by all mods

  for _, surface in pairs(game.surfaces) do
    local foundStops = surface.find_entities_filtered{type="train-stop"}
    if foundStops then
      for k, stop in pairs(foundStops) do
        AddStopName(stop.unit_number, stop.backer_name)
      end
    end
  end
end

-- run every time the mod configuration is changed to catch changes to wagon capacities by other mods
local function updateAllTrains()
  global.Dispatcher.availableTrains_total_capacity = 0
  global.Dispatcher.availableTrains_total_fluid_capacity = 0
  global.Dispatcher.availableTrains = {}
  global.StoppedTrains = {}
  -- remove all parked train from logistic stops
  for stopID, stop in pairs (global.LogisticTrainStops) do
    stop.parkedTrain =  nil
    stop.parkedTrainID = nil
    UpdateStopOutput(stop)
  end

  -- add still valid trains back to stops
  for force_name, force in pairs(game.forces) do
    local trains = force.get_trains()
    if trains then
      for _, train in pairs(trains) do
        if train.station and train.station.name == "logistic-train-stop" then
          TrainArrives(train)
        end
      end
    end
  end
end

-- register events
local function registerEvents()
  -- always track built/removed train stops for duplicate name list
  script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, OnEntityCreated)
  script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, OnEntityRemoved)
  if global.LogisticTrainStops and next(global.LogisticTrainStops) then
    script.on_event(defines.events.on_tick, OnTick)
    script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
    script.on_event(defines.events.on_train_created, OnTrainCreated)
  end
end

script.on_load(function()
  if global.LogisticTrainStops and next(global.LogisticTrainStops) then
    for stopID, stop in pairs(global.LogisticTrainStops) do --outputs are not stored in save
      -- UpdateStopOutput(stop)
      StopIDList[#StopIDList+1] = stopID
    end
    stopsPerTick = ceil(#StopIDList/(dispatcher_update_interval-1))
  end
  registerEvents()
  log("[LTN] on_load: complete")
end)

script.on_init(function()
  -- format version string to "00.00.00"
  local oldVersion, newVersion = nil
  local newVersionString = game.active_mods[MOD_NAME]
  if newVersionString then
    newVersion = string.format("%02d.%02d.%02d", string.match(newVersionString, "(%d+).(%d+).(%d+)"))
  end

  buildStopNameList()
  initialize(oldVersion, newVersion)
  updateAllTrains()
  registerEvents()
  log("[LTN] ".. MOD_NAME.." "..tostring(newVersionString).." initialized.")
end)

script.on_configuration_changed(function(data)
  buildStopNameList()
  if data and data.mod_changes[MOD_NAME] then
    -- format version string to "00.00.00"
    local oldVersion, newVersion = nil
    local oldVersionString = data.mod_changes[MOD_NAME].old_version
    if oldVersionString then
      oldVersion = string.format("%02d.%02d.%02d", string.match(oldVersionString, "(%d+).(%d+).(%d+)"))
    end
    local newVersionString = data.mod_changes[MOD_NAME].new_version
    if newVersionString then
      newVersion = string.format("%02d.%02d.%02d", string.match(newVersionString, "(%d+).(%d+).(%d+)"))
    end

    if oldVersion and oldVersion < "01.01.01" then
      log("[LTN] Migration failed. Migrating from "..tostring(oldVersionString).." to "..tostring(newVersionString).."not supported.")
      printmsg("[LTN] Error: Direct migration from "..tostring(oldVersionString).." to "..tostring(newVersionString).." is not supported. Oldest supported version: 1.1.1.")
      return
    else
      initialize(oldVersion, newVersion)
      log("[LTN] Migrating from "..tostring(oldVersionString).." to "..tostring(newVersionString).." complete.")
      printmsg("[LTN] Migration from "..tostring(oldVersionString).." to "..tostring(newVersionString).." complete.")
    end
  end
  updateAllTrains()
  registerEvents()
  log("[LTN] ".. MOD_NAME.." "..tostring(game.active_mods[MOD_NAME]).." configuration updated.")
end)

end

---- EVENTS ----

do --train state changed

-- update stop output when train enters stop
function TrainArrives(train)
  local stopID = train.station.unit_number
  local stop = global.LogisticTrainStops[stopID]
  if stop then
    -- assign main loco name and force
    local loco = GetMainLocomotive(train)
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
    stop.parkedTrain = train
    stop.parkedTrainID = train.id

    if message_level >= 3 then printmsg({"ltn-message.train-arrived", tostring(trainName), stop.entity.backer_name}, trainForce, false) end
    if debug_log then log("Train ["..train.id.."] "..tostring(trainName).." arrived at LTN-stop ["..stopID.."] "..stop.entity.backer_name) end

    local frontDistance = GetDistance(train.front_stock.position, train.station.position)
    local backDistance = GetDistance(train.back_stock.position, train.station.position)
    if debug_log then log("Front Stock Distance: "..frontDistance..", Back Stock Distance: "..backDistance) end
    if frontDistance > backDistance then
      stop.parkedTrainFacesStop = false
    else
      stop.parkedTrainFacesStop = true
    end

    if stop.isDepot then
      -- remove delivery
      RemoveDelivery(train.id)

      -- make train available for new deliveries
      local capacity, fluid_capacity = GetTrainCapacity(train)
      global.Dispatcher.availableTrains[train.id] = {train = train, force = loco.force.name, network_id = stop.network_id, capacity = capacity, fluid_capacity = fluid_capacity}
      global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity + capacity
      global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity + fluid_capacity
      -- log("added available train "..train.id..", inventory: "..tostring(global.Dispatcher.availableTrains[train.id].capacity)..", fluid capacity: "..tostring(global.Dispatcher.availableTrains[train.id].fluid_capacity))
      -- reset schedule
      local schedule = {current = 1, records = {}}
      schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "inactivity", depot_inactivity)
      train.schedule = schedule
      if stop.errorCode == 0 then
        setLamp(stopID, "blue", 1)
      end

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
          if inventory.hasbar and #inventory - inventory.getbar() > 0 then
            log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory - inventory.getbar()).." locked slots.")
            inventory.setbar()
          end
        end
      end
      end
    end

    UpdateStopOutput(stop)
  end
end

-- update stop output when train leaves stop
-- when called from on_train_changed stoppedTrain.train will be invalid
function TrainLeaves(trainID)
  local stoppedTrain = global.StoppedTrains[trainID]
  if not stoppedTrain then
    -- train wasn't stopped at ltn stop
    if debug_log then log("(TrainLeaves) train.id:"..tostring(trainID).." wasn't found in global.StoppedTrains") end
    -- log(serpent.block(global.StoppedTrains) )
    return
  end

  local stopID = stoppedTrain.stopID
  local stop = global.LogisticTrainStops[stopID]
  if not stop then
    -- stop became invalid
    if debug_log then log("(TrainLeaves) StopID: "..tostring(stopID).." wasn't found in global.LogisticTrainStops") end
    -- log(serpent.block(stoppedTrain) )
    -- log(serpent.block(global.LogisticTrainStops) )
    global.StoppedTrains[trainID] = nil
    return
  end

  -- train was stopped at LTN depot
  if stop.isDepot then
    if global.Dispatcher.availableTrains[trainID] then -- trains are normally removed when deliveries are created
      global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[trainID].capacity
      global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[trainID].fluid_capacity
      global.Dispatcher.availableTrains[trainID] = nil
    end
    if stop.errorCode == 0 then
      setLamp(stopID, "green", 1)
    end

  -- train was stopped at LTN stop
  else
    -- remove delivery from stop
    for i=#stop.activeDeliveries, 1, -1 do
      if stop.activeDeliveries[i] == trainID then
        table.remove(stop.activeDeliveries, i)
      end
    end

    local delivery = global.Dispatcher.Deliveries[trainID]
    if stoppedTrain.train.valid and delivery then
      if delivery.from == stop.entity.backer_name then
        -- update delivery counts to train inventory
        for item, count in pairs (delivery.shipment) do
          local itype, iname = match(item, "([^,]+),([^,]+)")
          if itype and iname and (game.item_prototypes[iname] or game.fluid_prototypes[iname]) then
            if itype == "fluid" then
              local traincount = stoppedTrain.train.get_fluid_count(iname)
              if debug_log then log("(TrainLeaves): updating delivery after train left "..delivery.from..", "..item.." "..tostring(traincount) ) end
              delivery.shipment[item] = traincount
            else
              local traincount = stoppedTrain.train.get_item_count(iname)
              if debug_log then log("(TrainLeaves): updating delivery after train left "..delivery.from..", "..item.." "..tostring(traincount) ) end
              delivery.shipment[item] = traincount
            end
          else -- remove invalid item from shipment
            delivery.shipment[item] = nil
          end
        end
        delivery.pickupDone = true -- remove reservations from this delivery
      elseif global.Dispatcher.Deliveries[trainID].to == stop.entity.backer_name then
        -- remove completed delivery
        global.Dispatcher.Deliveries[trainID] = nil
        -- reset schedule when ltn-dispatcher-early-schedule-reset is active
        if requester_delivery_reset then
          -- RemoveDelivery(trainID) -- make sure stop counters are reset
          local schedule = {current = 1, records = {}}
          -- log("Depot Name = "..train.schedule.records[1].station)
          schedule.records[1] = NewScheduleRecord(stoppedTrain.train.schedule.records[1].station, "inactivity", depot_inactivity)
          stoppedTrain.train.schedule = schedule
        end
      end
    end
    if stop.errorCode == 0 then
      if #stop.activeDeliveries > 0 then
        setLamp(stopID, "yellow", #stop.activeDeliveries)
      else
        setLamp(stopID, "green", 1)
      end
    end
  end

  -- remove train reference
  stop.parkedTrain = nil
  stop.parkedTrainID = nil
  if message_level >= 3 then printmsg({"ltn-message.train-left", tostring(stoppedTrain.name), stop.entity.backer_name}, stoppedTrain.force) end
  if debug_log then log("Train ["..trainID.."] "..tostring(stoppedTrain.trainName).." left LTN-stop ["..stopID.."] "..stop.entity.backer_name) end
  UpdateStopOutput(stop)

  global.StoppedTrains[trainID] = nil
end


function OnTrainStateChanged(event)
  local train = event.train
  if train.state == defines.train_state.wait_station and train.station ~= nil and train.station.name == "logistic-train-stop" then
    TrainArrives(train)
  elseif event.old_state == defines.train_state.wait_station then -- update to 0.16
    TrainLeaves(train.id)
  end
end

function OnTrainCreated(event)
  -- log("(on_train_created) Train name: "..tostring(GetTrainName(event.train))..", train.id:"..tostring(event.train.id)..", .old_train_id_1:"..tostring(event.old_train_id_1)..", .old_train_id_2:"..tostring(event.old_train_id_2)..", state: "..tostring(event.train.state))
  local train = event.train

  -- old train ids "leave" stops and deliveries are removed
  if event.old_train_id_1 then
    TrainLeaves(event.old_train_id_1)
    RemoveDelivery(event.old_train_id_1)
  end
  if event.old_train_id_2 then
    TrainLeaves(event.old_train_id_2)
    RemoveDelivery(event.old_train_id_2)
  end
  -- trains are always created in manual_control, they will be added in on_train_state_changed
end

end


-- add stop to TrainStopNames
function AddStopName(stopID, stopName)
  if stopName then -- is it possible to have stops without backer_name?
    if global.TrainStopNames[stopName] then
      -- prevent adding the same stop multiple times
      local idExists = false
      for i=1, #global.TrainStopNames[stopName] do
        if stopID == global.TrainStopNames[stopName][i] then
          idExists = true
          -- log(stopID.." already exists for "..stopName)
        end
      end
      if not idExists then
        -- multiple stops of same name > add id to the list
        table.insert(global.TrainStopNames[stopName], stopID)
        -- log("added "..stopID.." to "..stopName)
      end
    else
      -- create new name-id entry
      global.TrainStopNames[stopName] = {stopID}
      -- log("creating entry "..stopName..": "..stopID)
    end
  end
end

-- remove stop from TrainStopNames
function RemoveStopName(stopID, stopName)
  if global.TrainStopNames[stopName] then
    -- multiple stops of same name > remove id from the list
    for i=#global.TrainStopNames[stopName], 1, -1 do
      if global.TrainStopNames[stopName][i] == stopID then
        table.remove(global.TrainStopNames[stopName], i)
        -- log("removed "..stopID.." from "..stopName)
      end
    end
  end
  if not next(global.TrainStopNames[stopName]) then
    -- remove name-id entry
    global.TrainStopNames[stopName] = nil
    -- log("removed entry "..stopName..": "..stopID)
  end
end


do --create stop
local function createStop(entity)
  if global.LogisticTrainStops[entity.unit_number] then
    if message_level >= 1 then printmsg({"ltn-message.error-duplicated-unit_number", entity.unit_number}, entity.force) end
    if debug_log then log("(createStop) duplicate stop unit number "..entity.unit_number) end
    return
  end

  local posIn, posOut, rot
  --log("Stop created at "..entity.position.x.."/"..entity.position.y..", orientation "..entity.direction)
  if entity.direction == 0 then --SN
    posIn = {entity.position.x, entity.position.y-1}
    posOut = {entity.position.x-1, entity.position.y-1}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x-3, entity.position.y-3},{entity.position.x-1, entity.position.y+3}} }
    rot = 0
  elseif entity.direction == 2 then --WE
    posIn = {entity.position.x, entity.position.y}
    posOut = {entity.position.x, entity.position.y-1}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x-3, entity.position.y-3},{entity.position.x+3, entity.position.y-1}} }
    rot = 2
  elseif entity.direction == 4 then --NS
    posIn = {entity.position.x-1, entity.position.y}
    posOut = {entity.position.x, entity.position.y}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x+1, entity.position.y-3},{entity.position.x+3, entity.position.y+3}} }
    rot = 4
  elseif entity.direction == 6 then --EW
    posIn = {entity.position.x-1, entity.position.y-1}
    posOut = {entity.position.x-1, entity.position.y}
    --tracks = entity.surface.find_entities_filtered{type="straight-rail", area={{entity.position.x-3, entity.position.y+1},{entity.position.x+3, entity.position.y+3}} }
    rot = 6
  else --invalid orientation
    if message_level >= 1 then printmsg({"ltn-message.error-stop-orientation", entity.direction}, entity.force) end
    if debug_log then log("(createStop) invalid train stop orientation "..entity.direction) end
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
  local ghosts = entity.surface.find_entities({{entity.position.x-1.1, entity.position.y-1.1},{entity.position.x+1.1, entity.position.y+1.1}} )
  for _,ghost in pairs (ghosts) do
    if ghost.valid then
      if ghost.name == "entity-ghost" and ghost.ghost_name == "logistic-train-stop-input" then
        --printmsg("reviving ghost input at "..ghost.position.x..", "..ghost.position.y)
        _, input = ghost.revive()
      elseif ghost.name == "entity-ghost" and ghost.ghost_name == "logistic-train-stop-output" then
        --printmsg("reviving ghost output at "..ghost.position.x..", "..ghost.position.y)
        _, output = ghost.revive()
      -- something has built I/O already (e.g.) Creative Mode Instant Blueprint
      elseif ghost.name == "logistic-train-stop-input" then
        input = ghost
        --printmsg("Found existing input at "..ghost.position.x..", "..ghost.position.y)
      elseif ghost.name == "logistic-train-stop-output" then
        output = ghost
        --printmsg("Found existing output at "..ghost.position.x..", "..ghost.position.y)
      end
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
  input.get_or_create_control_behavior().circuit_condition = {condition = {comparator=">",first_signal={type="virtual",name="signal-anything"}}}

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
    network_id = -1,         --any network
    trainLimit = 0,
    activeDeliveries = {},   --delivery IDs to/from stop
    errorCode = -1,          --key to errorCodes table
    parkedTrain = nil,
    parkedTrainID = nil
  }
  StopIDList[#StopIDList+1] = entity.unit_number
  UpdateStopOutput(global.LogisticTrainStops[entity.unit_number])
end

function OnEntityCreated(event)
  local entity = event.created_entity
  if entity.type == "train-stop" then
     AddStopName(entity.unit_number, entity.backer_name) -- all stop names are monitored
    if entity.name == "logistic-train-stop" then
      createStop(entity)
      if #StopIDList == 1 then
        --initialize OnTick indexes
        stopsPerTick = 1
        global.stopIdStartIndex = 1
        -- register events
        script.on_event(defines.events.on_tick, OnTick)
        script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
        script.on_event(defines.events.on_train_created, OnTrainCreated)
        if debug_log then log("(OnEntityCreated) First LTN Stop built: OnTick, OnTrainStateChanged, OnTrainCreated registered") end
      end
    end
  end
end
end

do -- stop removed
function removeStop(entity)
  local stopID = entity.unit_number
  local stop = global.LogisticTrainStops[stopID]

  -- clean lookup tables
  for i=#StopIDList, 1, -1 do
    if StopIDList[i] == stopID then
      table.remove(StopIDList, i)
    end
  end
  for k,v in pairs(global.StopDistances) do
    if k:find(stopID) then
      global.StopDistances[k] = nil
    end
  end

  -- remove available train
  if stop and stop.isDepot and stop.parkedTrainID and global.Dispatcher.availableTrains[stop.parkedTrainID] then
    global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[stop.parkedTrainID].capacity
    global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[stop.parkedTrainID].fluid_capacity
    global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
  end

  -- destroy IO entities
  if stop and stop.input and stop.input.valid and stop.output and stop.output.valid and stop.lampControl and stop.lampControl.valid then
    stop.input.destroy()
    stop.output.destroy()
    stop.lampControl.destroy()
  else
    -- destroy broken IO entities
    local ghosts = entity.surface.find_entities({{entity.position.x-1.1, entity.position.y-1.1},{entity.position.x+1.1, entity.position.y+1.1}} )
    for _,ghost in pairs (ghosts) do
      if ghost.name == "logistic-train-stop-input" or ghost.name == "logistic-train-stop-output" or ghost.name == "logistic-train-stop-lamp-control" then
        --printmsg("removing broken "..ghost.name.." at "..ghost.position.x..", "..ghost.position.y)
        ghost.destroy()
      end
    end
  end

  global.LogisticTrainStops[stopID] = nil
end

function OnEntityRemoved(event)
-- script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, function(event)
  local entity = event.entity
  if  entity.type == "locomotive" then -- single locomotives are not handled by on_train_created
    TrainLeaves(entity.train.id) -- possible overhead from using shared function
    RemoveDelivery(entity.train.id)
  elseif entity.type == "train-stop" then
    RemoveStopName(entity.unit_number, entity.backer_name) -- all stop names are monitored
    if entity.name == "logistic-train-stop" then
      removeStop(entity)
      if StopIDList == nil or #StopIDList == 0 then
        -- unregister events
        script.on_event(defines.events.on_tick, nil)
        script.on_event(defines.events.on_train_changed_state, nil)
        script.on_event(defines.events.on_train_created, nil)
        if debug_log then log("(OnEntityRemoved) Removed last LTN Stop: OnTick, OnTrainStateChanged, OnTrainCreated unregistered") end
      end
    end
  end
end
end


do --rename stop
local function renamedStop(targetID, old_name, new_name)
  -- find identical stop names
  local duplicateName = false
  local renameDeliveries = true
  for stopID, stop in pairs(global.LogisticTrainStops) do
    if stop.entity.backer_name == old_name then
      renameDeliveries = false
    end
  end
  -- rename deliveries only if no other LTN stop old_name exists
  if renameDeliveries then
    if debug_log then log("(OnEntityRenamed) last LTN stop "..old_name.." renamed, updating deliveries to "..new_name..".") end
    for trainID, delivery in pairs(global.Dispatcher.Deliveries) do
      if delivery.to == old_name then
        delivery.to = new_name
        --log("renamed delivery.to "..old_name.." > "..new_name)
      end
      if delivery.from == old_name then
        delivery.from = new_name
        --log("renamed delivery.from "..old_name.." > "..new_name)
      end
    end
  end
end

script.on_event(defines.events.on_entity_renamed, function(event)
  local uid = event.entity.unit_number
  local oldName = event.old_name
  local newName = event.entity.backer_name

  if event.entity.type == "train-stop" then
    RemoveStopName(uid, oldName)
    AddStopName(uid, newName)
  end
  -- log("stoplist: "..serpent.block(global.TrainStopNames))


  if event.entity.name == "logistic-train-stop" then
    --log("(on_entity_renamed) uid:"..uid..", old name: "..oldName..", new name: "..newName)
    renamedStop(uid, oldName, newName)
  end
end)

end

-- update global.Dispatcher.Deliveries.force when forces are removed/merged
script.on_event(defines.events.on_forces_merging, function(event)
  for _, delivery in pairs(global.Dispatcher.Deliveries) do
    if delivery.force.name == event.source.name then
      delivery.force = event.destination
    end
  end
end)




function OnTick(event)
  -- exit when there are no logistic train stops
  local tick = game.tick
  global.tickCount = global.tickCount or 1

  if global.tickCount == 1 then
    stopsPerTick = ceil(#StopIDList/(dispatcher_update_interval-3)) -- 57 ticks for stop Updates, 3 ticks for dispatcher
    global.stopIdStartIndex = 1

    -- clear Dispatcher.Storage
    global.Dispatcher.Provided = {}
    global.Dispatcher.Requests = {}
    global.Dispatcher.Requests_by_Stop = {}
  end

  -- ticks 1 - 57: update stops
  if global.tickCount < dispatcher_update_interval - 2 then
    local stopIdLastIndex = global.stopIdStartIndex + stopsPerTick - 1
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
  elseif global.tickCount == dispatcher_update_interval - 2 then
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
        RemoveDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if message_level >= 1 then printmsg({"ltn-message.delivery-removed-timeout", delivery.from, delivery.to, tick-delivery.started}, delivery.force, false) end
        if debug_log then log("(OnTick) Delivery from "..delivery.from.." to "..delivery.to.." removed. Timed out after "..tick-delivery.started.."/"..delivery_timeout.." ticks.") end
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

    -- sort requests by age
    sort(global.Dispatcher.Requests, function(a, b)
        if a.priority ~= b.priority then --sort by priority
          return a.priority > b.priority
        else
          return a.age < b.age
        end
      end)

  -- tick 59: parse requests and dispatch trains
  elseif global.tickCount == dispatcher_update_interval - 1 then
    if dispatcher_enabled then
      if debug_log then log("(OnTick) Available train capacity: "..global.Dispatcher.availableTrains_total_capacity.." item stacks, "..global.Dispatcher.availableTrains_total_fluid_capacity.. " fluid capacity.") end
      local created_deliveries = {}
      for reqIndex, request in pairs (global.Dispatcher.Requests) do
        local delivery = ProcessRequest(reqIndex, request)
        if delivery then
          created_deliveries[#created_deliveries+1] = delivery
        end
      end
      if debug_log then log("(OnTick) Created "..#created_deliveries.." deliveries this cycle.") end
    else
      if message_level >= 1 then printmsg({"ltn-message.warning-dispatcher-disabled"}, nil, true) end
      if debug_log then log("(OnTick) Dispatcher disabled.") end
    end

  -- tick 60: reset
  else
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
      end
    end
  end
  global.Dispatcher.Deliveries[trainID] = nil
end

-- return new schedule_record
-- itemlist = {first_signal.type, first_signal.name, constant}
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

      local cond = {comparator = condComp, first_signal = {type = itemlist[i].type, name = itemlist[i].name}, constant = countOverride or itemlist[i].count}
      record.wait_conditions[#record.wait_conditions+1] = {type = condFluid or condType, compare_type = "and", condition = cond }
    end

    if waitEmpty then
      record.wait_conditions[#record.wait_conditions+1] = {type = "empty", compare_type = "and" }
    elseif finish_loading then -- let inserter/pumps finish
      record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "and", ticks = 120 }
    end

    if stop_timeout > 0 then -- if stop_timeout is set add time passed condition
      record.wait_conditions[#record.wait_conditions+1] = {type = "time", compare_type = "or", ticks = stop_timeout } -- send stuck trains away
    end
  elseif condType == "inactivity" then
    record.wait_conditions[#record.wait_conditions+1] = {type = condType, compare_type = "and", ticks = condComp }
  end
  return record
end


do --ProcessRequest

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
    local matched_networks = bit32.band(requestStation.network_id, stop.network_id)
    -- log("DEBUG: comparing 0x"..string.format("%x", bit32.band(requestStation.network_id)).." & 0x"..string.format("%x", bit32.band(stop.network_id)).." = 0x"..string.format("%x", bit32.band(matched_networks)) )

    if stop and stop.entity.force.name == force.name
    and matched_networks ~= 0
    and count >= stop.minProvided
    and (stop.minTraincars == 0 or max_length == 0 or stop.minTraincars <= max_length)
    and (stop.maxTraincars == 0 or min_length == 0 or stop.maxTraincars >= min_length) then --check if provider can actually service trains from requester
      local activeDeliveryCount = #stop.activeDeliveries
      local from_network_id_string = "0x"..string.format("%x", bit32.band(stop.network_id))
      if activeDeliveryCount and (stop.trainLimit == 0 or activeDeliveryCount < stop.trainLimit) then
        if debug_log then log("found "..count.."("..tostring(stop.minProvided)..")".."/"..req_count.." ".. item.." at "..stop.entity.backer_name.." {"..from_network_id_string.."}, priority: "..stop.providePriority..", active Deliveries: "..activeDeliveryCount.." minTraincars: "..stop.minTraincars..", maxTraincars: "..stop.maxTraincars..", locked Slots: "..stop.lockedSlots) end
        stations[#stations +1] = {entity = stop.entity, network_id = matched_networks, priority = stop.providePriority, activeDeliveryCount = activeDeliveryCount, item = item, count = count, minTraincars = stop.minTraincars, maxTraincars = stop.maxTraincars, lockedSlots = stop.lockedSlots}
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

-- return available train with smallest suitable inventory or largest available inventory
-- if minTraincars is set, number of locos + wagons has to be bigger
-- if maxTraincars is set, number of locos + wagons has to be smaller
local function getFreeTrain(nextStop, minTraincars, maxTraincars, type, size)
  local train = nil
  if minTraincars == nil or minTraincars < 0 then minTraincars = 0 end
  if maxTraincars == nil or maxTraincars < 0 then maxTraincars = 0 end
  local largestInventory = 0
  local smallestInventory = 0
  local minDistance = 0
  for trainID, trainData in pairs (global.Dispatcher.availableTrains) do
    if trainData.train.valid and trainData.train.station then
      local depot_network_id_string = "0x"..string.format("%x", bit32.band(trainData.network_id))
      local dest_network_id_string = "0x"..string.format("%x", bit32.band(nextStop.network_id))
      local inventorySize = trainData.capacity - (nextStop.lockedSlots * #trainData.train.cargo_wagons) -- subtract locked slots from every cargo wagon
      if type == "fluid" then
        inventorySize = trainData.fluid_capacity
      end

      if debug_log then log("checking train "..tostring(GetTrainName(trainData.train)).." ,force "..trainData.force.."/"..nextStop.entity.force.name..", network "..depot_network_id_string.."/"..dest_network_id_string..", length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..getStationDistance(trainData.train.station, nextStop.entity)) end

      if trainData.force == nextStop.entity.force.name -- forces match
      and bit32.btest(trainData.network_id, nextStop.network_id)
      and (minTraincars == 0 or #trainData.train.carriages >= minTraincars) and (maxTraincars == 0 or #trainData.train.carriages <= maxTraincars) then -- train length fits
        local distance = getStationDistance(trainData.train.station, nextStop.entity)
        if inventorySize >= size then
          -- train can be used for whole delivery
          if inventorySize < smallestInventory or (inventorySize == smallestInventory and distance < minDistance) or smallestInventory == 0 then
            minDistance = distance
            smallestInventory = inventorySize
            train = {id=trainID, inventorySize=inventorySize}
            if debug_log then log("(getFreeTrain) found train "..tostring(GetTrainName(trainData.train)).." {"..depot_network_id_string.."}, length: "..minTraincars.."<="..#trainData.train.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
          end
        elseif smallestInventory == 0 and inventorySize > 0 then
          -- train can be used for partial delivery, use only when no trains for whole delivery available
          if inventorySize > largestInventory or (inventorySize == largestInventory and distance < minDistance) or largestInventory == 0 then
            minDistance = distance
            largestInventory = inventorySize
            train = {id=trainID, inventorySize=inventorySize}
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

  return train
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
  local to_network_id_string = "0x"..string.format("%x", bit32.band(requestStation.network_id))
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
  local itype, iname = match(item, "([^,]+),([^,]+)")
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
      if debug_log then log("Skipping request "..requestStation.entity.backer_name.." {"..to_network_id_string.."}: "..item..". No trains available.") end
      return
    end
  else
    localname = game.item_prototypes[iname].localised_name
    -- skip if no trains are available
    if (global.Dispatcher.availableTrains_total_capacity or 0) == 0 then
      if debug_log then log("Skipping request "..requestStation.entity.backer_name.." {"..to_network_id_string.."}: "..item..". No trains available.") end
      return
    end
  end

  -- get providers ordered by priority
  local providers = getProviders(requestStation, item, count, minTraincars, maxTraincars)
  if not providers or #providers < 1 then
    if requestStation.noWarnings == false and message_level >= 1 then printmsg({"ltn-message.no-provider-found", localname}, requestForce, true) end
    if debug_log then log("No station supplying "..item.." found.") end
    -- goto skipRequestItem
    return nil
  end

  local providerStation = providers[1] -- only one delivery/request is created so use only the best provider
  local fromID = providerStation.entity.unit_number
  local from = providerStation.entity.backer_name

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
      local merge_type, merge_name = match(merge_item, "([^,]+),([^,]+)")
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
  -- TODO: rewrite train into availableTrains[train.id]
  local train = getFreeTrain(providerStation, minTraincars, maxTraincars, loadingList[1].type, totalStacks)
  if not train then
    if message_level >= 3 then printmsg({"ltn-message.no-train-found-merged", tostring(minTraincars), tostring(maxTraincars), tostring(totalStacks)}, requestForce, true) end
    if debug_log then log("No train with "..tostring(minTraincars).." <= length <= "..tostring(maxTraincars).." to transport "..tostring(totalStacks).." stacks found in Depot.") end
    return nil
  end
  if message_level >= 3 then printmsg({"ltn-message.train-found", tostring(train.inventorySize), tostring(totalStacks)}, requestForce) end
  if debug_log then log("Train to transport "..tostring(train.inventorySize).."/"..tostring(totalStacks).." stacks found in Depot.") end

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
  local selectedTrain = global.Dispatcher.availableTrains[train.id].train
  local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]
  local schedule = {current = 1, records = {}}
  schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "inactivity", depot_inactivity)
  schedule.records[2] = NewScheduleRecord(from, "item_count", ">", loadingList)
  schedule.records[3] = NewScheduleRecord(to, "item_count", "=", loadingList, 0)
  selectedTrain.schedule = schedule


  local delivery = {}
  if debug_log then log("Creating Delivery: "..totalStacks.." stacks, "..from.." >> "..to) end
  for i=1, #loadingList do
    local loadingListItem = loadingList[i].type..","..loadingList[i].name
    -- store Delivery
    delivery[loadingListItem] = loadingList[i].count

    -- remove Delivery from Provided items
    global.Dispatcher.Provided[loadingListItem][fromID] = global.Dispatcher.Provided[loadingListItem][fromID] - loadingList[i].count

    -- remove Request and reset age
    global.Dispatcher.Requests_by_Stop[toID][loadingListItem] = nil
    global.Dispatcher.RequestAge[loadingListItem..","..toID] = nil

    if debug_log then log("  "..loadingListItem..", "..loadingList[i].count.." in "..loadingList[i].stacks.." stacks ") end
  end
  global.Dispatcher.Deliveries[train.id] = {force=requestForce, train=selectedTrain, started=game.tick, from=from, to=to, shipment=delivery}
  global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[train.id].capacity
  global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[train.id].fluid_capacity
  global.Dispatcher.availableTrains[train.id] = nil

  -- train is no longer available => set depot to green even if train might has to wait inactivity timer
  setLamp(selectedTrain.station.unit_number, "yellow", 1)

  -- set lamps on stations to yellow
  -- trains will pick a stop by their own logic so we have to parse by name
  for stopID, stop in pairs (global.LogisticTrainStops) do
    if stop.entity.backer_name == from or stop.entity.backer_name == to then
      table.insert(global.LogisticTrainStops[stopID].activeDeliveries, train.id)
      setLamp(stopID, "yellow", #stop.activeDeliveries)
    end
  end

  -- return train ID / delivery ID
  return train.id
end

end -- ProcessRequest Block


------------------------------------- STOP FUNCTIONS -------------------------------------

do --UpdateStop

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

-- update stop input signals
function UpdateStop(stopID)
  local stop = global.LogisticTrainStops[stopID]
  global.Dispatcher.Requests_by_Stop[stopID] = nil

  -- remove invalid stops
  -- if not stop or not (stop.entity and stop.entity.valid) or not (stop.input and stop.input.valid) or not (stop.output and stop.output.valid) or not (stop.lampControl and stop.lampControl.valid) then
  if not(stop and stop.entity and stop.entity.valid and stop.input and stop.input.valid and stop.output and stop.output.valid and stop.lampControl and stop.lampControl.valid) then
    if message_level >= 1 then printmsg({"ltn-message.error-invalid-stop", stopID}) end
    if debug_log then log("(UpdateStop) Invalid stop: "..stopID) end
    for i=#StopIDList, 1, -1 do
      if StopIDList[i] == stopID then
        table.remove(StopIDList, i)
      end
    end
    return
  end

  -- remove invalid trains
  if stop.parkedTrain and not stop.parkedTrain.valid then
    global.LogisticTrainStops[stopID].parkedTrain = nil
    global.LogisticTrainStops[stopID].parkedTrainID = nil
  end

  -- remove invalid activeDeliveries -- shouldn't be necessary
  -- for i=#stop.activeDeliveries, 1, -1 do
    -- if not global.Dispatcher.Deliveries[stop.activeDeliveries[i]] then
      -- table.remove(stop.activeDeliveries, i)
    -- end
  -- end

  -- reset stop parameters just in case something goes wrong
  stop.minProvided = nil
  stop.minRequested = nil
  stop.minTraincars = 0
  stop.maxTraincars = 0
  stop.trainLimit = 0
  stop.providePriority = 0
  stop.lockedSlots = 0
  stop.noWarnings = 0

  -- reject any stop not in name list
  if not global.TrainStopNames[stop.entity.backer_name] then
    stop.errorCode = 2
    stop.activeDeliveries = {}
    if message_level >= 1 then printmsg({"ltn-message.error-invalid-stop", stop.entity.backer_name}) end
    if debug_log then log("(UpdateStop) Stop not in list global.TrainStopNames: "..stop.entity.backer_name) end
    return
  end

  -- skip short circuited stops
  if detectShortCircuit(stop) then
    stop.errorCode = 1
    stop.activeDeliveries = {}
    setLamp(stopID, ErrorCodes[stop.errorCode], 1)
    if debug_log then log("(UpdateStop) Short circuit error: "..stop.entity.backer_name) end
    return
  end

  -- skip deactivated stops
  local stopCB = stop.entity.get_control_behavior()
  if stopCB and stopCB.disabled then
    stop.errorCode = 1
    stop.activeDeliveries = {}
    setLamp(stopID, ErrorCodes[stop.errorCode], 2)
    if debug_log then log("(UpdateStop) Circuit deactivated stop: "..stop.entity.backer_name) end
    return
  end


  -- get circuit values 0.16.24
  local signals = stop.input.get_merged_signals()
  local signal_dict = {}
  -- log(stop.entity.backer_name.." signals: "..serpent.block(signals))

  if not signals then
    return
  end

  local signals_filtered = {}
  local vr_type = "virtual"

  -- initialize control signal values to defaults
  local isDepot = false
  local network_id = -1
  local minTraincars = 0
  local maxTraincars = 0
  local trainLimit = 0
  local minRequested = min_requested
  local requestPriority = 0
  local noWarnings = false
  local minProvided = min_provided
  local providePriority = 0
  local lockedSlots = 0

  local abs = math.abs

  for _,v in pairs(signals) do
      if v.signal.type ~= vr_type then
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
        elseif v.signal.name == MINREQUESTED then
          minRequested = abs(v.count)
        elseif v.signal.name == REQPRIORITY then
          requestPriority = v.count
        elseif v.signal.name == NOWARN and v.count > 0 then
          noWarnings = true
        elseif v.signal.name == MINPROVIDED then
           minProvided = abs(v.count)
        elseif v.signal.name == PROVPRIORITY then
          providePriority = v.count
        elseif v.signal.name == LOCKEDSLOTS and v.count > 0 then
          lockedSlots = v.count
        end
      end
  end
  local network_id_string = "0x"..string.format("%x", bit32.band(network_id))

  -- log(stop.entity.backer_name.." filtered signals: "..serpent.block(signals_filtered))
  -- log("Control Signals: isDepot:"..tostring(isDepot).." network_id:"..network_id.." network_id_string:"..network_id_string
  -- .." minTraincars:"..minTraincars.." maxTraincars:"..maxTraincars.." trainLimit:"..trainLimit
  -- .." minRequested:"..minRequested.." requestPriority:"..requestPriority.." noWarnings:"..tostring(noWarnings)
  -- .." minProvided:"..minProvided.." providePriority:"..providePriority.." lockedSlots:"..lockedSlots)


  -- skip duplicated names on non depots
  if #global.TrainStopNames[stop.entity.backer_name] ~= 1 and not isDepot then
    stop.errorCode = 2
    stop.activeDeliveries = {}
    setLamp(stopID, ErrorCodes[stop.errorCode], 1)
    if debug_log then log("(UpdateStop) Duplicate stop name: "..stop.entity.backer_name) end
    return
  end

  --update lamp colors when errorCode or isDepot changed state
  if stop.errorCode ~=0 or stop.isDepot ~= isDepot then
    stop.errorCode = 0 -- we are error free here
    if isDepot then
      if stop.parkedTrainID and stop.parkedTrain.valid then
        if global.Dispatcher.Deliveries[stop.parkedTrainID] then
          setLamp(stopID, "yellow", 1)
        else
          setLamp(stopID, "blue", 1)
        end
      else
        setLamp(stopID, "green", 1)
      end
    else
      if #stop.activeDeliveries > 0 then
        setLamp(stopID, "yellow", #stop.activeDeliveries)
      else
        setLamp(stopID, "green", 1)
      end
    end
  end

  -- check if it's a depot
  if isDepot then
    stop.isDepot = true
    stop.network_id = network_id
    stop.activeDeliveries = {} -- reset delivery count in case stops are toggled

    -- add parked train to available trains
    if stop.parkedTrainID and stop.parkedTrain.valid then
      if global.Dispatcher.Deliveries[stop.parkedTrainID] then
        if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} is depot with train.id "..stop.parkedTrainID.." assigned to delivery" ) end
      else
        if not global.Dispatcher.availableTrains[stop.parkedTrainID] then
          -- create new available train
          local loco = GetMainLocomotive(stop.parkedTrain)
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
        if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} is depot with available train.id "..stop.parkedTrainID ) end
      end
    else
      if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} is empty depot.") end
    end

  -- not a depot > check if the name is unique
  else
    stop.isDepot = false

    -- remove parked train from available trains
    if stop.parkedTrainID and global.Dispatcher.availableTrains[stop.parkedTrainID] then
      global.Dispatcher.availableTrains_total_capacity = global.Dispatcher.availableTrains_total_capacity - global.Dispatcher.availableTrains[stop.parkedTrainID].capacity
      global.Dispatcher.availableTrains_total_fluid_capacity = global.Dispatcher.availableTrains_total_fluid_capacity - global.Dispatcher.availableTrains[stop.parkedTrainID].fluid_capacity
      global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
    end

    global.Dispatcher.Requests_by_Stop[stopID] = {} -- Requests_by_Stop = {[stopID], {[item], count} }
    for _,sig in pairs (signals_filtered) do
      local item = sig.signal.type..","..sig.signal.name
      local count = sig.count
      for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
        local deliverycount = delivery.shipment[item]
        if deliverycount then
          if stop.parkedTrain and stop.parkedTrainID == trainID then
            -- calculate items +- train inventory
            local traincount = 0
            if sig.signal.type == "fluid" then
              traincount = stop.parkedTrain.get_fluid_count(sig.signal.name)
            else
              traincount = stop.parkedTrain.get_item_count(sig.signal.name)
            end

            if delivery.to == stop.entity.backer_name then
              local newcount = count + traincount
              if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
              if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} updating requested count with train inventory: "..item.." "..count.."+"..traincount.."="..newcount) end
              count = newcount
            elseif delivery.from == stop.entity.backer_name then
              if traincount <= deliverycount then
                local newcount = count - (deliverycount - traincount)
                if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
                if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} updating provided count with train inventory: "..item.." "..count.."-"..deliverycount - traincount.."="..newcount) end
                count = newcount
              else --train loaded more than delivery
                if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} updating delivery count with overloaded train inventory: "..item.." "..traincount) end
                -- update delivery to new size
                global.Dispatcher.Deliveries[trainID].shipment[item] = traincount
              end
            end

          else
            -- calculate items +- deliveries
            if delivery.to == stop.entity.backer_name then
              local newcount = count + deliverycount
              if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
              if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} updating requested count with delivery: "..item.." "..count.."+"..deliverycount.."="..newcount) end
              count = newcount
            elseif delivery.from == stop.entity.backer_name and not delivery.pickupDone then
              local newcount = count - deliverycount
              if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
              if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} updating provided count with delivery: "..item.." "..count.."-"..deliverycount.."="..newcount) end
              count = newcount
            end

          end
        end
      end -- for delivery

      -- update Dispatcher Storage
      -- Providers are used when above Provider Threshold
      -- Requests are handled when above Requester Threshold
      if count >= minProvided then
        local provided = global.Dispatcher.Provided[item] or {}
        provided[stopID] = count
        global.Dispatcher.Provided[item] = provided
        if debug_log then
          local trainsEnRoute = "";
          for k,v in pairs(stop.activeDeliveries) do
            trainsEnRoute=trainsEnRoute.." "..v
          end
          log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} provides "..item.." "..count.."("..minProvided..")"..", priority: "..providePriority..", min length: "..minTraincars..", max length: "..maxTraincars..", trains en route: "..trainsEnRoute)
        end
      elseif count*-1 >= minRequested then
        count = count * -1
        local ageIndex = item..","..stopID
        global.Dispatcher.RequestAge[ageIndex] = global.Dispatcher.RequestAge[ageIndex] or game.tick
        global.Dispatcher.Requests[#global.Dispatcher.Requests+1] = {age = global.Dispatcher.RequestAge[ageIndex], stopID = stopID, priority = requestPriority, item = item, count = count}
        global.Dispatcher.Requests_by_Stop[stopID][item] = count
        if debug_log then
          local trainsEnRoute = "";
          for k,v in pairs(stop.activeDeliveries) do
            trainsEnRoute=trainsEnRoute.." "..v
          end
          log("(UpdateStop) "..stop.entity.backer_name.." {"..network_id_string.."} requests "..item.." "..count.."("..minRequested..")"..", priority: "..requestPriority..", min length: "..minTraincars..", max length: "..maxTraincars..", age: "..global.Dispatcher.RequestAge[ageIndex].."/"..game.tick..", trains en route: "..trainsEnRoute)
        end
      end

    end -- for circuitValues

    stop.network_id = network_id
    stop.minProvided = minProvided
    stop.minRequested = minRequested
    stop.minTraincars = minTraincars
    stop.maxTraincars = maxTraincars
    stop.trainLimit = trainLimit
    stop.providePriority = providePriority
    stop.lockedSlots = lockedSlots
    stop.noWarnings = noWarnings
  end
end

end

do --setLamp
local ColorLookup = {
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

function setLamp(stopID, color, count)
  if ColorLookup[color] and global.LogisticTrainStops[stopID] then
    global.LogisticTrainStops[stopID].lampControl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name=ColorLookup[color]}, count = count }}}
    return true
  end
  return false
end
end

function UpdateStopOutput(trainStop)
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
              if c.condition.comparator == ">" then --train expects to be loaded to x of this item
                inventory[c.condition.first_signal.name] = c.condition.constant + 1
              elseif (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this item
                inventory[c.condition.first_signal.name] = nil
              end
            elseif c.type == "fluid_count" then
              if c.condition.comparator == ">" then --train expects to be loaded to x of this fluid
                fluidInventory[c.condition.first_signal.name] = c.condition.constant + 1
              elseif (c.condition.comparator == "=" and c.condition.constant == 0) then --train expects to be unloaded of each of this fluid
                fluidInventory[c.condition.first_signal.name] = nil
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
    -- log("[LTN] "..tostring(trainStop.entity.backer_name).. " displaying "..#signals.."/"..tostring(trainStop.output.get_control_behavior().signals_count).." signals.")

    while #signals > trainStop.output.get_control_behavior().signals_count do
      -- log("[LTN] removing signal "..tostring(signals[#signals].signal.name))
      table.remove(signals)
    end
    if index ~= #signals then
      if message_level >= 1 then printmsg({"ltn-message.error-stop-output-truncated", tostring(trainStop.entity.backer_name), tostring(trainStop.parkedTrain), trainStop.output.get_control_behavior().signals_count, index-#signals}, trainStop.entity.force) end
      if debug_log then log("(UpdateStopOutput) Inventory of train "..tostring(trainStop.parkedTrain.id).." at stop "..tostring(trainStop.entity.backer_name).." exceeds stop output limit of "..trainStop.output.get_control_behavior().signals_count.." by "..index-#signals.." signals.") end
    end
    trainStop.output.get_control_behavior().parameters = {parameters=signals}
    if debug_log then log("(UpdateStopOutput) Updating signals for "..tostring(trainStop.entity.backer_name)..": train "..tostring(trainStop.parkedTrain.id)..": "..index.." signals") end
  else
    trainStop.output.get_control_behavior().parameters = nil
    if debug_log then log("(UpdateStopOutput) Resetting signals for "..tostring(trainStop.entity.backer_name)..".") end
  end
end

---------------------------------- HELPER FUNCTIONS ----------------------------------

do --GetTrainCapacity(train)
local function getCargoWagonCapacity(entity)
  local capacity = entity.prototype.get_inventory_size(defines.inventory.cargo_wagon)
  log("(getCargoWagonCapacity) capacity for "..entity.name.." = "..capacity)
  global.WagonCapacity[entity.name] = capacity
  return capacity
end

local function getFluidWagonCapacity(entity)
  local capacity = 0
  for n=1, #entity.fluidbox do
    capacity = capacity + entity.fluidbox.get_capacity(n)
  end
  log("(getFluidWagonCapacity) capacity for "..entity.name.." = "..capacity)
  global.WagonCapacity[entity.name] = capacity
  return capacity
end

-- returns inventory and fluid capacity of a given train
function GetTrainCapacity(train)
  local inventorySize = 0
  local fluidCapacity = 0
  if train and train.valid then
    for _,wagon in pairs(train.cargo_wagons) do
      local capacity = global.WagonCapacity[wagon.name] or getCargoWagonCapacity(wagon)
       inventorySize = inventorySize + capacity
    end
    for _,wagon in pairs(train.fluid_wagons) do
      local capacity = global.WagonCapacity[wagon.name] or getFluidWagonCapacity(wagon)
      fluidCapacity = fluidCapacity + capacity
    end
  end
  return inventorySize, fluidCapacity
end

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

function GetTrainName(train)
  local loco = GetMainLocomotive(train)
  return loco and loco.backer_name
end

--local square = math.sqrt
function GetDistance(a, b)
  local x, y = a.x-b.x, a.y-b.y
  --return square(x*x+y*y) -- sqrt shouldn't be necessary for comparing distances
  return (x*x+y*y)
end
