--!strict

local MergeSort = {}

local function merge(input, recorder, metrics, left, middle, right, depth)
	metrics:IncrementMerges(1)
	metrics:PushRecursionDepth(depth)
	recorder:Record({
		type = "range",
		startIndex = left,
		endIndex = right,
		label = "Merge",
	})

	local leftSlice = table.create((middle - left) + 1)
	local rightSlice = table.create(right - middle)

	for index = left, middle do
		table.insert(leftSlice, input[index])
		metrics:IncrementReads(1)
	end

	for index = middle + 1, right do
		table.insert(rightSlice, input[index])
		metrics:IncrementReads(1)
	end

	local leftIndex = 1
	local rightIndex = 1
	local targetIndex = left

	while leftIndex <= #leftSlice and rightIndex <= #rightSlice do
		recorder:Record({
			type = "compare",
			indexA = left + leftIndex - 1,
			indexB = middle + rightIndex,
		})
		metrics:IncrementComparisons(1)

		local useLeft = leftSlice[leftIndex] <= rightSlice[rightIndex]
		local nextValue = if useLeft then leftSlice[leftIndex] else rightSlice[rightIndex]

		input[targetIndex] = nextValue
		recorder:Record({
			type = "overwrite",
			index = targetIndex,
			value = nextValue,
		})
		metrics:IncrementWrites(1)

		if useLeft then
			leftIndex += 1
		else
			rightIndex += 1
		end

		targetIndex += 1
		recorder:CommitSnapshot(input)
	end

	while leftIndex <= #leftSlice do
		input[targetIndex] = leftSlice[leftIndex]
		recorder:Record({
			type = "overwrite",
			index = targetIndex,
			value = leftSlice[leftIndex],
		})
		metrics:IncrementWrites(1)
		leftIndex += 1
		targetIndex += 1
		recorder:CommitSnapshot(input)
	end

	while rightIndex <= #rightSlice do
		input[targetIndex] = rightSlice[rightIndex]
		recorder:Record({
			type = "overwrite",
			index = targetIndex,
			value = rightSlice[rightIndex],
		})
		metrics:IncrementWrites(1)
		rightIndex += 1
		targetIndex += 1
		recorder:CommitSnapshot(input)
	end
end

local function sortRange(input, recorder, metrics, left, right, depth)
	if left >= right then
		return
	end

	metrics:PushRecursionDepth(depth)
	local middle = math.floor((left + right) * 0.5)

	sortRange(input, recorder, metrics, left, middle, depth + 1)
	sortRange(input, recorder, metrics, middle + 1, right, depth + 1)
	merge(input, recorder, metrics, left, middle, right, depth)
end

function MergeSort.Run(input, recorder, metrics)
	sortRange(input, recorder, metrics, 1, #input, 1)

	for index = 1, #input do
		recorder:Record({
			type = "markSorted",
			index = index,
		})
	end
end

return MergeSort
