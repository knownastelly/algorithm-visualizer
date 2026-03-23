--!strict

local TweenService = game:GetService("TweenService")

local BAR_WIDTH = 3
local BAR_DEPTH = 3
local BAR_SPACING = 1
local HEIGHT_SCALE = 0.45
local VISUALIZER_CENTER = Vector3.new(0, 0, -110)

local ANIMATION_DURATIONS = {
	Instant = 0,
	Quick = 0.08,
	Smooth = 0.2,
}

local COLORS = {
	Default = Color3.fromRGB(240, 240, 240),
	Compare = Color3.fromRGB(255, 209, 84),
	Swap = Color3.fromRGB(255, 100, 100),
	Sorted = Color3.fromRGB(89, 214, 115),
	Pivot = Color3.fromRGB(112, 170, 255),
	Range = Color3.fromRGB(255, 255, 255),
}

local BarRenderer = {}
BarRenderer.__index = BarRenderer

export type BarRenderer = typeof(setmetatable({} :: {
	_container: Folder?,
	_platform: Part?,
	_barPool: { Part },
	_indexToBar: { [number]: Part },
	_rangeAdornment: BoxHandleAdornment?,
	_heightScale: number,
	_origin: Vector3,
	_barCount: number,
	_animationMode: string,
	_speedMultiplier: number,
}, BarRenderer))

function BarRenderer.new(): BarRenderer
	return setmetatable({
		_container = nil,
		_platform=nil,
		_barPool = {},
		_indexToBar = {},
		_rangeAdornment = nil,
		_heightScale = HEIGHT_SCALE,
		_origin = Vector3.new(),
		_barCount = 0,
		_animationMode = "Quick",
		_speedMultiplier = 1,
	}, BarRenderer)
end

local function getOrCreateFolder(name: string, parent: Instance): Folder
	local folder = parent:FindFirstChild(name)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder :: Folder
end

function BarRenderer:Init()
	self._container = getOrCreateFolder("AlgorithmVisualizer", workspace)

	local platform = self._container:FindFirstChild("VisualizationPlatform") :: Part?
	if platform == nil then
		-- I keep the platform in one fixed place because the camera math is much easier to trust when the whole build has a stable anchor in the world.
		platform = Instance.new("Part")
		platform.Name = "VisualizationPlatform"
		platform.Anchored = true
		platform.Size = Vector3.new(180, 2, 40)
		platform.Color = Color3.fromRGB(33, 33, 40)
		platform.Material = Enum.Material.SmoothPlastic
		platform.Parent = self._container
	end

	platform.Position = VISUALIZER_CENTER
	self._platform = platform
	-- This ends up being the "floor line" for every bar. Once that origin is right, all of the later placement math can stay simple.
	self._origin = platform.Position + Vector3.new(0, platform.Size.Y * 0.5, 0)
end

function BarRenderer:_getBarFromPool(index: number): Part
	local bar=table.remove(self._barPool)

	if bar == nil then
		-- Reusing parts matters more than it sounds here. Rebuilds happen a lot while testing, and constantly recreating bars just adds noise and avoidable instance churn.
		bar = Instance.new("Part")
		bar.Anchored = true
		bar.Material = Enum.Material.SmoothPlastic
	end

	bar.Name = `Bar_{index}`
	bar.Parent = self._container
	bar.Transparency = 0
	bar.Color = COLORS.Default

	self._indexToBar[index] = bar

	return bar
end

function BarRenderer:_releaseExtraBars(count: number)
	for index, bar in self._indexToBar do
		if index > count then
			-- I only detach extras instead of destroying them so the next render can grab them back without paying the setup cost again.
			bar.Parent = nil
			table.insert(self._barPool, bar)
			self._indexToBar[index] = nil
		end
	end
end

function BarRenderer:_calcXPosition(index: number, count: number): Vector3
	-- The bars need to stay centered as a group, otherwise changing the array size makes the whole visualization drift to one side and the camera framing starts to feel wrong.
	local totalWidth = count * BAR_WIDTH + (count - 1)* BAR_SPACING
	local left = self._origin.X - totalWidth * 0.5 + BAR_WIDTH * 0.5
	local x = left + (index - 1) * (BAR_WIDTH + BAR_SPACING)

	return Vector3.new(x, self._origin.Y, self._origin.Z)
end

function BarRenderer:_getBarHeight(value: number): number
	-- The minimum height is there so tiny values still exist visually and do not disappear into the platform.
	return math.max(1, value * self._heightScale)
end

function BarRenderer:_calcBarPosition(index: number, count: number, height: number): Vector3
	local basePosition = self:_calcXPosition(index, count)
	-- Roblox positions parts from the center, not the bottom, so half the height has to be added here. If I skip that, short bars sink and tall bars hover.
	return basePosition + Vector3.new(0, height * 0.5, 0)
end

function BarRenderer:_getTweenDuration(): number
	local baseDuration = ANIMATION_DURATIONS[self._animationMode] or ANIMATION_DURATIONS.Quick
	-- Playback speed and tween speed have to move together. If the playback loop speeds up but the tween stays long, the bars start stacking animations and the whole thing reads badly.
	local speed = math.max( self._speedMultiplier, 0.25)
	return baseDuration / speed
