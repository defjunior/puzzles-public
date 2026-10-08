-- Actual Hitori puzzle implementation; selected authored presentation/defaults omitted.
-- Generation/rules/session interfaces retained; missing assets/config prevent standalone use.
-- Authored board/session defaults omitted. Supply configuration before running.
local Puzzle = { Name = "Hitori", ModeKey = "hitori" }

local BLOCKED_CELL_COLOR = nil -- Omitted: authored visual/cosmetic value.
local HITORI_CEL_CATEGORY = nil -- Omitted: authored visual/cosmetic value.
local HITORI_CEL_DEFAULT = nil -- Omitted: authored visual/cosmetic value.
local CHESS_SKIN_ID = nil -- Omitted: authored visual/cosmetic value.
local CHESS_PAWN_WEIGHT = nil -- Omitted: authored visual/cosmetic value.

local Classes = game.ServerScriptService.Classes
local BoardClass = require(Classes:WaitForChild("Board"))
local Gen = require(script.Gen)
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Framework = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Framework"))

local function indexToRowCol(index, width)
	local row = math.floor((index - 1) / width) + 1
	local col = ((index - 1) % width) + 1
	return row, col
end

local function normalizeGridValues(grid)
	local unique = {}
	local seen = {}

	for r = 1, #grid do
		for c = 1, #grid[r] do
			local value = grid[r][c]
			if not seen[value] then
				seen[value] = true
				unique[#unique + 1] = value
			end
		end
	end

	table.sort(unique)

	local remap = {}
	for i, value in ipairs(unique) do
		remap[value] = i
	end

	local normalized = table.create(#grid)
	for r = 1, #grid do
		local row = table.create(#grid[r])
		for c = 1, #grid[r] do
			row[c] = remap[grid[r][c]]
		end
		normalized[r] = row
	end

	return normalized
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
	local hitoriOrigins = origins and origins:FindFirstChild("Hitori")
	if hitoriOrigins then
		local resolved = resolveRotatableOrigin(hitoriOrigins)
		if resolved then
			return resolved
		end
	end
	-- Fallback for missing map origins.
	return CFrame.new(-12.5, 2, 55.5)
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

local function getHitoriCellFolder()
	local assets = ReplicatedFirst:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local hitoriCel = models and models:FindFirstChild("HitoriCel")
	if hitoriCel and hitoriCel:IsA("Folder") then
		return hitoriCel
	end
	return nil
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

local function chooseChessPieceModel(chessRoot)
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

function Puzzle:Generate(size)
	local grid, solutionMask = Gen:Generate(size, {
		attempts = 320,
		timeLimit = 6,
		unique = true,
		blackRatio = 0.24,
		valueRange = math.max(24, size * 4),
	})
	if not grid then
		grid, solutionMask = Gen:Generate(size, {
			attempts = 120,
			timeLimit = 2.5,
			unique = false,
			blackRatio = 0.22,
			valueRange = math.max(18, size * 3),
		})
	end
	if not grid then
		-- Omitted: authored fallback puzzle grid and solution mask.
		return nil
	end

	self.Size = size
	self.Grid = normalizeGridValues(grid)
	self.PlayerMask = table.create(size * size, 0)
	self.Solved = false
end

function Puzzle:_getCosmeticService()
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_getEquippedHitoriCelId(player)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_ensureHitoriCelFolder()
	if not (self.Board and self.Board.BoardFolder) then
		return nil
	end
	if self.HitoriCelFolder and self.HitoriCelFolder.Parent then
		return self.HitoriCelFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "HitoriCels"
	folder.Parent = self.Board.BoardFolder
	self.HitoriCelFolder = folder
	return folder
end

function Puzzle:_clearHitoriCel(index)
	if type(self.ActiveHitoriCels) ~= "table" then
		return
	end
	local existing = self.ActiveHitoriCels[index]
	if existing then
		existing:Destroy()
		self.ActiveHitoriCels[index] = nil
	end
end

function Puzzle:_placeHitoriCel(index, celId)
	-- Omitted: authored dialogue/cosmetic/skin selection and placement.
end

function Puzzle:_destroyHitoriCels()
	if type(self.ActiveHitoriCels) == "table" then
		for index, model in pairs(self.ActiveHitoriCels) do
			if model then
				model:Destroy()
			end
			self.ActiveHitoriCels[index] = nil
		end
	end
	if self.HitoriCelFolder and self.HitoriCelFolder.Parent then
		self.HitoriCelFolder:Destroy()
	end
	self.HitoriCelFolder = nil
end

function Puzzle:MarkCompletedVisual()
	if self.Board then
		self.Board:SetCompletedVisual()
	end
end

function Puzzle:IsSolved()
	local ok = Gen:ValidateFlatMask(self.Grid, self.PlayerMask, self.Size)
	return ok == true
end

function Puzzle:IsAdjacentBlack(index)
	local row, col = indexToRowCol(index, self.Size)
	local offsets = {
		{ 1, 0 },
		{ -1, 0 },
		{ 0, 1 },
		{ 0, -1 },
	}
	for _, offset in ipairs(offsets) do
		local r = row + offset[1]
		local c = col + offset[2]
		if r >= 1 and r <= self.Size and c >= 1 and c <= self.Size then
			local testIndex = ((r - 1) * self.Size) + c
			if self.PlayerMask[testIndex] == 1 then
				return true
			end
		end
	end
	return false
end

function Puzzle:IsBlockedByAdjacentBlack(index)
	if self.PlayerMask[index] == 1 then
		return false
	end
	return self:IsAdjacentBlack(index)
end

function Puzzle:RefreshInteractionVisuals()
	if not self.Board then
		return
	end

	for index = 1, #self.PlayerMask do
		if self.PlayerMask[index] == 1 then
			self.Board:SetCellColor(index, self.Board.Settings.fillColor)
		elseif self:IsBlockedByAdjacentBlack(index) then
			self.Board:SetCellColor(index, BLOCKED_CELL_COLOR)
		else
			self.Board:SetCellColor(index, self.Board.Settings.baseColor)
		end
	end
end

function Puzzle:GetSnapshot()
	return {
		Size = self.Size,
		Grid = self.Grid,
		PlayerMask = self.PlayerMask,
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
	return (clamped * clamped) * 4
end

function Puzzle:ResolveCellIndex(target)
	if type(target) == "number" then
		return target
	end
	if typeof(target) == "Instance" then
		return self.Board:GetCellIdFromInstance(target)
	end
	return nil
end

function Puzzle:HandleInteraction(player, target)
	if self.Solved then
		return false, "Puzzle already solved"
	end

	local index = self:ResolveCellIndex(target)
	if not index or not self.PlayerMask[index] then
		return false, "Invalid board cell"
	end

	local nextValue = self.PlayerMask[index] == 1 and 0 or 1
	if nextValue == 1 and self:IsAdjacentBlack(index) then
		self:RefreshInteractionVisuals()
		return false, "Cannot place adjacent black cells"
	end

	self.PlayerMask[index] = nextValue
	self.Board:SetData(index, nextValue)
	if nextValue == 1 then
		self:_placeHitoriCel(index, self:_getEquippedHitoriCelId(player))
	else
		self:_clearHitoriCel(index)
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
	if self.Board then
		self:_destroyHitoriCels()
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
		-- Keep legacy readability for two-digit values.
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
	self.ActiveHitoriCels = {}
	self:_ensureHitoriCelFolder()

	local index = 0
	for row = 1, self.Size do
		for col = 1, self.Size do
			index += 1
			self.Board:SetNumberDisplay(index, self.Grid[row][col])
			self.Board:SetData(index, 0)
		end
	end
	self:RefreshInteractionVisuals()
end

return Puzzle
