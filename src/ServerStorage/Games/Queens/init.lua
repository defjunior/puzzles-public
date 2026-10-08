-- Actual Queens puzzle implementation; selected authored presentation/defaults omitted.
-- Generation/rules/session interfaces retained; missing assets/config prevent standalone use.
-- Authored board/session defaults omitted. Supply configuration before running.
local Puzzle = { Name = "Queens", ModeKey = "queens" }

local BASE_CELL_COLOR_A = nil -- Omitted: authored visual/cosmetic value.
local BASE_CELL_COLOR_B = nil -- Omitted: authored visual/cosmetic value.
local QUEEN_CELL_COLOR = nil -- Omitted: authored visual/cosmetic value.
local QUEEN_CONFLICT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local BLOCKED_CELL_COLOR = nil -- Omitted: authored visual/cosmetic value.
local BASE_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local BLOCKED_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.

local REGION_BORDER_COLOR = nil -- Omitted: authored visual/cosmetic value.
local OUTER_BORDER_COLOR = nil -- Omitted: authored visual/cosmetic value.
local REGION_BORDER_THICKNESS = 0.12
local OUTER_BORDER_THICKNESS = 0.16
local GRID_LINE_HEIGHT = 0.08
local GRID_ELEVATION = 0.4
local GRID_LENGTH_PADDING = 0.05

local QUEENS_INDICATOR_CATEGORY = nil -- Omitted: authored visual/cosmetic value.
local QUEENS_INDICATOR_DEFAULT = nil -- Omitted: authored visual/cosmetic value.
local CHESS_SKIN_ID = nil -- Omitted: authored visual/cosmetic value.

local Classes = game.ServerScriptService.Classes
local BoardClass = require(Classes:WaitForChild("Board"))
local NDimensionalBoard = require(game.ServerStorage.Modules:WaitForChild("NDimensionalBoard"))
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Framework = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Framework"))

local EXTRA_ND_BOARD_CONFIGS = {} -- Omitted: authored presets/dialogue.

local function rowColToIndex(row, col, width)
	return ((row - 1) * width) + col
end

local function indexToRowCol(index, width)
	local row = math.floor((index - 1) / width) + 1
	local col = ((index - 1) % width) + 1
	return row, col
end

local function blendColor(a, b, alpha)
	local t = math.clamp(alpha, 0, 1)
	return Color3.new(
		(a.R * (1 - t)) + (b.R * t),
		(a.G * (1 - t)) + (b.G * t),
		(a.B * (1 - t)) + (b.B * t)
	)
end

