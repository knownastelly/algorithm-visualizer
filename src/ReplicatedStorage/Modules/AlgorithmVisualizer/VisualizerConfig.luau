--!strict

local Config = {
	Enabled = true,
	AlgorithmId = "BubbleSort",
	Pattern = "Random",
	Size = 20,
	Seed = 1337,
	Speed = 1,
	AnimationMode = "Smooth",
	AutoPlayOnJoin = true,
	AutoStartOnServer = true,
	Camera = {
		Enabled = true,
		Center = Vector3.new(0, 0, -110),
		Offset = Vector3.new(0, 28, 110),
		FocusOffset = Vector3.new(0, 14, 0),
		FieldOfView = 42,
	},
}

return Config
