--!strict

local Types = require(script.Parent.Types)
local Utility = require(script.Parent.Utility)

type Recording = Types.Recording
type RecordingSnapshot = Types.RecordingSnapshot
type VisualizationStep = Types.VisualizationStep
type DatasetPattern = Types.DatasetPattern
type AlgorithmId = Types.AlgorithmId

local SNAPSHOT_INTERVAL = 25

local StepRecorder = {}
StepRecorder.__index = StepRecorder

export type StepRecorder = typeof(setmetatable({} :: {
	_algorithmId: AlgorithmId,
	_initialValues: { number },
	_steps: { VisualizationStep },
	_snapshots: { RecordingSnapshot },
	_seed: number?,
	_pattern: DatasetPattern,
	_metricsTracker: any,
}, StepRecorder))

function StepRecorder.new(algorithmId: AlgorithmId, initialValues: { number }, pattern: DatasetPattern, seed: number?, metricsTracker: any): StepRecorder
	return setmetatable({
		_algorithmId = algorithmId,
		_initialValues = Utility.CloneArray(initialValues),
		_steps = {},
		_snapshots = {
			{
				stepIndex = 0,
				values = Utility.CloneArray(initialValues),
			},
		},
		_seed = seed,
		_pattern = pattern,
		_metricsTracker = metricsTracker,
	}, StepRecorder)
end

function StepRecorder:Record(step: VisualizationStep)
	table.insert(self._steps, step)
	self._metricsTracker:IncrementTotalSteps(1)
end

function StepRecorder:GetStepCount(): number
	return #self._steps
end

function StepRecorder:CommitSnapshot(values: { number })
	if (#self._steps % SNAPSHOT_INTERVAL) ~= 0 then
		return
	end

	table.insert(self._snapshots, {
		stepIndex = #self._steps,
		values = Utility.CloneArray(values),
	})
end

function StepRecorder:Finish(finalValues: { number }): Recording
	return {
		algorithmId = self._algorithmId,
		initialValues = Utility.CloneArray(self._initialValues),
		finalValues = Utility.CloneArray(finalValues),
		steps = self._steps,
		snapshots = self._snapshots,
		metadata = {
			size = #self._initialValues,
			pattern = self._pattern,
			seed = self._seed,
		},
	}
end

return StepRecorder
