data:extend({
    {
      type = "item-subgroup",
      name = "trainstop-upgrade",
      group = "logistics",
      order = "b",
    },
    {
      type = "upgrade-item",
      name = "trainstop-upgrade",
      icon = "__LogisticTrainNetwork__/graphics/icons/train-stop.png",
      icon_size = 64, icon_mipmaps = 4,
      subgroup = "trainstop-upgrade",
      order = "a[train-stop]-b[logistic]",
      stack_size = 1,
      stackable = false,
      draw_label_for_cursor_render = true,
      selection_color = {0, 1, 0},
      alt_selection_color = {0.7, 0.7, 0},
      selection_mode = {"any-entity"},
      alt_selection_mode = {"any-entity"},
      selection_cursor_box_type = "copy",
      alt_selection_cursor_box_type = "copy",
      upgrade_target = "logistic-train-stop",
      upgrade_from = {"train-stop"}
    },
  })
