-- Actual Minesweeper puzzle implementation; selected authored presentation/defaults omitted.
-- Generation/rules/session interfaces retained; missing assets/config prevent standalone use.
-- Authored board/session defaults omitted. Supply configuration before running.
local Puzzle = { Name = "Minesweeper", ModeKey = "minesweeper" }

local Classes = game.ServerScriptService.Classes
local BoardClass = require(Classes:WaitForChild("Board"))
local NDimensionalBoard = require(game.ServerStorage.Modules:WaitForChild("NDimensionalBoard"))
local Workspace = game:GetService("Workspace")

local EXTRA_ND_BOARD_CONFIGS = {} -- Omitted: authored presets/dialogue.

local function indexToRowCol(index, width)
	local row = math.floor((index - 1) / width) + 1
	local col = ((index - 1) % width) + 1
	return row, col
end

local function rowColToIndex(row, col, width)
	return ((row - 1) * width) + col
end

local function getNeighborIndexes(index, size)
	local row, col = indexToRowCol(index, size)
	local list = {}
	for dy = -1, 1 do
		for dx = -1, 1 do
			if not (dx == 0 and dy == 0) then
				local nr = row + dy
				local nc = col + dx
				if nr >= 1 and nr <= size and nc >= 1 and nc <= size then
					list[#list + 1] = rowColToIndex(nr, nc, size)
				end
			end
		end
	end
	return list
end

local function shuffledIndexes(total)
	local list = table.create(total)
	for i = 1, total do
		list[i] = i
	end
	for i = total, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
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
	local minesweeperOrigins = origins and origins:FindFirstChild("Minesweeper")
	if minesweeperOrigins then
		local resolved = resolveRotatableOrigin(minesweeperOrigins, originName)
		if resolved then
			return resolved
		end
	end
	-- Fallback for missing map origins.
	return CFrame.new(23.5, 2, 55.5)
end

local function resolveSpecificBoardOrigin(originName)
	if type(originName) ~= "string" or originName == "" then
		return nil
	end
	local origins = Workspace:FindFirstChild("Origins")
	local minesweeperOrigins = origins and origins:FindFirstChild("Minesweeper")
	local candidate = minesweeperOrigins and minesweeperOrigins:FindFirstChild(originName)
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

function Puzzle:_buildEmptyState(size)
	local total = size * size
	self.MineMap = table.create(total, false)
	self.NeighborCount = table.create(total, 0)
	self.Revealed = table.create(total, false)
	self.Flagged = table.create(total, false)
	self.FlaggedCount = 0
	self.RevealedCount = 0
	self.FirstClick = true
	self.Solved = false
	self.Failed = false
	self.Size = size
	self.TotalCells = total
	self.MineCount = math.max(1, math.floor(total * 0.18))
end

function Puzzle:_buildEmptyNDState(config, projection, origin)
	local size = math.max(2, math.floor(tonumber(config.Size) or 4))
	local dimensions = math.max(3, math.floor(tonumber(config.Dimensions) or 4))
	local total = NDimensionalBoard.TotalCells(size, dimensions)
	return {
		Key = tostring(config.OriginName or "NDimensional"),
		Origin = origin,
		Projection = projection,
		Size = size,
		Dimensions = dimensions,
		TotalCells = total,
		MineCount = math.max(1, math.floor(total * 0.18)),
		MineMap = table.create(total, false),
		NeighborCount = table.create(total, 0),
		Revealed = table.create(total, false),
		Flagged = table.create(total, false),
		FlaggedCount = 0,
		RevealedCount = 0,
		FirstClick = true,
		Solved = false,
		Failed = false,
	}
end

function Puzzle:_setNDHidden(state, index)
	local visual = state and state.Projection and state.Projection.GlobalToVisual[index]
	if not visual then
		return
	end
	visual.Board:SetData(visual.LocalIndex, 0)
	visual.Extension:SetHidden(visual.LocalIndex)
end

function Puzzle:_revealNDVisual(state, index, neighborCount, exploded)
	local visual = state and state.Projection and state.Projection.GlobalToVisual[index]
	if visual then
		visual.Extension:Reveal(visual.LocalIndex, neighborCount, exploded)
	end
end

function Puzzle:_showNDMine(state, index)
	local visual = state and state.Projection and state.Projection.GlobalToVisual[index]
	if visual then
		visual.Extension:ShowMine(visual.LocalIndex)
	end
end

function Puzzle:_setNDFlag(state, index, enabled, player)
	local visual = state and state.Projection and state.Projection.GlobalToVisual[index]
	if visual then
		visual.Extension:SetFlag(visual.LocalIndex, enabled, player)
	end
end

function Puzzle:_isMine(index)
	return self.MineMap[index] == true
end

function Puzzle:_placeMines(firstIndex)
	local blocked = {}
	blocked[firstIndex] = true
	for _, neighbor in ipairs(getNeighborIndexes(firstIndex, self.Size)) do
		blocked[neighbor] = true
	end

	local placed = 0
	for _, index in ipairs(shuffledIndexes(self.TotalCells)) do
		if placed >= self.MineCount then
			break
		end
		if not blocked[index] then
			self.MineMap[index] = true
			placed += 1
		end
	end

	if placed < self.MineCount then
		for _, index in ipairs(shuffledIndexes(self.TotalCells)) do
			if placed >= self.MineCount then
				break
			end
			if not self.MineMap[index] and index ~= firstIndex then
				self.MineMap[index] = true
				placed += 1
			end
		end
	end

	for index = 1, self.TotalCells do
		if self.MineMap[index] then
			self.NeighborCount[index] = -1
		else
			local count = 0
			for _, neighbor in ipairs(getNeighborIndexes(index, self.Size)) do
				if self.MineMap[neighbor] then
					count += 1
				end
			end
			self.NeighborCount[index] = count
		end
	end
end

function Puzzle:_placeNDMines(state, firstIndex)
	local blocked = {}
	blocked[firstIndex] = true
	for _, neighbor in ipairs(NDimensionalBoard.GetNeighborIndexes(firstIndex, state.Size, state.Dimensions)) do
		blocked[neighbor] = true
	end

	local placed = 0
	for _, index in ipairs(shuffledIndexes(state.TotalCells)) do
		if placed >= state.MineCount then
			break
		end
		if not blocked[index] then
			state.MineMap[index] = true
			placed += 1
		end
	end

	if placed < state.MineCount then
		for _, index in ipairs(shuffledIndexes(state.TotalCells)) do
			if placed >= state.MineCount then
				break
			end
			if not state.MineMap[index] and index ~= firstIndex then
				state.MineMap[index] = true
				placed += 1
			end
		end
	end

	for index = 1, state.TotalCells do
		if state.MineMap[index] then
			state.NeighborCount[index] = -1
		else
			local count = 0
			for _, neighbor in ipairs(NDimensionalBoard.GetNeighborIndexes(index, state.Size, state.Dimensions)) do
				if state.MineMap[neighbor] then
					count += 1
				end
			end
			state.NeighborCount[index] = count
		end
	end
end

function Puzzle:_revealCell(index, out)
	if self.Revealed[index] or self.Flagged[index] then
		return
	end
	if self.MineMap[index] then
		return
	end

	self.Revealed[index] = true
	self.RevealedCount += 1
	local count = self.NeighborCount[index]
	out[#out + 1] = {
		Index = index,
		NeighborCount = count,
		Exploded = false,
	}
	self.BoardExtension:Reveal(index, count, false)

	if count > 0 then
		return
	end

	for _, neighbor in ipairs(getNeighborIndexes(index, self.Size)) do
		if not self.Revealed[neighbor] and not self.Flagged[neighbor] and not self.MineMap[neighbor] then
			self:_revealCell(neighbor, out)
		end
	end
end

function Puzzle:_revealNDCell(state, index, out)
	if state.Revealed[index] or state.Flagged[index] then
		return
	end
	if state.MineMap[index] then
		return
	end

	state.Revealed[index] = true
	state.RevealedCount += 1
	local count = state.NeighborCount[index]
	out[#out + 1] = {
		Index = index,
		NeighborCount = count,
		Exploded = false,
		BoardGroupId = state.Projection.GroupId,
		Size = state.Size,
		Dimensions = state.Dimensions,
	}
	self:_revealNDVisual(state, index, count, false)

	if count > 0 then
		return
	end

	for _, neighbor in ipairs(NDimensionalBoard.GetNeighborIndexes(index, state.Size, state.Dimensions)) do
		if not state.Revealed[neighbor] and not state.Flagged[neighbor] and not state.MineMap[neighbor] then
			self:_revealNDCell(state, neighbor, out)
		end
	end
end

function Puzzle:_checkSolved()
	return self.RevealedCount >= (self.TotalCells - self.MineCount)
end

function Puzzle:_checkNDSolved(state)
	return state.RevealedCount >= (state.TotalCells - state.MineCount)
end

function Puzzle:_buildMineExplosionReveals(explodedIndex)
	local reveals = {
		{
			Index = explodedIndex,
			NeighborCount = -1,
			Exploded = true,
		},
	}

	self.BoardExtension:Reveal(explodedIndex, 0, true)
	for i = 1, self.TotalCells do
		if self.MineMap[i] and i ~= explodedIndex then
			self.BoardExtension:ShowMine(i)
			reveals[#reveals + 1] = {
				Index = i,
				NeighborCount = -1,
				Exploded = false,
			}
		end
	end

	return reveals
end

function Puzzle:_buildNDMineExplosionReveals(state, explodedIndex)
	local reveals = {
		{
			Index = explodedIndex,
			NeighborCount = -1,
			Exploded = true,
			BoardGroupId = state.Projection.GroupId,
			Size = state.Size,
			Dimensions = state.Dimensions,
		},
	}

	self:_revealNDVisual(state, explodedIndex, 0, true)
	for i = 1, state.TotalCells do
		if state.MineMap[i] and i ~= explodedIndex then
			self:_showNDMine(state, i)
			reveals[#reveals + 1] = {
				Index = i,
				NeighborCount = -1,
				Exploded = false,
				BoardGroupId = state.Projection.GroupId,
				Size = state.Size,
				Dimensions = state.Dimensions,
			}
		end
	end

	return reveals
end

function Puzzle:_handleChord(index)
	local expectedFlags = self.NeighborCount[index]
	if expectedFlags <= 0 then
		return false, "Cannot chord this cell"
	end

	local neighbors = getNeighborIndexes(index, self.Size)
	local flaggedCount = 0
	for _, neighbor in ipairs(neighbors) do
		if self.Flagged[neighbor] then
			flaggedCount += 1
		end
	end

	if flaggedCount ~= expectedFlags then
		return false, ("Need %d flags around this cell"):format(expectedFlags)
	end

	local targetNeighbors = {}
	for _, neighbor in ipairs(neighbors) do
		if not self.Flagged[neighbor] and not self.Revealed[neighbor] then
			targetNeighbors[#targetNeighbors + 1] = neighbor
		end
	end

	if #targetNeighbors == 0 then
		return false, "Nothing to reveal"
	end

	for _, neighbor in ipairs(targetNeighbors) do
		if self:_isMine(neighbor) then
			self.Failed = true
			local reveals = self:_buildMineExplosionReveals(neighbor)
			return true, self:_withStats({
				Index = index,
				Value = expectedFlags,
				Chord = true,
				Solved = false,
				Failed = true,
				Reveals = reveals,
				Message = "Boom",
			})
		end
	end

	local reveals = {}
	for _, neighbor in ipairs(targetNeighbors) do
		self:_revealCell(neighbor, reveals)
	end

	self.Solved = self:_checkSolved()
	if self.Solved then
		self:MarkCompletedVisual()
	end

	return true, self:_withStats({
		Index = index,
		Value = expectedFlags,
		Chord = true,
		Solved = self.Solved,
		Failed = false,
		Reveals = reveals,
	})
end

function Puzzle:_handleNDChord(state, index)
	local expectedFlags = state.NeighborCount[index]
	if expectedFlags <= 0 then
		return false, "Cannot chord this cell"
	end

	local neighbors = NDimensionalBoard.GetNeighborIndexes(index, state.Size, state.Dimensions)
	local flaggedCount = 0
	for _, neighbor in ipairs(neighbors) do
		if state.Flagged[neighbor] then
			flaggedCount += 1
		end
	end

	if flaggedCount ~= expectedFlags then
		return false, ("Need %d flags around this cell"):format(expectedFlags)
	end

	local targetNeighbors = {}
	for _, neighbor in ipairs(neighbors) do
		if not state.Flagged[neighbor] and not state.Revealed[neighbor] then
			targetNeighbors[#targetNeighbors + 1] = neighbor
		end
	end

	if #targetNeighbors == 0 then
		return false, "Nothing to reveal"
	end

	for _, neighbor in ipairs(targetNeighbors) do
		if state.MineMap[neighbor] then
			state.Failed = true
			local reveals = self:_buildNDMineExplosionReveals(state, neighbor)
			return true, {
				Index = index,
				Value = expectedFlags,
				Chord = true,
				Solved = false,
				Failed = true,
				Reveals = reveals,
				Message = "Boom",
				MineCount = state.MineCount,
				FlaggedCount = state.FlaggedCount,
				RevealedCount = state.RevealedCount,
				BoardGroupId = state.Projection.GroupId,
				Size = state.Size,
				Dimensions = state.Dimensions,
			}
		end
	end

	local reveals = {}
	for _, neighbor in ipairs(targetNeighbors) do
		self:_revealNDCell(state, neighbor, reveals)
	end

	state.Solved = self:_checkNDSolved(state)
	if state.Solved then
		NDimensionalBoard.SetCompletedVisual(state.Projection)
	end

	return true, {
		Index = index,
		Value = expectedFlags,
		Chord = true,
		Solved = state.Solved,
		Failed = false,
		Reveals = reveals,
		MineCount = state.MineCount,
		FlaggedCount = state.FlaggedCount,
		RevealedCount = state.RevealedCount,
		BoardGroupId = state.Projection.GroupId,
		Size = state.Size,
		Dimensions = state.Dimensions,
	}
end

function Puzzle:GetSnapshot()
	return {
		Size = self.Size,
		MineCount = self.MineCount,
		FlaggedCount = self.FlaggedCount,
		RevealedCount = self.RevealedCount,
		Solved = self.Solved,
		Failed = self.Failed,
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
			MineCount = state.MineCount,
			FlaggedCount = state.FlaggedCount,
			RevealedCount = state.RevealedCount,
			Solved = state.Solved,
			Failed = state.Failed,
		}
	end
	return snapshots
end

function Puzzle:_withStats(result)
	result.MineCount = self.MineCount
	result.FlaggedCount = self.FlaggedCount
	result.RevealedCount = self.RevealedCount
	return result
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
	if state.Failed then
		return false, "Round already failed"
	end

	local normalizedAction = string.lower(tostring(action or "reveal"))
	if normalizedAction == "flagtoggle" or normalizedAction == "flag" then
		if state.Revealed[index] then
			return false, "Cannot flag a revealed cell"
		end
		local nextFlagState = not state.Flagged[index]
		state.Flagged[index] = nextFlagState
		if nextFlagState then
			state.FlaggedCount += 1
		else
			state.FlaggedCount = math.max(0, state.FlaggedCount - 1)
		end
		self:_setNDFlag(state, index, nextFlagState, player)
		return true, {
			Index = index,
			Value = nextFlagState and 1 or 0,
			Flagged = nextFlagState,
			Solved = state.Solved,
			Failed = false,
			MineCount = state.MineCount,
			FlaggedCount = state.FlaggedCount,
			RevealedCount = state.RevealedCount,
			BoardGroupId = state.Projection.GroupId,
			Size = state.Size,
			Dimensions = state.Dimensions,
		}
	end

	if state.Revealed[index] then
		return self:_handleNDChord(state, index)
	end
	if state.Flagged[index] then
		return false, "Cell is flagged"
	end

	if state.FirstClick then
		self:_placeNDMines(state, index)
		state.FirstClick = false
	end

	if state.MineMap[index] then
		state.Failed = true
		local reveals = self:_buildNDMineExplosionReveals(state, index)
		return true, {
			Index = index,
			Value = -1,
			Solved = false,
			Failed = true,
			Reveals = reveals,
			Message = "Boom",
			MineCount = state.MineCount,
			FlaggedCount = state.FlaggedCount,
			RevealedCount = state.RevealedCount,
			BoardGroupId = state.Projection.GroupId,
			Size = state.Size,
			Dimensions = state.Dimensions,
		}
	end

	local reveals = {}
	self:_revealNDCell(state, index, reveals)
	state.Solved = self:_checkNDSolved(state)
	if state.Solved then
		NDimensionalBoard.SetCompletedVisual(state.Projection)
	end

	return true, {
		Index = index,
		Value = state.NeighborCount[index],
		Solved = state.Solved,
		Failed = false,
		Reveals = reveals,
		MineCount = state.MineCount,
		FlaggedCount = state.FlaggedCount,
		RevealedCount = state.RevealedCount,
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
	if self.Failed then
		return false, "Round already failed"
	end

	local index = self:ResolveCellIndex(target)
	if not index then
		return false, "Invalid board cell"
	end

	local normalizedAction = string.lower(tostring(action or "reveal"))
	if normalizedAction == "flagtoggle" or normalizedAction == "flag" then
		if self.Revealed[index] then
			return false, "Cannot flag a revealed cell"
		end
		local nextFlagState = not self.Flagged[index]
		self.Flagged[index] = nextFlagState
		if nextFlagState then
			self.FlaggedCount += 1
		else
			self.FlaggedCount = math.max(0, self.FlaggedCount - 1)
		end
		self.BoardExtension:SetFlag(index, nextFlagState, player)
		return true, self:_withStats({
			Index = index,
			Value = nextFlagState and 1 or 0,
			Flagged = nextFlagState,
			Solved = self.Solved,
			Failed = false,
		})
	end

	if self.Revealed[index] then
		return self:_handleChord(index)
	end
	if self.Flagged[index] then
		return false, "Cell is flagged"
	end

	if self.FirstClick then
		self:_placeMines(index)
		self.FirstClick = false
	end

	if self:_isMine(index) then
		self.Failed = true
		local reveals = self:_buildMineExplosionReveals(index)
		return true, self:_withStats({
			Index = index,
			Value = -1,
			Solved = false,
			Failed = true,
			Reveals = reveals,
			Message = "Boom",
		})
	end

	local reveals = {}
	self:_revealCell(index, reveals)
	self.Solved = self:_checkSolved()
	if self.Solved then
		self:MarkCompletedVisual()
	end

	return true, self:_withStats({
		Index = index,
		Value = self.NeighborCount[index],
		Solved = self.Solved,
		Failed = false,
		Reveals = reveals,
	})
end

function Puzzle:Init(size, options)
	if self.NDStates then
		for _, state in ipairs(self.NDStates) do
			NDimensionalBoard.Destroy(state.Projection)
		end
	end
	self.NDStates = {}

	if self.Board then
		self.Board:Destroy()
		self.Board = nil
	end

	options = type(options) == "table" and options or {}
	local parsed = math.floor(tonumber(size) or self.DefaultBoardSize)
	local clamped = math.clamp(parsed, self.MinBoardSize, self.MaxBoardSize)
	self:_buildEmptyState(clamped)

	local boardSettings = {
		origin = resolveBoardOrigin(),
		xDirection = Vector3.new(1, 0, 0),
		yDirection = Vector3.new(0, 0, 1),
		xSpan = clamped,
		ySpan = clamped,
		cellSize = 4,
		baseColor = Color3.fromRGB(228, 234, 241),
		fillColor = Color3.fromRGB(146, 162, 178),
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
	self.BoardExtension = self.Board:UseExtension("Minesweeper")
	for index = 1, self.TotalCells do
		self.Board:SetData(index, 0)
		self.BoardExtension:SetHidden(index)
	end

	for _, config in ipairs(EXTRA_ND_BOARD_CONFIGS) do
		local ndSize = math.max(2, math.floor(tonumber(config.Size) or 4))
		local dimensions = math.max(3, math.floor(tonumber(config.Dimensions) or 4))
		local requestedOrigin = resolveSpecificBoardOrigin(config.OriginName)
		local ndOrigin = requestedOrigin or offsetOrigin(boardSettings.origin, (clamped + ndSize + 8) * boardSettings.cellSize)
		local ndSettings = {
			origin = ndOrigin,
			xDirection = Vector3.new(1, 0, 0),
			yDirection = Vector3.new(0, 0, 1),
			cellSize = 3,
			baseColor = Color3.fromRGB(228, 234, 241),
			fillColor = Color3.fromRGB(146, 162, 178),
			displayAlwaysOnTop = false,
		}

		local projection = NDimensionalBoard.Construct({
			BoardClass = BoardClass,
			ModeKey = self.ModeKey,
			HoverKind = "minesweeper",
			GroupId = ("%s_%s_%dd"):format(self.ModeKey, tostring(config.OriginName or "origin"), dimensions),
			Size = ndSize,
			Dimensions = dimensions,
			BoardSettings = ndSettings,
			ExtensionName = "Minesweeper",
			SliceGapCells = 2,
		})
		local state = self:_buildEmptyNDState(config, projection, ndOrigin)
		self.NDStates[#self.NDStates + 1] = state
		for index = 1, state.TotalCells do
			self:_setNDHidden(state, index)
		end
	end
end

return Puzzle
