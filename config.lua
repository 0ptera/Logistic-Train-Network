-- update interval in ticks for reading circuit values at stops
-- default 60
station_update_interval = 60

-- update interval in ticks for generating deliveries and sending them to trains as schedules
-- default 60
dispatcher_update_interval = 60

-- min amount of items/fluids to trigger a delivery, can be overridden individually with min delivery size for each requesting stop
-- default 1000
min_delivery_size = 1000

-- duration in ticks deliveries can take before assuming the train was lost 
-- default 18000 = 5min
delivery_timeout = 18000

-- duration in ticks of inactivity before leaving un-loading stations 
-- default 18000 = 30s
-- off 0 (trains will wait forever to un-load
stop_timeout = 18000

-- when false provider stations holding less than request stations min_delivery_size are ignored
-- default true
use_Best_Effort = true            
