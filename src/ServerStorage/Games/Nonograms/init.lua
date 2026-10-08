-- Actual Nonograms puzzle implementation; selected authored presentation/defaults omitted.
-- Generation/rules/session interfaces retained; missing assets/config prevent standalone use.
-- Authored board/session defaults omitted. Supply configuration before running.
local Puzzle = { Name = "Nonograms", ModeKey = "nonograms" }

local UNKNOWN_CELL_COLOR_A = nil -- Omitted: authored visual/cosmetic value.
local UNKNOWN_CELL_COLOR_B = nil -- Omitted: authored visual/cosmetic value.
local FILLED_CELL_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CROSS_CELL_COLOR = nil -- Omitted: authored visual/cosmetic value.
local LOCKED_CROSS_CELL_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CROSS_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CLUE_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CLUE_PLATE_COLOR = nil -- Omitted: authored visual/cosmetic value.
local NONOGRAM_SUBGRID_SIZE = 5
local MINOR_GRID_COLOR = nil -- Omitted: authored visual/cosmetic value.
local MAJOR_GRID_COLOR = nil -- Omitted: authored visual/cosmetic value.
local MINOR_GRID_THICKNESS = 0.05
local MAJOR_GRID_THICKNESS = 0.16
local GRID_LINE_HEIGHT = 0.08
local GRID_ELEVATION = 0.4
local GRID_LENGTH_PADDING = 0.05
local NONOGRAM_MAX_LIVES = 5

local MISTAKE_MESSAGES = {} -- Omitted: authored presets/dialogue.

local NONOGRAM_CEL_CATEGORY = nil -- Omitted: authored visual/cosmetic value.
local NONOGRAM_CEL_DEFAULT = nil -- Omitted: authored visual/cosmetic value.

local Classes = game.ServerScriptService.Classes
local BoardClass = require(Classes:WaitForChild("Board"))
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Framework = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Framework"))

local function indexToRowCol(index, width)
	local row = math.floor((index - 1) / width) + 1
	local col = ((index - 1) % width) + 1
	return row, col
end

local function rowColToIndex(row, col, width)
	return ((row - 1) * width) + col
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
	local nonogramOrigins = origins and (origins:FindFirstChild("Nonograms") or origins:FindFirstChild("Nonogram"))
	if nonogramOrigins then
		local resolved = resolveRotatableOrigin(nonogramOrigins)
		if resolved then
			return resolved
		end
	end
	return CFrame.new(108.5, 2, 55.5)
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

local function checkerColor(size, index, primary, alternate)
	local row, col = indexToRowCol(index, size)
	if ((row + col) % 2) == 0 then
		return primary
	end
	return alternate
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

local function getNonogramCellFolder()
	local assets = ReplicatedFirst:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local celFolder = models and models:FindFirstChild("HitoriCel")
	if celFolder and celFolder:IsA("Folder") then
		return celFolder
	end
	return nil
end

