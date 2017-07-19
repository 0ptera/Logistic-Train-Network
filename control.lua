require "config"
require "interface"

local MOD_NAME = "LogisticTrainNetwork"

local ISDEPOT = "ltn-depot"
local MINTRAINLENGTH = "ltn-min-train-length"
local MAXTRAINLENGTH = "ltn-max-train-length"
local MAXTRAINS = "ltn-max-trains"
local MINREQUESTED = "ltn-requester-threshold"
local NOWARN = "ltn-disable-warnings"
local MINPROVIDED = "ltn-provider-threshold"
local PRIORITY = "ltn-provider-priority"
local LOCKEDSLOTS = "ltn-locked-slots"

local ControlSignals = {
  [ISDEPOT] = true,
  [MINTRAINLENGTH] = true,
  [MAXTRAINLENGTH] = true,
  [MAXTRAINS] = true,
  [MINREQUESTED] = true,
  [NOWARN] = true,
  [MINPROVIDED] = true,
  [PRIORITY] = true,
  [LOCKEDSLOTS] = true,
}

local ErrorCodes = {
  "red",    -- circuit/signal error
  "pink"    -- duplicate stop name
}
local StopIDList = {} -- stopIDs list for on_tick updates
local stopsPerTick = 1 -- step width of StopIDList

local match = string.match
local ceil = math.ceil
local sort = table.sort

---- BOOTSTRAP ----
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

  global.StopDistances = global.StopDistances or {} -- station distance lookup table
  global.stopIdStartIndex = global.stopIdStartIndex or 1 --global index should prevent desync by updating different stops

  ---- initialize Dispatcher
  global.Dispatcher = global.Dispatcher or {}
  global.Dispatcher.availableTrains = global.Dispatcher.availableTrains or {}
  global.Dispatcher.Provided = global.Dispatcher.Provided or {}
  global.Dispatcher.Requests = global.Dispatcher.Requests or {}
  global.Dispatcher.RequestAge = global.Dispatcher.RequestAge or {}
  global.Dispatcher.Orders = global.Dispatcher.Orders or {}
  global.Dispatcher.Deliveries = global.Dispatcher.Deliveries or {}

  -- clean obsolete global
  global.Dispatcher.Requested = nil
  global.Dispatcher.OrderAge = nil
  global.Dispatcher.Storage = nil
  global.useRailTanker = nil

  -- update to 0.4
  if oldVersion and oldVersion < "00.04.00" then
    log("[LTN] Updating Dispatcher.Deliveries to 0.4.0.")
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

  -- update to 1.4.0
  if oldVersion and oldVersion < "01.04.00" then
    global.Dispatcher.Requests = {}
    global.Dispatcher.RequestAge = {}
    global.Dispatcher.Orders = {}
  end

  ---- initialize stops
  global.LogisticTrainStops = global.LogisticTrainStops or {}
  local validLampControls = {}

  if next(global.LogisticTrainStops) then
    for stopID, stop in pairs (global.LogisticTrainStops) do
      global.LogisticTrainStops[stopID].errorCode = global.LogisticTrainStops[stopID].errorCode or 0

      -- update to 1.3.0
      global.LogisticTrainStops[stopID].minDelivery = nil
      global.LogisticTrainStops[stopID].ignoreMinDeliverySize = nil
      global.LogisticTrainStops[stopID].minRequested = global.LogisticTrainStops[stopID].minRequested or 0
      global.LogisticTrainStops[stopID].minProvided = global.LogisticTrainStops[stopID].minProvided or 0

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
        global.LogisticTrainStops[stopID].input.get_or_create_control_behavior().circuit_condition = {condition = {comparator=">",first_signal={type="virtual",name="signal-anything"}}}
      end
      -- update to 1.1.1 remove orphaned lamp controls
      validLampControls[stop.lampControl.unit_number] = true

      -- update to 0.9.5
      global.LogisticTrainStops[stopID].activeDeliveries = global.LogisticTrainStops[stopID].activeDeliveries or {}
      if type(stop.activeDeliveries) ~= "table" then
        stop.activeDeliveries = {}
        for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
          if delivery.from == stop.entity.backer_name or delivery.to == stop.entity.backer_name then
            table.insert(stop.activeDeliveries, trainID)
          end
        end
      end

      -- update to 0.10.2
      global.LogisticTrainStops[stopID].trainLimit = global.LogisticTrainStops[stopID].trainLimit or 0
      global.LogisticTrainStops[stopID].parkedTrainFacesStop = global.LogisticTrainStops[stopID].parkedTrainFacesStop or true
      global.LogisticTrainStops[stopID].lockedSlots = global.LogisticTrainStops[stopID].lockedSlots or 0

      UpdateStopOutput(stop) --make sure output is set
      --UpdateStop(stopID)
    end
  end

  -- update to 1.1.1 remove orphaned lamp controls
  if oldVersion and oldVersion < "01.01.01" then
    local lcDeleted = 0
    for _, surface in pairs(game.surfaces) do
      local lcEntities = surface.find_entities_filtered{name="logistic-train-stop-lamp-control"}
      if lcEntities then
      for k, v in pairs(lcEntities) do
        if not validLampControls[v.unit_number] then
          v.destroy()
          lcDeleted = lcDeleted+1
        end
      end
      end
    end
    log("[LTN] removed "..lcDeleted.. " orphaned lamp control entities.")
  end
