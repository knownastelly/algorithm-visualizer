--!strict

local Types = require(script.Parent.Types)
local SeededRandom = require(script.Parent.SeededRandom)
local Utility = require(script.Parent.Utility)

type DatasetConfig = Types.DatasetConfig

local DEFAULT_MIN_VALUE = 8
local DEFAULT_MAX_VALUE = 90

local DataGenerator = {}

local function getRandomStream(seed: number?)
	if seed ~= nil then
		return SeededRandom.new(seed)
	end

	local random = Random.new()
	return {
		NextInteger = function(_: any, minimum: number, maximum: number): number
			return random:NextInteger(minimum, maximum)
		end,
	}
end

local function buildRandomDataset(size: number, minimum: number, maximum: number, seed: number?): { number }
	local randomStream = getRandomStream(seed)
	local values = table.create(size)

	for index = 1, size do
		values[index] = randomStream:NextInteger(minimum, maximum)
	end

	return values
end

local function applyNearlySorted(values: { number })
	local swapCount = math.max(1, math.floor(#values * 0.12))

	for index = 1, swapCount do
		local a = math.max(1, math.min(#values, index * 2))
		local b = math.max(1, math.min(#values, a + 1))
		values[a], values[b] = values[b], values[a]
	end
end

local function applyReversed(values: { number })
	table.sort(values, function(left, right)
		return left > right
	end)
end

local function applyFewUnique(values: { number }, minimum: number, maximum: number)
	local uniqueValues = {
		minimum,
		math.floor((minimum + maximum) * 0.5),
		maximum,
	}

	for index = 1, #values do
		values[index] = uniqueValues[((index - 1) % #uniqueValues) + 1]
	end
end

function DataGenerator.Generate(config: DatasetConfig): { number }
	assert(config.size > 1, "Dataset size must be greater than 1")

	local minimum = config.minValue or DEFAULT_MIN_VALUE
	local maximum = config.maxValue or DEFAULT_MAX_VALUE
	local values = buildRandomDataset(config.size, minimum, maximum, config.seed)

	table.sort(values)

	if config.pattern == "Random" then
		values = buildRandomDataset(config.size, minimum, maximum, config.seed)
	elseif config.pattern == "NearlySorted" then
		applyNearlySorted(values)
	elseif config.pattern == "Reversed" then
		applyReversed(values)
	elseif config.pattern == "FewUnique" then
		applyFewUnique(values, minimum, maximum)
	end

	return Utility.CloneArray(values)
end

return DataGenerator
