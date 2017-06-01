log_level = tonumber(string.sub(settings.global["ltn-interface-log-level"].value, 1, 1))
log_output = settings.global["ltn-interface-log-output"].value
message_filter_age = settings.global["ltn-interface-message-filter-age"].value
min_requested = settings.global["ltn-dispatcher-requester-threshold"].value
min_provided = settings.global["ltn-dispatcher-provider-threshold"].value
stop_timeout = settings.global["ltn-dispatcher-stop-timeout"].value
delivery_timeout = settings.global["ltn-dispatcher-delivery-timeout"].value
finish_loading = settings.global["ltn-dispatcher-finish-loading"].value

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if not event then return end
  if event.setting == "ltn-interface-log-level" then log_level = tonumber(string.sub(settings.global["ltn-interface-log-level"].value, 1, 1)) end
  if event.setting == "ltn-interface-log-output" then log_output = settings.global["ltn-interface-log-output"].value end
  if event.setting == "ltn-interface-message-filter-age" then message_filter_age = settings.global["ltn-interface-message-filter-age"].value end
  if event.setting == "ltn-dispatcher-requester-threshold" then min_requested = settings.global["ltn-dispatcher-requester-threshold"].value end
  if event.setting == "ltn-dispatcher-provider-threshold" then min_provided = settings.global["ltn-dispatcher-provider-threshold"].value end
  if event.setting == "ltn-dispatcher-stop-timeout" then  stop_timeout = settings.global["ltn-dispatcher-stop-timeout"].value end
  if event.setting == "ltn-dispatcher-delivery-timeout" then delivery_timeout = settings.global["ltn-dispatcher-delivery-timeout"].value end
  if event.setting == "ltn-dispatcher-finish-loading" then finish_loading = settings.global["ltn-dispatcher-finish-loading"].value end
end)

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

  local tick = game.tick

  -- print message
  if global.messageBuffer[msgKey] == nil or not useFilter then
    if log_output == "console" or log_output == "console & logfile" then
      if force and force.valid then
        force.print(msg)
      else
        game.print(msg)
      end
    end
    if log_output == "logfile" or log_output == "console & logfile" then
      log("[LTN] " .. msgKey)
    end
  end

  -- store message in buffer
  global.messageBuffer[msgKey] = global.messageBuffer[msgKey] or {tick=tick}
end

return printmsg