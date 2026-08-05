local TweenService = game:GetService("TweenService")

local ParameterConfig = require(script.Parent.Parent.Config.ParameterConfig)

local Sequence = {}
Sequence.__index = Sequence

type ParameterType = "EasingDirection" | "EasingStyle" | "Time" | "DynamicProperty" | "Delay" | "Initial" | "StaticProperty"

type EvaluatedPhrase = {
	Type: ParameterType,
	Value: number | Enum 
}

local function parsePhrase(self, rawPhrase)
	local parsed = rawPhrase:gsub("%+", "")
	parsed = parsed:gsub("%(", "")
	parsed = parsed:gsub("%)", "")
	parsed = parsed:gsub("%-%-", "-%%")
	parsed = table.concat(parsed:split("-"), " ")
	parsed = parsed:gsub("%%", "-")
	parsed = parsed:split(" ")
	return parsed
end

local function evaluateUDim(self, x: number)
	x = tonumber(x)
	if x ~= 1 and math.round(x) == x then
		return UDim.new(0, x)
	end
	return UDim.new(x, 0)
end

local function getRawValue(self, dataType, values, name)
	if dataType == "number" then
		return tonumber(values[1])
	elseif dataType == "UDim2" then
		if values[1] == "c" then
			return UDim2.fromScale(0.5, 0.5)
		elseif #values == 1 then
			local x = evaluateUDim(self, values[1])
			return UDim2.new(x, x)
		elseif #values == 2 then
			local x = evaluateUDim(self, values[1])
			local y = evaluateUDim(self, values[2])
			return UDim2.new(x, y)
		elseif #values == 4 then
			return UDim2.new(
				values[1],
				values[2],
				values[3],
				values[4]
			)
		end
	elseif dataType == "Vector2" then
		if #values == 1 then
			return Vector2.new(values[1], values[1])
		end
		return Vector2.new(values[1], values[2])
	elseif dataType == "Color3" then
		if values[1] == "rgb" then
			return Color3.fromRGB(values[2], values[3], values[4])
		elseif values[1] == "hsv" then
			return Color3.fromRGB(values[2], values[3], values[4])
		elseif values[1] == "hex" then
			return Color3.fromHex(values[2])
		elseif values[1] == "new" then
			return Color3.new(values[2], values[3], values[4])
		end
	elseif dataType == "boolean" then
		if values[1] == "t" then
			return true
		elseif values[1] == "f" then
			return false
		end
	end
end

local function evaluateProperty(self, phrase, name, rawPhrase)
	local success, data = pcall(function()
		local dataType = ParameterConfig.Types[name]
		local index = 2
		local initial = nil
		local present = nil
		local operation = nil	

		if phrase[index] == "i" or phrase[index] == "initial" then
			index += 1
			initial = true
		end

		if phrase[index] == "p" or phrase[index] == "present" then
			index += 1
			present = true
		end
		
		if initial and present then
			error()
		end

		local v = phrase[index]
		if ParameterConfig.Operations[v] ~= nil then
			index += 1
			operation = ParameterConfig.Operations[v]
		end
		
		if present and operation == nil then
			error()
		end
		
		if initial and operation == nil and #phrase > 2 then
			error()
		end

		local values = {}
		for i = index, #phrase do
			table.insert(values, phrase[i])
		end

		local function getOperationFunction(operation)
			if operation == ParameterConfig.Operations["mult"] or operation == ParameterConfig.Operations["div"] then
				return function(currentValue)
					local v = getRawValue(self, dataType, values, name)
					if v then
						return operation(currentValue, v)
					end
					return operation(currentValue, getRawValue(self, "number", values, name))
				end
			end
			return function(currentValue)
				return operation(currentValue, getRawValue(self, dataType, values, name))
			end
		end

		local function getTarget()
			if name == "Scale" then
				local uiScale = self.GuiObject:FindFirstChildOfClass("UIScale")
				if uiScale then
					return uiScale
				end
			end
			return self.GuiObject
		end

		if initial and operation == nil then -- pos-i
			return getTarget()[name]
		end

		if (initial and operation ~= nil) or (present == nil and operation ~= nil) then
			return getOperationFunction(operation)(getTarget()[name]) -- pos-i-add-0.2
		end

		if present and operation ~= nil then -- pos-p-add-0.2
			return getOperationFunction(operation)
		end

		return getRawValue(self, dataType, values, name)
	end)
	if success then
		return data
	else
		error(`Invalid property syntax '{rawPhrase}' in '{self.State}' sequence affecting {self.GuiObject:GetFullName()}: {data}`)
	end
