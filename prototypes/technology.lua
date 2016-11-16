
data:extend({
  {
    type = "technology",
    name = "logistic-train-network",
    icon = "__"..MOD_NAME.."__/graphics/icons/logistic-train-network-small.png",
    prerequisites = {"automated-rail-transportation"},
    effects =
    {
      {
        type = "unlock-recipe",
        recipe = "logistic-train-stop"
      }
    },
    unit =
    {
      count = 150,
      ingredients = {
        {"science-pack-1", 1},
        {"science-pack-2", 1},
        {"science-pack-3", 1}
      },
      time = 30
    },
    order = "c-g-c"
  }
})
