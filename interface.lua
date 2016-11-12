

remote.add_interface("LogTrains",
    {
        help = function()
            game.player.print("-----  LogisticTrains: Remote functions  -----")
            game.player.print("|  remote.call('LogTrains', 'help')  - This help")
            game.player.print("|  remote.call('LogTrains', 'log_level', level)  - Set Log-Level to level n.")
            game.player.print("|     4: prints everything, 3: prints extended messages, 2: prints all Scheduler messages, 1 prints only important messages, 0: off")
            game.player.print("|  remote.call('LogTrains', 'log_output', 'console,log') - A set: 'console,log' or 'log' or 'console'")
            game.player.print("|  remote.call('LogTrains', 'log_status') - show current log status")
            game.player.print("")
        end,

        log_level = function(level)
            global.log_level = level
            remote.call('LogTrains', 'log_status')
        end,

        log_output = function(log_set)
            if log_set == nil or type(log_set) ~= 'string' then
                game.player.print("[LT] log_output: Wrong parameter type")
                return
            end
            local real_set = {}
            for i in string.gmatch(log_set, "[^,]*") do
                if i == 'console' or i == 'log' then
                    real_set[i] = i
                end
            end    
            
            global.log_output = real_set
            remote.call('LogTrains', 'log_status')
        end,
        
        log_status = function()
            local ctab = {}
            local n = 1
            for _, v in pairs(global.log_output) do
                ctab[n] = v
                n = n + 1
            end
            if #ctab == 0 then ctab = {"No Output! Use remote.call('LogTrains', 'help') to see possible settings"} end
            game.player.print("[LT] <log_status> log-level: " .. global.log_level .. " - log-output: " .. table.concat(ctab, ', '))
        end
    }
)


