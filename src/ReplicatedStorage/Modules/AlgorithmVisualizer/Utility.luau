--!strict

local Utility = {}

function Utility.CloneArray(values: { number }): { number }
	local clone = table.create(#values)

	for index, value in values do
		clone[index] = value
	end

	return clone
end

function Utility.Lerp(a: number, b: number, alpha: number): number
	return a + ((b - a) * alpha)
end

return Utility
