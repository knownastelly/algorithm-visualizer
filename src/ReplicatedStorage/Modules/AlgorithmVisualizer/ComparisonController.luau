--!strict

local VisualizerController = require(script.Parent.VisualizerController)

local ComparisonController = {}
ComparisonController.__index = ComparisonController

export type ComparisonController = typeof(setmetatable({} :: {
	_left: any,
	_right: any,
}, ComparisonController))

function ComparisonController.new(): ComparisonController
	return setmetatable({
		_left = VisualizerController.new(),
		_right = VisualizerController.new(),
	}, ComparisonController)
end

function ComparisonController:Init()
	self._left:Init()
	self._right:Init()
end

function ComparisonController:Prepare(leftAlgorithmId: any, rightAlgorithmId: any, size: number, pattern: any, seed: number?)
	local resolvedSeed = seed or 1337

	self._left:Prepare({
		algorithmId = leftAlgorithmId,
		size = size,
		pattern = pattern,
		seed = resolvedSeed,
	})

	self._right:Prepare({
		algorithmId = rightAlgorithmId,
		size = size,
		pattern = pattern,
		seed = resolvedSeed,
	})
end

function ComparisonController:GetVisualizers()
	return self._left, self._right
end

return ComparisonController
