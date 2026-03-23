--!strict

local Types = require(script.Parent.Types)

type MetricsSnapshot = Types.MetricsSnapshot

local MetricsTracker = {}
MetricsTracker.__index = MetricsTracker

export type MetricsTracker = typeof(setmetatable({} :: {
	_comparisons: number,
	_swaps: number,
	_reads: number,
	_writes: number,
	_recursionDepth: number,
	_partitions: number,
	_merges: number,
	_totalSteps: number,
	_executionTimeSeconds: number,
	_arraySize: number,
}, MetricsTracker))

function MetricsTracker.new(): MetricsTracker
	return setmetatable({
		_comparisons = 0,
		_swaps = 0,
		_reads = 0,
		_writes = 0,
		_recursionDepth = 0,
		_partitions = 0,
		_merges = 0,
		_totalSteps = 0,
		_executionTimeSeconds = 0,
		_arraySize = 0,
	}, MetricsTracker)
end

function MetricsTracker:Reset(arraySize: number)
	self._comparisons = 0
	self._swaps = 0
	self._reads = 0
	self._writes = 0
	self._recursionDepth = 0
	self._partitions = 0
	self._merges = 0
	self._totalSteps = 0
	self._executionTimeSeconds = 0
	self._arraySize = arraySize
end

local function addCount(self: MetricsTracker, key: string, amount: number?)
	(self :: any)[key] += amount or 1
end

function MetricsTracker:IncrementComparisons(amount: number?)
	addCount(self, "_comparisons", amount)
end

function MetricsTracker:IncrementSwaps(amount: number?)
	addCount(self, "_swaps", amount)
end

function MetricsTracker:IncrementReads(amount: number?)
	addCount(self, "_reads", amount)
end

function MetricsTracker:IncrementWrites(amount: number?)
	addCount(self, "_writes", amount)
end

function MetricsTracker:PushRecursionDepth(depth: number)
	self._recursionDepth = math.max(self._recursionDepth, depth)
end

function MetricsTracker:IncrementPartitions(amount: number?)
	addCount(self, "_partitions", amount)
end

function MetricsTracker:IncrementMerges(amount: number?)
	addCount(self, "_merges", amount)
end

function MetricsTracker:IncrementTotalSteps(amount: number?)
	addCount(self, "_totalSteps", amount)
end

function MetricsTracker:SetExecutionTimeSeconds(seconds: number)
	self._executionTimeSeconds = seconds
end

function MetricsTracker:GetSnapshot(): MetricsSnapshot
	return {
		comparisons = self._comparisons,
		swaps = self._swaps,
		reads = self._reads,
		writes = self._writes,
		recursionDepth = self._recursionDepth,
		partitions = self._partitions,
		merges = self._merges,
		totalSteps = self._totalSteps,
		executionTimeSeconds = self._executionTimeSeconds,
		arraySize = self._arraySize,
	}
end

return MetricsTracker