end


local function evaluatePhrase(self, rawPhrase): EvaluatedPhrase
	local parsedPhrase = parsePhrase(self, rawPhrase)
	local keyword = parsedPhrase[1]
	if keyword == "i" or keyword == "initial" then
		local values = {}
		local uiScale = self.GuiObject:FindFirstChildOfClass("UIScale")
		for _, propertyName in self.OtherProperties do
			local target = self.GuiObject
			if propertyName == "Scale" and uiScale then
				target = uiScale
			end
			
			local success, value = pcall(function()
				return target[propertyName]
			end)
			
			if success then
				values[propertyName] = value
			end
		end
		return {
			Type = "Initial",
			Values = values
		}
	end
	if tonumber(keyword) then -- 0.2
		return {
			Type = "Delay",
			Value = tonumber(keyword)
		}	
	end -- Inherently skips 0 or nil
	if keyword == "t" then -- t-0.2

		return {
			Type = "Time",
			Value = tonumber(parsedPhrase[2])
		}	
	end
	local v = ParameterConfig.EasingDirections[keyword]
	if v then 
		return {
			Type = "EasingDirection",
			Value = v
		}	
	end
	local v = ParameterConfig.EasingStyles[keyword]
	if v then 
		return {
			Type = "EasingStyle",
			Value = v
		}	
	end
	local name = ParameterConfig.DynamicProperties[keyword]
	if name then
		local v = evaluateProperty(self, parsedPhrase, name, rawPhrase)
		return {
			Type = "DynamicProperty",
			Name = name,
			Value = v
		}
	end
	local name = ParameterConfig.StaticProperties[keyword]
	if name then
		local v = evaluateProperty(self, parsedPhrase, name, rawPhrase)
		return {
			Type = "StaticProperty",
			Name = name,
			Value = v
		}
	end
	error(`Invalid phrase '{rawPhrase}' in '{self.State}'' sequence affecting {self.GuiObject:GetFullName()}`)
end


local function parsePhrases(self, sequence: {string})
	local phrases = {}
	for _, rawPhrase in sequence do
		local evaluatedPhrase = evaluatePhrase(self, rawPhrase)
		table.insert(phrases, evaluatedPhrase)
	end
	return phrases
end

local function parseSequence(self, rawSequence: string)
	local parsed = rawSequence
	parsed = table.concat(rawSequence:split(","), " ")
	parsed = table.concat(parsed:split(";"), " ")
	parsed = parsed:split(" ")
	local newParsed = {}
	for i, s in parsed do
		if s ~= "" then
			table.insert(newParsed, s)
		end
	end
	return newParsed
end

local function newItem()
	return {
		DynamicProperties = {},
		StaticProperties = {},
		Time = nil,
		EasingStyle = nil,
		EasingDirection = nil,
		Delay = nil
	}
end

local function itemizeSequence(self, parsedSequence)
	local sequence = {}
	local currentSequence = newItem()
	for _, item in parsedSequence do
		if item.Type == "Delay" then
			currentSequence.Delay = item.Value
			table.insert(sequence, currentSequence)
			currentSequence = newItem()
		else
			if item.Type == "DynamicProperty" then
				currentSequence.DynamicProperties[item.Name] = item.Value
			elseif item.Type == "StaticProperty" then
				currentSequence.StaticProperties[item.Name] = item.Value
			elseif item.Type == "EasingStyle" then
				currentSequence.EasingStyle = item.Value
			elseif item.Type == "EasingDirection" then
				currentSequence.EasingDirection = item.Value
			elseif item.Type == "Time" then
				currentSequence.Time = item.Value
			elseif item.Type == "Initial" then
				for propertyName, propertyValue in item.Values do
					if ParameterConfig.DynamicPropertiesCache[propertyName] then
						currentSequence.DynamicProperties[propertyName] = propertyValue
					elseif ParameterConfig.StaticPropertiesCache[propertyName] then
						currentSequence.StaticProperties[propertyName] = propertyValue						
					end
				end
			end
		end
	end
	currentSequence.Delay = nil
	table.insert(sequence, currentSequence)
	return sequence
