local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallwayGraph = require(ReplicatedStorage.Modules.HallwayGraph)

export type RouteNode = HallwayGraph.RouteNode

return HallwayGraph
