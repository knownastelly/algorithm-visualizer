--!strict

local Types = require(script.Parent.Types)
local Utility = require(script.Parent.Utility)
local MetricsTracker = require(script.Parent.MetricsTracker)
local StepRecorder = require(script.Parent.StepRecorder)

local BubbleSort = require(script.Parent.Algorithms.BubbleSort)
local SelectionSort = require(script.Parent.Algorithms.SelectionSort)
local InsertionSort = require(script.Parent.Algorithms.InsertionSort)
local MergeSort = require(script.Parent.Algorithms.MergeSort)
local QuickSort = require(script.Parent.Algorithms.QuickSort)

type AlgorithmId = Types.AlgorithmId
type DatasetPattern = Types.DatasetPattern
type Recording = Types.Recording
type MetricsSnapshot = Types.MetricsSnapshot

local ALGORITHMS: { [AlgorithmId]: Types.AlgorithmModule } = {
	BubbleSort = BubbleSort,
	SelectionSort = SelectionSort,
	InsertionSort = InsertionSort,
	MergeSort = MergeSort,
	QuickSort = QuickSort,
}

local AlgorithmRunner = {}

function AlgorithmRunner.GetAlgorithmIds(): { AlgorithmId }
	return { "BubbleSort", "SelectionSort", "InsertionSort", "MergeSort", "QuickSort" }
end

function AlgorithmRunner.ValidateAlgorithm(algorithmId: AlgorithmId)
	local algorithm = ALGORITHMS[algorithmId]
	assert(algorithm ~= nil, `Unknown algorithm: {algorithmId}`)
	assert(type(algorithm.Run) == "function", `Algorithm {algorithmId} must expose Run`)
end

function AlgorithmRunner.Run(algorithmId: AlgorithmId, inputValues: { number }, pattern: DatasetPattern, seed: number?): (Recording, MetricsSnapshot)
	AlgorithmRunner.ValidateAlgorithm(algorithmId)

	local workingValues = Utility.CloneArray(inputValues)
	local metricsTracker = MetricsTracker.new()
	metricsTracker:Reset(#workingValues)

	local recorder = StepRecorder.new(algorithmId, workingValues, pattern, seed, metricsTracker)
	local startedAt = os.clock()

	ALGORITHMS[algorithmId].Run(workingValues, recorder, metricsTracker)
	recorder:Record({
		type = "done",
	})

	metricsTracker:SetExecutionTimeSeconds(os.clock() - startedAt)

	return recorder:Finish(workingValues), metricsTracker:GetSnapshot()
end

return AlgorithmRunner