end

local function evaluateSequence(self, sequence)
	local parsedSequence = parseSequence(self, sequence)
	local parsedPhrases = parsePhrases(self, parsedSequence)
	local itemizedSequence = itemizeSequence(self, parsedPhrases)
	return itemizedSequence
end

local function getOtherProperties(self)
	if not self.OtherSequences then return end
	local properties = {}
	for _, sequence in self.OtherSequences do
		local parsedSequence = parseSequence(self, sequence)
		for _, phrase in parsedSequence do
			local keyword = phrase:split("-")[1]
			keyword = keyword:gsub("%(", "")
			keyword = keyword:gsub("%)", "")
			
			local propertyName = ParameterConfig.DynamicProperties[keyword] or ParameterConfig.StaticProperties[keyword]
			if propertyName and table.find(properties, propertyName) == nil then
				table.insert(properties, propertyName)
			end
		end
	end
	return properties
end

function Sequence.new(guiObject: GuiObject, sequence: string, otherSequences: {string}, state: string)
	local self = setmetatable({}, Sequence)
	
	self.GuiObject = guiObject
	self.RawSequence = sequence
	self.OtherSequences = otherSequences
	self.OtherProperties = getOtherProperties(self) or {}
	self.State = state
	

	
	self.Sequence = evaluateSequence(self, sequence)
	
	
	
	self.Tweens = {}
	
	return self
end

function Sequence:Play()
	self:Stop()
	self.Thread = task.defer(function()
		for _, data in self.Sequence do
			local uiScale = self.GuiObject:FindFirstChildOfClass("UIScale")
			if data.Time then
				local guiObjectClone = {}
				local uiScaleClone = {}
				
				for propertyName, propertyValue in data.DynamicProperties do
					local target = self.GuiObject
					if propertyName == "Scale" and uiScale then
						target = uiScale
					end
					
					local value = propertyValue
					if type(propertyValue) == "function" then
						value = propertyValue(target[propertyName])
					end
					
					if target == uiScale then
						uiScaleClone[propertyName] = value
					else
						guiObjectClone[propertyName] = value
					end
				end

				if next(guiObjectClone) then
					local tween = TweenService:Create(
						self.GuiObject,
						TweenInfo.new(data.Time, data.EasingStyle or Enum.EasingStyle.Linear, data.EasingDirection or Enum.EasingDirection.Out),
						guiObjectClone
					)
					table.insert(self.Tweens, tween)
					tween:Play()
				end

				if uiScale and next(uiScaleClone) then
					local tween = TweenService:Create(
						uiScale,
						TweenInfo.new(data.Time, data.EasingStyle or Enum.EasingStyle.Linear, data.EasingDirection or Enum.EasingDirection.Out),
						uiScaleClone
					)
					table.insert(self.Tweens, tween)
					tween:Play()
				end
			else
				for propertyName, propertyValue in data.DynamicProperties do
					local target = self.GuiObject
					if propertyName == "Scale" and uiScale then
						target = uiScale
					end
					
					if type(propertyValue) == "function" then
						target[propertyName] = propertyValue(target[propertyName])
					else
						target[propertyName] = propertyValue
					end
				end
			end
			for propertyName, propertyValue in data.StaticProperties do
				local target = self.GuiObject
				if propertyName == "Scale" and uiScale then
					target = uiScale
				end
				
				if type(propertyValue) == "function" then
					target[propertyName] = propertyValue(target[propertyName])
				else
					target[propertyName] = propertyValue
				end
			end
			if data.Delay ~= nil and data.Delay > 0 then
				task.wait(data.Delay)
			end
		end
	end)
end

function Sequence:Stop()
	if self.Thread then
		task.cancel(self.Thread)
	end
	if #self.Tweens > 0 then
		for _, tween in self.Tweens do
			tween:Cancel()
		end
		table.clear(self.Tweens)		
	end
end

return Sequence