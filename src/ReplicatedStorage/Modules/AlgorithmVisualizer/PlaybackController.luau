--!strict

local Types = require(script.Parent.Types)
local Utility = require(script.Parent.Utility)

type Recording = Types.Recording
type PlaybackState = Types.PlaybackState
type VisualizationStep = Types.VisualizationStep

local PlaybackController = {}
PlaybackController.__index = PlaybackController

export type PlaybackController = typeof(setmetatable({} :: {
	_renderer: any,
	_recording: Recording?,
	_state: PlaybackState,
	_speed: number,
	_currentStepIndex: number,
	_currentValues: { number },
	_runId: number,
	_onStep: ((number, VisualizationStep) -> ())?,
	_onStateChanged: ((PlaybackState) -> ())?,
}, PlaybackController))

local function isSortedColorStep(step: VisualizationStep): boolean
	return step.type == "markSorted" or step.type == "done"
end

function PlaybackController.new(renderer: any): PlaybackController
	return setmetatable({
		_renderer = renderer,
		_recording = nil,
		_state = "Idle",
		_speed = 1,
		_currentStepIndex = 0,
		_currentValues = {},
		_runId = 0,
		_onStep = nil,
		_onStateChanged = nil,
	}, PlaybackController)
end

function PlaybackController:SetCallbacks(onStep: ((number, VisualizationStep) -> ())?, onStateChanged: ((PlaybackState) -> ())?)
	self._onStep = onStep
	self._onStateChanged = onStateChanged
end

function PlaybackController:_setState(state: PlaybackState)
	self._state = state
	if self._onStateChanged ~= nil then
		self._onStateChanged(state)
	end
end

function PlaybackController:Load(recording: Recording)
	self._recording = recording
	self._currentStepIndex = 0
	self._currentValues = Utility.CloneArray(recording.initialValues)
	self._renderer:Reset(self._currentValues)
	self:_setState("Prepared")
	self._runId += 1
end

function PlaybackController:SetSpeed(multiplier: number)
	self._speed = math.max(0.25, multiplier)
	self._renderer:SetSpeedMultiplier(self._speed)
end

function PlaybackController:SetAnimationMode(mode: string)
	self._renderer:SetAnimationMode(mode)
end

function PlaybackController:GetState(): PlaybackState
	return self._state
end

function PlaybackController:StepForward(): boolean
	if self._recording == nil then
		return false
	end

	if self._currentStepIndex >= #self._recording.steps then
		self:_setState("Completed")
		return false
	end

	self._currentStepIndex += 1
	local step = self._recording.steps[self._currentStepIndex]
	self._renderer:ResetColors()

	if step.type == "compare" then
		self._renderer:HighlightCompare(step.indexA, step.indexB)
	elseif step.type == "swap" then
		self._currentValues[step.indexA], self._currentValues[step.indexB] = self._currentValues[step.indexB], self._currentValues[step.indexA]
		self._renderer:SwapBars(step.indexA, step.indexB)
	elseif step.type == "overwrite" then
		self._currentValues[step.index] = step.value
		self._renderer:UpdateBar(step.index, step.value, #self._currentValues)
	elseif step.type == "pivot" then
		self._renderer:SetPivot(step.index, step.active)
	elseif step.type == "range" then
		self._renderer:ShowRange(step.startIndex, step.endIndex)
	elseif step.type == "markSorted" then
		self._renderer:MarkSorted(step.index)
	elseif step.type == "done" then
		self._renderer:HideRange()
	end

	if self._onStep ~= nil then
		self._onStep(self._currentStepIndex, step)
	end

	if step.type == "done" then
		self:_setState("Completed")
	end

	return true
end

function PlaybackController:Pause()
	if self._state == "Playing" then
		self._runId += 1
		self:_setState("Paused")
	end
end

function PlaybackController:Reset()
	if self._recording == nil then
		return
	end

	self._runId += 1
	self._currentStepIndex = 0
	self._currentValues = Utility.CloneArray(self._recording.initialValues)
	self._renderer:Reset(self._currentValues)
	self:_setState("Prepared")
end

function PlaybackController:StepBack()
	if self._recording == nil then
		return
	end

	local targetStepIndex = math.max(0, self._currentStepIndex - 1)
	local snapshot = self._recording.snapshots[1]

	for _, candidate in self._recording.snapshots do
		if candidate.stepIndex <= targetStepIndex then
			snapshot = candidate
		else
			break
		end
	end

	self._currentStepIndex = snapshot.stepIndex
	self._currentValues = Utility.CloneArray(snapshot.values)
	self._renderer:Reset(self._currentValues)
	self:_setState("Paused")

	while self._currentStepIndex < targetStepIndex do
		self:StepForward()
	end
end

function PlaybackController:Play()
	if self._recording == nil then
		return
	end

	self._runId += 1
	local activeRunId = self._runId
	self:_setState("Playing")

	task.spawn(function()
		while self._state == "Playing" and self._recording ~= nil and self._currentStepIndex < #self._recording.steps do
			if activeRunId ~= self._runId then
				return
			end

			local didAdvance = self:StepForward()
			if not didAdvance then
				return
			end

			local currentStep = self._recording.steps[self._currentStepIndex]
			if not isSortedColorStep(currentStep) then
				task.wait(0.14 / self._speed)
			end
		end

		if activeRunId == self._runId and self._currentStepIndex >= #self._recording.steps then
			self:_setState("Completed")
		end
	end)
end

return PlaybackController
