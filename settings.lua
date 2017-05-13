data:extend({
  {
    type = "string-setting",
    name = "ltn-interface-log-level",
    order = "aa",
    setting_type = "runtime-global",
    default_value = "2: notifications",
    allowed_values =  {"0: off", "1: errors", "2: notifications", "3: expanded scheduler messages", "4: debug"}
  },
  {
    type = "string-setting",
    name = "ltn-interface-log-output",
    order = "ab",
    setting_type = "runtime-global",
    default_value = "console & logfile",
    allowed_values = {"console & logfile", "console", "logfile"}
  },
  {
    type = "int-setting",
    name = "ltn-interface-message-filter-age",
    order = "ac",
    setting_type = "runtime-global",
    default_value = 18000,
    minimum_value = 0
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-min-delivery-size",
    order = "bb",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1
  },
  {
    type = "bool-setting",
    name = "ltn-dispatcher-use-best-effort",
    order = "bc",
    setting_type = "runtime-global",
    default_value = false
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
  {
    type = "bool-setting",
    name = "ltn-stop-show-expected-inventory",
    order = "da",
    setting_type = "runtime-global",
    default_value = false
  }
})