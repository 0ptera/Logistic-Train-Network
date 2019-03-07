-- LTN interface event functions
function OnStopsUpdated(event)
  if event.data then
    log("Stop Data:"..serpent.block(event) )
  end
end

function OnDispatcherUpdated(event)
  if event.data then
    log("Dispatcher Data:"..serpent.block(event) )
  end
end

---- Initialisation  ----
script.on_init(function()
  -- register events from LTN
  if remote.interfaces["logistic-train-network"] then
    script.on_event(remote.call("logistic-train-network", "get_on_stops_updated_event"), OnStopsUpdated)
    script.on_event(remote.call("logistic-train-network", "get_on_dispatcher_updated_event"), OnDispatcherUpdated)
  end
end)

script.on_load(function(data)
  -- register events from LTN
  if remote.interfaces["logistic-train-network"] then
    script.on_event(remote.call("logistic-train-network", "get_on_stops_updated_event"), OnStopsUpdated)
    script.on_event(remote.call("logistic-train-network", "get_on_dispatcher_updated_event"), OnDispatcherUpdated)
    --[[ alternative anonymous function: 
         has to be copied between on_init and on_load
         script.on_event(remote.call("logistic-train-network", "get_on_stops_updated_event"), function(event)
           do something with event.data
         end)
     ]]
  end
end)
