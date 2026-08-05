local ReflectionService = game:GetService("ReflectionService")

local function unionProperties(...)
	local classes = {...}
	local union = {}
	for _, class in classes do
		local properties = ReflectionService:GetPropertiesOfClass(class)
		for propertyName, propertyData in properties do
			if union[propertyName] then continue end
			union[propertyName] = propertyData
		end
	end
	return union
end

local Properties = unionProperties("TextButton", "ImageLabel", "UIScale")

local Config = {}

Config.EasingDirections = {
	out = Enum.EasingDirection.Out,
	["in"] = Enum.EasingDirection.In,
	inout = Enum.EasingDirection.InOut
}

Config.EasingStyles = {
	linear = Enum.EasingStyle.Linear,
	sine = Enum.EasingStyle.Sine,
	quad = Enum.EasingStyle.Quad,
	cubic = Enum.EasingStyle.Cubic,
	quart = Enum.EasingStyle.Quart,
	quint = Enum.EasingStyle.Quint,
	exponential = Enum.EasingStyle.Exponential,
	exp = Enum.EasingStyle.Exponential,
	circular = Enum.EasingStyle.Circular,
	circ = Enum.EasingStyle.Circular,
	back = Enum.EasingStyle.Back,
	bounce = Enum.EasingStyle.Bounce,
	elastic = Enum.EasingStyle.Elastic
}


Config.DynamicProperties = {
	ap = "AnchorPoint",
	bgc = "BackgroundColor3",
	bgt = "BackgroundTransparency",
	bc = "BorderColor3",
	bsp = "BorderSizePixel",
	pos = "Position",
	p = "Position",
	rot = "Rotation",
	r = "Rotation",
	size = "Size",
	s = "Size",
	scale = "Scale",
	
	--text --> TextButton
	tc = "TextColor3",
	ts = "TextSize",
	tsc = "TextStrokeColor3",
	tst = "TextStrokeTransparency",
	tt = "TextTransparency",
	
	--image --> 
	ic = "ImageColor3",
	iro = "ImageRectOffset",
	irs = "ImageRectSize",
	it = "ImageTransparency"
}

Config.DynamicPropertiesCache = {}
for _, name in Config.DynamicProperties do
	Config.DynamicPropertiesCache[name] = true
end

Config.StaticProperties = {
	lo = "LayoutOrder",
	v = "Visible",
	z = "ZIndex"
}

Config.StaticPropertiesCache = {}
for _, name in Config.StaticProperties do
	Config.StaticPropertiesCache[name] = true
end

Config.Types = {}
for _, data in Properties do
	local name = data.Name
	local scriptType = data.Type.ScriptType
	
	if scriptType == "float" or scriptType == "int" or scriptType == "double" then
		scriptType = "number"
	end
	
	if not Config.Types[name] then
		Config.Types[name] = scriptType
	end
end

if not Config.Types.Scale then
	Config.Types.Scale = "number"
end

Config.Operations = {
	add = function(a, b) return a + b end,
	sub = function(a, b) return a - b end,
	mult = function(a, b) return a * b end,
	div = function(a, b) return a / b end
}

Config.Operations.a = Config.Operations.add
Config.Operations.s = Config.Operations.sub
Config.Operations.m = Config.Operations.mult
Config.Operations.d = Config.Operations.div

return Config
