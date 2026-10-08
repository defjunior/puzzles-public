-- Actual Sudoku puzzle implementation; selected authored presentation/defaults omitted.
-- Generation/rules/session interfaces retained; missing assets/config prevent standalone use.
-- Authored board/session defaults omitted. Supply configuration before running.
local Puzzle = { Name = "Sudoku", ModeKey = "sudoku" }

local BOARD_SIZE = 9
local SUBGRID_SIZE = 3

local BASE_CELL_COLOR_A = nil -- Omitted: authored visual/cosmetic value.
local BASE_CELL_COLOR_B = nil -- Omitted: authored visual/cosmetic value.
local FIXED_CELL_TINT = Color3.fromRGB(201, 214, 235)
local CLUE_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local ENTRY_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CONFLICT_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local MINOR_GRID_COLOR = nil -- Omitted: authored visual/cosmetic value.
local MAJOR_GRID_COLOR = nil -- Omitted: authored visual/cosmetic value.
local MINOR_GRID_THICKNESS = 0.05
local MAJOR_GRID_THICKNESS = 0.16
local GRID_LINE_HEIGHT = 0.08
local GRID_ELEVATION = 0.4
local GRID_LENGTH_PADDING = 0.05
local SUDOKU_MAX_LIVES = 5

local MISTAKE_MESSAGES = {} -- Omitted: authored presets/dialogue.

local Classes = game.ServerScriptService.Classes
local BoardClass = require(Classes:WaitForChild("Board"))
local Workspace = game:GetService("Workspace")

local DIGITS = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
local BAND_INDEXES = { 0, 1, 2 }

local function rowColToIndex(row, col, width)
	return ((row - 1) * width) + col
end

local function indexToRowCol(index, width)
	local row = math.floor((index - 1) / width) + 1
	local col = ((index - 1) % width) + 1
	return row, col
end

