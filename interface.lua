
remote.add_interface("LTN",
    {
        help = function()
            game.player.print("-----  LogisticTrainNetwork: Remote functions  -----")
            game.player.print("|  remote.call('LTN', 'help')  - This help")
            game.player.print("|  remote.call('LTN', 'log_level', level)  - Set Log-Level to level n.")
            game.player.print("|     4: prints everything, 3: prints extended messages, 2: prints all Scheduler messages, 1 prints only important messages, 0: off")
            game.player.print("|  remote.call('LTN', 'log_output', 'console,log') - A set: 'console,log' or 'log' or 'console'")
            game.player.print("|  remote.call('LTN', 'log_status') - show current log status")
            game.player.print("")
        end,

        log_level = function(level)
            global.log_level = level
            remote.call('LTN', 'log_status')
        end,

        log_output = function(log_set)
            if log_set == nil or type(log_set) ~= 'string' then
                game.player.print("[LTN] log_output: Wrong parameter type")
                return
            end
            local real_set = {}
            for i in string.gmatch(log_set, "[^,]*") do
                if i == 'console' or i == 'log' then
                    real_set[i] = i
                end
            end    
            
            global.log_output = real_set
            remote.call('LTN', 'log_status')
        end,
        
        log_status = function()
            local ctab = {}
            local n = 1
            for _, v in pairs(global.log_output) do
                ctab[n] = v
                n = n + 1
            end
            if #ctab == 0 then ctab = {"No Output! Use remote.call('LTN', 'help') to see possible settings"} end
            game.player.print("[LTN] <log_status> log-level: " .. global.log_level .. " - log-output: " .. table.concat(ctab, ', '))
        end
    }
)


function printmsg(msg)
  if global.log_output.console then
    game.print("[LTN] " .. msg)
  end
  if global.log_output.log then
    log("[LTN] " .. msg)
  end
end

return printmsg