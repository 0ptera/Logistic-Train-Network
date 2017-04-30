-- set notification level
-- 4: everything, 3: scheduler messages, 2: basic messages (default), 1 errors only, 0: off
--log_level = 2

-- set notification target
-- console: in game console, log: logfile in factorio root directory, both: default
--log_output = "both"

-- message age in ticks before filtered messages are shown again
-- default 18000 = 5min
--message_filter_age = 18000

-- update interval in ticks
-- default 60
dispatcher_update_interval = 60

-- min amount of items/fluids to trigger a delivery, can be overridden individually with min delivery size for each requesting stop
-- default 1000
--min_delivery_size = 1000

-- Prevent trains from leaving while inserters are working by adding 2s inactivity to all (un-)loading stations.
-- default true
--finish_loading = true

-- duration in ticks of inactivity before leaving (un-)loading stations (timeout)
-- default 7200 = 2min
-- off 0: trains will wait forever to (un-)load
--stop_timeout = 7200

-- duration in ticks deliveries can take before assuming the train was lost
-- default 18000 = 5min
--delivery_timeout = 18000

-- when false provider stations holding less than request stations min_delivery_size are ignored
-- default false
--use_Best_Effort = false
