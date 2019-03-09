--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local ltn_stop = copyPrototype("recipe", "train-stop", "logistic-train-stop")
ltn_stop.ingredients = {
  {"train-stop", 1},
  {"constant-combinator", 1},
  {"small-lamp", 1},
  {"green-wire", 2},
  {"red-wire", 2},
}
ltn_stop.enabled = false

data:extend({
  ltn_stop
})

-- support for cargo ship ports
if mods["cargo-ships"] then
  ltn_port = copyPrototype("recipe", "port", "ltn-port")
  ltn_port.ingredients = {
    {"port", 1},
    {"constant-combinator", 1},
    {"small-lamp", 1},
    {"green-wire", 2},
    {"red-wire", 2},
  }
  ltn_port.enabled = false

  data:extend({
    ltn_port
  })
end