end

function BarRenderer:SetAnimationMode(mode: string)
	if ANIMATION_DURATIONS[mode] == nil then
		return
	end

	self._animationMode = mode
end

function BarRenderer:SetSpeedMultiplier(speedMultiplier: number)
	self._speedMultiplier = math.max(speedMultiplier,0.25)
end

function BarRenderer:_tweenBar(bar: Part, size: Vector3?, position: Vector3?)
	local duration = self:_getTweenDuration()

	if duration <= 0 then
		if size then
			bar.Size = size
		end
		if position then
			bar.Position = position
		end
		return
	end

	local goals : { [string]: Vector3 } = {}
	if size then
		goals.Size = size
	end
	if position then
		goals.Position = position
	end

	local tween = TweenService:Create(
		bar,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
end

function BarRenderer:Render(values: { number })
	self:Init()
	self._barCount =#values
	self:_releaseExtraBars(#values)

	for index, value in values do
		local bar = self._indexToBar[index]
		if not bar then
			bar = self:_getBarFromPool(index)
		end

		-- Keeping bars keyed by array index is what lets playback stay data-driven. I never need to search the workspace and guess which bar belongs to which value.
		local height=self:_getBarHeight(value)
		bar.Size = Vector3.new(BAR_WIDTH, height, BAR_DEPTH)
		bar.Position = self:_calcBarPosition(index, #values, height)
		bar.Color = COLORS.Default
	end
end

function BarRenderer:GetBar(index: number): Part
	local bar = self._indexToBar[index]
	assert( bar, `Missing bar for index {index}`)
	return bar
end

function BarRenderer:UpdateBar(index: number, value: number, count: number)
	local bar = self:GetBar(index)
	local height=self:_getBarHeight(value)

	-- Overwrite steps show up in things like merge and insertion sort, so this path updates the bar in place instead of pretending every change is a swap.
	self:_tweenBar(
		bar,
		Vector3.new(BAR_WIDTH, height, BAR_DEPTH),
		self:_calcBarPosition(index, count, height)
	)

	bar.Color = COLORS.Swap
end

function BarRenderer:SwapBars(indexA: number, indexB: number)
	local barA = self:GetBar(indexA)
	local barB = self:GetBar(indexB)

	self._indexToBar[indexA] = barB
	self._indexToBar[indexB] = barA

	-- This is the part that fixes the floating-bar problem: each target position is rebuilt from that bar's own height instead of reusing the other bar's full position.
	self:_tweenBar(barA, nil, self:_calcBarPosition(indexB, self._barCount, barA.Size.Y))
	self:_tweenBar(barB,nil, self:_calcBarPosition(indexA, self._barCount, barB.Size.Y))

	barA.Color = COLORS.Swap
	barB.Color = COLORS.Swap
end

function BarRenderer:HighlightCompare(indexA: number, indexB: number)
	self:GetBar(indexA).Color = COLORS.Compare
	self:GetBar(indexB).Color = COLORS.Compare
end

function BarRenderer:MarkSorted(index: number)
	self:GetBar(index).Color = COLORS.Sorted
end

function BarRenderer:SetPivot(index: number, active: boolean)
	local bar = self:GetBar(index)
	if active then
		bar.Color = COLORS.Pivot
	else
		bar.Color = COLORS.Default
	end
end

function BarRenderer:ShowRange(startIndex: number, endIndex: number)
	self:HideRange()

	local firstBar = self:GetBar(startIndex)
	local lastBar = self:GetBar(endIndex)
	-- Range highlighting became important once recursive algorithms were in the mix, because otherwise merge sort and quick sort just look like random motion.
	local width = math.abs(lastBar.Position.X - firstBar.Position.X) + BAR_WIDTH + 1

	local adornment = Instance.new("BoxHandleAdornment")
	adornment.Name = "ActiveRangeAdornment"
	adornment.Adornee = self._platform
	adornment.AlwaysOnTop = true
	adornment.ZIndex = 10
	adornment.Transparency = 0.7
	adornment.Color3 = COLORS.Range
	-- I measure from the bars that are actually on screen, not from the original indices, so the range stays honest even after bars have been moved around.
	adornment.Size = Vector3.new(width, 1, BAR_DEPTH + 2)
	adornment.CFrame = CFrame.new(
		Vector3.new(
			(firstBar.Position.X + lastBar.Position.X) * 0.5,
			1.6,
			firstBar.Position.Z - 0.2
		)
	)
	adornment.Parent = self._container

	self._rangeAdornment = adornment
end

function BarRenderer:HideRange()
	if self._rangeAdornment then
		self._rangeAdornment:Destroy()
		self._rangeAdornment = nil
	end
end

function BarRenderer:ResetColors()
	for _, bar in self._indexToBar do
		if bar.Color ~= COLORS.Sorted then
			bar.Color = COLORS.Default
		end
	end
end

function BarRenderer:Reset(values: { number })
	self:HideRange()
	self:Render(values)
end

return BarRenderer
