-- Narrow showcase: dimension/index mapping and board construction.
-- Original implementation retained. Dependencies/runtime validation are documented in README.
local HttpService = game:GetService("HttpService")

local NDimensionalBoard = {}

local DEFAULT_SLICE_GAP_CELLS = 2

local function normalizeWholeNumber(value, fallback)
	local parsed = tonumber(value)
	if parsed == nil then
		return fallback
	end
	return math.floor(parsed + 0.5)
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

local function copySettings(settings)
	local copy = {}
	if type(settings) == "table" then
		for key, value in pairs(settings) do
			copy[key] = value
		end
	end
	return copy
end

function NDimensionalBoard.TotalCells(size, dimensions)
	local total = 1
	for _ = 1, dimensions do
		total *= size
	end
	return total
end

function NDimensionalBoard.IndexToCoords(index, size, dimensions)
	local coords = table.create(dimensions, 1)
	local remaining = math.max(0, math.floor(tonumber(index) or 1) - 1)
	for dimension = 1, dimensions do
		coords[dimension] = (remaining % size) + 1
		remaining = math.floor(remaining / size)
	end
	return coords
end

function NDimensionalBoard.CoordsToIndex(coords, size, dimensions)
	local multiplier = 1
	local index = 1
	for dimension = 1, dimensions do
		index += ((tonumber(coords[dimension]) or 1) - 1) * multiplier
		multiplier *= size
	end
	return index
end

function NDimensionalBoard.CoordsToLocalIndex(coords, size)
	local col = tonumber(coords[1]) or 1
	local row = tonumber(coords[2]) or 1
	return ((row - 1) * size) + col
end

