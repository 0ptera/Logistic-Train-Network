data:extend({
  {
    type = "int-setting",
    name = "ltn-interface-log-level",
    order = "aa",
    setting_type = "runtime-global",
    default_value = 2,
    maximum_value = 4,
    minimum_value = 0,
    per_user = true,
  },
  {
    type = "string-setting",
    name = "ltn-interface-log-output",
    order = "ab",
    setting_type = "runtime-global",
    default_value = "both",
    allowed_values = {"both", "console", "log"},
    per_user = true,
  },
  {
    type = "int-setting",
    name = "ltn-interface-message-filter-age",
    order = "ac",
    setting_type = "runtime-global",
    default_value = 18000,
    minimum_value = 0,
    per_user = true,
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-min-delivery-size",
    order = "bb",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1,
    per_user = true,
  },
  {
    type = "bool-setting",
    name = "ltn-dispatcher-use-best-effort",
    order = "bc",
    setting_type = "runtime-global",
    default_value = false,
    per_user = true,
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-stop-timeout",
    order = "ca",
    setting_type = "runtime-global",
    default_value = 7200,
    minimum_value = 0,
    per_user = true,
  },
  {
    type = "int-setting",
    name = "ltn-dispatcher-delivery-timeout",
    order = "cb",
    setting_type = "runtime-global",
    default_value = 18000,
    minimum_value = 3600,
    per_user = true,
  },
  {
    type = "bool-setting",
    name = "ltn-dispatcher-finish-loading",
    order = "cc",
    setting_type = "runtime-global",
    default_value = true,
    per_user = true,
  }
})