end

-- has to run every time the mod configuration is changed to catch stops from other mods
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

-- register events
local function registerEvents()
  -- always track built/removed train stops for duplicate name list
  script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, OnEntityCreated)
  script.on_event({defines.events.on_preplayer_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, OnEntityRemoved)
  if global.LogisticTrainStops and next(global.LogisticTrainStops) then
    script.on_event(defines.events.on_tick, OnTick)
    script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
    script.on_event(defines.events.on_train_created, OnTrainCreated)
  end
end

script.on_load(function()
  if global.LogisticTrainStops and next(global.LogisticTrainStops) then
    for stopID, stop in pairs(global.LogisticTrainStops) do --outputs are not stored in save
      UpdateStopOutput(stop)
      StopIDList[#StopIDList+1] = stopID
    end
    stopsPerTick = ceil(#StopIDList/(dispatcher_update_interval-1))
  end
  registerEvents()
  log("[LTN] on_load: complete")
end)

script.on_init(function()
  buildStopNameList()

  -- format version string to "00.00.00"
  local oldVersion, newVersion = nil
  local newVersionString = game.active_mods[MOD_NAME]
  if newVersionString then
    newVersion = string.format("%02d.%02d.%02d", string.match(newVersionString, "(%d+).(%d+).(%d+)"))
  end
  initialize(oldVersion, newVersion)
  registerEvents()
  log("[LTN] on_init: ".. MOD_NAME.." "..tostring(newVersionString).." initialized.")
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

    initialize(oldVersion, newVersion)
    registerEvents()
    log("[LTN] on_configuration_changed: ".. MOD_NAME.." "..tostring(newVersionString).." initialized. Previous version: "..tostring(oldVersionString))
  end
end)

end

---- EVENTS ----

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
  if global.TrainStopNames[stopName] and #global.TrainStopNames[stopName] > 1 then
    -- multiple stops of same name > remove id from the list
    for i=#global.TrainStopNames[stopName], 1, -1 do
      if global.TrainStopNames[stopName][i] == stopID then
        table.remove(global.TrainStopNames[stopName], i)
        -- log("removed "..stopID.." from "..stopName)
      end
    end
  else
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
    trainLimit = 0,
    activeDeliveries = {},  --delivery IDs to/from stop
    errorCode = 0,          --key to errorCodes table
    parkedTrain = nil,
    parkedTrainID = nil
  }
  StopIDList[#StopIDList+1] = entity.unit_number
  UpdateStopOutput(global.LogisticTrainStops[entity.unit_number])
end

function OnEntityCreated(event)
  local entity = event.created_entity
  if entity.type == "train-stop" then
     AddStopName(entity.unit_number, entity.backer_name)
  end
  if entity.valid and entity.name == "logistic-train-stop" then
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
  if stop and stop.isDepot and stop.parkedTrainID then
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
-- script.on_event({defines.events.on_preplayer_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, function(event)
  local entity = event.entity
  if entity.type == "train-stop" then
    RemoveStopName(entity.unit_number, entity.backer_name)
  end
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


do --train state changed
function OnTrainStateChanged(event)
-- script.on_event(defines.events.on_train_changed_state, function(event)
  UpdateTrain(event.train)
end

function OnTrainCreated(event)
-- script.on_event(defines.events.on_train_created, function(event)
  -- log("(on_train_created) Train name: "..tostring(GetTrainName(event.train))..",Train ID: "..tostring(GetTrainID(event.train))..", train.id:"..tostring(event.train.id))
  if event.train and event.train.valid and GetTrainID(event.train) then
    UpdateTrain(event.train)
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
  -- rename deliveries if no other stop old_name exists
  if renameDeliveries then
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

  if event.entity.name == "logistic-train-stop" then
    --log("(on_entity_renamed) uid:"..uid..", old name: "..oldName..", new name: "..newName)
    renamedStop(uid, oldName, newName)
  end
end)

script.on_event(defines.events.on_pre_entity_settings_pasted, function(event)
  local uid = event.destination.unit_number
  local oldName = event.destination.backer_name
  local newName = event.source.backer_name

  if event.destination.type == "train-stop" then
    RemoveStopName(uid, oldName)
    AddStopName(uid, newName)
  end

  if event.destination.name == "logistic-train-stop" then
    --log("(on_pre_entity_settings_pasted) uid:"..uid..", old name: "..oldName..", new name: "..newName)
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
    for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
      if not(delivery.train and delivery.train.valid) then
        if message_level >= 1 then printmsg({"ltn-message.delivery-removed-train-invalid", delivery.from, delivery.to}, delivery.force, false) end
        if debug_log then log("(OnTick) Delivery from "..delivery.from.." to "..delivery.to.." removed. Train no longer valid.") end
        removeDelivery(trainID)
      elseif tick-delivery.started > delivery_timeout then
        if message_level >= 1 then printmsg({"ltn-message.delivery-removed-timeout", delivery.from, delivery.to, tick-delivery.started}, delivery.force, false) end
        if debug_log then log("(OnTick) Delivery from "..delivery.from.." to "..delivery.to.." removed. Timed out after "..tick-delivery.started.."/"..delivery_timeout.." ticks.") end
        removeDelivery(trainID)
      end
    end

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
        return a.age < b.age
      end)

  -- tick 59: find best provider, merge shipments
  elseif global.tickCount == dispatcher_update_interval - 1 then
    if next(global.Dispatcher.availableTrains) ~= nil then -- no need to parse requests without available trains
      global.Dispatcher.Orders = ProcessRequests()
    end

  -- tick 60: find train, generate delivery, reset age
  elseif global.tickCount == dispatcher_update_interval then
    local deliveries = MakeDeliveries(global.Dispatcher.Orders)
    global.Dispatcher.Orders = {}
    global.tickCount = 0 -- reset tick count
  end

  global.tickCount = global.tickCount + 1
end


---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

function removeDelivery(trainID)
  if global.Dispatcher.Deliveries[trainID] then
    for stopID, stop in pairs(global.LogisticTrainStops) do
      for i=#stop.activeDeliveries, 1, -1 do --trainID should be unique => checking matching stop name not required
        if stop.activeDeliveries[i] == trainID then
          table.remove(stop.activeDeliveries, i)
        end
      end
    end
    global.Dispatcher.Deliveries[trainID] = nil
  end
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
        -- workaround for leaving with fluid residue, could time out trains
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

    if stop_timeout > 0 then -- if stop_timeout is set add inactivity condition
      record.wait_conditions[#record.wait_conditions+1] = {type = "inactivity", compare_type = "or", ticks = stop_timeout } -- send stuck trains away
    end
  elseif condType == "inactivity" then
    record.wait_conditions[#record.wait_conditions+1] = {type = condType, compare_type = "and", ticks = condComp }
  end
  return record
end


do --ProcessRequest
-- return all stations providing item, ordered by priority and item-count
local function GetProviders(requestStation, item, req_count, provider_merged_count ,min_length, max_length)
  local stations = {}
  local providers = global.Dispatcher.Provided[item]
  if not providers then
    return nil
  end
  local toID = requestStation.entity.unit_number
  local force = requestStation.entity.force

  for stopID, count in pairs (providers) do
    local stop = global.LogisticTrainStops[stopID]
    if stop and stop.entity.force.name == force.name
    and count >= stop.minProvided
    and (stop.minTraincars == 0 or max_length == 0 or stop.minTraincars <= max_length)
    and (stop.maxTraincars == 0 or min_length == 0 or stop.maxTraincars >= min_length) then --check if provider can actually service trains from requester
      local activeDeliveryCount = #stop.activeDeliveries
      if activeDeliveryCount and (stop.trainLimit == 0 or activeDeliveryCount < stop.trainLimit) then
        local merged_count = provider_merged_count[stopID..","..toID] or 0
        if debug_log then log("found "..count.."("..tostring(stop.minProvided)..")".."/"..req_count.." ".. item.." at "..stop.entity.backer_name..", priority: "..stop.priority..", used in "..merged_count.." orders, active Deliveries: "..activeDeliveryCount.." minTraincars: "..stop.minTraincars..", maxTraincars: "..stop.maxTraincars..", locked Slots: "..stop.lockedSlots) end
        stations[#stations +1] = {entity = stop.entity, priority = stop.priority, activeDeliveryCount = activeDeliveryCount, merged_count=merged_count, item = item, count = count, minTraincars = stop.minTraincars, maxTraincars = stop.maxTraincars, lockedSlots = stop.lockedSlots}
      end
    end
  end
  -- sort best matching station to the top
  sort(stations, function(a, b)
      if a.activeDeliveryCount ~= b.activeDeliveryCount then --sort by #deliveries 1st
        return a.activeDeliveryCount < b.activeDeliveryCount
      elseif a.priority ~= b.priority then --sort by priority 2nd
        return a.priority > b.priority
      elseif a.merged_count ~= b.merged_count then
        return a.merged_count > b.merged_count
      else
        return a.count > b.count --finally sort by item count
      end
    end)
  return stations
end

-- parse requests from global.Dispatcher.Request={stopID, item, age, count}
-- returns orders = {toID, fromID, minTraincars, maxTraincars, totalStacks, lockedSlots, {loadingList} }
function ProcessRequests()
  local orders = {}
  local provider_merged_count = {}

  for reqIndex, request in pairs (global.Dispatcher.Requests) do
    -- ensure validity of request stop
    local stopID = request.stopID
    local requestStation = global.LogisticTrainStops[stopID]

    if not requestStation or not (requestStation.entity and requestStation.entity.valid) then
      goto skipRequestItem -- station was removed since request was generated
    end

    local toID = requestStation.entity.unit_number
    local to = requestStation.entity.backer_name
    local item = request.item
    local count = request.count

    local minRequested = requestStation.minRequested
    local maxTraincars = requestStation.maxTraincars
    local minTraincars = requestStation.minTraincars
    local requestForce = requestStation.entity.force


    if debug_log then log("request "..reqIndex.."/"..#global.Dispatcher.Requests..": "..count.."("..minRequested..")".." "..item.." to "..requestStation.entity.backer_name.." min length: "..minTraincars.." max length: "..maxTraincars ) end

    if requestStation.trainLimit > 0 and #requestStation.activeDeliveries >= requestStation.trainLimit then
      if debug_log then log(requestStation.entity.backer_name.." Request station train limit reached: "..#requestStation.activeDeliveries.."("..requestStation.trainLimit..")" ) end
      goto skipRequestItem -- reached train limit
    end

    -- find providers for requested item
    local itype, iname = match(item, "([^,]+),([^,]+)")
    if not (itype and iname and (game.item_prototypes[iname] or game.fluid_prototypes[iname])) then
      if message_level >= 1 then printmsg({"ltn-message.error-parse-item", item}, requestForce) end
      if debug_log then log("(ProcessRequests) could not parse "..item) end
      goto skipRequestItem
    end

    local localname
    if itype=="fluid" then
      localname = game.fluid_prototypes[iname].localised_name
    else
      localname = game.item_prototypes[iname].localised_name
    end

    -- get providers ordered by priority
    local providers = GetProviders(requestStation, item, count, provider_merged_count, minTraincars, maxTraincars)
    if not providers or #providers < 1 then
      if requestStation.noWarnings == false and message_level >= 2 then printmsg({"ltn-message.no-provider-found", localname}, requestForce, true) end
      if debug_log then log("No station supplying "..item.." found.") end
      goto skipRequestItem
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

    -- limit count to availability of highest priority provider
    local deliverySize = count
    if count > providerStation.count then
      deliverySize = providerStation.count
    end

    local stacks = deliverySize -- for fluids stack = tanker capacity
    if itype == "item" then
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


    local insertnew = true
    local loadingList = {type=itype, name=iname, localname=localname, count=deliverySize, stacks=stacks}

    -- reserve amount from picked provider
    -- might be bigger than necessary, but we havn't merged orders and looked up available train capacity
    global.Dispatcher.Provided[item][fromID] = global.Dispatcher.Provided[item][fromID] - deliverySize

    -- try inserting into existing order
    if itype == "item" then
      for i=1, #orders do
        if orders[i].loadingList[1].type == "item" and orders[i].fromID == fromID and orders[i].toID == toID then
          orders[i].loadingList[#orders[i].loadingList+1] = loadingList
          orders[i].totalStacks = orders[i].totalStacks + stacks
          provider_merged_count[fromID..","..toID] = provider_merged_count[fromID..","..toID] + 1
          insertnew = false
          if debug_log then log("inserted into order "..i.."/"..#orders.." "..from.." >> "..to..": "..deliverySize.." in "..stacks.."/"..orders[i].totalStacks.." stacks "..itype..","..iname.." min length: "..minTraincars.." max length: "..maxTraincars) end
          break
        end
      end
    end
    -- create new order for fluids and different provider-requester pairs
    if insertnew then
      orders[#orders+1] = {toID=toID, fromID=fromID, minTraincars=minTraincars, maxTraincars=maxTraincars, totalStacks=stacks, lockedSlots=providerStation.lockedSlots, loadingList={loadingList} }
      provider_merged_count[fromID..","..toID] = 1
      if debug_log then log("added new order "..#orders.." "..from.." >> "..to..": "..deliverySize.." in "..stacks.." stacks "..itype..","..iname.." min length: "..minTraincars.." max length: "..maxTraincars) end
    end

    ::skipRequestItem:: -- use goto since lua doesn't know continue
  end -- for global.Dispatcher.Requests

  return orders
end

end

do --MakeDeliveries
local InventoryLookup = { --preoccupy table with wagons to ignore at 0 capacity
  ["rail-tanker"] = 0
}

local function getInventorySize(entity)
  local capacity = 0
  if entity.type == "cargo-wagon" then
    capacity = entity.prototype.get_inventory_size(defines.inventory.cargo_wagon)
  elseif entity.type == "fluid-wagon" then
    for n=1, #entity.fluidbox do
      capacity = capacity + entity.fluidbox.get_capacity(n)
    end
  end
  --log("(getInventorySize) adding "..entity.name.." capcacity: "..capacity)
  InventoryLookup[entity.name] = capacity
  return capacity
end

local function getTrainInventorySize(train, type, reserved)
  local inventorySize = 0
  local fluidCapacity = 0
  if not train.valid then
    return inventorySize
  end

  --log("Train "..GetTrainName(train).." carriages: "..#train.carriages..", cargo_wagons: "..#train.cargo_wagons)
  for _,wagon in pairs (train.carriages) do
    if wagon.type ~= "locomotive" then
      local capacity = InventoryLookup[wagon.name] or getInventorySize(wagon)
      --log("(getTrainInventorySize) wagon.name:"..wagon.name.." capacity:"..capacity)
      if wagon.type == "fluid-wagon" then
        fluidCapacity = fluidCapacity + capacity
      else
        inventorySize = inventorySize + capacity - reserved
      end
    end
  end
  if type == "fluid" then
    return fluidCapacity
  end
  return inventorySize
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
local function getFreeTrain(nextStop, minTraincars, maxTraincars, type, size, reserved)
  local train = nil
  if minTraincars == nil or minTraincars < 0 then minTraincars = 0 end
  if maxTraincars == nil or maxTraincars < 0 then maxTraincars = 0 end
  local largestInventory = 0
  local smallestInventory = 0
  local smallestDistance = 0
  for DispTrainKey, DispTrain in pairs (global.Dispatcher.availableTrains) do
    if DispTrain.valid and DispTrain.station then
      local locomotive = GetMainLocomotive(DispTrain)
      if locomotive.force.name == nextStop.force.name then -- train force matches
        local inventorySize = 0
        if (minTraincars == 0 or #DispTrain.carriages >= minTraincars) and (maxTraincars == 0 or #DispTrain.carriages <= maxTraincars) then -- train length fits
          -- get total inventory of train for requested item type
          inventorySize = getTrainInventorySize(DispTrain, type, reserved)
          if inventorySize >= size then
            -- train can be used for delivery
            if inventorySize <= smallestInventory or smallestInventory == 0 then
              local distance = getStationDistance(DispTrain.station, nextStop)
              if distance < smallestDistance or smallestDistance == 0 then
                smallestDistance = distance
                smallestInventory = inventorySize
                train = {id=DispTrainKey, inventorySize=inventorySize}
                if debug_log then log("(getFreeTrain): found train "..locomotive.backer_name..", length: "..minTraincars.."<="..#DispTrain.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
              end
            end

          elseif smallestInventory == 0 and inventorySize > 0 and (inventorySize >= largestInventory or largestInventory == 0) then
            -- store biggest available train
            local distance = getStationDistance(DispTrain.station, nextStop)
            if distance < smallestDistance or smallestDistance == 0 then
              smallestDistance = distance
              largestInventory = inventorySize
              train = {id=DispTrainKey, inventorySize=inventorySize}
              if debug_log then log("(getFreeTrain): largest available train "..locomotive.backer_name..", length: "..minTraincars.."<="..#DispTrain.carriages.."<="..maxTraincars.. ", inventory size: "..inventorySize.."/"..size..", distance: "..distance) end
            end
          end

        end --train length fits
      end
    else
      -- remove invalid train
      global.Dispatcher.availableTrains[DispTrainKey] = nil
    end
  end
  return train
end

-- sends available trains to run deliveries for given orders
-- returns {trainID} of generated global.Dispatcher.Deliveries[trainID]
function MakeDeliveries(orders)
  local deliveryIDs = {}
  for orderIndex=1, #orders do
    local loadingList = orders[orderIndex].loadingList
    local totalStacks = orders[orderIndex].totalStacks
    local lockedSlots = orders[orderIndex].lockedSlots
    local minTraincars = orders[orderIndex].minTraincars
    local maxTraincars = orders[orderIndex].maxTraincars

    -- get station names
    local toStop = global.LogisticTrainStops[orders[orderIndex].toID]
    local fromStop = global.LogisticTrainStops[orders[orderIndex].fromID]
    if not toStop or not fromStop then
      if message_level >= 1 then printmsg({"ltn-message.error-no-stop"}, requestForce) end
      if debug_log then log("(ProcessRequest) Couldn't get provider or requester stop.") end
      goto skipOrder
    end
    local to = toStop.entity.backer_name
    local from = fromStop.entity.backer_name

    -- find train
    local train = getFreeTrain(fromStop.entity, minTraincars, maxTraincars, loadingList[1].type, totalStacks, lockedSlots)
    if not train then
      if message_level >= 3 then printmsg({"ltn-message.no-train-found-merged", tostring(minTraincars), tostring(maxTraincars), tostring(totalStacks)}, requestForce, true) end
      if debug_log then log("No train with "..tostring(minTraincars).." <= length <= "..tostring(maxTraincars).." to transport "..tostring(totalStacks).." stacks found in Depot.") end
      goto skipOrder
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

    if message_level >= 2 then
      if #loadingList == 1 then
        printmsg({"ltn-message.creating-delivery", from, to, loadingList[1].count, loadingList[1].localname}, requestForce)
      else
        printmsg({"ltn-message.creating-delivery-merged", from, to, totalStacks}, requestForce)
      end
    end

    -- create schedule
    local selectedTrain = global.Dispatcher.availableTrains[train.id]
    local depot = global.LogisticTrainStops[selectedTrain.station.unit_number]
    local schedule = {current = 1, records = {}}
    schedule.records[1] = NewScheduleRecord(depot.entity.backer_name, "inactivity", 120)
    schedule.records[2] = NewScheduleRecord(from, "item_count", ">", loadingList)
    schedule.records[3] = NewScheduleRecord(to, "item_count", "=", loadingList, 0)
    selectedTrain.schedule = schedule

    -- store delivery
    local delivery = {}
    if debug_log then log("Creating Delivery: "..totalStacks.." stacks, "..from.." >> "..to) end
    for i=1, #loadingList do
      delivery[loadingList[i].type..","..loadingList[i].name] = loadingList[i].count

      -- move Requests to the back of the queue
      local ageIndex = loadingList[i].type..","..loadingList[i].name..","..orders[orderIndex].toID
      global.Dispatcher.RequestAge[ageIndex] = nil

      if debug_log then log("  "..loadingList[i].type..", "..loadingList[i].name..", "..loadingList[i].count.." in "..loadingList[i].stacks.." stacks ") end
    end
    global.Dispatcher.Deliveries[train.id] = {force=requestForce, train=selectedTrain, started=game.tick, from=from, to=to, shipment=delivery}
    global.Dispatcher.availableTrains[train.id] = nil

    -- set lamps on stations to yellow
    -- trains will pick a stop by their own logic so we have to parse by name
    for stopID, stop in pairs (global.LogisticTrainStops) do
      if stop.entity.backer_name == from or stop.entity.backer_name == to then
        table.insert(global.LogisticTrainStops[stopID].activeDeliveries, train.id)
      end
    end

    -- add trainID to return value
    deliveryIDs[#deliveryIDs+1] = train.id

    ::skipOrder:: -- use goto since lua doesn't know continue
  end --for orders

  return deliveryIDs
end

end


------------------------------------- TRAIN FUNCTIONS -------------------------------------

-- update stop output when train enters/leaves
function UpdateTrain(train)
  local trainForce = nil
  local loco = GetMainLocomotive(train)
  if loco then trainForce = loco.force end
  local trainID = GetTrainID(train)
  local trainName = GetTrainName(train)

  if not trainID then --train has no locomotive
    if debug_log then log("(UpdateTrain) couldn't assign train id") end
    --TODO: Update all stops?
    return
  end

  -- train arrived at station
  if train.valid and train.manual_mode == false and train.state == defines.train_state.wait_station and train.station ~= nil and train.station.name == "logistic-train-stop" then
    local stopID = train.station.unit_number
    local stop = global.LogisticTrainStops[stopID]
    if stop then
      stop.parkedTrain = train
      stop.parkedTrainID = trainID

      if message_level >= 3 then printmsg({"ltn-message.train-arrived", trainName, stop.entity.backer_name}, trainForce, false) end
      if debug_log then log("Train "..trainName.." arrived at station "..stop.entity.backer_name) end

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
        removeDelivery(trainID)

        -- make train available for new deliveries
        global.Dispatcher.availableTrains[trainID] = train

        -- reset schedule
        local schedule = {current = 1, records = {}}
        schedule.records[1] = NewScheduleRecord(stop.entity.backer_name, "inactivity", 300)
        train.schedule = schedule
        if stop.errorCode == 0 then
          setLamp(stopID, "blue")
        end
      end

      UpdateStopOutput(stop)
      return
    end

  -- train left station
  else
    for stopID, stop in pairs(global.LogisticTrainStops) do
      if stop.parkedTrainID == trainID then

        if stop.isDepot then
          global.Dispatcher.availableTrains[trainID] = nil
          if stop.errorCode == 0 then
            setLamp(stopID, "green")
          end

        else -- normal stop
          local delivery = global.Dispatcher.Deliveries[trainID]
          if delivery then
            -- remove delivery from stop
            for i=#stop.activeDeliveries, 1, -1 do
              if stop.activeDeliveries[i] == trainID then
                table.remove(stop.activeDeliveries, i)
              end
            end
            if delivery.from == stop.entity.backer_name then
              -- update delivery counts to train inventory
              for item, count in pairs (delivery.shipment) do
                local itype, iname = match(item, "([^,]+),([^,]+)")
                if itype and iname and (game.item_prototypes[iname] or game.fluid_prototypes[iname]) then
                  if itype == "item" then
                    local traincount = train.get_item_count(iname)
                    if debug_log then log("(UpdateTrain): updating delivery after train left "..delivery.from..", "..item.." "..tostring(traincount) ) end
                    delivery.shipment[item] = traincount
                  elseif itype == "fluid" then
                    local traincount = train.get_fluid_count(iname)
                    if debug_log then log("(UpdateTrain): updating delivery after train left "..delivery.from..", "..item.." "..tostring(traincount) ) end
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
            end
          end
        end

        -- remove train reference
        stop.parkedTrain = nil
        stop.parkedTrainID = nil
        if message_level >= 3 then printmsg({"ltn-message.train-left", trainName, stop.entity.backer_name}, trainForce) end
        if debug_log then log("Train "..trainName.." left station "..stop.entity.backer_name) end
        UpdateStopOutput(stop)
        return
      end
    end
  end
end

------------------------------------- STOP FUNCTIONS -------------------------------------

do --UpdateStop
local function getCircuitValues(entity)
  local greenWire = entity.get_circuit_network(defines.wire_type.green)
  local redWire =  entity.get_circuit_network(defines.wire_type.red)
  local items = {}
  if greenWire and greenWire.signals then
    for _, v in pairs(greenWire.signals) do
      if v.signal.type ~= "virtual" or ControlSignals[v.signal.name] then
        items[v.signal.type..","..v.signal.name] = v.count
      end
    end
  end
  if redWire and redWire.signals then
    for _, v in pairs(redWire.signals) do
      if v.signal.type ~= "virtual" or ControlSignals[v.signal.name] then
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

  -- reject any stop not in name list
  if not global.TrainStopNames[stop.entity.backer_name] then
    stop.errorCode = 2
    if message_level >= 1 then printmsg({"ltn-message.error-invalid-stop", stop.entity.backer_name}) end
    if debug_log then log("(UpdateStop) Stop not in list global.TrainStopNames: "..stop.entity.backer_name) end
    return
  end

  local stopForce = stop.entity.force

  -- remove invalid trains
  if stop.parkedTrain and not stop.parkedTrain.valid then
    global.LogisticTrainStops[stopID].parkedTrain = nil
    global.LogisticTrainStops[stopID].parkedTrainID = nil
  end

  -- get circuit values
  local circuitValues = getCircuitValues(stop.input)
  if not circuitValues then
    return
  end

  -- read configuration signals and remove them from the signal list (should leave only item and fluid signal types)
  local isDepot = circuitValues["virtual,"..ISDEPOT] or 0
  circuitValues["virtual,"..ISDEPOT] = nil
  local minTraincars = circuitValues["virtual,"..MINTRAINLENGTH] or 0
  circuitValues["virtual,"..MINTRAINLENGTH] = nil
  local maxTraincars = circuitValues["virtual,"..MAXTRAINLENGTH] or 0
  circuitValues["virtual,"..MAXTRAINLENGTH] = nil
  local trainLimit = circuitValues["virtual,"..MAXTRAINS] or 0
  circuitValues["virtual,"..MAXTRAINS] = nil
  local minRequested = circuitValues["virtual,"..MINREQUESTED] or min_requested
  circuitValues["virtual,"..MINREQUESTED] = nil
  local noWarnings = circuitValues["virtual,"..NOWARN] or 0
  circuitValues["virtual,"..NOWARN] = nil
  local minProvided = circuitValues["virtual,"..MINPROVIDED] or min_provided
  circuitValues["virtual,"..MINPROVIDED] = nil
  local priority = circuitValues["virtual,"..PRIORITY] or 0
  circuitValues["virtual,"..PRIORITY] = nil
  local lockedSlots = circuitValues["virtual,"..LOCKEDSLOTS] or 0
  circuitValues["virtual,"..LOCKEDSLOTS] = nil
  -- check if it's a depot
  if isDepot > 0 then
    stop.isDepot = true

    -- reset duplicate name error
    if stop.errorCode == 2 then
      stop.errorCode = 0
    end

    -- add parked train to available trains
    if stop.parkedTrainID and stop.parkedTrain.valid and not global.Dispatcher.Deliveries[stop.parkedTrainID] then
      global.Dispatcher.availableTrains[stop.parkedTrainID] = stop.parkedTrain
    end

    if detectShortCircuit(stop) then
      -- signal error
      global.LogisticTrainStops[stopID].errorCode = 1
      setLamp(stopID, ErrorCodes[1])
    else
      -- signal error fixed, depots ignore all other errors
      global.LogisticTrainStops[stopID].errorCode = 0

      -- reset signal parameters just in case something goes wrong
      global.LogisticTrainStops[stopID].minProvided = nil
      global.LogisticTrainStops[stopID].minRequested = nil
      global.LogisticTrainStops[stopID].minTraincars = 0
      global.LogisticTrainStops[stopID].maxTraincars = 0
      global.LogisticTrainStops[stopID].trainLimit = 0
      global.LogisticTrainStops[stopID].priority = 0
      global.LogisticTrainStops[stopID].lockedSlots = 0
      global.LogisticTrainStops[stopID].noWarnings = 0

      if stop.parkedTrain then
        setLamp(stopID, "blue")
      else
        setLamp(stopID, "green")
      end
    end

  -- not a depot > check if the name is unique
  elseif #global.TrainStopNames[stop.entity.backer_name] == 1 then
    stop.isDepot = false

    -- reset duplicate name error
    if stop.errorCode == 2 then
      stop.errorCode = 0
    end

    -- remove parked train from available trains
    if stop.parkedTrainID then
      global.Dispatcher.availableTrains[stop.parkedTrainID] = nil
    end

    -- update input signals of stop
    if detectShortCircuit(stop) then
      -- signal error
      global.LogisticTrainStops[stopID].errorCode = 1
      setLamp(stopID, ErrorCodes[1])
    else
      -- signal error fixed
      global.LogisticTrainStops[stopID].errorCode = 0
      for item, count in pairs (circuitValues) do
        for trainID, delivery in pairs (global.Dispatcher.Deliveries) do
          local deliverycount = delivery.shipment[item]
          if deliverycount then
            if stop.parkedTrain and stop.parkedTrainID == trainID then
              -- calculate items +- train inventory
              local itype, iname = match(item, "([^,]+),([^,]+)")
              if itype and iname then
                local traincount = 0
                if itype == "fluid" then
                  traincount = stop.parkedTrain.get_fluid_count(iname)
                else
                  traincount = stop.parkedTrain.get_item_count(iname)
                end

                if delivery.to == stop.entity.backer_name then
                  local newcount = count + traincount
                  if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
                  if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." updating requested count with train inventory: "..item.." "..count.."+"..traincount.."="..newcount) end
                  count = newcount
                elseif delivery.from == stop.entity.backer_name then
                  if traincount <= deliverycount then
                    local newcount = count - (deliverycount - traincount)
                    if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
                    if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." updating provided count with train inventory: "..item.." "..count.."-"..deliverycount - traincount.."="..newcount) end
                    count = newcount
                  else --train loaded more than delivery
                    if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." updating delivery count with overloaded train inventory: "..item.." "..traincount) end
                    -- update delivery to new size
                    global.Dispatcher.Deliveries[trainID].shipment[item] = traincount
                  end
                end
              end

            else
              -- calculate items +- deliveries
              if delivery.to == stop.entity.backer_name then
                local newcount = count + deliverycount
                if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
                if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." updating requested count with delivery: "..item.." "..count.."+"..deliverycount.."="..newcount) end
                count = newcount
              elseif delivery.from == stop.entity.backer_name and not delivery.pickupDone then
                local newcount = count - deliverycount
                if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
                if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." updating provided count with delivery: "..item.." "..count.."-"..deliverycount.."="..newcount) end
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
          if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." provides "..item.." "..count.."("..minProvided..")") end
        elseif count*-1 >= minRequested then
          count = count * -1
          -- requestItems[item] = count
          local ageIndex = item..","..stopID
          global.Dispatcher.RequestAge[ageIndex] = global.Dispatcher.RequestAge[ageIndex] or game.tick
          global.Dispatcher.Requests[#global.Dispatcher.Requests+1] = {age = global.Dispatcher.RequestAge[ageIndex], stopID = stopID, item = item, count = count}
          if debug_log then log("(UpdateStop) "..stop.entity.backer_name.." requests "..item.." "..count.."("..minRequested..")"..", age: "..global.Dispatcher.RequestAge[ageIndex].."/"..game.tick) end
        end

      end -- for circuitValues

      global.LogisticTrainStops[stopID].minProvided = minProvided
      global.LogisticTrainStops[stopID].minRequested = minRequested
      global.LogisticTrainStops[stopID].minTraincars = minTraincars
      global.LogisticTrainStops[stopID].maxTraincars = maxTraincars
      global.LogisticTrainStops[stopID].trainLimit = trainLimit
      global.LogisticTrainStops[stopID].priority = priority
      global.LogisticTrainStops[stopID].lockedSlots = lockedSlots
      if noWarnings > 0 then
        global.LogisticTrainStops[stopID].noWarnings = true
      else
        global.LogisticTrainStops[stopID].noWarnings = false
      end

      -- create Requests {stopID, age, itemlist={[item], count}}
      -- global.Dispatcher.Requests[#global.Dispatcher.Requests+1] = {age = global.Dispatcher.RequestAge[stopID], stopID = stopID, itemlist = requestItems}

      if #stop.activeDeliveries > 0 then
        setLamp(stopID, "yellow")
      else
        setLamp(stopID, "green")
      end

    end --if detectShortCircuit(stop)

  else
    -- duplicate stop name error
    global.LogisticTrainStops[stopID].errorCode = 2
    setLamp(stopID, ErrorCodes[2])
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
function setLamp(stopID, color)
  if ColorLookup[color] and global.LogisticTrainStops[stopID] then
    global.LogisticTrainStops[stopID].lampControl.get_control_behavior().parameters = {parameters={{index = 1, signal = {type="virtual",name=ColorLookup[color]}, count = 1 }}}
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
      if debug_log then log("(UpdateStopOutput) Inventory of train "..tostring(trainStop.parkedTrain).." at stop "..tostring(trainStop.entity.backer_name).." exceeds stop output limit of "..trainStop.output.get_control_behavior().signals_count.." by "..index-#signals.." signals.") end
    end
    trainStop.output.get_control_behavior().parameters = {parameters=signals}
  else
    trainStop.output.get_control_behavior().parameters = nil
  end
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

--local square = math.sqrt
function GetDistance(a, b)
  local x, y = a.x-b.x, a.y-b.y
  --return square(x*x+y*y) -- sqrt shouldn't be necessary for comparing distances
  return (x*x+y*y)
end
