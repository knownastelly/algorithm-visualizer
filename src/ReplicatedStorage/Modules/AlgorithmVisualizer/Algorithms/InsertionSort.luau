--!strict

local InsertionSort = {}

function InsertionSort.Run(input, recorder, metrics)
	for index = 2, #input do
		local currentValue = input[index]
		local position = index - 1

		metrics:IncrementReads(1)

		while position >= 1 do
			recorder:Record({
				type = "compare",
				indexA = position,
				indexB = position + 1,
			})
			metrics:IncrementComparisons(1)
			metrics:IncrementReads(1)

			if input[position] <= currentValue then
				break
			end

			input[position + 1] = input[position]
			recorder:Record({
				type = "overwrite",
				index = position + 1,
				value = input[position],
				sourceIndex = position,
			})
			metrics:IncrementWrites(1)
			position -= 1
			recorder:CommitSnapshot(input)
		end

		input[position + 1] = currentValue
		recorder:Record({
			type = "overwrite",
			index = position + 1,
			value = currentValue,
			sourceIndex = index,
		})
		metrics:IncrementWrites(1)
		recorder:CommitSnapshot(input)
	end

	for index = 1, #input do
		recorder:Record({
			type = "markSorted",
			index = index,
		})
	end
end

return InsertionSort
