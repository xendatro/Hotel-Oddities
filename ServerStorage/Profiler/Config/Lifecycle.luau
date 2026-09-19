-- Select the game's adapter here. Removing its scenario pack leaves the core usable.
local pack = script.Parent.Parent.Scenarios:FindFirstChild("HotelOddities")
return if pack and pack:FindFirstChild("Lifecycle") then require(pack.Lifecycle) else {Id="none",Version=1}
