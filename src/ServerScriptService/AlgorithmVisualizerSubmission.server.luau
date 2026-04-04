--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- These type definitions are here first so the rest of the file is easier to follow.
-- In simple terms: they describe the shape of the data that moves through the system.
-- The same data is passed between the generator, sorter, recorder, renderer, and playback code.

type DatasetPattern = "Random" | "NearlySorted" | "Reversed" | "FewUnique"
type PlaybackState = "Preparing" | "Playing" | "Paused" | "Completed"
type AnimationMode = "Instant" | "Quick" | "Smooth"

type CompareStep = {
	type: "compare",
	indexA: number,
	indexB: number,
}

type SwapStep = {
	type: "swap",
	indexA: number,
	indexB: number,
}

type PivotStep = {
	type: "pivot",
	index: number,
	active: boolean,
}

type RangeStep = {
	type: "range",
	startIndex: number,
	endIndex: number,
}

type MarkSortedStep = {
	type: "markSorted",
	index: number,
}

type DoneStep = {
	type: "done",
}

type VisualizationStep = CompareStep | SwapStep | PivotStep | RangeStep | MarkSortedStep | DoneStep

type RecordingSnapshot = {
	stepIndex: number,
	values: { number },
}

type Recording = {
	initialValues: { number },
	finalValues: { number },
	steps: { VisualizationStep },
	snapshots: { RecordingSnapshot },
	metadata: RecordingMetadata,
}

type RecordingMetadata = {
	size: number,
	pattern: DatasetPattern,
	seed: number,
}

type MetricsSnapshot = {
	comparisons: number,
	swaps: number,
	reads: number,
	writes: number,
	recursionDepth: number,
	partitions: number,
	totalSteps: number,
	executionTimeSeconds: number,
	arraySize: number,
}

local CONTAINER_NAME = "AlgorithmVisualizerSubmission"
local PLATFORM_NAME = "VisualizationPlatform"
local STATUS_BOARD_NAME = "StatusBoard"

local BAR_WIDTH = 2.6
local BAR_DEPTH = 2.6
local BAR_SPACING = 0.55
local HEIGHT_SCALE = 0.42
local PLATFORM_SIZE = Vector3.new(170, 2, 44)
local VISUALIZER_CENTER = Vector3.new(0, 0, -110)

local SNAPSHOT_INTERVAL = 20
local DEFAULT_SIZE = 36
local DEFAULT_PATTERN: DatasetPattern = "NearlySorted"
local DEFAULT_SEED = 1337
local MIN_VALUE = 8
local MAX_VALUE = 92
local LOOP_DELAY_SECONDS = 2.5

local ANIMATION_DURATIONS: { [AnimationMode]: number } = {
	Instant = 0,
	Quick = 0.08,
	Smooth = 0.18,
}

local COLORS = {
	Default = Color3.fromRGB(240, 240, 240),
	Compare = Color3.fromRGB(255, 209, 84),
	Swap = Color3.fromRGB(255, 100, 100),
	Sorted = Color3.fromRGB(89, 214, 115),
	Pivot = Color3.fromRGB(112, 170, 255),
	Range = Color3.fromRGB(255, 255, 255),
	Platform = Color3.fromRGB(33, 33, 40),
	Board = Color3.fromRGB(18, 23, 32),
	BoardAccent = Color3.fromRGB(71, 148, 255),
}

-- This file is self-contained because the submission requires one Luau script.
-- Even though it is one file, I still split the logic into clear sections:
-- 1. data generation
-- 2. metric tracking
-- 3. step recording
-- 4. sorting
-- 5. Roblox rendering
-- 6. playback
-- I did that so each part has one job and the reader can understand the flow in order.

local Utility = {}

