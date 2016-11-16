for i, force in pairs(game.forces) do 
  force.reset_recipes()
  force.reset_technologies()
  
  if force.technologies["logistic-train-network"].researched then
    force.recipes["logistic-train-stop"].enabled = true
  else
    force.recipes["logistic-train-stop"].enabled = false
  end
end
