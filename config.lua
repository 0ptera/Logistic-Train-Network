station_update_interval = 60      -- update interval in tick for reading circuit values at stops
dispatcher_update_interval = 60   -- update interval in tick for generating deliveries and sending them to trains as schedules
min_delivery_size = 1000          -- min amount of items/fluids to trigger a delivery, can be overridden individually with min delivery size for each requesting stop
delivery_timeout = 18000          -- duration in ticks deliveries can take before assuming the train was lost (default 18000 = 5min)
use_Best_Effort = true            -- when false provider stations holding less than request stations min_delivery_size are ignored
