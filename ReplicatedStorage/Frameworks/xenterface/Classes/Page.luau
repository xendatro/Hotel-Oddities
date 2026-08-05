local Toggle = require(script.Parent.Toggle)

local Page = {}
Page.__index = Page
setmetatable(Page, Toggle)

function Page.new(page: GuiObject, source: Configuration?)
	if not source then
		source = page
	end
	local self = setmetatable(Toggle.new(page, source, "Page"), Page)
	
	self.Page = page

	return self
end



return Page