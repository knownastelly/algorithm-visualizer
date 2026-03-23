--!strict

export type DatasetPattern = "Random" | "NearlySorted" | "Reversed" | "FewUnique"
export type AlgorithmId = "BubbleSort" | "SelectionSort" | "InsertionSort" | "MergeSort" | "QuickSort"
export type PlaybackState = "Idle" | "Prepared" | "Playing" | "Paused" | "Completed"
export type AnimationMode = "Instant" | "Quick" | "Smooth"

export type DatasetConfig = {
	size: number,
	pattern: DatasetPattern,
	seed: number?,
	minValue: number?,
	maxValue: number?,
}

export type CompareStep = {
	type: "compare",
	indexA: number,
	indexB: number,
}

export type SwapStep = {
	type: "swap",
	indexA: number,
	indexB: number,
}

export type OverwriteStep = {
	type: "overwrite",
	index: number,
	value: number,
	sourceIndex: number?,
}

export type PivotStep = {
	type: "pivot",
	index: number,
	active: boolean,
}

export type RangeStep = {
	type: "range",
	startIndex: number,
	endIndex: number,
	label: string?,
}

export type MarkSortedStep = {
	type: "markSorted",
	index: number,
}

export type DoneStep = {
	type: "done",
}

export type VisualizationStep = CompareStep | SwapStep | OverwriteStep | PivotStep | RangeStep | MarkSortedStep | DoneStep

export type RecordingSnapshot = {
	stepIndex: number,
	values: { number },
}

export type Recording = {
	algorithmId: AlgorithmId,
	initialValues: { number },
	finalValues: { number },
	steps: { VisualizationStep },
	snapshots: { RecordingSnapshot },
	metadata: {
		size: number,
		pattern: DatasetPattern,
		seed: number?,
	},
}

export type MetricsSnapshot = {
	comparisons: number,
	swaps: number,
	reads: number,
	writes: number,
	recursionDepth: number,
	partitions: number,
	merges: number,
	totalSteps: number,
	executionTimeSeconds: number,
	arraySize: number,
}

export type Recorder = {
	Record: (self: Recorder, step: VisualizationStep) -> (),
	CommitSnapshot: (self: Recorder, values: { number }) -> (),
	Finish: (self: Recorder, finalValues: { number }) -> Recording,
	GetStepCount: (self: Recorder) -> number,
}

export type MetricsTracker = {
	Reset: (self: MetricsTracker, arraySize: number) -> (),
	IncrementComparisons: (self: MetricsTracker, amount: number?) -> (),
	IncrementSwaps: (self: MetricsTracker, amount: number?) -> (),
	IncrementReads: (self: MetricsTracker, amount: number?) -> (),
	IncrementWrites: (self: MetricsTracker, amount: number?) -> (),
	PushRecursionDepth: (self: MetricsTracker, depth: number) -> (),
	IncrementPartitions: (self: MetricsTracker, amount: number?) -> (),
	IncrementMerges: (self: MetricsTracker, amount: number?) -> (),
	SetExecutionTimeSeconds: (self: MetricsTracker, seconds: number) -> (),
	GetSnapshot: (self: MetricsTracker) -> MetricsSnapshot,
}

export type AlgorithmModule = {
	Run: (input: { number }, recorder: Recorder, metrics: MetricsTracker) -> (),
}

return {}
