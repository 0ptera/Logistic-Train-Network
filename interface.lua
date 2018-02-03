message_level = tonumber(string.sub(settings.global["ltn-interface-console-level"].value, 1, 1))
message_filter_age = settings.global["ltn-interface-message-filter-age"].value
debug_log = settings.global["ltn-interface-debug-logfile"].value
min_requested = settings.global["ltn-dispatcher-requester-threshold"].value
min_provided = settings.global["ltn-dispatcher-provider-threshold"].value
depot_inactivity = settings.global["ltn-dispatcher-depot-inactivity"].value
stop_timeout = settings.global["ltn-dispatcher-stop-timeout"].value
delivery_timeout = settings.global["ltn-dispatcher-delivery-timeout"].value
finish_loading = settings.global["ltn-dispatcher-finish-loading"].value
requester_delivery_reset = settings.global["ltn-dispatcher-requester-delivery-reset"].value
dispatcher_enabled = settings.global["ltn-dispatcher-enabled"].value
reset_filters = settings.global["ltn-depot-reset-filters"].value


script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if not event then return end
  if event.setting == "ltn-interface-console-level" then message_level = tonumber(string.sub(settings.global["ltn-interface-console-level"].value, 1, 1)) end
  if event.setting == "ltn-interface-message-filter-age" then message_filter_age = settings.global["ltn-interface-message-filter-age"].value end
  if event.setting == "ltn-interface-debug-logfile" then debug_log = settings.global["ltn-interface-debug-logfile"].value end
  if event.setting == "ltn-dispatcher-requester-threshold" then min_requested = settings.global["ltn-dispatcher-requester-threshold"].value end
  if event.setting == "ltn-dispatcher-provider-threshold" then min_provided = settings.global["ltn-dispatcher-provider-threshold"].value end
  if event.setting == "ltn-dispatcher-depot-inactivity" then  depot_inactivity = settings.global["ltn-dispatcher-depot-inactivity"].value end
  if event.setting == "ltn-dispatcher-stop-timeout" then  stop_timeout = settings.global["ltn-dispatcher-stop-timeout"].value end
  if event.setting == "ltn-dispatcher-delivery-timeout" then delivery_timeout = settings.global["ltn-dispatcher-delivery-timeout"].value end
  if event.setting == "ltn-dispatcher-finish-loading" then finish_loading = settings.global["ltn-dispatcher-finish-loading"].value end
  if event.setting == "ltn-dispatcher-requester-delivery-reset" then requester_delivery_reset = settings.global["ltn-dispatcher-requester-delivery-reset"].value end
  if event.setting == "ltn-dispatcher-enabled" then dispatcher_enabled = settings.global["ltn-dispatcher-enabled"].value end
  if event.setting == "ltn-depot-reset-filters" then reset_filters = settings.global["ltn-depot-reset-filters"].value end
end)

-- write msg to console for all member of force
-- skips over any duplicate messages (clearing filter is done in on_tick)
function printmsg(msg, force, useFilter)
  local msgKey = ""
  if force and force.valid then
    msgKey = force.name..", "
  else
    msgKey = "all, "
  end
  if type(msg) == "table" then
    for k, v in pairs(msg) do
      if type(v) == "table" then
        msgKey = msgKey..v[1]..", "
      elseif type(v) == "string" then
        msgKey = msgKey..v..", "
      end
    end
  else
    msgKey = msg
  end

  -- print message
  if global.messageBuffer[msgKey] == nil or not useFilter then
    if force and force.valid then
      force.print(msg)
    else
      game.print(msg)
    end
  end

  -- add current tick to messageBuffer if msgKey doesn't exist
  global.messageBuffer[msgKey] = global.messageBuffer[msgKey] or {tick = game.tick}
end

return printmsg