function NDimensionalBoard.GetNeighborIndexes(index, size, dimensions)
	local originCoords = NDimensionalBoard.IndexToCoords(index, size, dimensions)
	local neighbors = {}
	local working = table.clone(originCoords)

	local function walk(dimension, changed)
		if dimension > dimensions then
			if changed then
				neighbors[#neighbors + 1] = NDimensionalBoard.CoordsToIndex(working, size, dimensions)
			end
			return
		end

		local base = originCoords[dimension]
		for delta = -1, 1 do
			local value = base + delta
			if value >= 1 and value <= size then
				working[dimension] = value
				walk(dimension + 1, changed or delta ~= 0)
			end
		end
		working[dimension] = base
	end

	walk(1, false)
	return neighbors
end

local function buildSliceCoordinateList(size, dimensions)
	local sliceDimensions = math.max(0, dimensions - 2)
	local sliceCount = NDimensionalBoard.TotalCells(size, sliceDimensions)
	local slices = table.create(sliceCount)

	for sliceIndex = 1, sliceCount do
		local coords = table.create(dimensions, 1)
		local remaining = sliceIndex - 1
		for dimension = 3, dimensions do
			coords[dimension] = (remaining % size) + 1
			remaining = math.floor(remaining / size)
		end
		slices[sliceIndex] = coords
	end

	return slices
end

local function getSliceGridPosition(sliceIndex, size, dimensions, sliceCount)
	if dimensions == 3 then
		return sliceIndex, 1, size, 1
	end
	if dimensions == 4 then
		local col = ((sliceIndex - 1) % size) + 1
		local row = math.floor((sliceIndex - 1) / size) + 1
		return col, row, size, size
	end

	local columns = math.ceil(math.sqrt(sliceCount))
	local row = math.floor((sliceIndex - 1) / columns) + 1
	local col = ((sliceIndex - 1) % columns) + 1
	local rows = math.ceil(sliceCount / columns)
	return col, row, columns, rows
end

function NDimensionalBoard.Construct(config)
	config = type(config) == "table" and config or {}

	local BoardClass = config.BoardClass
	if not BoardClass then
		error("BoardClass is required")
	end

	local dimensions = math.max(2, normalizeWholeNumber(config.Dimensions, 2))
	local size = math.max(2, normalizeWholeNumber(config.Size, 4))
	local baseSettings = copySettings(config.BoardSettings)
	baseSettings.xSpan = size
	baseSettings.ySpan = size

	local groupId = tostring(config.GroupId or HttpService:GenerateGUID(false))
	local originCFrame = resolveOriginCFrame(baseSettings.origin)
	baseSettings.origin = originCFrame

	local xDirection = baseSettings.xDirection
	if typeof(xDirection) ~= "Vector3" or xDirection.Magnitude <= 0 then
		xDirection = Vector3.new(1, 0, 0)
	end
	local yDirection = baseSettings.yDirection
	if typeof(yDirection) ~= "Vector3" or yDirection.Magnitude <= 0 then
		yDirection = Vector3.new(0, 0, 1)
	end
	local xDir = originCFrame:VectorToWorldSpace(xDirection.Unit)
	local yDir = originCFrame:VectorToWorldSpace(yDirection.Unit)
	local originRotation = originCFrame - originCFrame.Position
	local cellSize = tonumber(baseSettings.cellSize) or 4
	local sliceGap = tonumber(config.SliceGapCells or baseSettings.sliceGapCells) or DEFAULT_SLICE_GAP_CELLS
	local pitch = (size + sliceGap) * cellSize

	local projection = {
		GroupId = groupId,
		ModeKey = tostring(config.ModeKey or ""),
		HoverKind = tostring(config.HoverKind or ""),
		Size = size,
		Dimensions = dimensions,
		Boards = {},
		Extensions = {},
		BoardById = {},
		GlobalToVisual = {},
	}

	local slices = buildSliceCoordinateList(size, dimensions)
	local sliceCount = #slices
	for sliceIndex, sliceCoords in ipairs(slices) do
		local sliceCol, sliceRow, gridColumns, gridRows = getSliceGridPosition(sliceIndex, size, dimensions, sliceCount)
		local offsetX
		local offsetY
		if config.AnchorFirstSlice == true then
			offsetX = (sliceCol - 1) * pitch
			offsetY = (sliceRow - 1) * pitch
		else
			offsetX = (sliceCol - ((gridColumns + 1) * 0.5)) * pitch
			offsetY = (sliceRow - ((gridRows + 1) * 0.5)) * pitch
		end

		local settings = copySettings(baseSettings)
		settings.origin = CFrame.new(originCFrame.Position + (xDir * offsetX) + (yDir * offsetY)) * originRotation

		local board = BoardClass.new(settings)
		board:Construct()

		local extension = nil
		if type(config.ExtensionName) == "string" and config.ExtensionName ~= "" then
			extension = board:UseExtension(config.ExtensionName, config.ExtensionOptions)
		end

		local visual = {
			Board = board,
			Extension = extension,
			SliceIndex = sliceIndex,
			SliceCoords = sliceCoords,
		}
		projection.Boards[#projection.Boards + 1] = board
		projection.Extensions[board.Id] = extension
		projection.BoardById[board.Id] = visual

		for localIndex, cell in pairs(board.Cells) do
			local localRow = math.floor((localIndex - 1) / size) + 1
			local localCol = ((localIndex - 1) % size) + 1
			local coords = table.clone(sliceCoords)
			coords[1] = localCol
			coords[2] = localRow
			local globalIndex = NDimensionalBoard.CoordsToIndex(coords, size, dimensions)

			cell:SetAttribute("PuzzleModeKey", projection.ModeKey)
			cell:SetAttribute("PuzzleNDimensional", dimensions > 2)
			cell:SetAttribute("PuzzleNDGroupId", groupId)
			cell:SetAttribute("PuzzleNDHoverKind", projection.HoverKind)
			cell:SetAttribute("PuzzleNDSize", size)
			cell:SetAttribute("PuzzleNDDimensions", dimensions)
			cell:SetAttribute("PuzzleNDIndex", globalIndex)
			cell:SetAttribute("PuzzleNDLocalIndex", localIndex)
			cell:SetAttribute("PuzzleNDSliceIndex", sliceIndex)
			for dimension = 1, dimensions do
				cell:SetAttribute(("PuzzleNDD%d"):format(dimension), coords[dimension])
			end

			projection.GlobalToVisual[globalIndex] = {
				Board = board,
				Cell = cell,
				Extension = extension,
				LocalIndex = localIndex,
				SliceIndex = sliceIndex,
				Coords = coords,
			}
		end
	end

	return projection
end

function NDimensionalBoard.ResolveGlobalIndex(projection, target)
	if type(projection) ~= "table" or typeof(target) ~= "Instance" then
		return nil
	end

	local current = target
	while current do
		if current:IsA("BasePart") and current:GetAttribute("PuzzleNDGroupId") == projection.GroupId then
			local index = current:GetAttribute("PuzzleNDIndex")
			if type(index) == "number" then
				return index
			end
		end
		current = current.Parent
	end
	return nil
end

function NDimensionalBoard.Destroy(projection)
	if type(projection) ~= "table" then
		return
	end
	for _, board in ipairs(projection.Boards or {}) do
		if board and type(board.Destroy) == "function" then
			board:Destroy()
		end
	end
	table.clear(projection.Boards)
	table.clear(projection.Extensions)
	table.clear(projection.BoardById)
	table.clear(projection.GlobalToVisual)
end

function NDimensionalBoard.SetCompletedVisual(projection)
	if type(projection) ~= "table" then
		return
	end
	for _, board in ipairs(projection.Boards or {}) do
		if board and type(board.SetCompletedVisual) == "function" then
			board:SetCompletedVisual()
		end
	end
end

return NDimensionalBoard
