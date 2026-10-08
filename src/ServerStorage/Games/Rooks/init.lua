-- Actual Rooks puzzle implementation; selected authored presentation/defaults omitted.
-- Generation/rules/session interfaces retained; missing assets/config prevent standalone use.
-- Authored board/session defaults omitted. Supply configuration before running.
local Puzzle = { Name = "Rooks", ModeKey = "rooks" }

local BOARD_LIGHT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local BOARD_DARK_COLOR = nil -- Omitted: authored visual/cosmetic value.
local WHITE_PIECE_COLOR = nil -- Omitted: authored visual/cosmetic value.
local ROOK_COLOR = nil -- Omitted: authored visual/cosmetic value.
local ROOK_CONFLICT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local MARKED_EMPTY_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CLUE_PLATE_COLOR = nil -- Omitted: authored visual/cosmetic value.
local TEXT_DARK_COLOR = nil -- Omitted: authored visual/cosmetic value.
local TEXT_LIGHT_COLOR = nil -- Omitted: authored visual/cosmetic value.
local CLUE_TEXT_COLOR = nil -- Omitted: authored visual/cosmetic value.

local Classes = game.ServerScriptService.Classes
local BoardClass = require(Classes:WaitForChild("Board"))
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")

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
	local rooksOrigins = origins and origins:FindFirstChild("Rooks")
	if rooksOrigins then
		local resolved = resolveRotatableOrigin(rooksOrigins)
		if resolved then
			return resolved
		end
	end
	return CFrame.new(145.5, 2, 55.5)
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

local function checkerColor(size, index)
	local row, col = indexToRowCol(index, size)
	if ((row + col) % 2) == 0 then
		return BOARD_LIGHT_COLOR
	end
	return BOARD_DARK_COLOR
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

local function getChessRoot()
	local assets = ReplicatedFirst:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local flags = models and models:FindFirstChild("Flags")
	local chess = flags and flags:FindFirstChild("Chess")
	if chess and chess:IsA("Model") then
		return chess
	end
	return nil
end