local function shuffledCopy(values)
	local copy = table.clone(values)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function buildBandOrder()
	local order = {}
	local shuffledBands = shuffledCopy(BAND_INDEXES)
	for _, band in ipairs(shuffledBands) do
		local withinBand = shuffledCopy(BAND_INDEXES)
		for _, offset in ipairs(withinBand) do
			order[#order + 1] = (band * SUBGRID_SIZE) + offset + 1
		end
	end
	return order
end

local function generateSolvedGrid()
	local rows = buildBandOrder()
	local cols = buildBandOrder()
	local digitMap = shuffledCopy(DIGITS)
	local solved = table.create(BOARD_SIZE)

	for row = 1, BOARD_SIZE do
		local outputRow = table.create(BOARD_SIZE)
		local rowZero = rows[row] - 1
		for col = 1, BOARD_SIZE do
			local colZero = cols[col] - 1
			local baseValue = ((rowZero * SUBGRID_SIZE) + math.floor(rowZero / SUBGRID_SIZE) + colZero) % BOARD_SIZE + 1
			outputRow[col] = digitMap[baseValue]
		end
		solved[row] = outputRow
	end

	return solved
end

local function flattenGrid(grid)
	local flat = table.create(BOARD_SIZE * BOARD_SIZE)
	local index = 0
	for row = 1, BOARD_SIZE do
		for col = 1, BOARD_SIZE do
			index += 1
			flat[index] = grid[row][col]
		end
	end
	return flat
end

local function unflattenGrid(values)
	local grid = table.create(BOARD_SIZE)
	local index = 0
	for row = 1, BOARD_SIZE do
		local outputRow = table.create(BOARD_SIZE)
		for col = 1, BOARD_SIZE do
			index += 1
			outputRow[col] = values[index] or 0
		end
		grid[row] = outputRow
	end
	return grid
end

local function buildRemovalOrder(total)
	local order = table.create(total)
	for i = 1, total do
		order[i] = i
	end
	for i = total, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

local function blendColor(a, b, alpha)
	local t = math.clamp(alpha, 0, 1)
	return Color3.new(
		(a.R * (1 - t)) + (b.R * t),
		(a.G * (1 - t)) + (b.G * t),
		(a.B * (1 - t)) + (b.B * t)
	)
end

local function baseColorForCell(row, col)
	local checker = (math.floor((row - 1) / SUBGRID_SIZE) + math.floor((col - 1) / SUBGRID_SIZE)) % 2
	if checker == 0 then
		return BASE_CELL_COLOR_A
	end
	return BASE_CELL_COLOR_B
end

local function flattenOriginRotation(originCFrame)
	local position = originCFrame.Position
	local _, yaw, _ = originCFrame:ToOrientation()
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

local function resolveRotatableOrigin(container)
	if not container then
		return nil
	end

	for _, name in ipairs({ "Center", "Origin", "Origin1" }) do
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

local function resolveBoardOrigin()
	local origins = Workspace:FindFirstChild("Origins")
	local sudokuOrigins = origins and origins:FindFirstChild("Sudoku")
	if sudokuOrigins then
		local resolved = resolveRotatableOrigin(sudokuOrigins)
		if resolved then
			return resolved
		end
	end
	-- Fallback for missing map origins.
	return CFrame.new(60.5, 2, 55.5)
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

local function parseDigitAction(action)
	local normalized = string.lower(tostring(action or ""))
	if normalized == "clear" then
		return 0
	end

	local token = string.match(normalized, "^setdigit:(%d)$")
	if not token then
		return nil
	end

	local digit = tonumber(token)
	if digit and digit >= 0 and digit <= 9 then
		return digit
	end
	return nil
end

local function buildMistakeMessage(playerName, livesLeft)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
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

function Puzzle:_buildGridOverlay()
	if not self.Board or not self.Board.BoardFolder then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "SudokuGrid"
	folder.Parent = self.Board.BoardFolder

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
	local lineLength = totalSpan + GRID_LENGTH_PADDING

	for boundary = 0, self.Size do
		local offset = -halfSpan + (boundary * cellSize)
		local isMajor = (boundary % SUBGRID_SIZE) == 0
		local thickness = isMajor and MAJOR_GRID_THICKNESS or MINOR_GRID_THICKNESS
		local color = isMajor and MAJOR_GRID_COLOR or MINOR_GRID_COLOR

		local xBoundaryPosition = boardCenter + (xDir * offset) + (normal * GRID_ELEVATION)
		local xBoundaryCFrame = CFrame.fromMatrix(xBoundaryPosition, yDir, normal)
		self:_createGridLine(folder, xBoundaryCFrame, Vector3.new(lineLength, GRID_LINE_HEIGHT, thickness), color)

		local yBoundaryPosition = boardCenter + (yDir * offset) + (normal * GRID_ELEVATION)
		local yBoundaryCFrame = CFrame.fromMatrix(yBoundaryPosition, xDir, normal)
		self:_createGridLine(folder, yBoundaryCFrame, Vector3.new(lineLength, GRID_LINE_HEIGHT, thickness), color)
	end
end

function Puzzle:Generate(_size)
	local solutionGrid = generateSolvedGrid()
	local solutionFlat = flattenGrid(solutionGrid)

	local clues = math.random(33, 38)
	local total = BOARD_SIZE * BOARD_SIZE
	local removeCount = total - clues
	local removals = {}
	local order = buildRemovalOrder(total)
	for i = 1, removeCount do
		removals[order[i]] = true
	end

	local puzzleGrid = table.create(BOARD_SIZE)
	local fixedMask = table.create(total)
	local playerValues = table.create(total, 0)
	for row = 1, BOARD_SIZE do
		local outputRow = table.create(BOARD_SIZE)
		for col = 1, BOARD_SIZE do
			local index = rowColToIndex(row, col, BOARD_SIZE)
			local value = solutionGrid[row][col]
			if removals[index] then
				outputRow[col] = 0
				fixedMask[index] = false
				playerValues[index] = 0
			else
				outputRow[col] = value
				fixedMask[index] = true
				playerValues[index] = value
			end
		end
		puzzleGrid[row] = outputRow
	end

	self.Size = BOARD_SIZE
	self.PuzzleGrid = puzzleGrid
	self.SolutionFlat = solutionFlat
	self.PlayerValues = playerValues
	self.FixedMask = fixedMask
	self.LivesMax = SUDOKU_MAX_LIVES
	self.LivesRemaining = SUDOKU_MAX_LIVES
	self.Solved = false
end

function Puzzle:GetSessionAnchor()
	if self.Board and self.Board.Settings and self.Board.Settings.origin then
		return self.Board.Settings.origin.Position
	end
	return resolveBoardOrigin().Position
end

function Puzzle:GetRoundDuration(_size)
	return BOARD_SIZE * BOARD_SIZE * 9
end

function Puzzle:GetSnapshot()
	return {
		Size = self.Size,
		Grid = unflattenGrid(self.PlayerValues),
		PuzzleGrid = self.PuzzleGrid,
		FixedMask = self.FixedMask,
		LivesRemaining = self.LivesRemaining,
		LivesMax = self.LivesMax,
		Solved = self.Solved,
	}
end

function Puzzle:ResolveCellIndex(target)
	if type(target) == "number" then
		return target
	end
	if typeof(target) == "Instance" and self.Board then
		return self.Board:GetCellIdFromInstance(target)
	end
	return nil
end

function Puzzle:MarkCompletedVisual()
	if self.Board then
		self.Board:SetCompletedVisual()
	end
end

function Puzzle:_hasConflict(index)
	local value = self.PlayerValues[index]
	if not value or value == 0 then
		return false
	end

	local row, col = indexToRowCol(index, self.Size)
	for testCol = 1, self.Size do
		if testCol ~= col then
			local testIndex = rowColToIndex(row, testCol, self.Size)
			if self.PlayerValues[testIndex] == value then
				return true
			end
		end
	end

	for testRow = 1, self.Size do
		if testRow ~= row then
			local testIndex = rowColToIndex(testRow, col, self.Size)
			if self.PlayerValues[testIndex] == value then
				return true
			end
		end
	end

	local boxRowStart = (math.floor((row - 1) / SUBGRID_SIZE) * SUBGRID_SIZE) + 1
	local boxColStart = (math.floor((col - 1) / SUBGRID_SIZE) * SUBGRID_SIZE) + 1
	for testRow = boxRowStart, boxRowStart + SUBGRID_SIZE - 1 do
		for testCol = boxColStart, boxColStart + SUBGRID_SIZE - 1 do
			if not (testRow == row and testCol == col) then
				local testIndex = rowColToIndex(testRow, testCol, self.Size)
				if self.PlayerValues[testIndex] == value then
					return true
				end
			end
		end
	end

	return false
end

function Puzzle:_isSolved()
	-- Accept any valid completed Sudoku (not just the generator's specific solution).
	local size = self.Size
	if size ~= BOARD_SIZE then
		return false
	end

	-- Validate rows.
	for row = 1, size do
		local seen = {}
		for col = 1, size do
			local value = self.PlayerValues[rowColToIndex(row, col, size)]
			if type(value) ~= "number" or value < 1 or value > 9 or seen[value] then
				return false
			end
			seen[value] = true
		end
	end

	-- Validate columns.
	for col = 1, size do
		local seen = {}
		for row = 1, size do
			local value = self.PlayerValues[rowColToIndex(row, col, size)]
			if type(value) ~= "number" or value < 1 or value > 9 or seen[value] then
				return false
			end
			seen[value] = true
		end
	end

	-- Validate 3x3 boxes.
	for boxRow = 1, size, SUBGRID_SIZE do
		for boxCol = 1, size, SUBGRID_SIZE do
			local seen = {}
			for row = boxRow, boxRow + SUBGRID_SIZE - 1 do
				for col = boxCol, boxCol + SUBGRID_SIZE - 1 do
					local value = self.PlayerValues[rowColToIndex(row, col, size)]
					if type(value) ~= "number" or value < 1 or value > 9 or seen[value] then
						return false
					end
					seen[value] = true
				end
			end
		end
	end

	return true
end

function Puzzle:RefreshVisuals()
	if not self.Board then
		return
	end

	for index = 1, #self.PlayerValues do
		local row, col = indexToRowCol(index, self.Size)
		local cellColor = baseColorForCell(row, col)
		local isFixed = self.FixedMask[index] == true
		if isFixed then
			cellColor = blendColor(cellColor, FIXED_CELL_TINT, 0.55)
		end
		self.Board:SetCellColor(index, cellColor)

		local value = self.PlayerValues[index]
		if value and value > 0 then
			local textColor
			if self:_hasConflict(index) then
				textColor = CONFLICT_TEXT_COLOR
			elseif isFixed then
				textColor = CLUE_TEXT_COLOR
			else
				textColor = ENTRY_TEXT_COLOR
			end
			self.Board:SetCellText(index, tostring(value), textColor)
		else
			self.Board:SetCellText(index, "", ENTRY_TEXT_COLOR)
		end
	end
end

function Puzzle:HandleInteraction(player, target, action)
	if self.Solved then
		return false, "Puzzle already solved"
	end

	local index = self:ResolveCellIndex(target)
	if not index or not self.PlayerValues[index] then
		return false, "Invalid board cell"
	end

	local digit = parseDigitAction(action)
	if digit == nil then
		return false, "Select a square and type 1-9"
	end

	if self.FixedMask[index] then
		return false, "That clue cell is locked"
	end

	if digit > 0 and digit ~= self.SolutionFlat[index] then
		self.LivesRemaining = math.max(0, (self.LivesRemaining or SUDOKU_MAX_LIVES) - 1)
		self.PlayerValues[index] = 0
		self.Board.CellData[index] = 0
		self:RefreshVisuals()
		return true, {
			Index = index,
			Value = 0,
			Solved = false,
			Failed = self.LivesRemaining <= 0,
			LivesRemaining = self.LivesRemaining,
			LivesMax = self.LivesMax or SUDOKU_MAX_LIVES,
			MistakeMessage = buildMistakeMessage(player and player.Name, self.LivesRemaining),
		}
	end

	self.PlayerValues[index] = digit
	self.Board.CellData[index] = digit
	self:RefreshVisuals()

	self.Solved = self:_isSolved()
	if self.Solved then
		self:MarkCompletedVisual()
	end

	return true, {
		Index = index,
		Value = digit,
		Solved = self.Solved,
		LivesRemaining = self.LivesRemaining,
		LivesMax = self.LivesMax,
	}
end

function Puzzle:Init(size, options)
	if self.Board then
		self.Board:Destroy()
		self.Board = nil
	end

	options = type(options) == "table" and options or {}
	self:Generate(size or self.DefaultBoardSize)

	local boardSettings = {
		origin = resolveBoardOrigin(),
		xDirection = Vector3.new(1, 0, 0),
		yDirection = Vector3.new(0, 0, 1),
		xSpan = self.Size,
		ySpan = self.Size,
		cellSize = 3.4,
		baseColor = BASE_CELL_COLOR_A,
		fillColor = Color3.fromRGB(141, 165, 199),
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

	for index = 1, (self.Size * self.Size) do
		self.Board.CellData[index] = self.PlayerValues[index]
	end
	self:_buildGridOverlay()
	self:RefreshVisuals()
end

return Puzzle
