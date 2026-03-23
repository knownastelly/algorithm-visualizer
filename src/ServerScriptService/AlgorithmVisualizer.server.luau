--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[AlgorithmVisualizer] Server bootstrap starting")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AlgorithmVisualizerFolder = Modules:WaitForChild("AlgorithmVisualizer")
local VisualizerController = require(AlgorithmVisualizerFolder:WaitForChild("VisualizerController"))
local VisualizerConfig = require(AlgorithmVisualizerFolder:WaitForChild("VisualizerConfig"))

if not VisualizerConfig.Enabled or not VisualizerConfig.AutoStartOnServer then
	print("[AlgorithmVisualizer] Server bootstrap disabled by config")
	return
end

local REMOTES_FOLDER_NAME = "AlgorithmVisualizerRemotes"
local COMMAND_REMOTE_NAME = "Command"
local SNAPSHOT_REMOTE_NAME = "GetSnapshot"
local STATE_REMOTE_NAME = "StateUpdated"

local PATTERN_OPTIONS = { "Random" }
local SIZE_OPTIONS = { 10, 20, 35, 50, 75, 100 }
local SPEED_OPTIONS = { 0.5, 1, 2, 4, 6, 8, 10, 50 }
local ANIMATION_OPTIONS = { "Smooth" }

local controller = VisualizerController.new()
local currentSpeed = VisualizerConfig.Speed
local currentAnimationMode = VisualizerConfig.AnimationMode
local currentConfig = {
	algorithmId = VisualizerConfig.AlgorithmId,
	pattern = VisualizerConfig.Pattern,
	size = VisualizerConfig.Size,
	seed = VisualizerConfig.Seed,
}

local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME) :: Folder?
if remotesFolder == nil then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = REMOTES_FOLDER_NAME
	remotesFolder.Parent = ReplicatedStorage
end

local commandRemote = remotesFolder:FindFirstChild(COMMAND_REMOTE_NAME) :: RemoteEvent?
if commandRemote == nil then
	commandRemote = Instance.new("RemoteEvent")
	commandRemote.Name = COMMAND_REMOTE_NAME
	commandRemote.Parent = remotesFolder
end

local snapshotRemote = remotesFolder:FindFirstChild(SNAPSHOT_REMOTE_NAME) :: RemoteFunction?
if snapshotRemote == nil then
	snapshotRemote = Instance.new("RemoteFunction")
	snapshotRemote.Name = SNAPSHOT_REMOTE_NAME
	snapshotRemote.Parent = remotesFolder
end

local stateRemote = remotesFolder:FindFirstChild(STATE_REMOTE_NAME) :: RemoteEvent?
if stateRemote == nil then
	stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = STATE_REMOTE_NAME
	stateRemote.Parent = remotesFolder
end

local function makeSnapshot()
	return {
		configuration = controller:GetCurrentConfiguration(),
		metrics = controller:GetCurrentMetrics(),
		playbackState = controller:GetPlaybackState(),
		algorithmIds = controller:GetAlgorithmIds(),
		currentSpeed = currentSpeed,
		currentAnimationMode = currentAnimationMode,
		patternOptions = PATTERN_OPTIONS,
		sizeOptions = SIZE_OPTIONS,
		speedOptions = SPEED_OPTIONS,
		animationOptions = ANIMATION_OPTIONS,
	}
end

local function publishState(targetPlayer: Player?)
	local snapshot = makeSnapshot()

	if targetPlayer ~= nil then
		stateRemote:FireClient(targetPlayer, snapshot)
	else
		stateRemote:FireAllClients(snapshot)
	end
end

local function prepareCurrentConfig()
	controller:Prepare({
		algorithmId = currentConfig.algorithmId,
		size = currentConfig.size,
		pattern = currentConfig.pattern,
		seed = currentConfig.seed,
	})
	controller:SetSpeed(currentSpeed)
	controller:SetAnimationMode(currentAnimationMode)
end

snapshotRemote.OnServerInvoke = function(_player)
	return makeSnapshot()
end

controller:Connect("Prepared", function()
	publishState()
end)

controller:Connect("PlaybackStateChanged", function()
	publishState()
end)

controller:Connect("SpeedChanged", function(speed)
	currentSpeed = speed
	publishState()
end)

controller:Connect("AnimationModeChanged", function(mode)
	currentAnimationMode = mode
	publishState()
end)

commandRemote.OnServerEvent:Connect(function(_player, commandName, payload)
	if commandName == "Play" then
		controller:Play()
	elseif commandName == "Pause" then
		controller:Pause()
	elseif commandName == "Reset" then
		controller:Reset()
		publishState()
	elseif commandName == "StepForward" then
		controller:StepForward()
		publishState()
	elseif commandName == "StepBack" then
		controller:StepBack()
		publishState()
	elseif commandName == "SetSpeed" then
		if type(payload) == "number" then
			controller:SetSpeed(payload)
		end
	elseif commandName == "SetAnimationMode" then
		if type(payload) == "string" then
			controller:SetAnimationMode(payload)
		end
	elseif commandName == "Prepare" and type(payload) == "table" then
		currentConfig.algorithmId = payload.algorithmId or currentConfig.algorithmId
		currentConfig.pattern = payload.pattern or currentConfig.pattern
		currentConfig.size = payload.size or currentConfig.size
		currentConfig.seed = payload.seed or currentConfig.seed
		prepareCurrentConfig()
	elseif commandName == "Rebuild" then
		currentConfig.seed += 1
		prepareCurrentConfig()
	end
end)

local didBoot, bootError = pcall(function()
	controller:Init()
	prepareCurrentConfig()

	if VisualizerConfig.AutoPlayOnJoin then
		controller:Play()
	end

	publishState()
end)

if didBoot then
	print("[AlgorithmVisualizer] Server bootstrap complete")
else
	warn("[AlgorithmVisualizer] Server bootstrap failed:", bootError)
end
