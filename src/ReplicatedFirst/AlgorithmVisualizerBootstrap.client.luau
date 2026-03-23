--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

print("[AlgorithmVisualizer] ReplicatedFirst camera bootstrap starting")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AlgorithmVisualizerFolder = Modules:WaitForChild("AlgorithmVisualizer")
local VisualizerConfig = require(AlgorithmVisualizerFolder:WaitForChild("VisualizerConfig"))
local remotesFolder = ReplicatedStorage:WaitForChild("AlgorithmVisualizerRemotes")
local snapshotRemote = remotesFolder:WaitForChild("GetSnapshot") :: RemoteFunction
local stateRemote = remotesFolder:WaitForChild("StateUpdated") :: RemoteEvent

if not VisualizerConfig.Enabled or not VisualizerConfig.Camera.Enabled then
	print("[AlgorithmVisualizer] Camera bootstrap disabled by config")
	return
end

local RENDER_STEP_NAME = "AlgorithmVisualizerFixedCamera"
local cameraConfig = VisualizerConfig.Camera
local currentSize = VisualizerConfig.Size

local function getDynamicCameraOffset(): Vector3
	local extraBars = math.max(0, currentSize - 20)
	local distanceOffset = extraBars * 0.85
	local heightOffset = extraBars * 0.14

	return cameraConfig.Offset + Vector3.new(0, heightOffset, distanceOffset)
end

local function applyFixedCamera()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = cameraConfig.FieldOfView
	camera.CFrame = CFrame.lookAt(
		cameraConfig.Center + getDynamicCameraOffset(),
		cameraConfig.Center + cameraConfig.FocusOffset
	)
end

local didBoot, bootError = pcall(function()
	local initialSnapshot = snapshotRemote:InvokeServer()
	if initialSnapshot ~= nil and initialSnapshot.configuration ~= nil then
		currentSize = initialSnapshot.configuration.size or currentSize
	end

	applyFixedCamera()

	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		applyFixedCamera()
	end)

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		applyFixedCamera()
	end)

	stateRemote.OnClientEvent:Connect(function(snapshot)
		if snapshot ~= nil and snapshot.configuration ~= nil then
			currentSize = snapshot.configuration.size or currentSize
		end
	end)
end)

if didBoot then
	print("[AlgorithmVisualizer] ReplicatedFirst camera bootstrap complete")
else
	warn("[AlgorithmVisualizer] ReplicatedFirst camera bootstrap failed:", bootError)
end
