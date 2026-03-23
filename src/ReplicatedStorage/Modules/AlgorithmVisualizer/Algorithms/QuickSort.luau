--!strict

local QuickSort = {}

local function partition(input, recorder, metrics, low, high)
	local pivotValue = input[high]
	local smallerIndex = low - 1

	metrics:IncrementPartitions(1)
	metrics:IncrementReads(1)
	recorder:Record({
		type = "range",
		startIndex = low,
		endIndex = high,
		label = "Partition",
	})
	recorder:Record({
		type = "pivot",
		index = high,
		active = true,
	})

	for index = low, high - 1 do
		recorder:Record({
			type = "compare",
			indexA = index,
			indexB = high,
		})
		metrics:IncrementComparisons(1)
		metrics:IncrementReads(1)

		if input[index] <= pivotValue then
			smallerIndex += 1

			if smallerIndex ~= index then
				input[smallerIndex], input[index] = input[index], input[smallerIndex]
				recorder:Record({
					type = "swap",
					indexA = smallerIndex,
					indexB = index,
				})
				metrics:IncrementSwaps(1)
				metrics:IncrementWrites(2)
				recorder:CommitSnapshot(input)
			end
		end
	end

	local pivotIndex = smallerIndex + 1
	input[pivotIndex], input[high] = input[high], input[pivotIndex]
	recorder:Record({
		type = "swap",
		indexA = pivotIndex,
		indexB = high,
	})
	recorder:Record({
		type = "pivot",
		index = pivotIndex,
		active = false,
	})
	recorder:Record({
		type = "markSorted",
		index = pivotIndex,
	})
	metrics:IncrementSwaps(1)
	metrics:IncrementWrites(2)
	recorder:CommitSnapshot(input)

	return pivotIndex
end

local function quickSort(input, recorder, metrics, low, high, depth)
	if low > high then
		return
	end

	metrics:PushRecursionDepth(depth)

	if low == high then
		recorder:Record({
			type = "markSorted",
			index = low,
		})
		return
	end

	local pivotIndex = partition(input, recorder, metrics, low, high)
	quickSort(input, recorder, metrics, low, pivotIndex - 1, depth + 1)
	quickSort(input, recorder, metrics, pivotIndex + 1, high, depth + 1)
end

function QuickSort.Run(input, recorder, metrics)
	quickSort(input, recorder, metrics, 1, #input, 1)
end

return QuickSort