local function shuffleInPlace(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function getCardinalNeighbors(index, size)
	local row, col = indexToRowCol(index, size)
	local neighbors = {}
	if row > 1 then
		neighbors[#neighbors + 1] = rowColToIndex(row - 1, col, size)
	end
	if row < size then
		neighbors[#neighbors + 1] = rowColToIndex(row + 1, col, size)
	end
	if col > 1 then
		neighbors[#neighbors + 1] = rowColToIndex(row, col - 1, size)
	end
	if col < size then
		neighbors[#neighbors + 1] = rowColToIndex(row, col + 1, size)
	end
	return neighbors
end

local function getNDimensionalCardinalNeighbors(index, size, dimensions)
	local coords = NDimensionalBoard.IndexToCoords(index, size, dimensions)
	local neighbors = {}

	for dimension = 1, dimensions do
		local base = coords[dimension]
		for _, delta in ipairs({ -1, 1 }) do
			local value = base + delta
			if value >= 1 and value <= size then
				local neighborCoords = table.clone(coords)
				neighborCoords[dimension] = value
				neighbors[#neighbors + 1] = NDimensionalBoard.CoordsToIndex(neighborCoords, size, dimensions)
			end
		end
	end

	return neighbors
end

local function flattenOriginRotation(originCFrame)
	local position = originCFrame.Position
	local _, yaw, _ = originCFrame:ToOrientation()
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

local function resolveRotatableOrigin(container, preferredName)
	if not container then
		return nil
	end

	if container:IsA("BasePart") then
		return flattenOriginRotation(container.CFrame)
	end
	if container:IsA("Model") then
		return flattenOriginRotation(container:GetPivot())
	end

	local names = {}
	if type(preferredName) == "string" and preferredName ~= "" then
		names[#names + 1] = preferredName
	end
	for _, name in ipairs({ "Center", "Origin", "Origin1" }) do
		names[#names + 1] = name
	end

	for _, name in ipairs(names) do
		local candidate = container:FindFirstChild(name)
		if candidate then
			if candidate:IsA("BasePart") then
				return flattenOriginRotation(candidate.CFrame)
			end
			if candidate:IsA("Model") then
				return flattenOriginRotation(candidate:GetPivot())
			end
		end
	end

	local firstPart = container:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		return flattenOriginRotation(firstPart.CFrame)
	end

	if container:IsA("Model") then
		return flattenOriginRotation(container:GetPivot())
	end

	return nil
end

local function resolveBoardOrigin(originName)
	local origins = Workspace:FindFirstChild("Origins")
	local queensOrigins = origins and origins:FindFirstChild("Queens")
	if queensOrigins then
		local resolved = resolveRotatableOrigin(queensOrigins, originName)
		if resolved then
			return resolved
		end
	end
	return CFrame.new(84.5, 2, 55.5)
end

local function resolveSpecificBoardOrigin(originName)
	if type(originName) ~= "string" or originName == "" then
		return nil
	end
	local origins = Workspace:FindFirstChild("Origins")
	local queensOrigins = origins and origins:FindFirstChild("Queens")
	local candidate = queensOrigins and queensOrigins:FindFirstChild(originName)
	if candidate then
		local resolved = resolveRotatableOrigin(candidate)
		if resolved then
			return resolved
		end
	end
	return nil
end

local function offsetOrigin(originCFrame, studs)
	local origin = originCFrame or CFrame.new()
	local _, yaw, _ = origin:ToOrientation()
	return CFrame.new(origin.Position + (origin:VectorToWorldSpace(Vector3.new(studs, 0, 0)))) * CFrame.Angles(0, yaw, 0)
end

local function resolveOriginCFrame(originLike)
	if typeof(originLike) == "CFrame" then
		return originLike
	end
	if typeof(originLike) == "Vector3" then
		return CFrame.new(originLike)
	end
	return CFrame.new()
end

local function getDesiredMainCFrame(cell, anchorPart)
	local desiredPosition = cell.Position + Vector3.new(0, (cell.Size.Y * 0.5) + (anchorPart.Size.Y * 0.5), 0)
	local rotation = cell.CFrame - cell.Position
	return CFrame.new(desiredPosition) * rotation
end

local function alignModelOnCell(model, cell)
	local anchorPart = model:FindFirstChild("Main", true)
	if not (anchorPart and anchorPart:IsA("BasePart")) then
		anchorPart = model.PrimaryPart
	end
	if not (anchorPart and anchorPart:IsA("BasePart")) then
		anchorPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not (anchorPart and anchorPart:IsA("BasePart")) then
		return false
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	local currentPivot = model:GetPivot()
	local pivotToAnchor = currentPivot:ToObjectSpace(anchorPart.CFrame)
	local targetAnchor = getDesiredMainCFrame(cell, anchorPart)
	model:PivotTo(targetAnchor * pivotToAnchor:Inverse())
	return true
end

local function getFlagsFolder()
	local assets = ReplicatedFirst:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local flags = models and models:FindFirstChild("Flags")
	if flags and flags:IsA("Folder") then
		return flags
	end
	return nil
end

local function cloneQueenChessModel(chessRoot)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

local function tintModelBlackOrWhite(model)
	local useWhite = math.random() < 0.5
	local targetColor = useWhite and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(20, 20, 20)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = targetColor
		end
	end
end

function Puzzle:_baseColorForIndex(index)
	local row, col = indexToRowCol(index, self.Size)
	local regionId = self:_regionIdForIndex(index)
	local checker = ((row + col) % 2 == 0) and BASE_CELL_COLOR_A or BASE_CELL_COLOR_B
	local hue = ((regionId * 37) % 360) / 360
	local tint = Color3.fromHSV(hue, 0.28, 1)
	return blendColor(checker, tint, 0.38)
end

function Puzzle:_generateQueenColumns(size)
	local function solve(randomized)
		local columns = table.create(size, 0)
		local usedColumns = {}
		local usedDiagA = {}
		local usedDiagB = {}

		local function backtrack(row)
			if row > size then
				return true
			end

			local choices = table.create(size, 0)
			for col = 1, size do
				choices[col] = col
			end
			if randomized then
				shuffleInPlace(choices)
			end

			for _, col in ipairs(choices) do
				local diagA = row - col
				local diagB = row + col
				if not usedColumns[col] and not usedDiagA[diagA] and not usedDiagB[diagB] then
					columns[row] = col
					usedColumns[col] = true
					usedDiagA[diagA] = true
					usedDiagB[diagB] = true

					if backtrack(row + 1) then
						return true
					end

					usedColumns[col] = nil
					usedDiagA[diagA] = nil
					usedDiagB[diagB] = nil
				end
			end
			return false
		end

		if backtrack(1) then
			return columns
		end
		return nil
	end

	for _ = 1, 120 do
		local randomized = solve(true)
		if randomized then
			return randomized
		end
	end

	return solve(false)
end

function Puzzle:_generateRegionMap(size, queenColumns)
	local total = size * size
	local regionByIndex = table.create(total, 0)
	local queue = {}

	for regionId = 1, size do
		local seedIndex = rowColToIndex(regionId, queenColumns[regionId], size)
		regionByIndex[seedIndex] = regionId
		queue[#queue + 1] = seedIndex
	end

	while #queue > 0 do
		local queueIndex = math.random(1, #queue)
		local cellIndex = queue[queueIndex]
		queue[queueIndex] = queue[#queue]
		queue[#queue] = nil

		local regionId = regionByIndex[cellIndex]
		local neighbors = getCardinalNeighbors(cellIndex, size)
		shuffleInPlace(neighbors)
		for _, neighbor in ipairs(neighbors) do
			if regionByIndex[neighbor] == 0 then
				regionByIndex[neighbor] = regionId
				queue[#queue + 1] = neighbor
			end
		end
	end

	return regionByIndex
end

function Puzzle:_generateRegions(size)
	local queenColumns = self:_generateQueenColumns(size)
	if not queenColumns then
		queenColumns = table.create(size, 1)
		for row = 1, size do
			queenColumns[row] = row
		end
	end
	self.RegionSeeds = queenColumns
	self.RegionByIndex = self:_generateRegionMap(size, queenColumns)
end

function Puzzle:_generateNDQueenSeeds(size, dimensions)
	local seeds = table.create(size)
	local permutations = {}

	for dimension = 2, dimensions do
		local values = table.create(size)
		for value = 1, size do
			values[value] = value
		end
		permutations[dimension] = shuffleInPlace(values)
	end

	for regionId = 1, size do
		local coords = table.create(dimensions, 1)
		coords[1] = regionId
		for dimension = 2, dimensions do
			coords[dimension] = permutations[dimension][regionId]
		end
		seeds[regionId] = NDimensionalBoard.CoordsToIndex(coords, size, dimensions)
	end

	return seeds
end

function Puzzle:_generateNDRegionMap(size, dimensions, seeds)
	local total = NDimensionalBoard.TotalCells(size, dimensions)
	local regionByIndex = table.create(total, 0)
	local queue = {}

	for regionId = 1, size do
		local seedIndex = seeds[regionId]
		if seedIndex then
			regionByIndex[seedIndex] = regionId
			queue[#queue + 1] = seedIndex
		end
	end

	while #queue > 0 do
		local queueIndex = math.random(1, #queue)
		local cellIndex = queue[queueIndex]
		queue[queueIndex] = queue[#queue]
		queue[#queue] = nil

		local regionId = regionByIndex[cellIndex]
		local neighbors = getNDimensionalCardinalNeighbors(cellIndex, size, dimensions)
		shuffleInPlace(neighbors)
		for _, neighbor in ipairs(neighbors) do
			if regionByIndex[neighbor] == 0 then
				regionByIndex[neighbor] = regionId
				queue[#queue + 1] = neighbor
			end
		end
	end

	return regionByIndex
end

function Puzzle:_getCosmeticService()
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_getEquippedIndicatorId(player)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_ensureIndicatorFolder()
	if not (self.Board and self.Board.BoardFolder) then
		return nil
	end
	if self.IndicatorFolder and self.IndicatorFolder.Parent then
		return self.IndicatorFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "QueensIndicators"
	folder.Parent = self.Board.BoardFolder
	self.IndicatorFolder = folder
	return folder
end

function Puzzle:_clearIndicator(index)
	if type(self.ActiveIndicators) ~= "table" then
		return
	end
	local existing = self.ActiveIndicators[index]
	if existing then
		existing:Destroy()
		self.ActiveIndicators[index] = nil
	end
end

function Puzzle:_cloneIndicatorModel(indicatorId)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_placeIndicator(index, indicatorId)
	if not self.Board then
		return
	end
	local cell = self.Board:GetCell(index)
	if not cell then
		return
	end

	self:_clearIndicator(index)

	local folder = self:_ensureIndicatorFolder()
	if not folder then
		return
	end

	local clone = self:_cloneIndicatorModel(indicatorId)
	if not clone then
		return
	end
	clone.Name = ("Queen_%d"):format(index)
	if alignModelOnCell(clone, cell) then
		clone.Parent = folder
		self.ActiveIndicators[index] = clone
	else
		clone:Destroy()
	end
end

function Puzzle:_destroyIndicators()
	if type(self.ActiveIndicators) == "table" then
		for index, model in pairs(self.ActiveIndicators) do
			if model then
				model:Destroy()
			end
			self.ActiveIndicators[index] = nil
		end
	end
	if self.IndicatorFolder and self.IndicatorFolder.Parent then
		self.IndicatorFolder:Destroy()
	end
	self.IndicatorFolder = nil
end

function Puzzle:_buildEmptyNDState(config, projection, origin)
	local size = math.max(2, math.floor(tonumber(config.Size) or 4))
	local dimensions = math.max(3, math.floor(tonumber(config.Dimensions) or 4))
	local total = NDimensionalBoard.TotalCells(size, dimensions)
	local regionSeeds = self:_generateNDQueenSeeds(size, dimensions)
	return {
		Key = tostring(config.OriginName or "NDimensional"),
		Origin = origin,
		Projection = projection,
		Size = size,
		Dimensions = dimensions,
		TotalCells = total,
		PlayerMask = table.create(total, 0),
		RegionSeeds = regionSeeds,
		RegionByIndex = self:_generateNDRegionMap(size, dimensions, regionSeeds),
		RegionOverlayFolders = {},
		ActiveIndicators = {},
		Solved = false,
	}
end

function Puzzle:_clearNDIndicator(state, index)
	if type(state.ActiveIndicators) ~= "table" then
		return
	end
	local existing = state.ActiveIndicators[index]
	if existing then
		existing:Destroy()
		state.ActiveIndicators[index] = nil
	end
end

function Puzzle:_destroyNDStates()
	for _, state in ipairs(self.NDStates or {}) do
		if type(state.ActiveIndicators) == "table" then
			for index, model in pairs(state.ActiveIndicators) do
				if model then
					model:Destroy()
				end
				state.ActiveIndicators[index] = nil
			end
		end
		if type(state.RegionOverlayFolders) == "table" then
			for _, folder in pairs(state.RegionOverlayFolders) do
				if folder then
					folder:Destroy()
				end
			end
			table.clear(state.RegionOverlayFolders)
		end
		NDimensionalBoard.Destroy(state.Projection)
	end
	self.NDStates = {}
end

function Puzzle:_placeNDIndicator(state, index, indicatorId)
	local visual = state and state.Projection and state.Projection.GlobalToVisual[index]
	if not visual or not visual.Cell then
		return
	end

	self:_clearNDIndicator(state, index)

	local clone = self:_cloneIndicatorModel(indicatorId)
	if not clone then
		return
	end
	clone.Name = ("Queen_%d"):format(index)
	if alignModelOnCell(clone, visual.Cell) then
		clone.Parent = visual.Board.BoardFolder
		state.ActiveIndicators[index] = clone
	else
		clone:Destroy()
	end
end

function Puzzle:_baseNDColorForIndex(state, index)
	local coords = NDimensionalBoard.IndexToCoords(index, state.Size, state.Dimensions)
	local checker = (((coords[1] or 1) + (coords[2] or 1)) % 2 == 0) and BASE_CELL_COLOR_A or BASE_CELL_COLOR_B
	local regionId = state.RegionByIndex and tonumber(state.RegionByIndex[index]) or 0
	local hue = ((regionId * 37) % 360) / 360
	local tint = Color3.fromHSV(hue, 0.3, 1)
	return blendColor(checker, tint, 0.34)
end

function Puzzle:_isNDQueenConflict(state, index)
	if state.PlayerMask[index] ~= 1 then
		return false
	end

	local coords = NDimensionalBoard.IndexToCoords(index, state.Size, state.Dimensions)
	local myRegion = state.RegionByIndex and state.RegionByIndex[index] or 0
	for test = 1, state.TotalCells do
		if test ~= index and state.PlayerMask[test] == 1 then
			if myRegion ~= 0 and state.RegionByIndex and state.RegionByIndex[test] == myRegion then
				return true
			end
			local otherCoords = NDimensionalBoard.IndexToCoords(test, state.Size, state.Dimensions)
			for dimension = 1, state.Dimensions do
				if otherCoords[dimension] == coords[dimension] then
					return true
				end
			end
		end
	end
	return false
end

function Puzzle:_refreshNDVisuals(state)
	for index = 1, state.TotalCells do
		local visual = state.Projection.GlobalToVisual[index]
		if visual then
			visual.Cell:SetAttribute("PuzzleNDRegionId", state.RegionByIndex and state.RegionByIndex[index] or 0)
			local value = state.PlayerMask[index]
			if value == 1 then
				if self:_isNDQueenConflict(state, index) then
					visual.Board:SetCellColor(visual.LocalIndex, QUEEN_CONFLICT_COLOR)
				else
					visual.Board:SetCellColor(visual.LocalIndex, QUEEN_CELL_COLOR)
				end
				visual.Board:SetCellText(visual.LocalIndex, "", BASE_TEXT_COLOR)
			elseif value == 2 then
				visual.Board:SetCellColor(visual.LocalIndex, BLOCKED_CELL_COLOR)
				visual.Board:SetCellText(visual.LocalIndex, "X", BLOCKED_TEXT_COLOR)
			else
				visual.Board:SetCellColor(visual.LocalIndex, self:_baseNDColorForIndex(state, index))
				visual.Board:SetCellText(visual.LocalIndex, "", BASE_TEXT_COLOR)
			end
		end
	end
end

function Puzzle:_isNDSolved(state)
	local queens = {}
	for index = 1, state.TotalCells do
		if state.PlayerMask[index] == 1 then
			if self:_isNDQueenConflict(state, index) then
				return false
			end
			queens[#queens + 1] = index
		end
	end
	if #queens ~= state.Size then
		return false
	end

	for dimension = 1, state.Dimensions do
		local counts = table.create(state.Size, 0)
		for _, index in ipairs(queens) do
			local coords = NDimensionalBoard.IndexToCoords(index, state.Size, state.Dimensions)
			local value = coords[dimension]
			counts[value] = (counts[value] or 0) + 1
		end
		for value = 1, state.Size do
			if (counts[value] or 0) ~= 1 then
				return false
			end
		end
	end

	local regionCounts = {}
	for _, index in ipairs(queens) do
		local region = state.RegionByIndex and state.RegionByIndex[index] or 0
		regionCounts[region] = (regionCounts[region] or 0) + 1
	end
	for region = 1, state.Size do
		if (regionCounts[region] or 0) ~= 1 then
			return false
		end
	end

	return true
end

function Puzzle:_createGridLine(parent, cframe, size, color)
	local line = Instance.new("Part")
	line.Name = "GridLine"
	line.Anchored = true
	line.CanCollide = false
	line.CanTouch = false
	line.CanQuery = false
	line.Material = Enum.Material.SmoothPlastic
	line.CastShadow = false
	line.Color = color
	line.Size = size
	line.CFrame = cframe
	line.Parent = parent
end

function Puzzle:_buildRegionOverlay()
	if not self.Board or not self.Board.BoardFolder then
		return
	end

	if self.RegionOverlayFolder and self.RegionOverlayFolder.Parent then
		self.RegionOverlayFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "QueensRegions"
	folder.Parent = self.Board.BoardFolder
	self.RegionOverlayFolder = folder

	local settings = self.Board.Settings
	local originCFrame = resolveOriginCFrame(settings.origin)
	local xDirection = settings.xDirection
	local yDirection = settings.yDirection
	if typeof(xDirection) ~= "Vector3" or xDirection.Magnitude <= 0 then
		xDirection = Vector3.new(1, 0, 0)
	end
	if typeof(yDirection) ~= "Vector3" or yDirection.Magnitude <= 0 then
		yDirection = Vector3.new(0, 0, 1)
	end

	local xDir = originCFrame:VectorToWorldSpace(xDirection.Unit)
	local yDir = originCFrame:VectorToWorldSpace(yDirection.Unit)
	local normal = xDir:Cross(yDir)
	if normal.Magnitude <= 0 then
		normal = Vector3.new(0, 1, 0)
	else
		normal = normal.Unit
	end
	if normal.Y < 0 then
		normal = -normal
	end

	local boardCenter = originCFrame.Position
	local cellSize = tonumber(settings.cellSize) or 4
	local totalSpan = self.Size * cellSize
	local halfSpan = totalSpan * 0.5

	for row = 1, self.Size do
		local rowCenterOffset = -halfSpan + ((row - 0.5) * cellSize)
		for col = 1, (self.Size - 1) do
			local leftIndex = rowColToIndex(row, col, self.Size)
			local rightIndex = rowColToIndex(row, col + 1, self.Size)
			if self:_regionIdForIndex(leftIndex) ~= self:_regionIdForIndex(rightIndex) then
				local boundaryOffsetX = -halfSpan + (col * cellSize)
				local position = boardCenter + (xDir * boundaryOffsetX) + (yDir * rowCenterOffset) + (normal * GRID_ELEVATION)
				local cframe = CFrame.fromMatrix(position, yDir, normal)
				self:_createGridLine(
					folder,
					cframe,
					Vector3.new(cellSize + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, REGION_BORDER_THICKNESS),
					REGION_BORDER_COLOR
				)
			end
		end
	end

	for row = 1, (self.Size - 1) do
		local boundaryOffsetY = -halfSpan + (row * cellSize)
		for col = 1, self.Size do
			local topIndex = rowColToIndex(row, col, self.Size)
			local bottomIndex = rowColToIndex(row + 1, col, self.Size)
			if self:_regionIdForIndex(topIndex) ~= self:_regionIdForIndex(bottomIndex) then
				local colCenterOffset = -halfSpan + ((col - 0.5) * cellSize)
				local position = boardCenter + (xDir * colCenterOffset) + (yDir * boundaryOffsetY) + (normal * GRID_ELEVATION)
				local cframe = CFrame.fromMatrix(position, xDir, normal)
				self:_createGridLine(
					folder,
					cframe,
					Vector3.new(cellSize + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, REGION_BORDER_THICKNESS),
					REGION_BORDER_COLOR
				)
			end
		end
	end

	for _, boundary in ipairs({ 0, self.Size }) do
		local offset = -halfSpan + (boundary * cellSize)
		local xBoundaryPosition = boardCenter + (xDir * offset) + (normal * GRID_ELEVATION)
		local xBoundaryCFrame = CFrame.fromMatrix(xBoundaryPosition, yDir, normal)
		self:_createGridLine(
			folder,
			xBoundaryCFrame,
			Vector3.new(totalSpan + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, OUTER_BORDER_THICKNESS),
			OUTER_BORDER_COLOR
		)

		local yBoundaryPosition = boardCenter + (yDir * offset) + (normal * GRID_ELEVATION)
		local yBoundaryCFrame = CFrame.fromMatrix(yBoundaryPosition, xDir, normal)
		self:_createGridLine(
			folder,
			yBoundaryCFrame,
			Vector3.new(totalSpan + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, OUTER_BORDER_THICKNESS),
			OUTER_BORDER_COLOR
		)
	end
end

function Puzzle:_destroyNDRegionOverlay(state)
	if type(state) ~= "table" or type(state.RegionOverlayFolders) ~= "table" then
		return
	end
	for key, folder in pairs(state.RegionOverlayFolders) do
		if folder then
			folder:Destroy()
		end
		state.RegionOverlayFolders[key] = nil
	end
end

function Puzzle:_buildNDRegionOverlay(state)
	if type(state) ~= "table" or not (state.Projection and state.RegionByIndex) then
		return
	end

	self:_destroyNDRegionOverlay(state)
	state.RegionOverlayFolders = {}

	for boardId, visualBoard in pairs(state.Projection.BoardById or {}) do
		local board = visualBoard.Board
		if board and board.BoardFolder then
			local folder = Instance.new("Folder")
			folder.Name = "QueensNDRegions"
			folder.Parent = board.BoardFolder
			state.RegionOverlayFolders[boardId] = folder

			local settings = board.Settings
			local originCFrame = resolveOriginCFrame(settings.origin)
			local xDirection = settings.xDirection
			local yDirection = settings.yDirection
			if typeof(xDirection) ~= "Vector3" or xDirection.Magnitude <= 0 then
				xDirection = Vector3.new(1, 0, 0)
			end
			if typeof(yDirection) ~= "Vector3" or yDirection.Magnitude <= 0 then
				yDirection = Vector3.new(0, 0, 1)
			end

			local xDir = originCFrame:VectorToWorldSpace(xDirection.Unit)
			local yDir = originCFrame:VectorToWorldSpace(yDirection.Unit)
			local normal = xDir:Cross(yDir)
			if normal.Magnitude <= 0 then
				normal = Vector3.new(0, 1, 0)
			else
				normal = normal.Unit
			end
			if normal.Y < 0 then
				normal = -normal
			end

			local boardCenter = originCFrame.Position
			local cellSize = tonumber(settings.cellSize) or 4
			local totalSpan = state.Size * cellSize
			local halfSpan = totalSpan * 0.5
			local sliceCoords = visualBoard.SliceCoords or {}

			local function globalIndex(row, col)
				local coords = table.clone(sliceCoords)
				coords[1] = col
				coords[2] = row
				return NDimensionalBoard.CoordsToIndex(coords, state.Size, state.Dimensions)
			end

			for row = 1, state.Size do
				local rowCenterOffset = -halfSpan + ((row - 0.5) * cellSize)
				for col = 1, (state.Size - 1) do
					local leftIndex = globalIndex(row, col)
					local rightIndex = globalIndex(row, col + 1)
					if state.RegionByIndex[leftIndex] ~= state.RegionByIndex[rightIndex] then
						local boundaryOffsetX = -halfSpan + (col * cellSize)
						local position = boardCenter + (xDir * boundaryOffsetX) + (yDir * rowCenterOffset) + (normal * GRID_ELEVATION)
						local cframe = CFrame.fromMatrix(position, yDir, normal)
						self:_createGridLine(
							folder,
							cframe,
							Vector3.new(cellSize + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, REGION_BORDER_THICKNESS),
							REGION_BORDER_COLOR
						)
					end
				end
			end

			for row = 1, (state.Size - 1) do
				local boundaryOffsetY = -halfSpan + (row * cellSize)
				for col = 1, state.Size do
					local topIndex = globalIndex(row, col)
					local bottomIndex = globalIndex(row + 1, col)
					if state.RegionByIndex[topIndex] ~= state.RegionByIndex[bottomIndex] then
						local colCenterOffset = -halfSpan + ((col - 0.5) * cellSize)
						local position = boardCenter + (xDir * colCenterOffset) + (yDir * boundaryOffsetY) + (normal * GRID_ELEVATION)
						local cframe = CFrame.fromMatrix(position, xDir, normal)
						self:_createGridLine(
							folder,
							cframe,
							Vector3.new(cellSize + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, REGION_BORDER_THICKNESS),
							REGION_BORDER_COLOR
						)
					end
				end
			end

			for _, boundary in ipairs({ 0, state.Size }) do
				local offset = -halfSpan + (boundary * cellSize)
				local xBoundaryPosition = boardCenter + (xDir * offset) + (normal * GRID_ELEVATION)
				local xBoundaryCFrame = CFrame.fromMatrix(xBoundaryPosition, yDir, normal)
				self:_createGridLine(
					folder,
					xBoundaryCFrame,
					Vector3.new(totalSpan + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, OUTER_BORDER_THICKNESS),
					OUTER_BORDER_COLOR
				)

				local yBoundaryPosition = boardCenter + (yDir * offset) + (normal * GRID_ELEVATION)
				local yBoundaryCFrame = CFrame.fromMatrix(yBoundaryPosition, xDir, normal)
				self:_createGridLine(
					folder,
					yBoundaryCFrame,
					Vector3.new(totalSpan + GRID_LENGTH_PADDING, GRID_LINE_HEIGHT, OUTER_BORDER_THICKNESS),
					OUTER_BORDER_COLOR
				)
			end
		end
	end
end

function Puzzle:_regionIdForIndex(index)
	if not self.RegionByIndex then
		return 0
	end
	return tonumber(self.RegionByIndex[index]) or 0
end

function Puzzle:_isQueenConflict(index)
	if self.PlayerMask[index] ~= 1 then
		return false
	end

	local row, col = indexToRowCol(index, self.Size)
	local myRegion = self:_regionIdForIndex(index)

	for test = 1, #self.PlayerMask do
		if test ~= index and self.PlayerMask[test] == 1 then
			local tRow, tCol = indexToRowCol(test, self.Size)

			if tRow == row or tCol == col then
				return true
			end

			local rowDelta = math.abs(tRow - row)
			local colDelta = math.abs(tCol - col)

			-- Only immediate diagonal neighbors should conflict
			if rowDelta == 1 and colDelta == 1 then
				return true
			end

			if self:_regionIdForIndex(test) == myRegion then
				return true
			end
		end
	end

	return false
end

function Puzzle:IsSolved()
	local queens = {}
	for index = 1, #self.PlayerMask do
		if self.PlayerMask[index] == 1 then
			queens[#queens + 1] = index
		end
	end
	if #queens ~= self.Size then
		return false
	end

	local rowCounts = {}
	local colCounts = {}
	local regionCounts = {}
	for _, index in ipairs(queens) do
		local row, col = indexToRowCol(index, self.Size)
		local region = self:_regionIdForIndex(index)
		rowCounts[row] = (rowCounts[row] or 0) + 1
		colCounts[col] = (colCounts[col] or 0) + 1
		regionCounts[region] = (regionCounts[region] or 0) + 1
		if self:_isQueenConflict(index) then
			return false
		end
	end

	for i = 1, self.Size do
		if (rowCounts[i] or 0) ~= 1 then
			return false
		end
		if (colCounts[i] or 0) ~= 1 then
			return false
		end
		if (regionCounts[i] or 0) ~= 1 then
			return false
		end
	end

	return true
end

function Puzzle:RefreshInteractionVisuals()
	if not self.Board then
		return
	end

	for index = 1, #self.PlayerMask do
		local value = self.PlayerMask[index]
		local baseColor = self:_baseColorForIndex(index)
		if value == 1 then
			if self:_isQueenConflict(index) then
				self.Board:SetCellColor(index, QUEEN_CONFLICT_COLOR)
			else
				self.Board:SetCellColor(index, QUEEN_CELL_COLOR)
			end
			self.Board:SetCellText(index, "", BASE_TEXT_COLOR)
		elseif value == 2 then
			self.Board:SetCellColor(index, BLOCKED_CELL_COLOR)
			self.Board:SetCellText(index, "X", BLOCKED_TEXT_COLOR)
		else
			self.Board:SetCellColor(index, baseColor)
			self.Board:SetCellText(index, "", BASE_TEXT_COLOR)
		end
	end
end

function Puzzle:GetSnapshot()
	return {
		Size = self.Size,
		PlayerMask = self.PlayerMask,
		Solved = self.Solved,
		NDimensionalBoards = self:_getNDSnapshot(),
	}
end

function Puzzle:_getNDSnapshot()
	local snapshots = {}
	for _, state in ipairs(self.NDStates or {}) do
		snapshots[#snapshots + 1] = {
			Key = state.Key,
			Size = state.Size,
			Dimensions = state.Dimensions,
			RegionByIndex = state.RegionByIndex,
			Solved = state.Solved,
		}
	end
	return snapshots
end

function Puzzle:GetSessionAnchor()
	if self.Board and self.Board.Settings and self.Board.Settings.origin then
		return self.Board.Settings.origin.Position
	end
	return resolveBoardOrigin().Position
end

function Puzzle:GetSessionAnchors()
	local anchors = {}
	if self.Board and self.Board.Settings and self.Board.Settings.origin then
		anchors[#anchors + 1] = self.Board.Settings.origin.Position
	else
		anchors[#anchors + 1] = resolveBoardOrigin().Position
	end

	for _, state in ipairs(self.NDStates or {}) do
		local origin = state.Origin
		if typeof(origin) == "CFrame" then
			anchors[#anchors + 1] = origin.Position
		end
	end
	if not self.NDStates or #self.NDStates == 0 then
		for _, config in ipairs(EXTRA_ND_BOARD_CONFIGS) do
			local origin = resolveSpecificBoardOrigin(config.OriginName)
			if typeof(origin) == "CFrame" then
				anchors[#anchors + 1] = origin.Position
			end
		end
	end
	return anchors
end

function Puzzle:GetRoundDuration(size)
	local parsed = math.floor(tonumber(size) or self.DefaultBoardSize)
	local clamped = math.clamp(parsed, self.MinBoardSize, self.MaxBoardSize)
	return clamped * clamped * 6
end

function Puzzle:ResolveCellIndex(target)
	if type(target) == "number" then
		return target
	end
	local _, ndIndex = self:_resolveNDStateAndIndex(target)
	if ndIndex then
		return ndIndex
	end
	if typeof(target) == "Instance" and self.Board then
		return self.Board:GetCellIdFromInstance(target)
	end
	return nil
end

function Puzzle:_resolveNDStateAndIndex(target)
	if typeof(target) ~= "Instance" then
		return nil, nil
	end
	for _, state in ipairs(self.NDStates or {}) do
		local index = NDimensionalBoard.ResolveGlobalIndex(state.Projection, target)
		if index then
			return state, index
		end
	end
	return nil, nil
end

function Puzzle:MarkCompletedVisual()
	if self.Board then
		self.Board:SetCompletedVisual()
	end
	for _, state in ipairs(self.NDStates or {}) do
		if state.Solved then
			NDimensionalBoard.SetCompletedVisual(state.Projection)
		end
	end
end

function Puzzle:_handleNDInteraction(player, state, index, action)
	if state.Solved then
		return false, "Puzzle already solved"
	end

	local normalizedAction = string.lower(tostring(action or "reveal"))
	local current = state.PlayerMask[index]
	local nextValue
	if normalizedAction == "flagtoggle" or normalizedAction == "flag" then
		nextValue = (current == 2) and 0 or 2
	else
		nextValue = (current == 1) and 0 or 1
	end

	state.PlayerMask[index] = nextValue
	if nextValue == 1 then
		self:_placeNDIndicator(state, index, self:_getEquippedIndicatorId(player))
	else
		self:_clearNDIndicator(state, index)
	end

	self:_refreshNDVisuals(state)
	state.Solved = self:_isNDSolved(state)
	if state.Solved then
		NDimensionalBoard.SetCompletedVisual(state.Projection)
	end

	return true, {
		Index = index,
		Value = nextValue,
		Solved = state.Solved,
		BoardGroupId = state.Projection.GroupId,
		Size = state.Size,
		Dimensions = state.Dimensions,
	}
end

function Puzzle:HandleInteraction(player, target, action)
	local ndState, ndIndex = self:_resolveNDStateAndIndex(target)
	if ndState and ndIndex then
		return self:_handleNDInteraction(player, ndState, ndIndex, action)
	end

	if self.Solved then
		return false, "Puzzle already solved"
	end

	local index = self:ResolveCellIndex(target)
	if not index or not self.PlayerMask[index] then
		return false, "Invalid board cell"
	end

	local normalizedAction = string.lower(tostring(action or "reveal"))
	local current = self.PlayerMask[index]
	local nextValue
	if normalizedAction == "flagtoggle" or normalizedAction == "flag" then
		nextValue = (current == 2) and 0 or 2
	else
		nextValue = (current == 1) and 0 or 1
	end

	self.PlayerMask[index] = nextValue
	self.Board:SetData(index, nextValue == 1 and 1 or 0)
	if nextValue == 1 then
		self:_placeIndicator(index, self:_getEquippedIndicatorId(player))
	else
		self:_clearIndicator(index)
	end

	self:RefreshInteractionVisuals()
	self.Solved = self:IsSolved()
	if self.Solved then
		self:MarkCompletedVisual()
	end

	return true, {
		Index = index,
		Value = nextValue,
		Solved = self.Solved,
	}
end

function Puzzle:Init(size, options)
	self:_destroyNDStates()

	if self.Board then
		self:_destroyIndicators()
		if self.RegionOverlayFolder and self.RegionOverlayFolder.Parent then
			self.RegionOverlayFolder:Destroy()
			self.RegionOverlayFolder = nil
		end
		self.Board:Destroy()
		self.Board = nil
	end

	options = type(options) == "table" and options or {}
	local parsed = math.floor(tonumber(size) or self.DefaultBoardSize)
	self.Size = math.clamp(parsed, self.MinBoardSize, self.MaxBoardSize)
	self:_generateRegions(self.Size)
	self.PlayerMask = table.create(self.Size * self.Size, 0)
	self.Solved = false

	local boardSettings = {
		origin = resolveBoardOrigin(),
		xDirection = Vector3.new(1, 0, 0),
		yDirection = Vector3.new(0, 0, 1),
		xSpan = self.Size,
		ySpan = self.Size,
		cellSize = 4,
		displayAlwaysOnTop = false,
	}
	if typeof(options.Origin) == "CFrame" or typeof(options.Origin) == "Vector3" then
		boardSettings.origin = options.Origin
	elseif typeof(options.origin) == "CFrame" or typeof(options.origin) == "Vector3" then
		boardSettings.origin = options.origin
	end
	if type(options.BoardSettings) == "table" then
		for key, value in pairs(options.BoardSettings) do
			boardSettings[key] = value
		end
	end

	self.Board = BoardClass.new(boardSettings)
	self.Board:Construct()

	self.ActiveIndicators = {}
	self:_ensureIndicatorFolder()

	for index = 1, self.Size * self.Size do
		self.Board:SetData(index, 0)
		self.Board:SetCellText(index, "", BASE_TEXT_COLOR)
	end
	self:RefreshInteractionVisuals()
	self:_buildRegionOverlay()

	for _, config in ipairs(EXTRA_ND_BOARD_CONFIGS) do
		local ndSize = math.max(2, math.floor(tonumber(config.Size) or 4))
		local dimensions = math.max(3, math.floor(tonumber(config.Dimensions) or 4))
		local requestedOrigin = resolveSpecificBoardOrigin(config.OriginName)
		local ndOrigin = requestedOrigin or offsetOrigin(boardSettings.origin, (self.Size + ndSize + 8) * boardSettings.cellSize)
		local ndSettings = {
			origin = ndOrigin,
			xDirection = Vector3.new(1, 0, 0),
			yDirection = Vector3.new(0, 0, 1),
			cellSize = 3,
			displayAlwaysOnTop = false,
		}

		local projection = NDimensionalBoard.Construct({
			BoardClass = BoardClass,
			ModeKey = self.ModeKey,
			HoverKind = "queens",
			GroupId = ("%s_%s_%dd"):format(self.ModeKey, tostring(config.OriginName or "origin"), dimensions),
			Size = ndSize,
			Dimensions = dimensions,
			BoardSettings = ndSettings,
			SliceGapCells = 2,
		})
		local state = self:_buildEmptyNDState(config, projection, ndOrigin)
		self.NDStates[#self.NDStates + 1] = state
		for index = 1, state.TotalCells do
			local visual = state.Projection.GlobalToVisual[index]
			if visual then
				visual.Board:SetData(visual.LocalIndex, 0)
				visual.Board:SetCellText(visual.LocalIndex, "", BASE_TEXT_COLOR)
			end
		end
		self:_buildNDRegionOverlay(state)
		self:_refreshNDVisuals(state)
	end
end

return Puzzle
