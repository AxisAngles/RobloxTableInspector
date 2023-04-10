-- local tableInspector = TableInspector.new()
-- set tableInspector.backFrame.Parent to something in the playerGui or starterGui (such as a ScreenGui)

-- local tableRoot = tableInspector:addTable(name, tab) to make a new tableRoot which looks at tab
-- local anotherTableRoot = tableInspector:addPath(name, {tab, 1, "t"}) to make a new tableRoot which looks at tab[1].t

-- LMB on the background to drag everything
-- LMB on a table to drag just the table
-- MMB on a table to delete the table
-- Doubleclick LMB on a table to expand/collapse
-- Shift + LMB on any value to drag out the path
-- Ctrl + LMB on a table to drag out the table

-- settings for customizing the look of the table inspector
local textPad = Vector2.new(2, 2) -- radius
local entryPad = Vector2.new(1, 1)
local tableBorder = 1
local linePad = 1

local fontSize = 14
local font = Enum.Font.Code

local separatorSize = Vector2.new(10, 10)

-- before padding
local maxClosedSize = Vector2.new(7*14, 14*2)
local maxOpenedSize = Vector2.new(7*48, 14*8)
local maxOpenedTableSize = Vector2.new(1/0, 1/0)


local boolColor3 = Color3.fromRGB(248, 109, 124)
local numberColor3 = Color3.fromRGB(255, 198, 0)
local stringColor3 = Color3.fromRGB(173, 241, 149)
local functionColor3 = Color3.fromRGB(119, 255, 255)

local backgroundColor3 = Color3.fromRGB(48, 48, 48)
local operatorColor3 = Color3.fromRGB(204, 204, 204)

local highlightColor3 = Color3.fromRGB(255, 183, 0)

local doubleClickPeriod = 1/4







local TableInspector = {}
TableInspector.__index = TableInspector

local TableRoot = {}
TableRoot.__index = TableRoot

local Element = {}
Element.__index = Element

local Entry = {}
Entry.__index = Entry

local TextService = game:GetService("TextService")


local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")

local function toVector2(vector)
	return Vector2.new(vector.x, vector.y)
end

local function getMousePosition()
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

function TableInspector.new()
	local self = setmetatable({}, TableInspector)

	self._logScale = 0

	self._tableRoots = {}

	self.backFrame = Instance.new("Frame")
	self.backFrame.BackgroundTransparency = 1 
	self.backFrame.Size = UDim2.fromOffset(600, 400) -- just initialize with something small
	self.backFrame.ClipsDescendants = true

	self.basisFrame = Instance.new("Frame")
	--self.basisFrame.Size = UDim2.fromOffset(100, 100)
	self.basisFrame.Size = UDim2.fromOffset(100, 100) -- doesn't matter so much. 1 is as good a number as any other
	self.basisFrame.Transparency = 1
	self.basisFrame.Parent = self.backFrame

	self.basisScale = Instance.new("UIScale")
	self.basisScale.Parent = self.basisFrame

	self._activeElements = setmetatable({}, {__mode = "k"})
	self:registerFrame(self.backFrame, self)

	self._connections = {}
	self._hoveringFrames = {}

	self._connections[1] = game:GetService("RunService").RenderStepped:Connect(function()
		local mousePosition = getMousePosition()
		self._hoveringFrames = playerGui:getGuiObjectsAtPosition(mousePosition.x, mousePosition.y)

		-- highlight effect
		self.highlightedValue = nil
		for i, frame in self._hoveringFrames do
			local object = self._activeElements[frame]
			if object and object.getValue then
				local value = object:getValue()
				if type(value) == "table" then
					self.highlightedValue = value
					break
				end
			end
		end

		for tableRoot in self._tableRoots do
			tableRoot:update()
		end
	end)

	self._connections[2] = UserInputService.InputBegan:Connect(function(inputObject, inputProcessed)
		if inputProcessed then return end
		if game:GetService("UserInputService").MouseBehavior == Enum.MouseBehavior.LockCenter then
			return
		end

		for i, frame in self._hoveringFrames do
			local object = self._activeElements[frame]
			if object and object.inputBegan then
				local stopInput = object:inputBegan(inputObject, frame)
				if stopInput then return end
			end
		end
	end)

	self._connections[3] = UserInputService.InputChanged:Connect(function(inputObject, inputProcessed)
		if inputProcessed then return end
		if game:GetService("UserInputService").MouseBehavior == Enum.MouseBehavior.LockCenter then
			return
		end

		for i, frame in self._hoveringFrames do
			local object = self._activeElements[frame]
			if object and object.inputChanged then
				local stopInput = object:inputChanged(inputObject, frame)
				if stopInput then return end
			end
		end
	end)

	self._connections[4] = UserInputService.InputEnded:Connect(function(inputObject, inputProcessed)
		--if inputProcessed then return end

		for i, frame in self._hoveringFrames do
			local object = self._activeElements[frame]
			if object and object.inputEnded then
				local stopInput = object:inputEnded(inputObject, frame)
				if stopInput then return end
			end
		end
	end)


	self.highlightedValue = nil

	return self
