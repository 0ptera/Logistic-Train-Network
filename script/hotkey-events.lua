script.on_event("ltn-toggle-dispatcher", function(event)
  local player = game.get_player(event.player_index)

  local enabled = settings.global["ltn-dispatcher-enabled"].value
  if enabled then
    settings.global["ltn-dispatcher-enabled"] = {value = false}
    printmsg({"ltn-message.dispatcher-disabled", player.name}, nil, false)
  else
    settings.global["ltn-dispatcher-enabled"] = {value = true}
    printmsg({"ltn-message.dispatcher-enabled", player.name}, nil, false)
  end
end)