local function cloneChessPiece(preferredNames, randomize)
	local chessRoot = getChessRoot()
	if not chessRoot then
		return nil
	end

	local names = type(preferredNames) == "table" and preferredNames or { preferredNames }
	if randomize == true then
		local available = {}
		for _, preferredName in ipairs(names) do
			local preferred = chessRoot:FindFirstChild(tostring(preferredName or ""))
			if preferred and preferred:IsA("Model") then
				available[#available + 1] = preferred
			end
		end
		if #available > 0 then
			return available[math.random(1, #available)]:Clone()
		end
	end

	for _, preferredName in ipairs(names) do
		local preferred = chessRoot:FindFirstChild(tostring(preferredName or ""))
		if preferred and preferred:IsA("Model") then
			return preferred:Clone()
		end
	end

	local fallback = chessRoot:FindFirstChild("Pawn")
	if fallback and fallback:IsA("Model") then
		return fallback:Clone()
	end

	for _, child in ipairs(chessRoot:GetChildren()) do
		if child:IsA("Model") then
			return child:Clone()
		end
	end
	return nil
end

local function tintModel(model, color)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

local function shuffledIndexes(total)
	local list = table.create(total)
	for index = 1, total do
		list[index] = index
	end
	for index = total, 2, -1 do
		local swapIndex = math.random(1, index)
		list[index], list[swapIndex] = list[swapIndex], list[index]
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

local function getAllNeighbors(index, size)
	local row, col = indexToRowCol(index, size)
	local neighbors = {}
	for rowDelta = -1, 1 do
		for colDelta = -1, 1 do
			if not (rowDelta == 0 and colDelta == 0) then
				local nextRow = row + rowDelta
				local nextCol = col + colDelta
				if nextRow >= 1 and nextRow <= size and nextCol >= 1 and nextCol <= size then
					neighbors[#neighbors + 1] = rowColToIndex(nextRow, nextCol, size)
				end
			end
		end
	end
	return neighbors
end

function Puzzle:_canPlaceSolutionRook(index)
	if self.SolutionRooks[index] == true or self.WhitePieces[index] == true then
		return false
	end
	for _, neighbor in ipairs(getAllNeighbors(index, self.Size)) do
		if self.SolutionRooks[neighbor] == true then
			return false
		end
	end
	return true
end

function Puzzle:_collectWhitePieceCandidates(rookIndex)
	local candidates = {}
	for _, neighbor in ipairs(getCardinalNeighbors(rookIndex, self.Size)) do
		if self.SolutionRooks[neighbor] ~= true and self.WhitePieces[neighbor] ~= true then
			candidates[#candidates + 1] = neighbor
		end
	end
	return candidates
end

function Puzzle:_buildClues()
	local rowClues = table.create(self.Size, 0)
	local colClues = table.create(self.Size, 0)
	for index = 1, self.Size * self.Size do
		if self.SolutionRooks[index] == true then
			local row, col = indexToRowCol(index, self.Size)
			rowClues[row] = (rowClues[row] or 0) + 1
			colClues[col] = (colClues[col] or 0) + 1
		end
	end
	self.RowClues = rowClues
	self.ColClues = colClues
end

function Puzzle:Generate(size)
	local parsed = math.floor(tonumber(size) or self.DefaultBoardSize)
	self.Size = math.clamp(parsed, self.MinBoardSize, self.MaxBoardSize)
	local total = self.Size * self.Size
	self.SolutionRooks = table.create(total, false)
	self.WhitePieces = table.create(total, false)
	self.PlayerMask = table.create(total, 0)
	self.Solved = false

	local targetRooks = math.clamp(math.floor(self.Size * 1.35), self.Size, math.floor(total * 0.26))
	local placed = 0
	for _, rookIndex in ipairs(shuffledIndexes(total)) do
		if placed >= targetRooks then
			break
		end
		if self:_canPlaceSolutionRook(rookIndex) then
			local whiteCandidates = self:_collectWhitePieceCandidates(rookIndex)
			if #whiteCandidates > 0 then
				local whiteIndex = whiteCandidates[math.random(1, #whiteCandidates)]
				self.SolutionRooks[rookIndex] = true
				self.WhitePieces[whiteIndex] = true
				placed += 1
			end
		end
	end

	self:_buildClues()
end

function Puzzle:_ensureClueCellFolder()
	if not (self.Board and self.Board.BoardFolder) then
		return nil
	end
	if self.ClueCellFolder and self.ClueCellFolder.Parent then
		return self.ClueCellFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "RooksClueCells"
	folder.Parent = self.Board.BoardFolder
	self.ClueCellFolder = folder
	return folder
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

function Puzzle:_ensurePieceFolder()
	if not (self.Board and self.Board.BoardFolder) then
		return nil
	end
	if self.PieceFolder and self.PieceFolder.Parent then
		return self.PieceFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "RooksPieces"
	folder.Parent = self.Board.BoardFolder
	self.PieceFolder = folder
	return folder
end

function Puzzle:_clearPiece(index)
	if type(self.ActivePieces) ~= "table" then
		return
	end
	local existing = self.ActivePieces[index]
	if existing then
		existing:Destroy()
		self.ActivePieces[index] = nil
	end
end

function Puzzle:_destroyPieces()
	if type(self.ActivePieces) == "table" then
		for index, model in pairs(self.ActivePieces) do
			if model then
				model:Destroy()
			end
			self.ActivePieces[index] = nil
		end
	end
	if self.PieceFolder and self.PieceFolder.Parent then
		self.PieceFolder:Destroy()
	end
	self.PieceFolder = nil
end

function Puzzle:_placePiece(index, pieceNames, color, randomize)
	if not self.Board then
		return false
	end

	local cell = self.Board:GetCell(index)
	local folder = self:_ensurePieceFolder()
	if not cell or not folder then
		return false
	end

	self:_clearPiece(index)

	local clone = cloneChessPiece(pieceNames, randomize == true)
	if not clone then
		return false
	end

	local label = type(pieceNames) == "table" and tostring(pieceNames[1] or "Piece") or tostring(pieceNames or "Piece")
	clone.Name = ("%s_%d"):format(label, index)
	tintModel(clone, color)
	if alignModelOnCell(clone, cell) then
		clone.Parent = folder
		self.ActivePieces[index] = clone
		return true
	end

	clone:Destroy()
	return false
end

function Puzzle:_getBoardBasis()
	local cell11 = self.Board and self.Board:GetCell(rowColToIndex(1, 1, self.Size))
	if not cell11 then
		return nil
	end

	local rotation = cell11.CFrame - cell11.Position
	local cell12 = self.Size >= 2 and self.Board:GetCell(rowColToIndex(1, 2, self.Size)) or nil
	local cell21 = self.Size >= 2 and self.Board:GetCell(rowColToIndex(2, 1, self.Size)) or nil
	local settings = self.Board and self.Board.Settings
	local originCFrame = resolveOriginCFrame(settings and settings.origin)
	local xDirection = settings and settings.xDirection or Vector3.new(1, 0, 0)
	local yDirection = settings and settings.yDirection or Vector3.new(0, 0, 1)
	local cellSize = tonumber(settings and settings.cellSize) or 4

	local rightDir = originCFrame:VectorToWorldSpace((typeof(xDirection) == "Vector3" and xDirection.Magnitude > 0) and xDirection.Unit or Vector3.new(1, 0, 0))
	local downDir = originCFrame:VectorToWorldSpace((typeof(yDirection) == "Vector3" and yDirection.Magnitude > 0) and yDirection.Unit or Vector3.new(0, 0, 1))
	local xSpacing = cellSize
	local ySpacing = cellSize

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

	return {
		topLeftPuzzleCell = cell11,
		rotation = rotation,
		rightDir = rightDir,
		downDir = downDir,
		xSpacing = xSpacing,
		ySpacing = ySpacing,
	}
end

function Puzzle:_getVirtualCellCFrame(virtualRow, virtualCol)
	local basis = self:_getBoardBasis()
	if not basis then
		return nil
	end

	local dx = virtualCol - 2
	local dy = virtualRow - 2
	local position = basis.topLeftPuzzleCell.Position
		+ (basis.rightDir * (dx * basis.xSpacing))
		+ (basis.downDir * (dy * basis.ySpacing))
	return CFrame.new(position) * basis.rotation
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

function Puzzle:_ensureCloneText(instance, text)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.Text = ""
			descendant.Visible = true
			descendant.BackgroundTransparency = 1
		end
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.Text = tostring(text or "")
			descendant.Visible = true
			descendant.BackgroundTransparency = 1
			descendant.TextScaled = true
			descendant.TextWrapped = false
			descendant.TextColor3 = CLUE_TEXT_COLOR
			descendant.TextStrokeTransparency = 0.85
		end
	end

	for _, face in ipairs({
		Enum.NormalId.Top,
	}) do
		local existing = instance:FindFirstChild("ClueGui_" .. face.Name)
		if existing then
			existing:Destroy()
		end

		local gui = Instance.new("SurfaceGui")
		gui.Name = "ClueGui_" .. face.Name
		gui.Face = face
		gui.AlwaysOnTop = false
		gui.CanvasSize = Vector2.new(256, 256)
		gui.Parent = instance

		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = tostring(text or "")
		label.TextColor3 = CLUE_TEXT_COLOR
		label.TextStrokeTransparency = 0.85
		label.Parent = gui
	end
end

function Puzzle:_createClueClone(name, templateCell, cframe, text)
	local folder = self:_ensureClueCellFolder()
	if not folder or not (templateCell and templateCell:IsA("BasePart")) then
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
	clone:SetAttribute("BoardId", nil)
	clone:SetAttribute("CellId", nil)

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
	if not templateCell then
		return
	end

	for row = 1, self.Size do
		for sideName, virtualCol in pairs({
			left = 1,
			right = self.Size + 2,
		}) do
			local cframe = self:_getVirtualCellCFrame(row + 1, virtualCol)
			if cframe then
				local key = ("row_%s_%d"):format(sideName, row)
				self.ActiveClueCells[key] = self:_createClueClone(key, templateCell, cframe, tostring(self.RowClues[row] or 0))
			end
		end
	end
	for col = 1, self.Size do
		for sideName, virtualRow in pairs({
			top = 1,
			bottom = self.Size + 2,
		}) do
			local cframe = self:_getVirtualCellCFrame(virtualRow, col + 1)
			if cframe then
				local key = ("col_%s_%d"):format(sideName, col)
				self.ActiveClueCells[key] = self:_createClueClone(key, templateCell, cframe, tostring(self.ColClues[col] or 0))
			end
		end
	end
end

function Puzzle:_isRookConflict(index)
	if self.PlayerMask[index] ~= 1 then
		return false
	end
	if self.WhitePieces[index] == true then
		return true
	end
	local row, col = indexToRowCol(index, self.Size)
	local rowCount = 0
	local colCount = 0
	for offset = 1, self.Size do
		if self.PlayerMask[rowColToIndex(row, offset, self.Size)] == 1 then
			rowCount += 1
		end
		if self.PlayerMask[rowColToIndex(offset, col, self.Size)] == 1 then
			colCount += 1
		end
	end
	if rowCount > (self.RowClues[row] or 0) or colCount > (self.ColClues[col] or 0) then
		return true
	end
	for _, neighbor in ipairs(getAllNeighbors(index, self.Size)) do
		if self.PlayerMask[neighbor] == 1 then
			return true
		end
	end
	for _, neighbor in ipairs(getCardinalNeighbors(index, self.Size)) do
		if self.WhitePieces[neighbor] == true then
			return false
		end
	end
	return true
end

function Puzzle:RefreshInteractionVisuals()
	if not self.Board then
		return
	end

	for index = 1, self.Size * self.Size do
		if self.WhitePieces[index] == true then
			self.Board:SetCellColor(index, WHITE_PIECE_COLOR)
			if not (self.ActivePieces and self.ActivePieces[index]) then
				if not self:_placePiece(index, { "Queen", "King", "Bishop", "Knight", "Pawn" }, WHITE_PIECE_COLOR, true) then
					self.Board:SetCellText(index, "W", TEXT_DARK_COLOR)
				else
					self.Board:SetCellText(index, "", TEXT_DARK_COLOR)
				end
			else
				self.Board:SetCellText(index, "", TEXT_DARK_COLOR)
			end
		elseif self.PlayerMask[index] == 1 then
			self.Board:SetCellColor(index, self:_isRookConflict(index) and ROOK_CONFLICT_COLOR or ROOK_COLOR)
			if not (self.ActivePieces and self.ActivePieces[index]) then
				if not self:_placePiece(index, { "Rook", "Castle", "Tower" }, ROOK_COLOR, false) then
					self.Board:SetCellText(index, "R", TEXT_LIGHT_COLOR)
				else
					self.Board:SetCellText(index, "", TEXT_LIGHT_COLOR)
				end
			else
				self.Board:SetCellText(index, "", TEXT_LIGHT_COLOR)
			end
		elseif self.PlayerMask[index] == 2 then
			self:_clearPiece(index)
			self.Board:SetCellColor(index, MARKED_EMPTY_COLOR)
			self.Board:SetCellText(index, "X", TEXT_LIGHT_COLOR)
		else
			self:_clearPiece(index)
			self.Board:SetCellColor(index, checkerColor(self.Size, index))
			self.Board:SetCellText(index, "", TEXT_LIGHT_COLOR)
		end
	end
end

function Puzzle:IsSolved()
	local totalRooks = 0
	for row = 1, self.Size do
		local rowCount = 0
		for col = 1, self.Size do
			local index = rowColToIndex(row, col, self.Size)
			if self.PlayerMask[index] == 1 then
				rowCount += 1
				totalRooks += 1
				if self:_isRookConflict(index) then
					return false
				end
			end
		end
		if rowCount ~= (self.RowClues[row] or 0) then
			return false
		end
	end

	for col = 1, self.Size do
		local colCount = 0
		for row = 1, self.Size do
			if self.PlayerMask[rowColToIndex(row, col, self.Size)] == 1 then
				colCount += 1
			end
		end
		if colCount ~= (self.ColClues[col] or 0) then
			return false
		end
	end

	local whiteCount = 0
	for index = 1, self.Size * self.Size do
		if self.WhitePieces[index] == true then
			whiteCount += 1
			local hasRook = false
			for _, neighbor in ipairs(getCardinalNeighbors(index, self.Size)) do
				if self.PlayerMask[neighbor] == 1 then
					hasRook = true
					break
				end
			end
			if not hasRook then
				return false
			end
		end
	end

	return totalRooks == whiteCount
end

function Puzzle:GetSnapshot()
	return {
		Size = self.Size,
		RowClues = self.RowClues,
		ColClues = self.ColClues,
		PlayerMask = self.PlayerMask,
		WhitePieces = self.WhitePieces,
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
	if self.WhitePieces[index] == true then
		return false, "White pieces are fixed"
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
	if self.Board then
		self:_destroyPieces()
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
	self.ActivePieces = {}
	self.ActiveClueCells = {}
	self:_ensurePieceFolder()
	self:_ensureClueCellFolder()

	for index = 1, self.Size * self.Size do
		self.Board:SetData(index, 0)
		self.Board:SetCellText(index, "", TEXT_DARK_COLOR)
	end

	self:RefreshInteractionVisuals()
	self:_buildClueCells()
end

return Puzzle
