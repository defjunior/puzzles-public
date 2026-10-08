-- Narrow showcase: constraint validation/search and bounded puzzle generation.
-- Original implementation retained. Dependencies/runtime validation are documented in README.
local Hitori = {}

local UNKNOWN = -1
local BLACK = 1
local WHITE = 0

local function copy2D(source)
	local out = table.create(#source)
	for r = 1, #source do
		local row = source[r]
		local clone = table.create(#row)
		for c = 1, #row do
			clone[c] = row[c]
		end
		out[r] = clone
	end
	return out
end

local function inBounds(r, c, size)
	return r >= 1 and c >= 1 and r <= size and c <= size
end

local function hasAdjacentBlack(mask, r, c, size)
	return (
		(inBounds(r - 1, c, size) and mask[r - 1][c] == BLACK)
		or (inBounds(r + 1, c, size) and mask[r + 1][c] == BLACK)
		or (inBounds(r, c - 1, size) and mask[r][c - 1] == BLACK)
		or (inBounds(r, c + 1, size) and mask[r][c + 1] == BLACK)
	)
end

local function areWhitesConnected(mask)
	local size = #mask
	local totalWhites = 0
	local startR, startC

	for r = 1, size do
		for c = 1, size do
			if mask[r][c] == WHITE then
				totalWhites += 1
				if not startR then
					startR = r
					startC = c
				end
			end
		end
	end

	if totalWhites == 0 then
		return false
	end

	local visited = table.create(size)
	for r = 1, size do
		visited[r] = table.create(size, false)
	end

	local queue = { { startR, startC } }
	visited[startR][startC] = true
	local queueIndex = 1
	local reached = 1

	while queueIndex <= #queue do
		local cell = queue[queueIndex]
		queueIndex += 1
		local r, c = cell[1], cell[2]

		local neighbors = {
			{ r - 1, c },
			{ r + 1, c },
			{ r, c - 1 },
			{ r, c + 1 },
		}

		for _, neighbor in ipairs(neighbors) do
			local nr, nc = neighbor[1], neighbor[2]
			if inBounds(nr, nc, size) and not visited[nr][nc] and mask[nr][nc] == WHITE then
				visited[nr][nc] = true
				reached += 1
				queue[#queue + 1] = { nr, nc }
			end
		end
	end

	return reached == totalWhites
end

local function validateMask(grid, mask)
	local size = #grid

	for r = 1, size do
		for c = 1, size do
			if mask[r][c] == BLACK and hasAdjacentBlack(mask, r, c, size) then
				return false, "adjacent blacks"
			end
		end
	end

	for r = 1, size do
		local seen = {}
		for c = 1, size do
			if mask[r][c] == WHITE then
				local value = grid[r][c]
				if seen[value] then
					return false, ("row duplicate at row %d"):format(r)
				end
				seen[value] = true
			end
		end
	end

	for c = 1, size do
		local seen = {}
		for r = 1, size do
			if mask[r][c] == WHITE then
				local value = grid[r][c]
				if seen[value] then
					return false, ("col duplicate at col %d"):format(c)
				end
				seen[value] = true
			end
		end
	end

	if not areWhitesConnected(mask) then
		return false, "whites disconnected"
	end

	return true, "ok"
end

local function shuffledRange(size)
	local values = table.create(size)
	for i = 1, size do
		values[i] = i
	end
	for i = size, 2, -1 do
		local j = math.random(i)
		values[i], values[j] = values[j], values[i]
	end
	return values
end

local function buildLatinBase(size)
	local rowOrder = shuffledRange(size)
	local colOrder = shuffledRange(size)
	local symbolOrder = shuffledRange(size)

	local grid = table.create(size)
	for r = 1, size do
		local row = table.create(size)
		for c = 1, size do
			local baseValue = ((rowOrder[r] + colOrder[c] - 2) % size) + 1
			row[c] = symbolOrder[baseValue]
		end
		grid[r] = row
	end
	return grid
end

local function buildLabelSet(size, valueMin, valueMax)
	local minValue = math.floor(tonumber(valueMin) or 1)
	local maxValue = math.floor(tonumber(valueMax) or size)
	if maxValue < minValue then
		maxValue = minValue
	end

	if (maxValue - minValue + 1) < size then
		maxValue = minValue + size - 1
	end

	local pool = {}
	for value = minValue, maxValue do
		pool[#pool + 1] = value
	end

	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local labels = table.create(size)
	for i = 1, size do
		labels[i] = pool[i]
	end
	return labels
end

local function buildSolutionMask(size, targetBlackCount)
	local mask = table.create(size)
	for r = 1, size do
		mask[r] = table.create(size, WHITE)
	end

	local cells = table.create(size * size)
	for r = 1, size do
		for c = 1, size do
			cells[#cells + 1] = { r, c }
		end
	end
	for i = #cells, 2, -1 do
		local j = math.random(i)
		cells[i], cells[j] = cells[j], cells[i]
	end

	local blackCount = 0
	for _, cell in ipairs(cells) do
		if blackCount >= targetBlackCount then
			break
		end

		local r, c = cell[1], cell[2]
		if not hasAdjacentBlack(mask, r, c, size) then
			mask[r][c] = BLACK
			if areWhitesConnected(mask) then
				blackCount += 1
			else
				mask[r][c] = WHITE
			end
		end
	end

	return mask, blackCount
end

local function collectWhiteValuesInRow(baseGrid, mask, row)
	local values = {}
	for c = 1, #baseGrid[row] do
		if mask[row][c] == WHITE then
			values[#values + 1] = baseGrid[row][c]
		end
	end
	return values
end

local function collectWhiteValuesInCol(baseGrid, mask, col)
	local values = {}
	for r = 1, #baseGrid do
		if mask[r][col] == WHITE then
			values[#values + 1] = baseGrid[r][col]
		end
	end
	return values
end

local function buildPuzzleGrid(baseGrid, mask, labels)
	local size = #baseGrid
	local grid = copy2D(baseGrid)

	local blackCells = {}
	for r = 1, size do
		for c = 1, size do
			if mask[r][c] == BLACK then
				blackCells[#blackCells + 1] = { r, c }
			end
		end
	end
	for i = #blackCells, 2, -1 do
		local j = math.random(i)
		blackCells[i], blackCells[j] = blackCells[j], blackCells[i]
	end

	for _, cell in ipairs(blackCells) do
		local r, c = cell[1], cell[2]
		local currentValue = baseGrid[r][c]
		local bestValue = nil
		local bestScore = -math.huge

		for _, candidateValue in ipairs(labels) do
			if candidateValue ~= currentValue then
				local rowAnchor = false
				local colAnchor = false
				local rowConflicts = 0
				local colConflicts = 0

				for cc = 1, size do
					if cc ~= c then
						if mask[r][cc] == WHITE and baseGrid[r][cc] == candidateValue then
							rowAnchor = true
						end
						if mask[r][cc] == BLACK and grid[r][cc] == candidateValue then
							rowConflicts += 1
						end
					end
				end
				for rr = 1, size do
					if rr ~= r then
						if mask[rr][c] == WHITE and baseGrid[rr][c] == candidateValue then
							colAnchor = true
						end
						if mask[rr][c] == BLACK and grid[rr][c] == candidateValue then
							colConflicts += 1
						end
					end
				end

				if rowAnchor or colAnchor then
					local score = 0
					if rowAnchor then
						score += 3
					end
					if colAnchor then
						score += 3
					end
					score -= (rowConflicts + colConflicts)
					score += math.random() * 0.5
					if score > bestScore then
						bestScore = score
						bestValue = candidateValue
					end
				end
			end
		end

		if not bestValue then
			local fallbackValues = {}
			local seen = {}
			for _, value in ipairs(collectWhiteValuesInRow(baseGrid, mask, r)) do
				if value ~= currentValue and not seen[value] then
					seen[value] = true
					fallbackValues[#fallbackValues + 1] = value
				end
			end
			for _, value in ipairs(collectWhiteValuesInCol(baseGrid, mask, c)) do
				if value ~= currentValue and not seen[value] then
					seen[value] = true
					fallbackValues[#fallbackValues + 1] = value
				end
			end

			if #fallbackValues > 0 then
				bestValue = fallbackValues[math.random(#fallbackValues)]
			else
				bestValue = labels[math.random(#labels)]
				if #labels > 1 then
					while bestValue == currentValue do
						bestValue = labels[math.random(#labels)]
					end
				end
			end
		end

		grid[r][c] = bestValue
	end

	return grid
end

local function getDuplicateCells(grid)
	local size = #grid
	local duplicate = table.create(size)
	for r = 1, size do
		duplicate[r] = table.create(size, false)
	end

	for r = 1, size do
		local rowFreq = {}
		for c = 1, size do
			local value = grid[r][c]
			rowFreq[value] = (rowFreq[value] or 0) + 1
		end
		for c = 1, size do
			if rowFreq[grid[r][c]] > 1 then
				duplicate[r][c] = true
			end
		end
	end

	for c = 1, size do
		local colFreq = {}
		for r = 1, size do
			local value = grid[r][c]
			colFreq[value] = (colFreq[value] or 0) + 1
		end
		for r = 1, size do
			if colFreq[grid[r][c]] > 1 then
				duplicate[r][c] = true
			end
		end
	end

	return duplicate
end

local function copyMask(mask)
	local out = table.create(#mask)
	for r = 1, #mask do
		local row = mask[r]
		local clone = table.create(#row)
		for c = 1, #row do
			clone[c] = row[c]
		end
		out[r] = clone
	end
	return out
end

local function countSolutions(grid, maxSolutions, deadline)
	local size = #grid
	local duplicate = getDuplicateCells(grid)

	local state = table.create(size)
	local whiteRow = table.create(size)
	local whiteCol = table.create(size)
	local candidates = {}

	for r = 1, size do
		state[r] = table.create(size)
		whiteRow[r] = {}
	end
	for c = 1, size do
		whiteCol[c] = {}
	end

	for r = 1, size do
		for c = 1, size do
			local value = grid[r][c]
			if duplicate[r][c] then
				state[r][c] = UNKNOWN
				candidates[#candidates + 1] = { r = r, c = c, value = value }
			else
				state[r][c] = WHITE
				whiteRow[r][value] = true
				whiteCol[c][value] = true
			end
		end
	end

	local solutionCount = 0
	local firstSolution = nil
	local timedOut = false

	local function canBeWhite(cell)
		local r = cell.r
		local c = cell.c
		local value = cell.value
		return not whiteRow[r][value] and not whiteCol[c][value]
	end

	local function canBeBlack(cell)
		return not hasAdjacentBlack(state, cell.r, cell.c, size)
	end

	local function setWhite(cell)
		local r = cell.r
		local c = cell.c
		local value = cell.value
		state[r][c] = WHITE
		whiteRow[r][value] = true
		whiteCol[c][value] = true
	end

	local function unsetWhite(cell)
		local r = cell.r
		local c = cell.c
		local value = cell.value
		state[r][c] = UNKNOWN
		whiteRow[r][value] = nil
		whiteCol[c][value] = nil
	end

	local function setBlack(cell)
		state[cell.r][cell.c] = BLACK
	end

	local function unsetBlack(cell)
		state[cell.r][cell.c] = UNKNOWN
	end

	local function whitesConnectedThroughOpenCells()
		local startR, startC
		local openCount = 0
		local whiteCount = 0

		for r = 1, size do
			for c = 1, size do
				if state[r][c] ~= BLACK then
					openCount += 1
				end
				if state[r][c] == WHITE then
					whiteCount += 1
					if not startR then
						startR = r
						startC = c
					end
				end
			end
		end

		if openCount == 0 then
			return false
		end
		if whiteCount <= 1 then
			return true
		end

		local visited = table.create(size)
		for r = 1, size do
			visited[r] = table.create(size, false)
		end
		local queue = { { startR, startC } }
		visited[startR][startC] = true
		local queueIndex = 1

		while queueIndex <= #queue do
			local cell = queue[queueIndex]
			queueIndex += 1
			local r, c = cell[1], cell[2]
			local neighbors = {
				{ r - 1, c },
				{ r + 1, c },
				{ r, c - 1 },
				{ r, c + 1 },
			}
			for _, neighbor in ipairs(neighbors) do
				local nr, nc = neighbor[1], neighbor[2]
				if inBounds(nr, nc, size) and not visited[nr][nc] and state[nr][nc] ~= BLACK then
					visited[nr][nc] = true
					queue[#queue + 1] = { nr, nc }
				end
			end
		end

		for r = 1, size do
			for c = 1, size do
				if state[r][c] == WHITE and not visited[r][c] then
					return false
				end
			end
		end

		return true
	end

	local function chooseNextCell()
		local bestCell = nil
		local bestOptionCount = 3
		local bestTieBreak = -math.huge

		for _, cell in ipairs(candidates) do
			if state[cell.r][cell.c] == UNKNOWN then
				local allowWhite = canBeWhite(cell)
				local allowBlack = canBeBlack(cell)
				local options = (allowWhite and 1 or 0) + (allowBlack and 1 or 0)
				if options == 0 then
					return cell, false, false, true
				end

				local tieBreak = 0
				local r, c, value = cell.r, cell.c, cell.value
				for cc = 1, size do
					if cc ~= c and grid[r][cc] == value then
						tieBreak += 1
					end
				end
				for rr = 1, size do
					if rr ~= r and grid[rr][c] == value then
						tieBreak += 1
					end
				end

				if options < bestOptionCount or (options == bestOptionCount and tieBreak > bestTieBreak) then
					bestOptionCount = options
					bestTieBreak = tieBreak
					bestCell = cell
				end
			end
		end

		if not bestCell then
			return nil, false, false, false
		end
		return bestCell, canBeWhite(bestCell), canBeBlack(bestCell), false
	end

	local function search()
		if timedOut or solutionCount >= maxSolutions then
			return
		end
		if deadline and os.clock() > deadline then
			timedOut = true
			return
		end

		local cell, allowWhite, allowBlack, contradiction = chooseNextCell()
		if contradiction then
			return
		end

		if not cell then
			local finalMask = copyMask(state)
			local ok = validateMask(grid, finalMask)
			if ok then
				solutionCount += 1
				if solutionCount == 1 then
					firstSolution = finalMask
				end
			end
			return
		end

		if allowWhite then
			setWhite(cell)
			if whitesConnectedThroughOpenCells() then
				search()
			end
			unsetWhite(cell)
		end

		if not timedOut and solutionCount < maxSolutions and allowBlack then
			setBlack(cell)
			if whitesConnectedThroughOpenCells() then
				search()
			end
			unsetBlack(cell)
		end
	end

	search()
	return solutionCount, firstSolution, timedOut
end

local function scoreGrid(grid, mask)
	local size = #grid
	local blackCount = 0
	local rowCoverage = 0
	local colCoverage = 0
	local duplicateCells = 0

	for r = 1, size do
		local hasBlack = false
		for c = 1, size do
			if mask[r][c] == BLACK then
				blackCount += 1
				hasBlack = true
			end
		end
		if hasBlack then
			rowCoverage += 1
		end
	end

	for c = 1, size do
		local hasBlack = false
		for r = 1, size do
			if mask[r][c] == BLACK then
				hasBlack = true
				break
			end
		end
		if hasBlack then
			colCoverage += 1
		end
	end

	local duplicate = getDuplicateCells(grid)
	for r = 1, size do
		for c = 1, size do
			if duplicate[r][c] then
				duplicateCells += 1
			end
		end
	end

	return blackCount * 5 + rowCoverage * 3 + colCoverage * 3 + duplicateCells
end

function Hitori:Generate(size, opts)
	opts = opts or {}
	if opts.seed ~= nil then
		math.randomseed(opts.seed)
	end

	local attempts = math.max(tonumber(opts.attempts) or 200, 1)
	local totalTime = math.max(tonumber(opts.timeLimit) or 2.5, 0.25)
	local requireUnique = opts.unique ~= false
	local blackRatio = math.clamp(tonumber(opts.blackRatio) or 0.23, 0.12, 0.35)
	local valueMin = math.floor(tonumber(opts.valueMin) or 1)
	local valueRange = math.floor(tonumber(opts.valueRange) or math.max(size * 3, 18))
	local valueMax = math.max(valueMin, valueRange)
	local deadline = os.clock() + totalTime

	local minBlack = math.max(2, math.floor(size * 0.5))
	local targetBlack = math.clamp(math.floor(size * size * blackRatio + 0.5), minBlack, math.floor(size * size * 0.35))

	local bestGrid, bestMask
	local bestScore = -math.huge

	for _ = 1, attempts do
		if os.clock() > deadline then
			break
		end

		local labels = buildLabelSet(size, valueMin, valueMax)
		local baseGrid = buildLatinBase(size)
		for r = 1, size do
			for c = 1, size do
				local symbol = baseGrid[r][c]
				baseGrid[r][c] = labels[symbol]
			end
		end
		local mask, blackCount = buildSolutionMask(size, targetBlack)
		if blackCount < minBlack then
			continue
		end

		local grid = buildPuzzleGrid(baseGrid, mask, labels)
		local valid = validateMask(grid, mask)
		if not valid then
			continue
		end

		local score = scoreGrid(grid, mask)

		if requireUnique then
			local remaining = deadline - os.clock()
			if remaining <= 0 then
				break
			end
			local solveDeadline = os.clock() + math.max(0.02, math.min(0.35, remaining * 0.4))
			local solutionCount, _, timedOut = countSolutions(grid, 2, solveDeadline)
			if not timedOut and solutionCount == 1 then
				return grid, mask
			end

			if timedOut then
				score -= 60
			else
				score -= (solutionCount - 1) * 120
			end
		else
			return grid, mask
		end

		if score > bestScore then
			bestScore = score
			bestGrid = grid
			bestMask = mask
		end
	end

	if bestGrid and bestMask then
		return bestGrid, bestMask
	end

	return nil, nil
end

function Hitori:PrettyPrintGrid(grid)
	if not grid then
		print("nil grid")
		return
	end
	for r = 1, #grid do
		local row = {}
		for c = 1, #grid[1] do
			row[#row + 1] = tostring(grid[r][c])
		end
		print(table.concat(row, " "))
	end
end

function Hitori:PrettyPrintMask(mask)
	if not mask then
		print("nil mask")
		return
	end
	for r = 1, #mask do
		local row = {}
		for c = 1, #mask[1] do
			row[#row + 1] = tostring(mask[r][c])
		end
		print(table.concat(row, " "))
	end
end

function Hitori:ValidateMask(grid, mask)
	return validateMask(grid, mask)
end

function Hitori:ValidateFlatMask(grid, flatMask, n)
	if type(flatMask) ~= "table" or #flatMask ~= n * n then
		return false, "invalid mask size"
	end

	local mask = table.create(n)
	local index = 0
	for r = 1, n do
		mask[r] = table.create(n)
		for c = 1, n do
			index += 1
			mask[r][c] = flatMask[index]
		end
	end

	return validateMask(grid, mask)
end

return Hitori
