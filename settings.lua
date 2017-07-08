data:extend({
  {
    type = "string-setting",
    name = "ltn-interface-console-level",
    order = "aa",
    setting_type = "runtime-global",
    default_value = "2: notifications",
    allowed_values =  {"0: off", "1: errors", "2: notifications", "3: expanded scheduler messages"}
  },
  {
    type = "int-setting",
    name = "ltn-interface-message-filter-age",
    order = "ab",
    setting_type = "runtime-global",
    default_value = 18000,
    minimum_value = 0
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
    minimum_value = 1
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-provider-threshold",
    order = "bb",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-stop-timeout",
    order = "ca",
    setting_type = "runtime-global",
    default_value = 7200,
    minimum_value = 0
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-delivery-timeout",
    order = "cb",
    setting_type = "runtime-global",
    default_value = 18000,
    minimum_value = 3600
  },
  {
    type = "bool-setting",
    name = "ltn-dispatcher-finish-loading",
    order = "cc",
    setting_type = "runtime-global",
    default_value = true
  },
})