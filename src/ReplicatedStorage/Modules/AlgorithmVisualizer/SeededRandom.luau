--!strict

local MODULUS = 2 ^ 31
local MULTIPLIER = 1103515245
local INCREMENT = 12345

local SeededRandom = {}
SeededRandom.__index = SeededRandom

export type SeededRandom = typeof(setmetatable({} :: {
	_state: number,
}, SeededRandom))

function SeededRandom.new(seed: number): SeededRandom
	return setmetatable({
		_state = math.floor(seed) % MODULUS,
	}, SeededRandom)
end

function SeededRandom:NextNumber(): number
	self._state = ((self._state * MULTIPLIER) + INCREMENT) % MODULUS
	return self._state / MODULUS
end

function SeededRandom:NextInteger(minimum: number, maximum: number): number
	return math.floor(self:NextNumber() * ((maximum - minimum) + 1)) + minimum
end

return SeededRandom
