--!strict

local BubbleSort = {}

function BubbleSort.Run(input, recorder, metrics)
	local length = #input

	for endIndex = length, 2, -1 do
		for index = 1, endIndex - 1 do
			recorder:Record({
				type = "compare",
				indexA = index,
				indexB = index + 1,
			})
			metrics:IncrementComparisons(1)
			metrics:IncrementReads(2)

			if input[index] > input[index + 1] then
				input[index], input[index + 1] = input[index + 1], input[index]
				recorder:Record({
					type = "swap",
					indexA = index,
					indexB = index + 1,
				})
				metrics:IncrementSwaps(1)
				metrics:IncrementWrites(2)
			end

			recorder:CommitSnapshot(input)
		end

		recorder:Record({
			type = "markSorted",
			index = endIndex,
		})
	end

	recorder:Record({
		type = "markSorted",
		index = 1,
	})
end

return BubbleSort
