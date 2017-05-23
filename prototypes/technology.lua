
data:extend({
  {
    type = "technology",
    name = "logistic-train-network",
    icon = "__LogisticTrainNetwork__/graphics/tech/logistic-train-network.png",
    icon_size = 128,
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
      count = 300,
      ingredients = {
        {"science-pack-1", 1},
        {"science-pack-2", 1}
      },
      time = 30
    },
    order = "c-g-c"
  }
})
