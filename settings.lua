data:extend({
  {
    type = "bool-setting",
    name = "ltn-dispatcher-enabled",
    order = "a",
    setting_type = "runtime-global",
		default_value = true
  },
  {
    type = "string-setting",
    name = "ltn-interface-console-level",
    order = "aa",
    setting_type = "runtime-global",
    default_value = "2: Notifications",
    allowed_values =  {"0: Off", "1: Errors & Warnings", "2: Notifications", "3: Detailed Messages"}
  },
  {
    type = "int-setting",
    name = "ltn-interface-message-filter-age",
    order = "ab",
    setting_type = "runtime-global",
    default_value = 18000,
    minimum_value = 0,
    maximum_value = 4294967295, -- prevent 32bit signed overflow
  },
	{
    type = "bool-setting",
    name = "ltn-interface-debug-logfile",
    order = "ac",
    setting_type = "runtime-global",
		default_value = false
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-requester-threshold",
    order = "ba",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1,
    maximum_value = 4294967295, -- prevent 32bit signed overflow
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-provider-threshold",
    order = "bb",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1,
    maximum_value = 4294967295, -- prevent 32bit signed overflow
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-depot-inactivity",
    order = "ca",
    setting_type = "runtime-global",
    default_value = 300, --5s
    minimum_value = 60, --1s
    maximum_value = 4294967295, -- prevent 32bit signed overflow
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-stop-timeout",
    order = "cb",
    setting_type = "runtime-global",
    default_value = 7200, --2min
    minimum_value = 0, --0:off
    maximum_value = 216000, -- 60min
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-delivery-timeout",
    order = "cc",
    setting_type = "runtime-global",
    default_value = 18000, --5min
    minimum_value = 3600, -- 1min
    maximum_value = 216000, -- 60min
  },
  {
    type = "bool-setting",
    name = "ltn-dispatcher-requester-delivery-reset",
    order = "cd",
    setting_type = "runtime-global",
    default_value = false
  },
  {
    type = "bool-setting",
    name = "ltn-dispatcher-finish-loading",
    order = "ce",
    setting_type = "runtime-global",
    default_value = true
  },
  {
    type = "bool-setting",
    name = "ltn-depot-reset-filters",
    order = "da",
    setting_type = "runtime-global",
    default_value = true
  },
})