local function runLengths(lineValues)
	local runs = {}
	local streak = 0

	for _, value in ipairs(lineValues) do
		if value == 1 then
			streak += 1
		else
			if streak > 0 then
				runs[#runs + 1] = streak
			end
			streak = 0
		end
	end

	if streak > 0 then
		runs[#runs + 1] = streak
	end

	return runs
end

local function buildMistakeMessage(playerName, livesLeft)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

local function pullRandomIndex(values)
	local count = #values
	if count <= 0 then
		return nil
	end

	local pick = math.random(1, count)
	local value = values[pick]
	values[pick] = values[count]
	values[count] = nil
	return value
end

local function countFilled(mask)
	local total = 0
	for _, value in ipairs(mask) do
		if value == 1 then
			total += 1
		end
	end
	return total
end

local function countLineRuns(mask, size, isRow, lineIndex)
	local runs = 0
	local inRun = false

	for offset = 1, size do
		local row = isRow and lineIndex or offset
		local col = isRow and offset or lineIndex
		local filled = mask[rowColToIndex(row, col, size)] == 1

		if filled and not inRun then
			runs += 1
			inRun = true
		elseif not filled then
			inRun = false
		end
	end

	return runs
end

local function countNeighbors(mask, size, row, col)
	local neighbors = 0
	local minRow = math.max(1, row - 1)
	local maxRow = math.min(size, row + 1)
	local minCol = math.max(1, col - 1)
	local maxCol = math.min(size, col + 1)

	for otherRow = minRow, maxRow do
		for otherCol = minCol, maxCol do
			if not (otherRow == row and otherCol == col) then
				if mask[rowColToIndex(otherRow, otherCol, size)] == 1 then
					neighbors += 1
				end
			end
		end
	end

	return neighbors
end

local function smoothMask(mask, size, passes)
	local working = mask
	for _ = 1, passes do
		local nextMask = table.create(size * size, 0)
		for row = 1, size do
			for col = 1, size do
				local index = rowColToIndex(row, col, size)
				local current = working[index]
				local neighbors = countNeighbors(working, size, row, col)

				if current == 1 then
					nextMask[index] = (neighbors >= 3) and 1 or 0
				else
					nextMask[index] = (neighbors >= 5) and 1 or 0
				end
			end
		end
		working = nextMask
	end
	return working
end

local function pruneSmallComponents(mask, size, minComponentSize)
	local totalCells = size * size
	local visited = table.create(totalCells, false)
	local kept = table.create(totalCells, 0)
	local largest = nil
	local largestSize = 0

	local function flood(startIndex)
		local component = {}
		local stack = { startIndex }

		while #stack > 0 do
			local index = stack[#stack]
			stack[#stack] = nil

			if not visited[index] and mask[index] == 1 then
				visited[index] = true
				component[#component + 1] = index

				local row, col = indexToRowCol(index, size)
				if row > 1 then
					stack[#stack + 1] = rowColToIndex(row - 1, col, size)
				end
				if row < size then
					stack[#stack + 1] = rowColToIndex(row + 1, col, size)
				end
				if col > 1 then
					stack[#stack + 1] = rowColToIndex(row, col - 1, size)
				end
				if col < size then
					stack[#stack + 1] = rowColToIndex(row, col + 1, size)
				end
			end
		end

		return component
	end

	local minSize = math.max(2, math.floor(tonumber(minComponentSize) or 2))

	for index = 1, totalCells do
		if mask[index] == 1 and not visited[index] then
			local component = flood(index)
			local sizeOfComponent = #component
			if sizeOfComponent > largestSize then
				largestSize = sizeOfComponent
				largest = component
			end
			if sizeOfComponent >= minSize then
				for _, componentIndex in ipairs(component) do
					kept[componentIndex] = 1
				end
			end
		end
	end

	local hasAny = false
	for index = 1, totalCells do
		if kept[index] == 1 then
			hasAny = true
			break
		end
	end

	if hasAny then
		return kept
	end

	if largest then
		for _, index in ipairs(largest) do
			kept[index] = 1
		end
	end

	return kept
end

local function enforceFillBounds(mask, size)
	local totalCells = size * size
	local minFilled = math.max(size, math.floor(totalCells * 0.20))
	local maxFilled = math.floor(totalCells * 0.55)
	local filled = countFilled(mask)

	if filled <= 0 then
		local centerRow = math.random(1, size)
		local centerCol = math.random(1, size)
		mask[rowColToIndex(centerRow, centerCol, size)] = 1
		filled = 1
	end

	local directionOffsets = {
		{ -1, 0 },
		{ 1, 0 },
		{ 0, -1 },
		{ 0, 1 },
	}

	local growthAttempts = 0
	while filled < minFilled and growthAttempts < (totalCells * 10) do
		growthAttempts += 1
		local source = math.random(1, totalCells)
		if mask[source] == 1 then
			local row, col = indexToRowCol(source, size)
			local dir = directionOffsets[math.random(1, #directionOffsets)]
			local newRow = row + dir[1]
			local newCol = col + dir[2]
			if newRow >= 1 and newRow <= size and newCol >= 1 and newCol <= size then
				local target = rowColToIndex(newRow, newCol, size)
				if mask[target] == 0 then
					mask[target] = 1
					filled += 1
				end
			end
		end
	end

	local carveAttempts = 0
	while filled > maxFilled and carveAttempts < (totalCells * 12) do
		carveAttempts += 1
		local candidate = math.random(1, totalCells)
		if mask[candidate] == 1 then
			local row, col = indexToRowCol(candidate, size)
			local neighbors = countNeighbors(mask, size, row, col)
			if neighbors <= 3 or math.random() < 0.25 then
				mask[candidate] = 0
				filled -= 1
			end
		end
	end

	return mask
end

local function createBlobNoiseMask(size)
	local mask = table.create(size * size, 0)
	local minBlobs = math.max(4, math.floor(size / 4))
	local maxBlobs = math.max(minBlobs + 1, math.floor(size / 2))
	local blobs = math.random(minBlobs, maxBlobs)
	local centers = {}

	for _ = 1, blobs do
		centers[#centers + 1] = {
			row = math.random(1, size),
			col = math.random(1, size),
			radius = math.random(math.max(2, math.floor(size * 0.11)), math.max(3, math.floor(size * 0.26))),
			weight = 0.55 + (math.random() * 0.75),
		}
	end

	local threshold = 0.80 + (math.random() * 0.35)
	for row = 1, size do
		for col = 1, size do
			local influence = 0
			for _, center in ipairs(centers) do
				local dr = row - center.row
				local dc = col - center.col
				local distanceSq = (dr * dr) + (dc * dc)
				local normalized = distanceSq / (center.radius * center.radius)
				if normalized <= 3.8 then
					influence += center.weight * math.exp(-normalized * 1.35)
				end
			end

			influence += (math.random() - 0.5) * 0.38
			if influence > threshold then
				mask[rowColToIndex(row, col, size)] = 1
			end
		end
	end

	return mask
end

local function collectLineRuns(mask, size, isRow, lineIndex)
	local runs = {}
	local streakStart = nil

	for offset = 1, size do
		local row = isRow and lineIndex or offset
		local col = isRow and offset or lineIndex
		local filled = mask[rowColToIndex(row, col, size)] == 1

		if filled and not streakStart then
			streakStart = offset
		end

		if streakStart and (not filled or offset == size) then
			local endOffset = filled and offset or (offset - 1)
			runs[#runs + 1] = {
				startOffset = streakStart,
				endOffset = endOffset,
				length = endOffset - streakStart + 1,
			}
			streakStart = nil
		end
	end

	return runs
end

local function setLineCell(mask, size, isRow, lineIndex, offset, value)
	if offset < 1 or offset > size then
		return
	end
	local row = isRow and lineIndex or offset
	local col = isRow and offset or lineIndex
	mask[rowColToIndex(row, col, size)] = value
end

local function isSingletonCandidate(mask, size, isRow, lineIndex, offset)
	local row = isRow and lineIndex or offset
	local col = isRow and offset or lineIndex
	local index = rowColToIndex(row, col, size)
	if mask[index] == 1 then
		return false
	end

	local left = offset - 1
	local right = offset + 1

	local leftFilled = false
	if left >= 1 then
		local leftRow = isRow and lineIndex or left
		local leftCol = isRow and left or lineIndex
		leftFilled = mask[rowColToIndex(leftRow, leftCol, size)] == 1
	end

	local rightFilled = false
	if right <= size then
		local rightRow = isRow and lineIndex or right
		local rightCol = isRow and right or lineIndex
		rightFilled = mask[rowColToIndex(rightRow, rightCol, size)] == 1
	end

	return (not leftFilled) and (not rightFilled)
end

local function nudgeLineRuns(mask, size, isRow, lineIndex)
	local runs = collectLineRuns(mask, size, isRow, lineIndex)
	local runCount = #runs

	if runCount < 2 then
		if runCount == 0 then
			local first = math.random(2, math.max(2, size - 1))
			local second = math.random(2, math.max(2, size - 1))
			if math.abs(first - second) < 2 then
				second = math.clamp(first + (math.random() < 0.5 and -2 or 2), 1, size)
			end
			setLineCell(mask, size, isRow, lineIndex, first, 1)
			setLineCell(mask, size, isRow, lineIndex, second, 1)
			return
		end

		local run = runs[1]
		if run.length >= 4 then
			local splitAt = math.floor((run.startOffset + run.endOffset) * 0.5)
			setLineCell(mask, size, isRow, lineIndex, splitAt, 0)
			return
		end

		local candidates = {}
		for offset = 1, size do
			if isSingletonCandidate(mask, size, isRow, lineIndex, offset) then
				candidates[#candidates + 1] = offset
			end
		end
		if #candidates > 0 then
			setLineCell(mask, size, isRow, lineIndex, candidates[math.random(1, #candidates)], 1)
		else
			local offset = math.random(1, size)
			setLineCell(mask, size, isRow, lineIndex, offset, 1)
		end
		return
	end

	if runCount > 4 then
		local bestGapStart = nil
		local bestGapEnd = nil
		local bestGapLength = math.huge

		for i = 1, runCount - 1 do
			local gapStart = runs[i].endOffset + 1
			local gapEnd = runs[i + 1].startOffset - 1
			if gapEnd >= gapStart then
				local gapLength = gapEnd - gapStart + 1
				if gapLength < bestGapLength then
					bestGapLength = gapLength
					bestGapStart = gapStart
					bestGapEnd = gapEnd
				end
			end
		end

		if bestGapStart and bestGapEnd then
			for offset = bestGapStart, bestGapEnd do
				setLineCell(mask, size, isRow, lineIndex, offset, 1)
			end
		end
	end
end

local function tuneMaskRunDistribution(mask, size, passes)
	local totalPasses = math.max(1, math.floor(tonumber(passes) or 1))
	for _ = 1, totalPasses do
		for row = 1, size do
			nudgeLineRuns(mask, size, true, row)
		end
		for col = 1, size do
			nudgeLineRuns(mask, size, false, col)
		end
	end
	return mask
end

local function scoreMaskComplexity(mask, size)
	local totalRuns = 0
	local underLimit = 0
	local overLimit = 0
	local zeroRunLines = 0

	for row = 1, size do
		local runs = countLineRuns(mask, size, true, row)
		totalRuns += runs
		if runs == 0 then
			zeroRunLines += 1
		end
		if runs < 2 then
			underLimit += (2 - runs)
		end
		if runs > 4 then
			overLimit += (runs - 4)
		end
	end

	for col = 1, size do
		local runs = countLineRuns(mask, size, false, col)
		totalRuns += runs
		if runs == 0 then
			zeroRunLines += 1
		end
		if runs < 2 then
			underLimit += (2 - runs)
		end
		if runs > 4 then
			overLimit += (runs - 4)
		end
	end

	local lines = size * 2
	local averageRuns = totalRuns / lines
	local fillRatio = countFilled(mask) / (size * size)
	local fillPenalty = 0
	if fillRatio < 0.20 then
		fillPenalty = (0.20 - fillRatio) * 20
	elseif fillRatio > 0.55 then
		fillPenalty = (fillRatio - 0.55) * 20
	end

	return (zeroRunLines * 22)
		+ (underLimit * 9)
		+ (overLimit * 7)
		+ (math.abs(averageRuns - 3.0) * 3)
		+ fillPenalty
end

local function countRunRangeViolations(mask, size)
	local violations = 0

	for row = 1, size do
		local runs = countLineRuns(mask, size, true, row)
		if runs < 2 or runs > 4 then
			violations += 1
		end
	end

	for col = 1, size do
		local runs = countLineRuns(mask, size, false, col)
		if runs < 2 or runs > 4 then
			violations += 1
		end
	end

	return violations
end

function Puzzle:_generateSolution(size)
	local bestMask = nil
	local bestScore = math.huge
	local bestViolations = math.huge
	local attempts = 40

	for _ = 1, attempts do
		local candidate = createBlobNoiseMask(size)
		candidate = smoothMask(candidate, size, math.random(0, 1))
		candidate = pruneSmallComponents(candidate, size, math.max(3, math.floor(size * 0.06)))
		candidate = enforceFillBounds(candidate, size)
		candidate = tuneMaskRunDistribution(candidate, size, 3)
		candidate = smoothMask(candidate, size, math.random(0, 1))
		candidate = tuneMaskRunDistribution(candidate, size, 1)

		local score = scoreMaskComplexity(candidate, size)
		local violations = countRunRangeViolations(candidate, size)
		if violations < bestViolations or (violations == bestViolations and score < bestScore) then
			bestViolations = violations
			bestScore = score
			bestMask = candidate
		end
		if violations <= math.max(1, math.floor(size * 0.12)) and score <= 3 then
			break
		end
	end

	if bestMask then
		return bestMask
	end

	return createBlobNoiseMask(size)
end

function Puzzle:_seedStarterHints()
	local totalCells = self.Size * self.Size
	local emptyCandidates = {}

	for index = 1, totalCells do
		if self.SolutionMask[index] == 0 then
			emptyCandidates[#emptyCandidates + 1] = index
		end
	end

	local minHints = math.max(3, math.floor(self.Size * 0.25))
	local maxHints = math.max(minHints, math.floor(totalCells * 0.12))
	local targetHints = math.clamp(math.floor(totalCells * (0.04 + (math.random() * 0.03))), minHints, maxHints)

	self.LockedMask = table.create(totalCells, false)
	self.StarterHintCount = 0

	for _ = 1, math.min(targetHints, #emptyCandidates) do
		local index = pullRandomIndex(emptyCandidates)
		if index then
			self.LockedMask[index] = true
			self.PlayerMask[index] = 2
			self.StarterHintCount += 1
		end
	end
end

function Puzzle:_buildClues()
	local rowClues = {}
	local colClues = {}

	for row = 1, self.Size do
		local line = {}
		for col = 1, self.Size do
			line[#line + 1] = self.SolutionMask[rowColToIndex(row, col, self.Size)]
		end
		rowClues[row] = runLengths(line)
	end

	for col = 1, self.Size do
		local line = {}
		for row = 1, self.Size do
			line[#line + 1] = self.SolutionMask[rowColToIndex(row, col, self.Size)]
		end
		colClues[col] = runLengths(line)
	end

	self.RowClues = rowClues
	self.ColClues = colClues
end

function Puzzle:_computeClueBandSizes()
	local leftClueWidth = 1
	local topClueHeight = 1

	for row = 1, self.Size do
		local count = #(self.RowClues[row] or {})
		if count > leftClueWidth then
			leftClueWidth = count
		end
	end

	for col = 1, self.Size do
		local count = #(self.ColClues[col] or {})
		if count > topClueHeight then
			topClueHeight = count
		end
	end

	self.LeftClueWidth = leftClueWidth
	self.TopClueHeight = topClueHeight
end

function Puzzle:Generate(size)
	local parsed = math.floor(tonumber(size) or self.DefaultBoardSize)
	local clamped = math.clamp(parsed, self.MinBoardSize, self.MaxBoardSize)

	self.Size = clamped
	self.SolutionMask = self:_generateSolution(clamped)
	self.PlayerMask = table.create(clamped * clamped, 0)
	self.LockedMask = table.create(clamped * clamped, false)
	self.StarterHintCount = 0
	self.LivesMax = NONOGRAM_MAX_LIVES
	self.LivesRemaining = NONOGRAM_MAX_LIVES
	self.Solved = false
	self:_seedStarterHints()

	self:_buildClues()
	self:_computeClueBandSizes()
end

function Puzzle:_getCosmeticService()
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_getEquippedNonogramCelId(player)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_ensureNonogramCelFolder()
	if not (self.Board and self.Board.BoardFolder) then
		return nil
	end

	if self.NonogramCelFolder and self.NonogramCelFolder.Parent then
		return self.NonogramCelFolder
	end

	local folder = Instance.new("Folder")
	folder.Name = "NonogramCels"
	folder.Parent = self.Board.BoardFolder
	self.NonogramCelFolder = folder
	return folder
end

function Puzzle:_ensureClueCellFolder()
	if not (self.Board and self.Board.BoardFolder) then
		return nil
	end

	if self.ClueCellFolder and self.ClueCellFolder.Parent then
		return self.ClueCellFolder
	end

	local folder = Instance.new("Folder")
	folder.Name = "NonogramClueCells"
	folder.Parent = self.Board.BoardFolder
	self.ClueCellFolder = folder
	return folder
end

function Puzzle:_clearNonogramCel(index)
	if type(self.ActiveNonogramCels) ~= "table" then
		return
	end

	local existing = self.ActiveNonogramCels[index]
	if existing then
		existing:Destroy()
		self.ActiveNonogramCels[index] = nil
	end
end

function Puzzle:_placeNonogramCel(index, celId)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_destroyNonogramCels()
	if type(self.ActiveNonogramCels) == "table" then
		for index, model in pairs(self.ActiveNonogramCels) do
			if model then
				model:Destroy()
			end
			self.ActiveNonogramCels[index] = nil
		end
	end

	if self.NonogramCelFolder and self.NonogramCelFolder.Parent then
		self.NonogramCelFolder:Destroy()
	end

	self.NonogramCelFolder = nil
end

function Puzzle:_destroyClueCells()
	if type(self.ActiveClueCells) == "table" then
		for key, instance in pairs(self.ActiveClueCells) do
			if instance then
				instance:Destroy()
			end
			self.ActiveClueCells[key] = nil
		end
	end

	if self.ClueCellFolder and self.ClueCellFolder.Parent then
		self.ClueCellFolder:Destroy()
	end

	self.ClueCellFolder = nil
	self.ActiveClueCells = {}
end

function Puzzle:_getBoardBasis()
	local cell11 = self.Board and self.Board:GetCell(rowColToIndex(1, 1, self.Size))
	if not cell11 then
		return nil
	end

	local rotation = cell11.CFrame - cell11.Position

	local rightDir
	local downDir
	local xSpacing
	local ySpacing

	local cell12 = self.Size >= 2 and self.Board:GetCell(rowColToIndex(1, 2, self.Size)) or nil
	local cell21 = self.Size >= 2 and self.Board:GetCell(rowColToIndex(2, 1, self.Size)) or nil

	if cell12 then
		local delta = cell12.Position - cell11.Position
		if delta.Magnitude > 0.001 then
			rightDir = delta.Unit
			xSpacing = delta.Magnitude
		end
	end

	if cell21 then
		local delta = cell21.Position - cell11.Position
		if delta.Magnitude > 0.001 then
			downDir = delta.Unit
			ySpacing = delta.Magnitude
		end
	end

	local settings = self.Board and self.Board.Settings
	local originCFrame = resolveOriginCFrame(settings and settings.origin)
	local xDirection = settings and settings.xDirection or Vector3.new(0, 0, 1)
	local yDirection = settings and settings.yDirection or Vector3.new(-1, 0, 0)
	local cellSize = tonumber(settings and settings.cellSize) or 4

	if not rightDir then
		rightDir = originCFrame:VectorToWorldSpace((typeof(xDirection) == "Vector3" and xDirection.Magnitude > 0) and xDirection.Unit or Vector3.new(0, 0, 1))
		xSpacing = cellSize
	end

	if not downDir then
		downDir = originCFrame:VectorToWorldSpace((typeof(yDirection) == "Vector3" and yDirection.Magnitude > 0) and yDirection.Unit or Vector3.new(-1, 0, 0))
		ySpacing = cellSize
	end

	return {
		topLeftPuzzleCell = cell11,
		rotation = rotation,
		rightDir = rightDir,
		downDir = downDir,
		xSpacing = xSpacing or cellSize,
		ySpacing = ySpacing or cellSize,
	}
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
	if not (self.Board and self.Board.BoardFolder) then
		return
	end

	if self.GridOverlayFolder and self.GridOverlayFolder.Parent then
		self.GridOverlayFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "NonogramGrid"
	folder.Parent = self.Board.BoardFolder
	self.GridOverlayFolder = folder

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
		local isMajor = boundary == 0 or boundary == self.Size or (boundary % NONOGRAM_SUBGRID_SIZE) == 0
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

function Puzzle:_getVirtualCellCFrame(virtualRow, virtualCol)
	local basis = self:_getBoardBasis()
	if not basis then
		return nil
	end

	local puzzleStartRow = self.TopClueHeight + 1
	local puzzleStartCol = self.LeftClueWidth + 1

	local dx = virtualCol - puzzleStartCol
	local dy = virtualRow - puzzleStartRow

	local position = basis.topLeftPuzzleCell.Position
		+ (basis.rightDir * (dx * basis.xSpacing))
		+ (basis.downDir * (dy * basis.ySpacing))

	return CFrame.new(position) * basis.rotation
end

function Puzzle:_clearCloneText(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.Text = ""
			descendant.Visible = true
			descendant.BackgroundTransparency = 1
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = true
		end
	end
end

function Puzzle:_applyTextToClone(instance, text)
	local applied = false
	local finalText = tostring(text or "")

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = true
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.Text = finalText
			descendant.Visible = true
			descendant.BackgroundTransparency = 1
			descendant.TextScaled = true
			descendant.TextWrapped = false
			descendant.TextColor3 = CLUE_TEXT_COLOR
			descendant.TextStrokeTransparency = 0.85
			applied = true
		end
	end

	return applied
end

function Puzzle:_createFallbackFaceGui(part, face, text)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ClueGui_" .. face.Name
	gui.Face = face
	gui.AlwaysOnTop = false
	gui.CanvasSize = Vector2.new(256, 256)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = false
	label.Text = tostring(text or "")
	label.TextColor3 = CLUE_TEXT_COLOR
	label.TextStrokeTransparency = 0.85
	label.Parent = gui
end

function Puzzle:_ensureCloneText(instance, text)
	local finalText = tostring(text or "")
	self:_clearCloneText(instance)

	if finalText == "" then
		self:_applyTextToClone(instance, "")
		return
	end

	if self:_applyTextToClone(instance, finalText) then
		return
	end

	for _, face in ipairs({
		Enum.NormalId.Top,
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	}) do
		self:_createFallbackFaceGui(instance, face, finalText)
	end
end

function Puzzle:_getRowClueValueAt(virtualRow, virtualCol)
	local puzzleRow = virtualRow - self.TopClueHeight
	if puzzleRow < 1 or puzzleRow > self.Size then
		return nil
	end

	local clues = self.RowClues[puzzleRow] or {}
	local startCol = self.LeftClueWidth - #clues + 1

	if virtualCol < startCol or virtualCol > self.LeftClueWidth then
		return nil
	end

	local clueIndex = virtualCol - startCol + 1
	return clues[clueIndex]
end

function Puzzle:_getColClueValueAt(virtualRow, virtualCol)
	local puzzleCol = virtualCol - self.LeftClueWidth
	if puzzleCol < 1 or puzzleCol > self.Size then
		return nil
	end

	local clues = self.ColClues[puzzleCol] or {}
	local startRow = self.TopClueHeight - #clues + 1

	if virtualRow < startRow or virtualRow > self.TopClueHeight then
		return nil
	end

	local clueIndex = virtualRow - startRow + 1
	return clues[clueIndex]
end

function Puzzle:_isVirtualPuzzleCell(virtualRow, virtualCol)
	return virtualRow > self.TopClueHeight and virtualCol > self.LeftClueWidth
end

function Puzzle:_stripClueCloneInteraction(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ClickDetector") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

function Puzzle:_createClueClone(name, templateCell, cframe, text)
	local folder = self:_ensureClueCellFolder()
	if not folder then
		return nil
	end
	if not (templateCell and templateCell:IsA("BasePart")) then
		return nil
	end

	local clone = templateCell:Clone()
	clone.Name = name
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.Color = CLUE_PLATE_COLOR
	clone.CFrame = cframe

	self:_stripClueCloneInteraction(clone)
	self:_ensureCloneText(clone, text)

	clone.Parent = folder
	return clone
end

function Puzzle:_buildClueCells()
	if not self.Board then
		return
	end

	self:_destroyClueCells()
	self.ActiveClueCells = {}

	local templateCell = self.Board:GetCell(rowColToIndex(1, 1, self.Size))
	if not (templateCell and templateCell:IsA("BasePart")) then
		return
	end

	local totalVirtualRows = self.TopClueHeight + self.Size
	local totalVirtualCols = self.LeftClueWidth + self.Size

	for virtualRow = 1, totalVirtualRows do
		for virtualCol = 1, totalVirtualCols do
			if not self:_isVirtualPuzzleCell(virtualRow, virtualCol) then
				local clueValue = nil

				if virtualRow > self.TopClueHeight and virtualCol <= self.LeftClueWidth then
					clueValue = self:_getRowClueValueAt(virtualRow, virtualCol)
				elseif virtualRow <= self.TopClueHeight and virtualCol > self.LeftClueWidth then
					clueValue = self:_getColClueValueAt(virtualRow, virtualCol)
				end

				if clueValue ~= nil then
					local cframe = self:_getVirtualCellCFrame(virtualRow, virtualCol)
					if cframe then
						local key = ("%d_%d"):format(virtualRow, virtualCol)
						self.ActiveClueCells[key] = self:_createClueClone(
							("ClueCell_%s"):format(key),
							templateCell,
							cframe,
							tostring(clueValue)
						)
					end
				end
			end
		end
	end
end

function Puzzle:RefreshInteractionVisuals()
	if not self.Board then
		return
	end

	for index = 1, #self.PlayerMask do
		local value = self.PlayerMask[index]
		local isLocked = self.LockedMask and self.LockedMask[index] == true
		if value == 1 then
			self.Board:SetCellColor(index, FILLED_CELL_COLOR)
			self.Board:SetCellText(index, "", CLUE_TEXT_COLOR)
		elseif value == 2 then
			self.Board:SetCellColor(index, isLocked and LOCKED_CROSS_CELL_COLOR or CROSS_CELL_COLOR)
			self.Board:SetCellText(index, "X", CROSS_TEXT_COLOR)
		else
			self.Board:SetCellColor(index, checkerColor(self.Size, index, UNKNOWN_CELL_COLOR_A, UNKNOWN_CELL_COLOR_B))
			self.Board:SetCellText(index, "", CLUE_TEXT_COLOR)
		end
	end
end

function Puzzle:IsSolved()
	for index = 1, #self.SolutionMask do
		local expected = self.SolutionMask[index]
		local current = self.PlayerMask[index]

		if expected == 1 and current ~= 1 then
			return false
		end
		if expected == 0 and current == 1 then
			return false
		end
	end

	return true
end

function Puzzle:GetSnapshot()
	return {
		Size = self.Size,
		RowClues = self.RowClues,
		ColClues = self.ColClues,
		PlayerMask = self.PlayerMask,
		LockedMask = self.LockedMask,
		StarterHintCount = self.StarterHintCount,
		LivesRemaining = self.LivesRemaining,
		LivesMax = self.LivesMax,
		Solved = self.Solved,
	}
end

function Puzzle:GetSessionAnchor()
	if self.Board and self.Board.Settings and self.Board.Settings.origin then
		return self.Board.Settings.origin.Position
	end
	return resolveBoardOrigin().Position
end

function Puzzle:GetRoundDuration(size)
	local parsed = math.floor(tonumber(size) or self.DefaultBoardSize)
	local clamped = math.clamp(parsed, self.MinBoardSize, self.MaxBoardSize)
	return (clamped * clamped) * 5
end

function Puzzle:ResolveCellIndex(target)
	if type(target) == "number" then
		return target
	end

	if typeof(target) == "Instance" then
		if self.ClueCellFolder and target:IsDescendantOf(self.ClueCellFolder) then
			return nil
		end

		if self.Board then
			return self.Board:GetCellIdFromInstance(target)
		end
	end

	return nil
end

function Puzzle:MarkCompletedVisual()
	if self.Board then
		self.Board:SetCompletedVisual()
	end
end

function Puzzle:HandleInteraction(player, target, action)
	if self.Solved then
		return false, "Puzzle already solved"
	end

	local index = self:ResolveCellIndex(target)
	if not index or not self.PlayerMask[index] then
		return false, "Invalid board cell"
	end
	if self.LockedMask and self.LockedMask[index] then
		return false, "That clue cell is locked"
	end

	local normalizedAction = string.lower(tostring(action or "reveal"))
	local current = self.PlayerMask[index]
	local nextValue

	if normalizedAction == "flagtoggle" or normalizedAction == "flag" then
		nextValue = (current == 2) and 0 or 2
	else
		nextValue = (current == 1) and 0 or 1
	end

	if nextValue == 1 and self.SolutionMask[index] == 0 then
		self.LivesRemaining = math.max(0, (self.LivesRemaining or NONOGRAM_MAX_LIVES) - 1)
		self.PlayerMask[index] = 2
		self.LockedMask[index] = true
		self.StarterHintCount = (self.StarterHintCount or 0) + 1
		self.Board:SetData(index, 0)
		self:_clearNonogramCel(index)
		self:RefreshInteractionVisuals()

		return true, {
			Index = index,
			Value = self.PlayerMask[index],
			Solved = false,
			Failed = self.LivesRemaining <= 0,
			LivesRemaining = self.LivesRemaining,
			LivesMax = self.LivesMax or NONOGRAM_MAX_LIVES,
			MistakeMessage = buildMistakeMessage(player and player.Name, self.LivesRemaining),
		}
	end

	self.PlayerMask[index] = nextValue
	self.Board:SetData(index, nextValue == 1 and 1 or 0)

	if nextValue == 1 then
		self:_placeNonogramCel(index, self:_getEquippedNonogramCelId(player))
	else
		self:_clearNonogramCel(index)
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
		LivesRemaining = self.LivesRemaining,
		LivesMax = self.LivesMax,
	}
end

function Puzzle:Init(size, options)
	if self.Board then
		self:_destroyNonogramCels()
		self:_destroyClueCells()
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
	self:_buildGridOverlay()

	self.ActiveNonogramCels = {}
	self.ActiveClueCells = {}

	self:_ensureNonogramCelFolder()
	self:_ensureClueCellFolder()

	for index = 1, self.Size * self.Size do
		local value = self.PlayerMask[index] or 0
		self.Board:SetData(index, value == 1 and 1 or 0)
		self.Board:SetCellText(index, "", CLUE_TEXT_COLOR)
		if value == 1 then
			self:_placeNonogramCel(index, NONOGRAM_CEL_DEFAULT)
		else
			self:_clearNonogramCel(index)
		end
	end

	self:RefreshInteractionVisuals()
	self:_buildClueCells()
end

return Puzzle
