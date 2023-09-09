-- derpy's layout system v1 - derpy54320

local mt_layout = {__index = {}}

-- create
function F_CreateLayout()
	local layout = setmetatable({n = 1,x = 0,y = 0,w = 1,h = 1},mt_layout)
	layout[1] = layout -- last table in stack is always the layout table itself
	return layout
end

-- stack
function mt_layout.__index:start()
	self[self.n] = {x = self.x,y = self.y,w = self.w,h = self.h}
	table.insert(self,self)
end
function mt_layout.__index:finish(x,y)
	local state = self[self.n-1]
	if x then
		local width = ((self.x - state.x) + self.w) * x
		local height = ((self.y - state.y) + self.h) * y
		if width > state.w then
			width = state.w
		end
		if height > state.h then
			height = state.h
		end
		self.x = state.x + width
		self.y = state.y + height
		self.w = state.w - width
		self.h = state.h - height
	else
		self.x = state.x
		self.w = state.w
		self.y = state.y
		self.h = state.h
	end
	table.remove(self)
	self[self.n] = self
end

-- query
function mt_layout.__index:get(stack)
	if not stack then
		return self
	elseif stack < 0 then
		return self[self.n+stack+1]
	end
	return self[stack]
end
function mt_layout.__index:space(width,height,stack)
	local state = self:get(stack)
	return state.w > (width or 0) and state.h > (height or 0)
end

-- style
function mt_layout.__index:advance(x,y,parent)
	local state = self:get(parent)
	local width = state.w * x
	local height = state.h * y
	if width > self.w then
		width = self.w
	end
	if height > self.h then
		height = self.h
	end
	self.x = self.x + width
	self.y = self.y + height
	self.w = self.w - width
	self.h = self.h - height
end
function mt_layout.__index:align(x,y,parent)
	local state = self:get(parent)
	if x then
		self.x = state.x + (state.w - self.w) * x
	end
	if y then
		self.y = state.y + (state.h - self.h) * y
	end
end
function mt_layout.__index:aspect(ratio,cover,parent)
	local state = self:get(parent)
	local current = state.w / state.h
	ratio = ratio / GetDisplayAspectRatio()
	if cover then
		if ratio >= current then
			self.w = state.h * ratio
		else
			self.h = state.w / ratio
		end
	elseif ratio <= current then
		self.w = state.h * ratio
	else
		self.h = state.w / ratio
	end
end
function mt_layout.__index:padding(height,parent)
	local width
	if parent ~= 1 then
		local state = self:get(parent)
		height = state.h * height
		width = height / (state.w / state.h)
	else
		width = height / GetDisplayAspectRatio()
	end
	if width > self.w then
		width = self.w
	end
	if height > self.h then
		height = self.h
	end
	self.x = self.x + width / 2
	self.y = self.y + height / 2
	self.w = self.w - width
	self.h = self.h - height
end
function mt_layout.__index:position(x,y,parent)
	local state = self:get(parent)
	self.x = state.x + state.w * x
	self.y = state.y + state.h * y
end
function mt_layout.__index:size(width,height,parent)
	local state = self:get(parent)
	self.w = state.w * width
	self.h = state.h * height
end

-- debug
function mt_layout.__index:debug(hue)
	local h = math.mod(tonumber(hue) or 0,360)
	local x = 1 - math.abs(math.mod(h/60,2)-1)
	local r,g,b
	if h < 60 then
		r,g,b = 1,x,0
	elseif h < 120 then
		r,g,b = x,1,0
	elseif h < 180 then
		r,g,b = 0,1,x
	elseif h < 240 then
		r,g,b = 0,x,1
	elseif h < 300 then
		r,g,b = x,0,1
	else
		r,g,b = 1,0,x
	end
	DrawRectangle(self.x,self.y,self.w,self.h,r*255,g*255,b*255,255)
end
