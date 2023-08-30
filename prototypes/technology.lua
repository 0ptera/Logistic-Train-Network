--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

data:extend({
  {
    type = "technology",
    name = "logistic-train-network",
    icon = "__LogisticTrainNetwork__/graphics/technology/ltn_technology.png",
    icon_size = 256,
    icon_mipmaps = 4,
    prerequisites = {"automated-rail-transportation", "circuit-network"},
    effects =
    {
      {
        type = "unlock-recipe",
        recipe = "logistic-train-stop"
      }
    },
    unit =
    {
      count = 300,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      time = 30
    },
    order = "c-g-c"
  }
})

-- support for cargo ship ports
if mods["cargo-ships"] then
    data:extend({
      {
        type = "technology",
        name = "logistic-ship-network",
        icon = "__LogisticTrainNetwork__/graphics/technology/lsn_technology.png",
        icon_size = 128,
        icon_mipmaps = 1,
        prerequisites = {"circuit-network", "automated_water_transport" },
        effects =
        {
          {
            type = "unlock-recipe",
            recipe = "ltn-port"
          }
        },
        unit =
        {
          count = 300,
          ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1}
          },
          time = 30
        },
        order = "c-g-d"
      }
    })
end
