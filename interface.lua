
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
            global.log_level = level
            remote.call('LTN', 'log_status')
        end,

        log_output = function(log_set)
            if log_set == nil or type(log_set) ~= 'string' then
                game.player.print("[LTN] log_output: Wrong parameter type")
                return
            end
            if log_set == "console" or log_set == "log" or log_set == "both" then
              global.log_output = log_set
              remote.call('LTN', 'log_status')
            else
              game.player.print("[LTN] log_output: Wrong parameter "..log_set)
              return
            end
        end,
        
        log_status = function()
            game.player.print("[LTN] <log_status> log-level: " .. global.log_level .. " - log-output: " .. global.log_output)
        end
    }
)


function printmsg(msg)
  if global.lastMessage == msg then
    -- don't spam the same message
    return
  end
  global.lastMessage = msg
  if global.log_output == "console" or global.log_output == "both" then
    game.print("[LTN] " .. msg)
  end
  if global.log_output == "log" or global.log_output == "both" then
    log("[LTN] " .. msg)
  end
end

return printmsg