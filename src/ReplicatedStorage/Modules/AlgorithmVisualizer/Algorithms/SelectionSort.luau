--!strict

local SelectionSort = {}

function SelectionSort.Run(input, recorder, metrics)
	local length = #input

	for sortedIndex = 1, length do
		local smallestIndex = sortedIndex

		for index = sortedIndex + 1, length do
			recorder:Record({
				type = "compare",
				indexA = smallestIndex,
				indexB = index,
			})
			metrics:IncrementComparisons(1)
			metrics:IncrementReads(2)

			if input[index] < input[smallestIndex] then
				smallestIndex = index
			end
		end

		if smallestIndex ~= sortedIndex then
			input[sortedIndex], input[smallestIndex] = input[smallestIndex], input[sortedIndex]
			recorder:Record({
				type = "swap",
				indexA = sortedIndex,
				indexB = smallestIndex,
			})
			metrics:IncrementSwaps(1)
			metrics:IncrementWrites(2)
			recorder:CommitSnapshot(input)
		end

		recorder:Record({
			type = "markSorted",
			index = sortedIndex,
		})
	end
end

return SelectionSort
