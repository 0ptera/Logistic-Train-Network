for i, force in pairs(game.forces) do 
  force.reset_recipes()
  force.reset_technologies()
  
  if force.technologies["automated-rail-transportation"].researched then
    force.recipes["logistic-train-stop"].enabled = true
  end
end
