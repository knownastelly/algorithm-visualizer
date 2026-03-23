--!strict

local Types = require(script.Parent.Types)
local DataGenerator = require(script.Parent.DataGenerator)
local AlgorithmRunner = require(script.Parent.AlgorithmRunner)
local BarRenderer = require(script.Parent.BarRenderer)
local PlaybackController = require(script.Parent.PlaybackController)

type AlgorithmId = Types.AlgorithmId
type DatasetPattern = Types.DatasetPattern
type Recording = Types.Recording
type MetricsSnapshot = Types.MetricsSnapshot

local VisualizerController = {}
VisualizerController.__index = VisualizerController

export type VisualizerController = typeof(setmetatable({} :: {
	_renderer: any,
	_playback: any,
	_currentRecording: Recording?,
	_currentMetrics: MetricsSnapshot?,
	_currentValues: { number },
	_currentPattern: DatasetPattern,
	_currentSeed: number?,
	_currentAlgorithm: AlgorithmId,
	_currentSize: number,
	_listeners: { [string]: { (...any) -> () } },
}, VisualizerController))

function VisualizerController.new(): VisualizerController
	local renderer = BarRenderer.new()
	local playback = PlaybackController.new(renderer)

	return setmetatable({
		_renderer = renderer,
		_playback = playback,
		_currentRecording = nil,
		_currentMetrics = nil,
		_currentValues = {},
		_currentPattern = "Random",
		_currentSeed = 1337,
		_currentAlgorithm = "BubbleSort",
		_currentSize = 20,
		_listeners = {},
	}, VisualizerController)
end

function VisualizerController:_emit(eventName: string, ...: any)
	local callbacks = self._listeners[eventName]
	if callbacks == nil then
		return
	end

	for _, callback in callbacks do
		callback(...)
	end
end

function VisualizerController:Connect(eventName: string, callback: (...any) -> ())
	if self._listeners[eventName] == nil then
		self._listeners[eventName] = {}
	end

	table.insert(self._listeners[eventName], callback)
end

function VisualizerController:Init()
	self._renderer:Init()
	self._playback:SetCallbacks(function(stepIndex, step)
		self:_emit("PlaybackStep", stepIndex, step)
	end, function(state)
		self:_emit("PlaybackStateChanged", state)
	end)
end

function VisualizerController:Prepare(config: {
	algorithmId: AlgorithmId?,
	size: number?,
	pattern: DatasetPattern?,
	seed: number?,
})
	self._currentAlgorithm = config.algorithmId or self._currentAlgorithm
	self._currentSize = config.size or self._currentSize
	self._currentPattern = config.pattern or self._currentPattern
	self._currentSeed = config.seed

	self._currentValues = DataGenerator.Generate({
		size = self._currentSize,
		pattern = self._currentPattern,
		seed = self._currentSeed,
	})

	self._currentRecording, self._currentMetrics = AlgorithmRunner.Run(
		self._currentAlgorithm,
		self._currentValues,
		self._currentPattern,
		self._currentSeed
	)

	self._playback:Load(self._currentRecording)
	self:_emit("Prepared", self._currentRecording, self._currentMetrics, self._currentValues)
end

function VisualizerController:SetSpeed(multiplier: number)
	self._playback:SetSpeed(multiplier)
	self:_emit("SpeedChanged", multiplier)
end

function VisualizerController:SetAnimationMode(mode: string)
	self._playback:SetAnimationMode(mode)
	self:_emit("AnimationModeChanged", mode)
end

function VisualizerController:Play()
	self._playback:Play()
end

function VisualizerController:Pause()
	self._playback:Pause()
end

function VisualizerController:Reset()
	self._playback:Reset()
end

function VisualizerController:StepForward()
	self._playback:StepForward()
end

function VisualizerController:StepBack()
	self._playback:StepBack()
end

function VisualizerController:GetAlgorithmIds()
	return AlgorithmRunner.GetAlgorithmIds()
end

function VisualizerController:GetCurrentMetrics(): MetricsSnapshot?
	return self._currentMetrics
end

function VisualizerController:GetPlaybackState()
	return self._playback:GetState()
end

function VisualizerController:GetCurrentConfiguration()
	return {
		algorithmId = self._currentAlgorithm,
		size = self._currentSize,
		pattern = self._currentPattern,
		seed = self._currentSeed,
	}
end

return VisualizerController