function Utility.CloneArray(values: { number }): { number }
	-- This makes a copy of an array.
	-- I do this so one part of the script does not accidentally change data that another part is
	-- still relying on.
	-- table.create reserves enough array space for the copy.
	local clone = table.create(#values)

	for index, value in values do
		-- Put each value from the original array into the same slot in the new array.
		clone[index] = value
	end

	-- Return the finished copy.
	return clone
end

local SeededRandom = {}
SeededRandom.__index = SeededRandom

local RANDOM_MODULUS = 2 ^ 31
local RANDOM_MULTIPLIER = 1103515245
local RANDOM_INCREMENT = 12345

function SeededRandom.new(seed: number)
	-- A seed means "start the random sequence from this exact point".
	-- That lets me recreate the same dataset later instead of getting a different one every time.
	return setmetatable({
		-- Store the starting random state on the object.
		_state = math.floor(seed) % RANDOM_MODULUS,
	}, SeededRandom)
end

function SeededRandom:NextNumber(): number
	-- This moves the internal random state forward and returns a number between 0 and 1.
	-- The important part is that the sequence stays repeatable for the same seed.
	-- Update the saved random state using the LCG formula.
	self._state = ((self._state * RANDOM_MULTIPLIER) + RANDOM_INCREMENT) % RANDOM_MODULUS
	-- Convert the state into a decimal between 0 and 1.
	return self._state / RANDOM_MODULUS
end

function SeededRandom:NextInteger(minimum: number, maximum: number): number
	-- The visualizer needs whole numbers for bar heights, so this converts the random decimal into
	-- an integer inside the requested range.
	return math.floor(self:NextNumber() * ((maximum - minimum) + 1)) + minimum
end

local DataGenerator = {}

local function buildRandomDataset(size: number, seed: number): { number }
	-- This creates the starting list of numbers.
	-- It is kept separate from quicksort so I can change the input data without changing the sorting code.
	local randomStream = SeededRandom.new(seed)
	-- Pre-allocate the array that will hold the bar values.
	local values = table.create(size)

	for index = 1, size do
		-- Fill each slot with one seeded random integer.
		values[index] = randomStream:NextInteger(MIN_VALUE, MAX_VALUE)
	end

	-- Return the finished dataset.
	return values
end

local function applyNearlySorted(values: { number })
	-- This turns a sorted list into a list that is "almost" sorted.
	-- I use it because it makes the mistakes easy to spot with your eyes.
	local swapCount = math.max(1, math.floor(#values * 0.14))

	for offset = 1, swapCount do
		-- I only disturb nearby positions, so the list still looks mostly ordered.
		-- Choose the first position to disturb.
		local a = math.max(1, math.min(#values - 1, offset * 2))
		-- Pick the neighbor directly to the right.
		local b = a + 1
		-- Swap the two nearby values.
		values[a], values[b] = values[b], values[a]
	end
end

local function applyFewUnique(values: { number })
	-- This forces many bars to share the same few heights.
	-- That makes groups and duplicates easier to notice during the quicksort run.
	local distinctValues = {
		MIN_VALUE,
		math.floor((MIN_VALUE + MAX_VALUE) * 0.5),
		MAX_VALUE,
	}

	for index = 1, #values do
		-- Cycle through the small list of allowed values and assign one into the current slot.
		values[index] = distinctValues[((index - 1) % #distinctValues) + 1]
	end
end

function DataGenerator.Generate(size: number, pattern: DatasetPattern, seed: number): { number }
	assert(size > 1, "Dataset size must be greater than 1")

	-- This is the main entry point for building the dataset.
	-- First I make the base numbers, then I shape them into the pattern I want to demonstrate.
	local values = buildRandomDataset(size, seed)

	if pattern == "Random" then
		-- If the caller asked for random data, return the original random dataset right away.
		return values
	end

	-- For the non-random patterns, I start from a sorted version first.
	-- That gives me a clean base before I turn it into "nearly sorted", "reversed", or "few unique".
	table.sort(values)

	if pattern == "NearlySorted" then
		-- Make the sorted list only slightly disordered.
		applyNearlySorted(values)
	elseif pattern == "Reversed" then
		-- Sort the values in descending order instead of ascending order.
		table.sort(values, function(left, right)
			return left > right
		end)
	elseif pattern == "FewUnique" then
		-- Replace the dataset with repeating values from a small pool.
		applyFewUnique(values)
	end

	-- After this point, dataset creation is finished.
	-- The sorting code receives the result and takes over from there.
	return values
end

local MetricsTracker = {}
MetricsTracker.__index = MetricsTracker

function MetricsTracker.new()
	-- This object stores counters like comparisons, swaps, and reads.
	-- I wrapped them in methods so the sorting code can say what happened in plain terms.
	return setmetatable({
		_comparisons = 0,
		_swaps = 0,
		_reads = 0,
		_writes = 0,
		_recursionDepth = 0,
		_partitions = 0,
		_totalSteps = 0,
		_executionTimeSeconds = 0,
		_arraySize = 0,
	}, MetricsTracker)
end

local function incrementMetric(self: any, fieldName: string, amount: number?)
	-- All the metric increment methods work the same way, so this helper keeps that logic in one place.
	self[fieldName] += amount or 1
end

function MetricsTracker:Reset(arraySize: number)
	-- This clears the old counters so each demo run starts from zero.
	-- comparisons = how many value comparisons quicksort made
	self._comparisons = 0
	-- swaps = how many actual value swaps happened
	self._swaps = 0
	-- reads = how many times values were looked up
	self._reads = 0
	-- writes = how many times values were written back
	self._writes = 0
	-- recursionDepth = deepest recursive level reached
	self._recursionDepth = 0
	-- partitions = how many partition passes ran
	self._partitions = 0
	-- totalSteps = how many visual steps were recorded
	self._totalSteps = 0
	-- execution time = how long the recording phase took
	self._executionTimeSeconds = 0
	-- Save the size of the dataset this run is measuring.
	self._arraySize = arraySize
end

function MetricsTracker:IncrementComparisons(amount: number?)
	incrementMetric(self, "_comparisons", amount)
end

function MetricsTracker:IncrementSwaps(amount: number?)
	incrementMetric(self, "_swaps", amount)
end

function MetricsTracker:IncrementReads(amount: number?)
	incrementMetric(self, "_reads", amount)
end

function MetricsTracker:IncrementWrites(amount: number?)
	incrementMetric(self, "_writes", amount)
end

function MetricsTracker:PushRecursionDepth(depth: number)
	self._recursionDepth = math.max(self._recursionDepth, depth)
end

function MetricsTracker:IncrementPartitions(amount: number?)
	incrementMetric(self, "_partitions", amount)
end

function MetricsTracker:IncrementTotalSteps(amount: number?)
	incrementMetric(self, "_totalSteps", amount)
end

function MetricsTracker:SetExecutionTimeSeconds(seconds: number)
	self._executionTimeSeconds = seconds
end

function MetricsTracker:GetSnapshot(): MetricsSnapshot
	-- The renderer only needs a plain copy of the numbers to display on the board.
	-- It does not need direct control over the tracker object itself.
	return {
		comparisons = self._comparisons,
		swaps = self._swaps,
		reads = self._reads,
		writes = self._writes,
		recursionDepth = self._recursionDepth,
		partitions = self._partitions,
		totalSteps = self._totalSteps,
		executionTimeSeconds = self._executionTimeSeconds,
		arraySize = self._arraySize,
	}
end

local StepRecorder = {}
StepRecorder.__index = StepRecorder

function StepRecorder.new(initialValues: { number }, pattern: DatasetPattern, seed: number, metricsTracker: any)
	-- This recorder is the bridge between "sorting the data" and "showing the sorting visually".
	-- The algorithm runs once and stores the important moments it went through.
	-- Later, playback reads those saved moments and turns them into animation.
	return setmetatable({
		-- Save a copy of the starting values so playback can reset back to the beginning.
		_initialValues = Utility.CloneArray(initialValues),
		-- This array will hold every recorded step in order.
		_steps = {} :: { VisualizationStep },
		-- The first snapshot is step 0, which means "before any sorting step happened".
		_snapshots = {
			{
				stepIndex = 0,
				values = Utility.CloneArray(initialValues),
			},
		} :: { RecordingSnapshot },
		-- Store metadata about the run for the status board.
		_pattern = pattern,
		_seed = seed,
		-- Keep a reference to the metrics object so recording steps can increase the total step count.
		_metricsTracker = metricsTracker,
	}, StepRecorder)
end

function StepRecorder:Record(step: VisualizationStep)
	-- I save meaningful actions here, not raw Part changes.
	-- For example: "compare these two bars" is more useful than "change this color right now".
	-- Add the new step to the end of the recording.
	table.insert(self._steps, step)
	-- Increase the total number of recorded steps by 1.
	self._metricsTracker:IncrementTotalSteps(1)
end

function StepRecorder:CommitSnapshot(values: { number })
	-- Every so often I save a full copy of the array.
	-- This is useful for jumping backward later without having to replay the entire sort from step 1.
	if (#self._steps % SNAPSHOT_INTERVAL) ~= 0 then
		-- If this is not a snapshot interval, stop here and do not save a full array copy yet.
		return
	end

	-- Save the step number and a copy of the current array values.
	table.insert(self._snapshots, {
		stepIndex = #self._steps,
		values = Utility.CloneArray(values),
	})
end

function StepRecorder:Finish(finalValues: { number }): Recording
	-- This packages everything the playback system needs:
	-- the original values, the final values, the saved steps, a few snapshots, and some metadata.
	return {
		-- Save the starting array.
		initialValues = Utility.CloneArray(self._initialValues),
		-- Save the fully sorted array.
		finalValues = Utility.CloneArray(finalValues),
		-- Save the step-by-step history.
		steps = self._steps,
		-- Save the rewind snapshots.
		snapshots = self._snapshots,
		-- Save metadata that describes this run.
		metadata = {
			size = #self._initialValues,
			pattern = self._pattern,
			seed = self._seed,
		},
	}
end

local QuickSort = {}

local function partition(values: { number }, recorder: any, metrics: any, low: number, high: number): number
	-- This is the most important part of quicksort.
	-- The last value is used as the pivot.
	-- Then the code scans the current range from left to right and pushes smaller values toward the front.
	-- This is also the easiest part to visualize, so I record a lot of detail here.
	-- Read the last value in the range and use it as the pivot.
	local pivotValue = values[high]
	-- smallerIndex tracks the boundary of the "values smaller than or equal to the pivot" section.
	local smallerIndex = low - 1

	-- Count one new partition operation.
	metrics:IncrementPartitions(1)
	-- Count one read for taking the pivot value.
	metrics:IncrementReads(1)
	-- Record the active sub-range so playback can draw the white range box.
	recorder:Record({
		type = "range",
		startIndex = low,
		endIndex = high,
	})
	-- Record which bar is acting as the pivot.
	recorder:Record({
		type = "pivot",
		index = high,
		active = true,
	})

	for index = low, high - 1 do
		-- Here I compare the current value to the pivot.
		-- If the current value belongs on the "smaller than pivot" side, I move it left.
		recorder:Record({
			type = "compare",
			indexA = index,
			indexB = high,
		})
		metrics:IncrementComparisons(1)
		metrics:IncrementReads(1)

		if values[index] <= pivotValue then
			-- Move the "smaller than or equal to pivot" boundary one slot to the right.
			smallerIndex += 1

			if smallerIndex ~= index then
				-- I only record real swaps.
				-- If both positions are already the same slot, there is no visible move to show.
				-- Swap the smaller value into the left partition.
				values[smallerIndex], values[index] = values[index], values[smallerIndex]
				-- Record the swap so playback can animate it.
				recorder:Record({
					type = "swap",
					indexA = smallerIndex,
					indexB = index,
				})
				-- Count the swap and the two array writes it caused.
				metrics:IncrementSwaps(1)
				metrics:IncrementWrites(2)
				-- Save a snapshot if this step hits the snapshot interval.
				recorder:CommitSnapshot(values)
			end
		end
	end

	-- The pivot belongs immediately after the smaller partition.
	local pivotIndex = smallerIndex + 1
	-- After the scan is done, the pivot is moved into its final correct position.
	-- Once that happens, quicksort will never move that pivot again.
	-- Swap the pivot into its final sorted slot.
	values[pivotIndex], values[high] = values[high], values[pivotIndex]
	-- Record the pivot-moving swap.
	recorder:Record({
		type = "swap",
		indexA = pivotIndex,
		indexB = high,
	})
	-- Turn off the old pivot marker.
	recorder:Record({
		type = "pivot",
		index = high,
		active = false,
	})
	-- Mark the pivot's final slot as sorted.
	recorder:Record({
		type = "markSorted",
		index = pivotIndex,
	})
	-- Count the pivot swap and the two writes it caused.
	metrics:IncrementSwaps(1)
	metrics:IncrementWrites(2)
	-- Save a snapshot if needed.
	recorder:CommitSnapshot(values)

	-- Return the pivot's final index so quicksort knows where to split next.
	return pivotIndex
end

local function quickSort(values: { number }, recorder: any, metrics: any, low: number, high: number, depth: number)
	-- This function keeps splitting the problem into smaller pieces.
	-- First it solves one partition, then it repeats the same idea on the left side and the right side.
	if low > high then
		-- If the range is invalid, there is nothing to sort.
		return
	end

	-- Update the maximum recursion depth reached so far.
	metrics:PushRecursionDepth(depth)

	if low == high then
		-- A section with one value is already sorted.
		-- I still record it so the playback can show that this branch is finished.
		recorder:Record({
			type = "markSorted",
			index = low,
		})
		return
	end

	-- Partition the current range and get the pivot's final position.
	local pivotIndex = partition(values, recorder, metrics, low, high)
	-- After the pivot is fixed, everything left of it and right of it is handled separately.
	quickSort(values, recorder, metrics, low, pivotIndex - 1, depth + 1)
	quickSort(values, recorder, metrics, pivotIndex + 1, high, depth + 1)
end

function QuickSort.Run(inputValues: { number }, pattern: DatasetPattern, seed: number): (Recording, MetricsSnapshot)
	-- I sort a copy instead of the original array.
	-- That way the playback system can still remember what the unsorted starting state looked like.
	-- Copy the input into a working array that quicksort is allowed to change.
	local workingValues = Utility.CloneArray(inputValues)
	-- Create a fresh metrics object for this run.
	local metrics = MetricsTracker.new()
	-- Reset the metrics using the current array size.
	metrics:Reset(#workingValues)

	-- Create the recorder that will store the step-by-step history.
	local recorder = StepRecorder.new(workingValues, pattern, seed, metrics)
	-- Save the start time so the recording duration can be measured.
	local startTime = os.clock()

	-- Important detail: the actual sorting work happens here first.
	-- The on-screen animation does not happen yet.
	-- The animation comes later by replaying the saved steps.
	-- Run quicksort on the working array and record the steps while it runs.
	quickSort(workingValues, recorder, metrics, 1, #workingValues, 1)
	-- Add one final step that says the run is finished.
	recorder:Record({
		type = "done",
	})

	-- Save how long the recording phase took.
	metrics:SetExecutionTimeSeconds(os.clock() - startTime)

	-- Return the completed recording and a plain copy of the metrics.
	return recorder:Finish(workingValues), metrics:GetSnapshot()
end

local BarRenderer = {}
BarRenderer.__index = BarRenderer

function BarRenderer.new()
	-- This object is responsible for everything the player can see in the demo.
	-- That includes the floor platform, the bars, the range box, and the text board.
	return setmetatable({
		-- Folder that stores all generated demo objects.
		_container = nil :: Folder?,
		-- The floor under the bars.
		_platform = nil :: Part?,
		-- Invisible anchor used for the status board.
		_boardPart = nil :: Part?,
		-- Top line of board text.
		_statusLabel = nil :: TextLabel?,
		-- Lower board text that shows metrics.
		_metricsLabel = nil :: TextLabel?,
		-- Spare bars that are not in use right now.
		_barPool = {} :: { Part },
		-- Map from array index to visible bar object.
		_indexToBar = {} :: { [number]: Part },
		-- White box that shows the active quicksort range.
		_rangeAdornment = nil :: BoxHandleAdornment?,
		-- Converts value size into visual bar height.
		_heightScale = HEIGHT_SCALE,
		-- Base world position used for placement math.
		_origin = Vector3.zero,
		-- Number of bars currently being rendered.
		_barCount = 0,
		-- Current animation preset.
		_animationMode = "Quick" :: AnimationMode,
		-- Current playback speed.
		_speedMultiplier = 1,
	}, BarRenderer)
end

local function getOrCreateFolder(name: string, parent: Instance): Folder
	-- This keeps all generated objects inside one folder so the demo stays organized in Explorer.
	local folder = parent:FindFirstChild(name)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder :: Folder
end

local function createLabel(name: string, order: number, height: number, textSize: number, textXAlignment: Enum.TextXAlignment): TextLabel
	-- I build the board UI in code rather than relying on pre-authored objects so the file remains fully self-contained.
	-- Create one new text label object.
	local label = Instance.new("TextLabel")
	-- Set the label name so it can be found later.
	label.Name = name
	-- Decide where the label appears inside the vertical layout.
	label.LayoutOrder = order
	-- Hide the label background and only show text.
	label.BackgroundTransparency = 1
	-- Set the label size inside the board frame.
	label.Size = UDim2.new(1, 0, 0, height)
	-- Set font and text styling.
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(244, 247, 255)
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = textXAlignment
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = false
	-- Return the finished label instance.
	return label
end

function BarRenderer:Init()
	-- This sets up the 3D area where the visualizer lives.
	-- I keep it in one fixed place so every rerun uses the same layout.
	self._container = getOrCreateFolder(CONTAINER_NAME, Workspace)

	local platform = self._container:FindFirstChild(PLATFORM_NAME) :: Part?
	if platform == nil then
		-- The platform is the floor under the bars.
		-- It also gives me one stable object to measure everything else from.
		platform = Instance.new("Part")
		platform.Name = PLATFORM_NAME
		platform.Anchored = true
		platform.Material = Enum.Material.SmoothPlastic
		platform.Color = COLORS.Platform
		platform.TopSurface = Enum.SurfaceType.Smooth
		platform.BottomSurface = Enum.SurfaceType.Smooth
		platform.Parent = self._container
	end

	platform.Size = PLATFORM_SIZE
	-- Place the platform at the fixed world position for this demo.
	platform.CFrame = CFrame.new(VISUALIZER_CENTER)
	self._platform = platform
	-- Bar positions are easier to compute from the top face of the platform than from its center.
	self._origin = platform.Position + Vector3.new(0, platform.Size.Y * 0.5, 0)

	self:_ensureStatusBoard()
end

function BarRenderer:_ensureStatusBoard()
	assert(self._container ~= nil and self._platform ~= nil, "Renderer must be initialized before creating UI")

	-- The text board is attached to an invisible part.
	-- I do that so I can place it in 3D space with normal CFrame math, while BillboardGui keeps the
	-- text facing the camera.
	local boardPart = self._container:FindFirstChild(STATUS_BOARD_NAME) :: Part?
	if boardPart == nil then
		-- If the invisible anchor does not exist yet, create it now.
		boardPart = Instance.new("Part")
		boardPart.Name = STATUS_BOARD_NAME
		boardPart.Anchored = true
		boardPart.CanCollide = false
		boardPart.Transparency = 1
		boardPart.Size = Vector3.new(18, 9, 1)
		boardPart.Parent = self._container
	end

	boardPart.CFrame = CFrame.lookAt(
		self._platform.Position + Vector3.new(0, 15, 18),
		self._platform.Position + Vector3.new(0, 8, 0)
	)
	-- CFrame.lookAt keeps the board naturally aimed toward the visualizer instead of forcing me to guess the rotation by hand.

	local billboard = boardPart:FindFirstChild("Billboard") :: BillboardGui?
	if billboard == nil then
		-- Create the BillboardGui that holds the visible board UI.
		billboard = Instance.new("BillboardGui")
		billboard.Name = "Billboard"
		billboard.Size = UDim2.fromOffset(420, 220)
		billboard.StudsOffset = Vector3.new(0, 0, 0)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 300
		billboard.Adornee = boardPart
		billboard.Parent = boardPart
	end

	local frame = billboard:FindFirstChild("Frame") :: Frame?
	if frame == nil then
		-- The board is simple on purpose: it exists to explain the run, not to distract from it.
		-- Create the main frame that the labels will sit inside.
		frame = Instance.new("Frame")
		frame.Name = "Frame"
		frame.BackgroundColor3 = COLORS.Board
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = billboard

		-- Add rounded corners to the frame.
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = frame

		-- Add a thin outline around the frame.
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.BoardAccent
		stroke.Thickness = 2
		stroke.Transparency = 0.2
		stroke.Parent = frame

		-- Add inner spacing so the text is not flush against the edges.
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 14)
		padding.PaddingBottom = UDim.new(0, 14)
		padding.PaddingLeft = UDim.new(0, 16)
		padding.PaddingRight = UDim.new(0, 16)
		padding.Parent = frame

		-- Automatically stack child labels from top to bottom.
		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 6)
		listLayout.Parent = frame
	end

	local statusLabel = frame:FindFirstChild("StatusLabel") :: TextLabel?
	if statusLabel == nil then
		-- Create the top label if it does not exist yet.
		statusLabel = createLabel("StatusLabel", 1, 54, 20, Enum.TextXAlignment.Left)
		statusLabel.Parent = frame
	end

	local metricsLabel = frame:FindFirstChild("MetricsLabel") :: TextLabel?
	if metricsLabel == nil then
		-- Create the lower metrics label if it does not exist yet.
		metricsLabel = createLabel("MetricsLabel", 2, 130, 16, Enum.TextXAlignment.Left)
		metricsLabel.Parent = frame
	end

	-- Save references so later functions can update the board quickly.
	self._boardPart = boardPart
	self._statusLabel = statusLabel
	self._metricsLabel = metricsLabel
end

function BarRenderer:_getBarHeight(value: number): number
	-- A minimum visible height prevents tiny values from disappearing into the platform.
	return math.max(1, value * self._heightScale)
end

function BarRenderer:_calcXPosition(index: number, count: number): Vector3
	-- I center the full array so changing the number of bars does not make the whole build drift.
	local totalWidth = count * BAR_WIDTH + (count - 1) * BAR_SPACING
	local leftEdge = self._origin.X - totalWidth * 0.5 + BAR_WIDTH * 0.5
	local x = leftEdge + (index - 1) * (BAR_WIDTH + BAR_SPACING)
	return Vector3.new(x, self._origin.Y, self._origin.Z)
end

function BarRenderer:_calcBarPosition(index: number, count: number, height: number): Vector3
	local basePosition = self:_calcXPosition(index, count)
	-- Roblox places a Part by its center, not by its bottom.
	-- So I add half the bar height here to stop the bar from sinking into the floor.
	return basePosition + Vector3.new(0, height * 0.5, 0)
end

function BarRenderer:_getBarFromPool(index: number): Part
	-- I reuse old bars whenever possible so repeated runs do not create unnecessary instance churn.
	-- Take one spare bar from the pool if one exists.
	local bar = table.remove(self._barPool)

	if bar == nil then
		-- If the pool is empty, create a new bar part.
		bar = Instance.new("Part")
		bar.Anchored = true
		bar.Material = Enum.Material.SmoothPlastic
		bar.TopSurface = Enum.SurfaceType.Smooth
		bar.BottomSurface = Enum.SurfaceType.Smooth
	end

	-- Give the bar its current identity and visual defaults.
	bar.Name = `Bar_{index}`
	bar.CanCollide = false
	bar.Parent = self._container
	bar.Transparency = 0
	bar.Color = COLORS.Default

	-- Save which array index this bar currently belongs to.
	self._indexToBar[index] = bar
	return bar
end

function BarRenderer:_releaseExtraBars(count: number)
	-- When a later dataset is smaller, I detach the extras and keep them in a pool for reuse.
	for index, bar in self._indexToBar do
		if index > count then
			-- Remove the extra bar from the world.
			bar.Parent = nil
			-- Save it in the pool for later reuse.
			table.insert(self._barPool, bar)
			-- Remove the old index mapping.
			self._indexToBar[index] = nil
		end
	end
end

function BarRenderer:_getTweenDuration(): number
	-- The tween duration is scaled by playback speed so the visuals do not lag behind the logical step stream.
	local baseDuration = ANIMATION_DURATIONS[self._animationMode]
	local playbackSpeed = math.max(self._speedMultiplier, 0.25)
	return baseDuration / playbackSpeed
end

function BarRenderer:_tweenBar(bar: Part, size: Vector3?, position: Vector3?)
	local duration = self:_getTweenDuration()

	if duration <= 0 then
		-- Instant mode is helpful for debugging because it removes animation timing from the equation.
		if size ~= nil then
			bar.Size = size
		end
		if position ~= nil then
			bar.Position = position
		end
		return
	end

	local goals: { [string]: Vector3 } = {}
	if size ~= nil then
		goals.Size = size
	end
	if position ~= nil then
		goals.Position = position
	end

	-- TweenService is only given the properties that changed, which keeps each transition focused.
	local tween = TweenService:Create(
		bar,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
end

function BarRenderer:SetAnimationMode(mode: AnimationMode)
	-- Animation mode controls feel, while playback speed controls tempo.
	self._animationMode = mode
end

function BarRenderer:SetSpeedMultiplier(speedMultiplier: number)
	self._speedMultiplier = math.max(speedMultiplier, 0.25)
end

function BarRenderer:Render(values: { number })
	-- Make sure the world objects exist before placing bars.
	self:Init()
	-- Save how many bars this render should contain.
	self._barCount = #values
	-- Remove any bars that are no longer needed.
	self:_releaseExtraBars(#values)

	for index, value in values do
		-- Each array index owns one bar entry in the map, which makes future compare and swap steps straightforward.
		local bar = self._indexToBar[index]
		if bar == nil then
			-- Create or reuse a bar if this slot does not already have one.
			bar = self:_getBarFromPool(index)
		end

		-- Convert the numeric value into a visible height.
		local height = self:_getBarHeight(value)
		-- Apply the new size to the bar.
		bar.Size = Vector3.new(BAR_WIDTH, height, BAR_DEPTH)
		-- Move the bar to its correct world position.
		bar.Position = self:_calcBarPosition(index, #values, height)
		-- Reset the bar color back to default.
		bar.Color = COLORS.Default
	end
end

function BarRenderer:GetBar(index: number): Part
	-- A missing bar would indicate broken bookkeeping, so I fail loudly instead of hiding it.
	local bar = self._indexToBar[index]
	assert(bar ~= nil, `Missing bar for index {index}`)
	return bar
end

function BarRenderer:UpdateStatus(state: PlaybackState, metadata: RecordingMetadata, metrics: MetricsSnapshot, stepIndex: number, stepCount: number)
	-- Make sure the text board exists before writing to it.
	self:Init()
	assert(self._statusLabel ~= nil and self._metricsLabel ~= nil, "Status board must exist after initialization")

	-- The status board is updated on every step so someone looking at the place mid-run can still understand what they are seeing.
	-- Write the high-level run state into the top label.
	self._statusLabel.Text = string.format(
		"Quick Sort Visualizer\nState: %s | Size: %d | Pattern: %s | Seed: %d",
		state,
		metadata.size,
		metadata.pattern,
		metadata.seed
	)

	-- Write the numeric metrics into the lower label.
	self._metricsLabel.Text = string.format(
		"Steps: %d / %d\nComparisons: %d\nSwaps: %d\nReads: %d | Writes: %d\nPartitions: %d | Max recursion depth: %d\nRecording time: %.4fs",
		stepIndex,
		stepCount,
		metrics.comparisons,
		metrics.swaps,
		metrics.reads,
		metrics.writes,
		metrics.partitions,
		metrics.recursionDepth,
		metrics.executionTimeSeconds
	)
end

function BarRenderer:HighlightCompare(indexA: number, indexB: number)
	-- Comparing two values should not move them.
	-- I only change their color here so the viewer knows which bars are being checked.
	self:GetBar(indexA).Color = COLORS.Compare
	self:GetBar(indexB).Color = COLORS.Compare
end

function BarRenderer:SwapBars(indexA: number, indexB: number)
	local barA = self:GetBar(indexA)
	local barB = self:GetBar(indexB)

	-- First I swap the mapping.
	-- This means "the bar that used to belong to slot A now belongs to slot B", and vice versa.
	self._indexToBar[indexA] = barB
	self._indexToBar[indexB] = barA

	-- Then I move the physical bars to match the new mapping.
	-- I recalculate each destination using that bar's own height so the base stays on the floor.
	self:_tweenBar(barA, nil, self:_calcBarPosition(indexB, self._barCount, barA.Size.Y))
	self:_tweenBar(barB, nil, self:_calcBarPosition(indexA, self._barCount, barB.Size.Y))

	barA.Color = COLORS.Swap
	barB.Color = COLORS.Swap
end

function BarRenderer:SetPivot(index: number, active: boolean)
	-- Pivot state is temporary, so it returns to the default palette when the pivot is no longer active.
	local bar = self:GetBar(index)
	bar.Color = if active then COLORS.Pivot else COLORS.Default
end

function BarRenderer:ShowRange(startIndex: number, endIndex: number)
	self:HideRange()

	-- Quicksort only works on one slice of the array at a time.
	-- This white box shows which section is currently active.
	local firstBar = self:GetBar(startIndex)
	local lastBar = self:GetBar(endIndex)
	local width = math.abs(lastBar.Position.X - firstBar.Position.X) + BAR_WIDTH + 1

	local adornment = Instance.new("BoxHandleAdornment")
	adornment.Name = "ActiveRangeAdornment"
	adornment.Adornee = self._platform
	adornment.AlwaysOnTop = true
	adornment.ZIndex = 10
	adornment.Transparency = 0.7
	adornment.Color3 = COLORS.Range
	adornment.Size = Vector3.new(width, 1, BAR_DEPTH + 2)
	adornment.CFrame = CFrame.new(
		Vector3.new(
			(firstBar.Position.X + lastBar.Position.X) * 0.5,
			1.6,
			firstBar.Position.Z - 0.2
		)
	)
	adornment.Parent = self._container

	self._rangeAdornment = adornment
end

function BarRenderer:HideRange()
	-- There is either one active range highlight or none, so destroying the old adornment keeps the state simple.
	if self._rangeAdornment ~= nil then
		self._rangeAdornment:Destroy()
		self._rangeAdornment = nil
	end
end

function BarRenderer:MarkSorted(index: number)
	-- Sorted bars get a persistent color so the final order accumulates visually over time.
	self:GetBar(index).Color = COLORS.Sorted
end

function BarRenderer:ResetColors()
	-- Sorted bars keep their solved color while temporary compare and swap colors are cleared away.
	for _, bar in self._indexToBar do
		if bar.Color ~= COLORS.Sorted then
			bar.Color = COLORS.Default
		end
	end
end

function BarRenderer:Reset(values: { number })
	-- Reset rebuilds the current dataset from scratch and clears any leftover range highlight.
	-- Remove the old range highlight first.
	self:HideRange()
	-- Then draw the bars from the supplied values.
	self:Render(values)
end

local PlaybackController = {}
PlaybackController.__index = PlaybackController

function PlaybackController.new(renderer: any)
	-- Playback stays separate so a recorded run can be replayed deterministically.
	-- This also keeps the renderer independent from the algorithm implementation.
	return setmetatable({
		-- Renderer object that will receive visual update commands.
		_renderer = renderer,
		-- Current loaded recording, or nil if nothing is loaded yet.
		_recording = nil :: Recording?,
		-- Metrics snapshot for the current run.
		_metrics = nil :: MetricsSnapshot?,
		-- Current playback state string.
		_state = "Preparing" :: PlaybackState,
		-- Current playback speed multiplier.
		_speed = 1,
		-- Index of the last step that has been played.
		_currentStepIndex = 0,
		-- Current array values as playback advances.
		_currentValues = {} :: { number },
		-- Counter used to stop older playback loops.
		_runId = 0,
	}, PlaybackController)
end

local function getStepDelay(step: VisualizationStep, speed: number): number
	-- Sorted markers and the final completion step are quick punctuation beats, not the main motion.
	if step.type == "markSorted" or step.type == "done" then
		-- Return a very short delay for visual punctuation steps.
		return 0.02
	end

	-- Scale the default delay by the current playback speed.
	return 0.12 / math.max(speed, 0.25)
end

function PlaybackController:SetSpeed(multiplier: number)
	-- Renderer speed is updated too so animation timing and playback timing stay synchronized.
	-- Save the playback speed locally.
	self._speed = math.max(multiplier, 0.25)
	-- Tell the renderer to use the same speed for tweens.
	self._renderer:SetSpeedMultiplier(self._speed)
end

function PlaybackController:Load(recording: Recording, metrics: MetricsSnapshot)
	-- This loads a finished recording and resets the visualizer back to the unsorted starting point.
	-- Nothing is animated yet. It just prepares the replay.
	-- Store the loaded recording and its metrics.
	self._recording = recording
	self._metrics = metrics
	-- Reset the played-step counter back to the beginning.
	self._currentStepIndex = 0
	-- Restore the starting array values.
	self._currentValues = Utility.CloneArray(recording.initialValues)
	-- Rebuild the bar view from the starting values.
	self._renderer:Reset(self._currentValues)
	-- Mark playback as prepared but not yet playing.
	self._state = "Preparing"
	-- Advance the run id so older playback loops can no longer continue.
	self._runId += 1
	-- Update the board to show the prepared state.
	self._renderer:UpdateStatus(self._state, recording.metadata, metrics, 0, #recording.steps)
end

function PlaybackController:StepForward(): boolean
	if self._recording == nil or self._metrics == nil then
		-- If nothing is loaded, there is no step to play.
		return false
	end

	-- Playback reads one saved step and turns it back into visible behavior.
	-- In other words, this is the function that turns "recorded sort history" into animation.
	if self._currentStepIndex >= #self._recording.steps then
		-- If the recording is already at the end, mark playback as completed.
		self._state = "Completed"
		self._renderer:UpdateStatus(self._state, self._recording.metadata, self._metrics, self._currentStepIndex, #self._recording.steps)
		return false
	end

	-- Move to the next step in the recording.
	self._currentStepIndex += 1
	-- Read the step that should be applied now.
	local step = self._recording.steps[self._currentStepIndex]
	-- Clear temporary highlight colors before applying the new step.
	self._renderer:ResetColors()

	-- Each step type means a different visual action.
	-- I keep this explicit on purpose so the connection between the saved step and the on-screen
	-- result is easy to read.
	if step.type == "compare" then
		-- Highlight the two bars being compared.
		self._renderer:HighlightCompare(step.indexA, step.indexB)
	elseif step.type == "swap" then
		-- Swap the saved array values so playback state matches the visual swap.
		self._currentValues[step.indexA], self._currentValues[step.indexB] = self._currentValues[step.indexB], self._currentValues[step.indexA]
		-- Animate the two bars trading places.
		self._renderer:SwapBars(step.indexA, step.indexB)
	elseif step.type == "pivot" then
		-- Turn pivot highlighting on or off for one bar.
		self._renderer:SetPivot(step.index, step.active)
	elseif step.type == "range" then
		-- Show which part of the array quicksort is working on.
		self._renderer:ShowRange(step.startIndex, step.endIndex)
	elseif step.type == "markSorted" then
		-- Mark one bar as permanently sorted.
		self._renderer:MarkSorted(step.index)
	elseif step.type == "done" then
		-- Hide the range box because the run is finished.
		self._renderer:HideRange()
	end

	if step.type == "done" then
		-- Update the playback state once the final step is reached.
		self._state = "Completed"
	end

	-- Refresh the board after applying the step.
	self._renderer:UpdateStatus(self._state, self._recording.metadata, self._metrics, self._currentStepIndex, #self._recording.steps)

	return true
end

function PlaybackController:Play()
	if self._recording == nil then
		-- If no recording was loaded yet, there is nothing to play.
		return
	end

	-- If a new run starts while an older one is still playing, the older one should stop.
	-- This run id is a simple way to make sure only the newest playback loop stays alive.
	-- Increase the run id so any older playback loop becomes outdated.
	self._runId += 1
	-- Save the current run id for this specific playback loop.
	local activeRunId = self._runId
	-- Mark playback as actively playing.
	self._state = "Playing"
	-- Update the board right away so the viewer sees that playback started.
	self._renderer:UpdateStatus(self._state, self._recording.metadata, self._metrics :: MetricsSnapshot, self._currentStepIndex, #self._recording.steps)

	task.spawn(function()
		-- The loop runs in its own task so a newer run can supersede it without stalling the script.
		while self._recording ~= nil and self._currentStepIndex < #self._recording.steps do
			if activeRunId ~= self._runId then
				-- Stop this loop if another playback run has started after it.
				return
			end

			-- Play one saved step.
			local didAdvance = self:StepForward()
			if not didAdvance then
				-- Stop if playback could not advance any further.
				return
			end

			-- Read the step that just played so the delay can match that step type.
			local currentStep = self._recording.steps[self._currentStepIndex]
			-- Wait before moving on to the next recorded step.
			task.wait(getStepDelay(currentStep, self._speed))
		end
	end)
end

local function prepareDemo(playback: any, seed: number, pattern: DatasetPattern)
	-- This is one full demo cycle:
	-- 1. build the dataset
	-- 2. record the quicksort run
	-- 3. play the saved steps on screen
	-- Build the array values for the next run.
	local values = DataGenerator.Generate(DEFAULT_SIZE, pattern, seed)
	-- Record the full quicksort run and collect its metrics.
	local recording, metrics = QuickSort.Run(values, pattern, seed)
	-- Load the recording into the playback system.
	playback:Load(recording, metrics)
	-- Start playing the saved recording.
	playback:Play()
end

-- Create the renderer object that owns the visible Roblox instances.
local renderer = BarRenderer.new()
-- Use the "Quick" tween preset for bar movement.
renderer:SetAnimationMode("Quick")

-- Create the playback controller and give it the renderer.
local playback = PlaybackController.new(renderer)
-- Speed the playback up slightly so the full demo moves at a better pace.
playback:SetSpeed(1.35)

-- Build the workspace objects once before the repeating demo loop starts.
renderer:Init()

task.spawn(function()
	-- Start from a fixed seed so the sequence can be reproduced later.
	local seed = DEFAULT_SEED
	-- Rotate through several dataset patterns instead of showing only one type of input forever.
	local patterns: { DatasetPattern } = { DEFAULT_PATTERN, "Random", "FewUnique", "Reversed" }
	-- Start at the first pattern in the list.
	local patternIndex = 1

	while true do
		-- Rotating patterns makes the place show several input characteristics instead of repeating only one case forever.
		-- Read the current pattern from the list.
		local pattern = patterns[patternIndex]
		-- Run one full generate -> record -> playback cycle.
		prepareDemo(playback, seed, pattern)

		-- Move to a new seed for the next run.
		seed += 17
		-- Advancing the seed by a fixed step keeps the sequence reproducible across sessions.
		-- Advance to the next pattern and wrap back to 1 after the last one.
		patternIndex = (patternIndex % #patterns) + 1

		-- Pause briefly before starting the next automatic demo cycle.
		task.wait(LOOP_DELAY_SECONDS + 8)
	end
end)