end

function TableInspector:destroy()
	for i, connection in self._connections do
		connection:Disconnect()
	end
end

--function TableInspector:registerHighlight(value, element)
--	if not self._highlightableElements[value] then
--		self._highlightableElements[value] = {}
--	end

--	self._highlightableElements[value][element] = true
--end

--function TableInspector:unregisterHighlight(value, element)
--	self._highlightableElements[value][element] = nil

--	if not next(self._highlightableElements[value]) then
--		self._highlightableElements[value] = nil
--	end
--end

function TableInspector:addPath(name, path, optionalElement)
	local tableRoot = TableRoot.new(self, `...{name}`, path, optionalElement)
	tableRoot.backFrame.Parent = self.basisFrame
	self._tableRoots[tableRoot] = true
	return tableRoot
end

function TableInspector:addTable(name, tab, optionalElement)
	local tableRoot = TableRoot.new(self, name, {tab}, optionalElement)
	tableRoot.backFrame.Parent = self.basisFrame
	self._tableRoots[tableRoot] = true
	return tableRoot
end

function TableInspector:registerFrame(frame, object)
	self._activeElements[frame] = object
end

function TableInspector:inputChanged(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseWheel then
		local mousePosition = getMousePosition()
		local basisPosition = self.basisFrame.AbsolutePosition
		local newLogScale = math.clamp(self._logScale + inputObject.Position.z, -4, 4)
		local logScaleDelta = newLogScale - self._logScale
		self._logScale = newLogScale

		local scaleFactor = 2^(logScaleDelta/2)
		basisPosition = scaleFactor*(basisPosition - mousePosition) + mousePosition

		-- doesn't work if rotated. So don't rotate it
		local basisRelative = (basisPosition - self.backFrame.AbsolutePosition)/self.backFrame.AbsoluteSize

		self.basisScale.Scale = 2^(self._logScale/2)
		self.basisFrame.Position = UDim2.fromScale(basisRelative.x, basisRelative.y)

		return true
	end
end

function TableInspector:inputBegan(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		self:drag(Enum.UserInputType.MouseButton1)
		return true
	end
end

-- drag routine
function TableInspector:drag(exitInputType)
	local mousePosition = getMousePosition()
	local mouseOffsetScale = (mousePosition - self.basisFrame.AbsolutePosition)/self.basisFrame.AbsoluteSize
	if self._dragging then
		self._dragging = false
		self._dragConnection1:Disconnect()
		self._dragConnection2:Disconnect()
	end

	self._dragging = true

	self._dragConnection1 = game:GetService("RunService").RenderStepped:Connect(function()
		local newPosition = getMousePosition() - mouseOffsetScale*self.basisFrame.AbsoluteSize
		local newScalePosition = (newPosition - self.basisFrame.Parent.AbsolutePosition)/self.basisFrame.Parent.AbsoluteSize
		self.basisFrame.Position = UDim2.fromScale(newScalePosition.x, newScalePosition.y)
	end)

	self._dragConnection2 = game:GetService("UserInputService").InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType ~= exitInputType then return end

		local newPosition = getMousePosition() - mouseOffsetScale*self.basisFrame.AbsoluteSize
		local newScalePosition = (newPosition - self.basisFrame.Parent.AbsolutePosition)/self.basisFrame.Parent.AbsoluteSize
		self.basisFrame.Position = UDim2.fromScale(newScalePosition.x, newScalePosition.y)

		self._dragging = false
		self._dragConnection1:Disconnect()
		self._dragConnection2:Disconnect()
	end)
end
























function TableRoot.new(tableInspector, name, path, element)
	local self = setmetatable({}, TableRoot)

	self._tableInspector = tableInspector
	self._name = name

	local dataSize = TextService:GetTextSize(name, fontSize, font, Vector2.zero)
	-- just a basis
	self.backFrame = Instance.new("Frame")
	self.backFrame.Size = UDim2.fromOffset(100, 100)
	self.backFrame.Transparency = 1

	self.dragFrame = Instance.new("Frame")
	self.dragFrame.Transparency = 1
	--self.dragFrame.ZIndex = -1
	self.dragFrame.Parent = self.backFrame

	self.nameFrame = Instance.new("TextLabel")
	self.nameFrame.AnchorPoint = Vector2.new(0, 1)
	self.nameFrame.Size = UDim2.fromOffset(dataSize.x + 4, dataSize.y + 4)
	self.nameFrame.Position = UDim2.fromOffset(0, -1)
	self.nameFrame.TextSize = fontSize
	self.nameFrame.BorderSizePixel = 0
	self.nameFrame.TextColor3 = operatorColor3
	self.nameFrame.BackgroundColor3 = backgroundColor3
	self.nameFrame.Font = Enum.Font.Code
	self.nameFrame.Text = name
	self.nameFrame.Parent = self.backFrame

	self._path = path

	if element then
		local pos = element.backFrame.AbsolutePosition
		local basisFrame = tableInspector.basisFrame
		local relScale = (pos - basisFrame.AbsolutePosition)/basisFrame.AbsoluteSize
		self.backFrame.Position = UDim2.fromScale(relScale.x, relScale.y)
	end

	self._rootElement = element or Element.new(self._tableInspector, self, nil)
	self._rootElement.parent = self
	self._rootElement.backFrame.Position = UDim2.fromOffset(0, 0)
	self._rootElement.backFrame.Parent = self.backFrame

	self._tableInspector:registerFrame(self.dragFrame, self)
	self._tableInspector:registerFrame(self.nameFrame, self)

	self._dragging = false
	self._dragConnection1 = nil
	self._dragConnection2 = nil

	return self
end

function TableRoot:destroy()
	self._rootElement:destroy()
	self.backFrame:Destroy()
	self._tableInspector._tableRoots[self] = nil -- BAD
end

function TableRoot:getIndex()
	return self._name
end

function TableRoot:getPath()
	-- this is ridiculous lol
	local n = #self._path
	local copy = table.create(n)
	table.move(self._path, 1, n, 1, copy)
	return copy
end

function TableRoot:getValue()
	local path = self._path
	local cur = path[1]
	for i = 2, #path do
		local index = path[i]
		if type(cur) ~= "table" then
			return nil
		end
		cur = cur[index]
	end

	return cur
end

function TableRoot:update()
	self._rootElement:setValue(self:getValue())
	local size = self._rootElement:update()
	self.dragFrame.Size = UDim2.fromOffset(size.x, size.y)
end

function TableRoot:inputBegan(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		self:drag(Enum.UserInputType.MouseButton1)
		return true
	elseif inputObject.UserInputType == Enum.UserInputType.MouseButton3 then
		self:destroy()
		return true
	end
end

-- drag routine
function TableRoot:drag(exitInputType)
	local mousePosition = getMousePosition()
	local mouseOffsetScale = (mousePosition - self.backFrame.AbsolutePosition)/self.backFrame.AbsoluteSize
	if self._dragging then
		self._dragging = false
		self._dragConnection1:Disconnect()
		self._dragConnection2:Disconnect()
	end

	self._dragging = true

	self._dragConnection1 = game:GetService("RunService").RenderStepped:Connect(function()
		local newPosition = getMousePosition() - mouseOffsetScale*self.backFrame.AbsoluteSize
		local newScalePosition = (newPosition - self.backFrame.Parent.AbsolutePosition)/self.backFrame.Parent.AbsoluteSize
		self.backFrame.Position = UDim2.fromScale(newScalePosition.x, newScalePosition.y)
	end)

	self._dragConnection2 = game:GetService("UserInputService").InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType ~= exitInputType then return end

		local newPosition = getMousePosition() - mouseOffsetScale*self.backFrame.AbsoluteSize
		local newScalePosition = (newPosition - self.backFrame.Parent.AbsolutePosition)/self.backFrame.Parent.AbsoluteSize
		self.backFrame.Position = UDim2.fromScale(newScalePosition.x, newScalePosition.y)

		self._dragging = false
		self._dragConnection1:Disconnect()
		self._dragConnection2:Disconnect()
	end)
end





















function Element.new(tableInspector, parent, value)
	local self = setmetatable({}, Element)
	self._tableInspector = tableInspector

	self._value = value
	self._isExpanded = false
	self._scrollingEnabled = false

	self._upToDate = false

	self.parent = parent
	self.backFrame = Instance.new("Frame")
	self.backFrame.BackgroundColor3 = backgroundColor3
	self.backFrame.BorderColor3 = operatorColor3
	self.backFrame.BorderSizePixel = 0
	self.backFrame.BorderMode = Enum.BorderMode.Inset

	self.clipFrame = Instance.new("Frame")
	self.clipFrame.BackgroundTransparency = 1
	self.clipFrame.ClipsDescendants = true
	self.clipFrame.Position = UDim2.fromScale(1/2, 1/2)
	self.clipFrame.AnchorPoint = Vector2.new(1/2, 1/2)
	self.clipFrame.Parent = self.backFrame

	self.dataFrame = Instance.new("TextLabel") -- base object
	self.dataFrame.BackgroundColor3 = backgroundColor3
	self.dataFrame.TextXAlignment = Enum.TextXAlignment.Left
	self.dataFrame.TextYAlignment = Enum.TextYAlignment.Top
	self.dataFrame.BorderSizePixel = 0
	-- self.dataFrame.TextWrapped = true
	self.dataFrame.TextSize = fontSize
	self.dataFrame.Font = font
	self.dataFrame.Text = ""
	self.dataFrame.Parent = self.clipFrame

	self._size = Vector2.zero
	self._entries = {}

	self._tableInspector:registerFrame(self.backFrame, self)
	self._lastExpansionAttempt = -1/0
	self._lastExpansionAttemptPosition = Vector2.zero

	return self
end

function Element:destroy()
	self.backFrame:Destroy()
end

function Element:inputEnded(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local controlPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shiftPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

	if controlPressed and shiftPressed then
	elseif controlPressed then -- pulls out the literal table
	elseif shiftPressed then -- pulls out the pathway
	else
		local t = os.clock()
		self._lastExpansionAttempt = t
		self._lastExpansionAttemptPosition = getMousePosition()
	end
end

function Element:getPath()
	if not self.parent then
		return {self._value}
	end

	return self.parent:getPath(self)
end

function Element:inputBegan(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local controlPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shiftPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

	if controlPressed and shiftPressed then
	elseif controlPressed then -- pulls out the literal table
		if type(self._value) ~= "table" then return end
		if not self.parent or not self.parent.pullOutElement then return end
		-- pull this off and make a new root
		local name = tostring(self.parent:getIndex())
		self.parent:pullOutElement(self) -- just replaces itself in the parent Entry with a blank thing
		self.parent = nil
		local tableRoot = self._tableInspector:addTable(name, self._value, self)
		tableRoot:drag(Enum.UserInputType.MouseButton1)
		return true
	elseif shiftPressed then -- pulls out the pathway
		-- if type(self._value) ~= "table" then return end
		if not self.parent or not self.parent.pullOutElement then return end
		if self.parent:getIndexElement() == self then return end
		-- pull this off and make a new root
		local name = tostring(self.parent:getIndex())
		local path = self:getPath()

		self.parent:pullOutElement(self) -- just replaces itself in the parent Entry with a blank thing
		self.parent = nil

		local tableRoot = self._tableInspector:addPath(name, path, self)
		tableRoot:drag(Enum.UserInputType.MouseButton1)
		return true
	else
		local t = os.clock()
		if t - self._lastExpansionAttempt < doubleClickPeriod and 
			(self._lastExpansionAttemptPosition - getMousePosition()).magnitude < 4 then
			self:toggleExpansion()
			return true
		end
	end
end

function Element:inputChanged(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseWheel then
		if not self._scrollingEnabled then return end
		local delta = inputObject.Position.z
		local lateralScroll = self._lateralScrollEnabled or UserInputService:IsKeyDown("LeftShift") or UserInputService:IsKeyDown("RightShift")
		local dataPosX = self.dataFrame.Position.X.Offset
		local dataPosY = self.dataFrame.Position.Y.Offset
		local dataSizeX = self.dataFrame.Size.X.Offset
		local dataSizeY = self.dataFrame.Size.Y.Offset
		local clipSizeX = self.clipFrame.Size.X.Offset
		local clipSizeY = self.clipFrame.Size.Y.Offset
		local minPosX = clipSizeX - dataSizeX
		local minPosY = clipSizeY - dataSizeY
		if lateralScroll then
			local nextPosX = math.clamp(dataPosX + fontSize*delta, minPosX, 0)
			local nextPosY = math.clamp(dataPosY, minPosY, 0)
			self.dataFrame.Position = UDim2.fromOffset(nextPosX, nextPosY)
		else
			local nextPosX = math.clamp(dataPosX, minPosX, 0)
			local nextPosY = math.clamp(dataPosY + fontSize*delta, minPosY, 0)
			self.dataFrame.Position = UDim2.fromOffset(nextPosX, nextPosY)
		end
		return true
	end
end

function Element:setValue(value)
	if self._value ~= value then
		self._upToDate = false
		--self._tableInspector:unregisterHighlight(self._value)
		--self._tableInspector:registerHighlight(self._value)
		self._value = value
	end
end

function Element:collapse()
	if self._isExpanded then
		self._upToDate = false
		self._isExpanded = false
		for i, entry in self._entries do
			entry.backFrame.Visible = false
		end
	end
end

function Element:expand()
	if not self._isExpanded then
		self._upToDate = false
		self._isExpanded = true
		for i, entry in self._entries do
			-- this will look weird
			entry.backFrame.Visible = true
		end
	end
end

function Element:toggleExpansion()
	if self._isExpanded then
		self:collapse()
	else
		self:expand()
	end
end

function Element:getValue()
	return self._value
end

function Element:getSize()
	return self._size
end

function Element:update()
	if self._value == self._tableInspector.highlightedValue then
		self.backFrame.BorderColor3 = highlightColor3--Color3.fromRGB(0, 0, 0):Lerp(highlightColor3, math.sin(2*math.pi*os.clock())^2)
	else
		self.backFrame.BorderColor3 = operatorColor3
	end

	local vType = typeof(self._value)
	if vType == "table" then
		self:setToTableForm()
		self:renderTable()
		self._upToDate = true
		return self._size
	end

	if self._upToDate then
		return self._size
	end

	if vType == "boolean" then
		self:setToValueForm()
		self:renderBoolean()
	elseif vType == "number" then
		self:setToValueForm()
		self:renderNumber()
	elseif vType == "string" then
		self:setToValueForm()
		self:renderString()
	elseif vType == "function" then
		self:setToValueForm()
		self:renderFunction()
	else
		self:setToValueForm()
		self:renderAnything()
	end

	-- the previous code should have updated self.Size
	self._upToDate = true
	return self._size
end

function Element:setToValueForm()
	if self._form == "value" then return end
	self._form = "value"

	self.backFrame.BorderSizePixel = 0
	for i, entry in self._entries do
		entry:destroy()
	end
	table.clear(self._entries)
end

function Element:setToTableForm()
	if self._form == "table" then return end
	self._form = "table"

	self.backFrame.BorderSizePixel = tableBorder
end

-- lots of caching and in-place movement made this a lot more work than I wanted it to be
function Element:remapEntries()
	local tab = self._value
	local entries = self._entries

	-- get orphaned indices
	local orphanedEntries = {}
	local orphanedValueElements = {}

	for index, entry in entries do
		if tab[index] == nil then
			table.insert(orphanedEntries, entry)
			entries[index] = nil
		end
	end

	-- reassign indices for maximum reuse
	for index, value in tab do
		if not entries[index] then
			local entry = table.remove(orphanedEntries)
			if entry then
				entries[entry:getIndex()] = nil
				entries[index] = entry
				entry:setIndex(index)
				entry:collapseIndex()
			else
				entry = Entry.new(self._tableInspector, self, index)
				entry.backFrame.Parent = self.dataFrame
				if not self._isExpanded then
					entry.backFrame.Visible = false
				end
				entries[index] = entry
			end
		end
	end

	for i, entry in orphanedEntries do
		table.insert(orphanedValueElements, entry:getValueElement())
	end

	local valueToEntry = {}
	for index, newValue in tab do
		local entry = entries[index]
		local oldValue = entry:getValue()
		if newValue == oldValue then continue end
		if type(oldValue) == "table" then
			table.insert(orphanedValueElements, entry:getValueElement())
		end
		if type(newValue) == "table" then
			valueToEntry[newValue] = entry
		end
	end

	for i, valueElement in orphanedValueElements do
		local oldValue = valueElement:getValue()
		local entry = valueToEntry[oldValue]
		if entry then
			entry:swapValueElement(valueElement.parent)
		end
	end

	-- update all the valueElements to have the new value
	for index, newValue in tab do
		local entry = entries[index]
		entry:setValue(newValue)
	end

	for i, entry in orphanedEntries do
		entry:destroy()
	end
end

function Element:renderBoolean()
	self:setText(self._value and "true" or "false")
	self.dataFrame.TextColor3 = boolColor3
end

function Element:renderNumber()
	self:setText(tostring(self._value))
	self.dataFrame.TextColor3 = numberColor3
end

function Element:renderString()
	self:setText(self._value)
	self.dataFrame.TextColor3 = stringColor3
end

function Element:renderFunction()
	if self._isExpanded then
		self:setText(tostring(self._value))
	else
		self:setText("f(x)")
	end
	self.dataFrame.TextColor3 = functionColor3
end

function Element:renderAnything()
	self:setText(tostring(self._value))
	self.dataFrame.TextColor3 = operatorColor3
end

local typeOrder = {
	["boolean"] = 1;
	["string"] = 2;
	["table"] = 3;
	["function"] = 4;
	["number"] = 5;
}

local function compare(a, b)
	if a == b then
		return 0
	end

	local typeA = type(a)
	local typeB = type(b)

	local compA
	local compB

	if typeA ~= typeB then
		compA, compB = typeOrder[typeA], typeOrder[typeB]
	elseif typeA == "string" then
		compA, compB = a, b
	elseif typeA == "number" then
		compA, compB = a, b
	elseif typeA == "boolean" then
		compA, compB = a and 1 or 0, b and 1 or 0
	else
		compA, compB = tostring(a), tostring(b)
	end

	-- just in case
	return compA == compB and 0 or compA < compB and -1 or 1
end

local function indexLT(a, b)
	return compare(a, b) < 0
end

local function getSortedIndices(tab)
	local indexList = {}
	for i in next, tab do
		table.insert(indexList, i)
	end
	table.sort(indexList, indexLT)
	return indexList
end

function Element:renderTable()
	if not self._isExpanded then
		local tab = self._value
		local i = 0
		local k = 0
		while tab[i + 1] ~= nil do
			i += 1
		end
		for index in tab do
			k += 1
		end
		k -= i

		local text = `{k}k {i}i`
		if self.dataFrame.Text == text then return end -- source of bugs

		local dataSize = TextService:GetTextSize(text, fontSize, font, Vector2.zero)
		local clipSize = Vector2.new(
			math.min(dataSize.x, maxClosedSize.x),
			math.min(dataSize.y, maxClosedSize.y))
		local backSize = clipSize + 2*textPad -- so that it aligns in size with a normal text value

		self._scrollingEnabled = false

		self.dataFrame.Text = text
		self.dataFrame.TextColor3 = operatorColor3
		self.dataFrame.Size = UDim2.fromOffset(dataSize.x, dataSize.y)
		self.clipFrame.Size = UDim2.fromOffset(clipSize.x, clipSize.y)
		self.backFrame.Size = UDim2.fromOffset(backSize.x, backSize.y)
		--self.clipFrame.Position = UDim2.fromOffset(textPad.x, textPad.y)

		self._size = backSize
		return
	end

	self:remapEntries()
	local entries = self._entries

	-- if it is expanded, but there's nothing inside
	if next(entries) == nil then
		local dataSize = Vector2.new(fontSize, fontSize) + 2*textPad + 2*entryPad
		local clipSize = dataSize
		local backSize = clipSize + 2*tableBorder*Vector2.one
		self._scrollingEnabled = false
		self._size = backSize

		--if self.dataFrame.Text == "" then return end -- source of bugs

		self.dataFrame.Text = ""
		self.dataFrame.Size = UDim2.fromOffset(dataSize.x, dataSize.y)
		self.clipFrame.Size = UDim2.fromOffset(clipSize.x, clipSize.y)
		self.backFrame.Size = UDim2.fromOffset(backSize.x, backSize.y)
		return
	end

	local sortedIndices = getSortedIndices(entries)

	local dataSizeX = 0
	local dataSizeY = 0

	for i, index in sortedIndices do
		local entry = entries[index]
		local entrySize = entry:update()
		entry.backFrame.Position = UDim2.fromOffset(0, dataSizeY)
		dataSizeX = math.max(dataSizeX, entrySize.x)
		dataSizeY = dataSizeY + entrySize.y + linePad
	end

	for index, entry in entries do
		local entrySize = entry:getSize()
		entry.backFrame.Size = UDim2.fromOffset(dataSizeX, entrySize.y)
	end

	dataSizeY -= linePad

	local dataSize = Vector2.new(dataSizeX, dataSizeY)
	local clipSize = Vector2.new(
		math.min(dataSize.x, maxOpenedTableSize.x),
		math.min(dataSize.y, maxOpenedTableSize.y))
	local backSize = clipSize + 2*tableBorder*Vector2.one

	self._scrollingEnabled = dataSize ~= clipSize
	self._lateralScrollEnabled = dataSize.y == clipSize.y


	self.dataFrame.Text = ""
	self.dataFrame.Size = UDim2.fromOffset(dataSize.x, dataSize.y)
	self.clipFrame.Size = UDim2.fromOffset(clipSize.x, clipSize.y)
	self.backFrame.Size = UDim2.fromOffset(backSize.x, backSize.y)

	self._size = backSize
end

function Element:setText(text)
	-- this will be a source of bugs.
	--if self.dataFrame.Text == text then return end

	local dataSize, clipSize, backSize

	if self._isExpanded then
		dataSize = TextService:GetTextSize(text, fontSize, font, Vector2.zero)
		clipSize = Vector2.new(
			math.min(dataSize.x, maxOpenedSize.x),
			math.min(dataSize.y, maxOpenedSize.y))

		self._scrollingEnabled = dataSize ~= clipSize
		self._lateralScrollEnabled = dataSize.y == clipSize.y
	else
		dataSize = TextService:GetTextSize(text, fontSize, font, Vector2.zero)
		clipSize = Vector2.new(
			math.min(dataSize.x, maxClosedSize.x),
			math.min(dataSize.y, maxClosedSize.y))

		self._scrollingEnabled = false
	end

	backSize = clipSize + 2*textPad

	self.dataFrame.Text = text
	self.dataFrame.Size = UDim2.fromOffset(dataSize.x, dataSize.y)
	self.clipFrame.Size = UDim2.fromOffset(clipSize.x, clipSize.y)
	self.backFrame.Size = UDim2.fromOffset(backSize.x, backSize.y)
	--self.clipFrame.Position = UDim2.fromOffset(textPad.x, textPad.y)

	self._size = backSize
end














-- an entry is tied to an element parent, for now.
function Entry.new(tableInspector, parent, index)
	local self = setmetatable({}, Entry)
	self._tableInspector = tableInspector
	self.parent = parent

	self.backFrame = Instance.new("Frame")
	self.backFrame.BorderSizePixel = 0
	self.backFrame.BackgroundColor3 = Color3.fromRGB(96, 96, 96)

	self.separatorFrame = Instance.new("TextLabel")
	self.separatorFrame.BackgroundTransparency = 1
	self.separatorFrame.TextColor3 = operatorColor3
	self.separatorFrame.Text = "="
	self.separatorFrame.Font = font
	self.separatorFrame.TextSize = fontSize
	--self.separatorFrame.BorderSizePixel = 0
	--self.separatorFrame.BackgroundColor3 = operatorColor3
	self.separatorFrame.Size = UDim2.fromOffset(separatorSize.x, separatorSize.y)
	self.separatorFrame.Parent = self.backFrame

	--local corner = Instance.new("UICorner")
	--corner.CornerRadius = UDim.new(1, 0)
	--corner.Parent = self.separatorFrame

	self._indexElement = Element.new(self._tableInspector, self, index)
	self._valueElement = Element.new(self._tableInspector, self, nil)

	self._indexElement.backFrame.Parent = self.backFrame
	self._valueElement.backFrame.Parent = self.backFrame
	--self.backFrame.Parent = parent.backFrame

	self._size = Vector2.zero

	return self
end

function Entry:destroy()
	self._indexElement:destroy()
	self._valueElement:destroy()
	self.backFrame:Destroy()
end

function Entry:getPath(element)
	if self._indexElement == element then
		return {element:getValue()}
	elseif self._valueElement == element then
		local path = self.parent:getPath()
		table.insert(path, self._indexElement:getValue())
		return path
	else
		error("Element not found in Entry")
	end
end

function Entry:setIndex(index)
	self._indexElement:setValue(index)
end

function Entry:setValue(value)
	self._valueElement:setValue(value)
end

function Entry:getIndex(index)
	return self._indexElement:getValue()
end

function Entry:getValue(value)
	return self._valueElement:getValue()
end

function Entry:getValueElement()
	return self._valueElement
end

function Entry:getIndexElement()
	return self._indexElement
end

function Entry:collapseIndex()
	self._indexElement:collapse()
end

function Entry:swapValueElement(entry)
	self._valueElement, entry._valueElement = entry._valueElement, self._valueElement
	self._valueElement.parent = self
	entry._valueElement.parent = entry
	self._valueElement.backFrame.Parent = self.backFrame
	entry._valueElement.backFrame.Parent = entry.backFrame
end

function Entry:pullOutElement(element)
	if self._indexElement == element then
		self._indexElement = Element.new(self._tableInspector, self, element:getValue())
		self._indexElement.backFrame.Parent = self.backFrame
	elseif self._valueElement == element then
		self._valueElement = Element.new(self._tableInspector, self, nil)
		self._valueElement.backFrame.Parent = self.backFrame
	else
		error("Element not found in entry")
	end
end

function Entry:update()
	local indexSize = self._indexElement:update()
	local valueSize = self._valueElement:update()

	if self._prevIndexSize == indexSize and self._prevValueSize == valueSize then
		-- no changes, no need to update
		return self._size
	end

	self.prevIndexSize = indexSize
	self.prevValueSize = valueSize

	local padX = entryPad.x
	local padY = entryPad.y

	local sizeX = padX + indexSize.x + padX + separatorSize.x + padX + valueSize.x + padX
	local sizeY = padY + math.max(indexSize.y, separatorSize.y, valueSize.y) + padY
	self._size = Vector2.new(sizeX, sizeY)

	self.separatorFrame.Position = UDim2.fromOffset(padX + indexSize.x + padX, padY + math.min(indexSize.y, valueSize.y)/2 - separatorSize.y/2)
	self._indexElement.backFrame.Position = UDim2.fromOffset(padX, padY)
	self._valueElement.backFrame.Position = UDim2.fromOffset(padX + indexSize.x + padX + separatorSize.x + padX, padY)

	return self._size
	-- updating the entry's backFrame size and position are the responsibility of the parent Element
end

-- gets the size, but does not update
function Entry:getSize()
	return self._size
end

return TableInspector
