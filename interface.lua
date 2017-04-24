remote.add_interface("LTN",
    {
        help = function()
            game.player.print("-----  LogisticTrainNetwork: Remote functions  -----")
            game.player.print("|  remote.call('LTN', 'help')  - This help")
            game.player.print("|  remote.call('LTN', 'log_level', level)  - Set Log-Level to level n.")
            game.player.print("|     4: everything, 3: scheduler messages, 2: basic messages, 1 errors only, 0: off")
            game.player.print("|  remote.call('LTN', 'log_output', 'console, log, both') - A set: 'console,log' or 'log' or 'console'")
            game.player.print("|  remote.call('LTN', 'log_status') - show current log status")
            game.player.print("")
        end,

        log_level = function(level)
            if level == nil or type(level) ~= 'number' then
                game.player.print("[LTN] log_level: Wrong parameter type")
                return
            end
            log_level = level
            game.player.print("[LTN] Warning! Having different log settings will cause desync. Use log_level in config.lua for MP instead.")
            remote.call('LTN', 'log_status')
        end,

        log_output = function(log_set)
            if log_set == nil or type(log_set) ~= 'string' then
                game.player.print("[LTN] log_output: Wrong parameter type")
                return
            end
            if log_set == "console" or log_set == "log" or log_set == "both" then
              log_output = log_set
              game.player.print("[LTN] Warning! Having different log settings will cause desync. Use log_level in config.lua for MP instead.")
              remote.call('LTN', 'log_status')
            else
              game.player.print("[LTN] log_output: Wrong parameter "..log_set)
              return
            end
        end,

        log_status = function()
            game.player.print("[LTN] <log_status> log-level: " .. log_level .. " - log-output: " .. log_output)
        end
    }
)

function printmsg(msg, useFilter)
  local msgKey = ""
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
    if log_output == "console" or log_output == "both" then
      game.print(msg)
    end
    if log_output == "log" or log_output == "both" then
      log("[LTN] " .. msgKey)
    end
  end

  -- store message in buffer
  global.messageBuffer[msgKey] = global.messageBuffer[msgKey] or {tick=tick}
end

return printmsg, log_output, log_level