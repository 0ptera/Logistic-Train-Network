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
    script.on_event(remote.call("logistic-train-network", "on_stops_updated"), OnStopsUpdated)
    script.on_event(remote.call("logistic-train-network", "on_dispatcher_updated"), OnDispatcherUpdated)
  end
end)

script.on_load(function(data)
  -- register events from LTN
  if remote.interfaces["logistic-train-network"] then
    script.on_event(remote.call("logistic-train-network", "on_stops_updated"), OnStopsUpdated)
    script.on_event(remote.call("logistic-train-network", "on_dispatcher_updated"), OnDispatcherUpdated)
    --[[ alternative anonymous function: 
         has to be copied between on_init and on_load
         script.on_event(remote.call("logistic-train-network", "on_stops_updated"), function(event)
           do something with event.data
         end)
     ]]
  end
end)
