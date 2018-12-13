for i, force in pairs(game.forces) do 
  force.reset_recipes()
  force.reset_technologies()
  
  if force.technologies["logistic-train-network"].researched then
    force.recipes["logistic-train-stop"].enabled = true
    if force.recipes["ltn-port"] then force.recipes["ltn-port"].enabled = true end
  else
    force.recipes["logistic-train-stop"].enabled = false
    if force.recipes["ltn-port"] then force.recipes["ltn-port"].enabled = false end
  end
end
