-- derpy's script server: account system - derpy54320 & SWEGTA
api = GetScriptNetworkTable()
LoadScript("layout.lua")

-- globals
gStarting = true
gUsername = false
gUiActive = false
gIsTyping = false

-- api
function api.get_username() -- can also be used to check if we're signed in at all
	if gUsername then
		return gUsername
	end
end
function api.is_ui_active() -- most scripts should wait until this returns false before starting
	return gStarting or gUiActive
end

-- cleanup
function MissionCleanup()
	if gIsTyping then
		StopTyping()
	end
end

-- main
function main()
	SendNetworkEvent("account:started")
	SoundPlay2D("ButtonDown")
	F_SetUI(true)
	gStarting = false
	while gUiActive do
		Wait(0)
	end
	TerminateCurrentScript()
end
function F_SetUI(on)
	if gUiActive then
		if gIsTyping then
			StopTyping()
			gIsTyping = false
		end
		for _,thread in ipairs(gThreads) do
			TerminateThread(thread)
		end
		gCursor = nil
		gInput = nil
		gThreads = nil
	end
	gUiActive = on
	if on then
		gCursor = {x = 0.5,y = 0.5,h = 0.02}
		gInput = {
			active = true, -- set false when waiting on some server response
			signup = false,
			focus = 1, -- item in focus
			hover = 0, -- item hovered over by cursor
			boxes = {}, -- hitboxes for each input item
			items = {"user","pass","pass2","login","create"},
			typed = {
				user = "username",
				pass = "password",
				pass2 = "confirm",
			},
			tabs = {
				[false] = {1,2,4,5},
				[true] = {1,2,3,4,5},
			},
			iserror = false, -- notification
			notification = "",
			username = "",
			password = "",
			confirm = "",
		}
		gThreads = {
			CreateDrawingThread("T_ControlUI"),
			CreateDrawingThread("T_DrawUI"),
		}
	end
end

-- sign in / out
RegisterNetworkEventHandler("account:setuser",function(user)
	gUsername = user or false
end)

-- update controls
function T_ControlUI()
	while true do
		if not IsGamePaused() then
			F_ControlUI()
		end
		Wait(0)
	end
end
function F_ControlUI()
	local mx,my = GetMouseInput()
	local click = IsMouseBeingPressed(0)
	local speed = GetFrameTime() * 0.02
	gCursor.x = math.max(0,math.min(1,gCursor.x+mx*(speed/GetDisplayAspectRatio())))
	gCursor.y = math.max(0,math.min(1,gCursor.y+my*speed))
	gInput.hover = 0
	for i,box in pairs(gInput.boxes) do
		if F_IsCursorHovering(i,unpack(box)) then
			gInput.hover = i
		end
	end
	if gInput.active then
		if click then
			if gInput.hover ~= 0 then
				if gInput.focus ~= gInput.hover then
					F_StopTyping()
				end
				gInput.focus = gInput.hover
				SoundPlay2D("ButtonDown")
			else
				SoundPlay2D("NavInvalid")
			end
		end
		if click or IsKeyBeingPressed("RETURN") then
			if click and gInput.hover ~= 0 then
				gInput.focus = gInput.hover
			end
			if not F_ConfirmInput(gInput.items[gInput.focus]) and not click then
				F_TabInput(false) -- go forward one when hitting enter on something that isnt a button
			elseif not click then
				SoundPlay2D("ButtonDown") -- KEYBOARD button sound
			end
		elseif IsKeyBeingPressed("TAB") then
			F_StopTyping()
			F_TabInput(IsKeyPressed("LSHIFT"))
		end
		F_UpdateTyping(gInput.items[gInput.focus])
	end
end
function F_IsCursorHovering(i,x,y,w,h)
	if gCursor.x >= x and gCursor.x < x + w and gCursor.y >= y and gCursor.y < y + h then
		for _,tab in ipairs(gInput.tabs[gInput.signup]) do
			if tab == i then
				return true
			end
		end
	end
	return false
end
function F_StopTyping()
	if gIsTyping then
		StopTyping()
		gIsTyping = false
	end
end
function F_UpdateTyping(item)
	local field = gInput.typed[item]
	if field and not IsConsoleActive() then
		if not (gIsTyping and IsTypingActive()) then
			if gIsTyping and WasTypingAborted() then
				gIsTyping = StartTyping() -- hit escape
			else
				gIsTyping = StartTyping(gInput[field])
			end
		end
		if gIsTyping then
			gInput[field] = GetTypingString()
		end
	elseif gIsTyping then
		StopTyping()
		gIsTyping = false
	end
end
function F_ConfirmInput(item)
	if item == "login" then
		gInput.notification = ""
		if gInput.signup then
			F_AttemptSignup()
		else
			F_AttemptLogin()
		end
		return true
	elseif item == "create" then
		F_StopTyping()
		gInput.signup = not gInput.signup
		gInput.focus = 1
		gInput.hover = gInput.tabs[gInput.signup][1]
		gInput.notification = ""
		gInput.username = ""
		gInput.password = ""
		gInput.confirm = ""
		return true
	end
	return false
end
function F_TabInput(backwards)
	local index = 1
	local tabs = gInput.tabs[gInput.signup]
	for i,tab in ipairs(tabs) do
		if gInput.focus == tab then
			index = i
			break
		end
	end
	if backwards then
		index = index - 1
		if index < 1 then
			index = table.getn(tabs)
		end
		SoundPlay2D("NavUp")
	else
		index = index + 1
		if index > table.getn(tabs) then
			index = 1
		end
		SoundPlay2D("NavDwn")
	end
	gInput.focus = tabs[index]
end

-- confirm signup
function F_AttemptSignup()
	local cfg = GetScriptConfig()
	local user_filter = GetConfigString(cfg,"use_character_filter")
	local max_username = GetConfigNumber(cfg,"max_username_length")
	local min_password = GetConfigNumber(cfg,"min_password_length",1)
	if string.len(gInput.username) < 1 then
		gInput.iserror = true
		gInput.notification = "Username must be at least 1 character."
	elseif user_filter and string.find(gInput.username,user_filter) then
		gInput.iserror = true
		gInput.notification = "Username contains a forbidden character."
		gInput.username = ""
	elseif max_username and string.len(gInput.username) > max_username then
		gInput.iserror = true
		gInput.notification = "Usernames are limited to "..max_username.." characters."
		gInput.username = ""
	elseif string.len(gInput.password) < min_password then
		gInput.iserror = true
		if min_password == 1 then
			gInput.notification = "Password must be at least 1 character."
		else
			gInput.notification = "Password must be at least "..min_password.." characters."
		end
		gInput.password = ""
		gInput.confirm = ""
	elseif gInput.password ~= gInput.confirm then
		gInput.iserror = true
		gInput.notification = "Passwords do not match."
		gInput.password = ""
		gInput.confirm = ""
	else
		F_Signup()
	end
end
function F_Signup()
	local salt = F_GetSalt(8)
	gInput.active = false
	gInput.iserror = false
	gInput.notification = "Signing up..."
	SendNetworkEvent("account:signup",gInput.username,ObjectNameToHashID(gInput.password..salt),salt)
end

-- signup response
RegisterNetworkEventHandler("account:signup",function(failure)
	if gUiActive then
		gInput.active = true
		gInput.iserror = failure ~= nil
		gInput.notification = failure or "Account created! You may now go login."
		gInput.username = ""
		gInput.password = ""
		gInput.confirm = ""
	end
end)

-- confirm login
function F_AttemptLogin()
	if string.len(gInput.username) < 1 or string.len(gInput.password) < 1 then
		gInput.iserror = true
		gInput.notification = "Please enter your username and password."
		gInput.password = ""
	else
		F_Login()
	end
end
function F_Login()
	gInput.active = false
	gInput.iserror = false
	gInput.notification = "Signing in..."
	SendNetworkEvent("account:login",gInput.username) -- will tell the server to give us salt so we can actually try to sign in
end

-- login response
RegisterNetworkEventHandler("account:login",function(response,argument)
	if gUiActive then
		if response then -- this event is in response to us trying to sign in
			if argument then
				gInput.active = true
				gInput.iserror = true
				gInput.notification = argument -- server provided reason for not signing in
				gInput.username = ""
				gInput.password = ""
			else
				F_SetUI(false) -- success!
			end
		else -- or the server just gave us salt and we will now try to sign in
			SendNetworkEvent("account:login",gInput.username,ObjectNameToHashID(gInput.password..argument))
		end
	end
end)

-- password utility
function F_GetSalt(length)
	local salt = {}
	math.randomseed(GetTimer())
	for i = 1,length do
		salt[i] = math.random(1,255)
	end
	return string.char(unpack(salt))
end

-- draw ui
function T_DrawUI()
	local cfg = GetScriptConfig()
	local lo = F_CreateLayout()
	local ui = {
		title_bar = 0.1,
		border_line = 0.004,
		title_text = GetConfigString(cfg,"ui_title_text"),
		news_title = GetConfigString(cfg,"ui_news_title"),
		news_text = GetConfigString(cfg,"ui_news_text"),
		image_arrow = CreateTexture("image/arrow.png"),
		image_confirm = CreateTexture("image/confirm.png"),
		image_login = CreateTexture("image/login.png"),
		image_news = CreateTexture("image/news.png"),
		image_password = CreateTexture("image/password.png"),
		image_signup = CreateTexture("image/signup.png"),
		image_username = CreateTexture("image/username.png"),
	}
	if GetConfigValue(cfg,"ui_news_image") then
		ui.news_image = CreateTexture(GetConfigString(cfg,"ui_news_image"))
	end
	while true do
		if not IsGamePaused() then
			F_DrawUI(lo,ui)
			DrawTexture(ui.image_arrow,gCursor.x,gCursor.y,gCursor.h*GetTextureDisplayAspectRatio(ui.image_arrow),gCursor.h,255,255,255,255)
		end
		Wait(0)
	end
end
function F_DrawUI(lo,ui)
	lo:start()
		lo:aspect(4/3)
		lo:size(0.45*(3/2),0.45)
		--lo:size(0.59,0.43) -- swegta's original size
		--lo:size(0.9,0.55) -- my original size
		lo:align(0.5,0.5,-2)
		lo:start()
			lo:start()
				lo:padding(-ui.border_line,1)
				DrawRectangle(lo.x,lo.y,lo.w,lo.h,255,213,3,255) -- window border
			lo:finish()
			lo:start()
				lo:size(0.42,1)
				F_DrawNewsUI(lo,ui) -- news section
			lo:finish(1,0)
			lo:start()
				lo:size(0.01,1)
				DrawRectangle(lo.x,lo.y,lo.w,lo.h,13,25,23,255) -- news / login border
			lo:finish(1,0)
			lo:start()
				F_DrawLoginUI(lo,ui,gInput.signup) -- login section
			lo:finish()
		lo:finish()
		if ui.title_text then
			F_DrawTitleUI(lo,ui) -- single title instead of "news" / "login"
		end
	lo:finish()
end
function F_DrawNewsUI(lo,ui)
	lo:start()
		lo:size(1,ui.title_bar)
		if not ui.title_text then
			DrawRectangle(lo.x,lo.y,lo.w,lo.h,13,25,23,255) -- news title bar
			lo:start()
				lo:padding(0.015,1)
				lo:aspect(GetTextureAspectRatio(ui.image_news))
				lo:align(0.5,nil,-2)
				DrawTexture(ui.image_news,lo.x,lo.y,lo.w,lo.h,255,213,3,255) -- "news"
			lo:finish()
		end
	lo:finish(0,1)
	lo:start()
		lo:start()
			DrawRectangle(lo.x,lo.y,lo.w,lo.h,31,56,59,255) -- news background
			lo:advance(0,0.01,-2)
			if ui.news_image then
				lo:start()
					lo:size(1,0.4)
					lo:start()
						lo:padding(0.01,1)
						lo:aspect(GetTextureAspectRatio(ui.news_image))
						lo:align(0.5,0.5,-2)
						lo:start()
							lo:padding(-ui.border_line,1)
							DrawRectangle(lo.x,lo.y,lo.w,lo.h,255,213,3,255)
						lo:finish()
						DrawTexture(ui.news_image,lo.x,lo.y,lo.w,lo.h,255,255,255,255)
					lo:finish()
				lo:finish(0,1)
			end
			if lo:space() then
				lo:start()
					SetTextFont("Georgia")
					SetTextBold()
					SetTextColor(255,213,3,255)
					SetTextHeight(lo:get(-3).h*0.075)
					SetTextClipping(lo.w*0.95,lo.h)
					SetTextPosition(lo.x+lo.w/2,lo.y)
					lo.w,lo.h = DrawText(ui.news_title)
				lo:finish(0,1)
			end
			if lo:space() then
				lo:start()
					SetTextFont("Arial")
					SetTextBlack()
					SetTextColor(240,240,240,255)
					SetTextHeight(lo:get(-3).h*0.04)
					SetTextWrapping(lo.w*0.95)
					SetTextClipping(nil,lo.h)
					SetTextPosition(lo.x+lo.w/2,lo.y)
					DrawText(ui.news_text)
				lo:finish()
			end
		lo:finish()
	lo:finish()
end
function F_DrawLoginUI(lo,ui,signup)
	lo:start()
		lo:size(1,ui.title_bar)
		if not ui.title_text then
			DrawRectangle(lo.x,lo.y,lo.w,lo.h,13,25,23,255) -- login title bar
			lo:start()
				if signup then
					lo:padding(0.015,1)
					lo:aspect(GetTextureAspectRatio(ui.image_signup))
					lo:align(0.5,nil,-2)
					DrawTexture(ui.image_signup,lo.x,lo.y,lo.w,lo.h,255,213,3,255) -- "signup"
				else
					lo:padding(0.015,1)
					lo:aspect(GetTextureAspectRatio(ui.image_login))
					lo:align(0.5,nil,-2)
					DrawTexture(ui.image_login,lo.x,lo.y,lo.w,lo.h,255,213,3,255) -- "login"
				end
			lo:finish()
		end
	lo:finish(0,1)
	lo:start()
		DrawRectangle(lo.x,lo.y,lo.w,lo.h,49,85,90,255) -- login background
		lo:padding(0.04,1)
		lo:start()
			F_DrawTextUI(lo,ui,ui.image_username,gInput.username,1)
			F_DrawTextUI(lo,ui,ui.image_password,string.rep("*",string.len(gInput.password)),2)
			if signup then
				F_DrawTextUI(lo,ui,ui.image_confirm,string.rep("*",string.len(gInput.confirm)),3)
			end
			lo:start()
				lo:size(0.95,0.16,-3)
				lo:align(0.5,0,-2)
				lo:start()
					lo:size(0.5,1)
					lo:align(0,0.5,-2)
					lo:start()
						lo:padding(0.01,1)
						F_DrawButtonUI(lo,ui,signup and "Sign-Up" or "Login",4)
					lo:finish()
				lo:finish()
				lo:start()
					lo:size(0.5,1)
					lo:align(1,0.5,-2)
					lo:start()
						lo:padding(0.01,1)
						F_DrawButtonUI(lo,ui,signup and "Cancel" or "Create Account",5)
					lo:finish()
				lo:finish()
			lo:finish(0,1)
			if lo:space() and (signup or gInput.notification ~= "") then
				lo:start()
					lo:size(1,0.11,-3)
					lo:align(0,1,-2)
					SetTextFont("Arial")
					SetTextBlack()
					SetTextOutline()
					SetTextColor(220,20,20,255)
					SetTextAlign("C","B")
					SetTextHeight(lo.h*0.35)
					SetTextClipping(lo.w,lo.h)
					SetTextPosition(lo.x+lo.w/2,lo.y+lo.h)
					if gInput.notification ~= "" then
						if not gInput.iserror then
							SetTextColor(255,213,3,255)
						end
						DrawText(gInput.notification)
					else
						DrawText("Passwords are *not* secure, don't use one you care about.")
					end
				lo:finish()
			end
		lo:finish()
	lo:finish()
end
function F_DrawTitleUI(lo,ui)
	lo:start()
		lo:size(1,ui.title_bar,-2)
		DrawRectangle(lo.x,lo.y,lo.w,lo.h,13,25,23,255) -- full title bar
		lo:start()
			SetTextFont("Georgia")
			SetTextBold()
			SetTextOutline()
			SetTextColor(255,213,3,255)
			SetTextAlign("C","C")
			SetTextHeight(lo.h*0.9)
			SetTextClipping(lo.w,lo.h)
			SetTextPosition(lo.x+lo.w/2,lo.y+lo.h/2)
			DrawText(ui.title_text)
		lo:finish()
	lo:finish()
end
function F_DrawTextUI(lo,ui,texture,text,item)
	lo:start()
		lo:size(1,0.07,-3)
		lo:aspect(GetTextureAspectRatio(texture))
		lo:align(0,0,-2)
		DrawTexture(texture,lo.x,lo.y,lo.w,lo.h,255,213,3,255)
	lo:finish(0,1)
	lo:advance(0,0.01,-2)
	lo:start()
		lo:size(1,0.12,-3)
		DrawRectangle(lo.x,lo.y,lo.w,lo.h,20,20,20,255)
		gInput.boxes[item] = {lo.x,lo.y,lo.w,lo.h}
		lo:size(0.965,1)
		lo:align(0.5,0,-2)
		lo:start()
			if lo:space() and text ~= "" then
				lo:start()
					SetTextFont("Arial")
					SetTextBlack()
					if gInput.focus == item or gInput.hover == item then
						SetTextColor(240,240,240,255)
					else
						SetTextColor(200,200,200,255)
					end
					SetTextHeight(lo.h*0.5)
					if MeasureText(text) > lo.w then
						SetTextAlign("R","C")
						SetTextClipping(lo.w,lo.h)
						SetTextPosition(lo.x+lo.w,lo.y+lo.h/2)
					else
						SetTextAlign("L","C")
						SetTextClipping(lo.w,lo.h)
						SetTextPosition(lo.x,lo.y+lo.h/2)
					end
					lo.w,lo.h = DrawText(text)
				lo:finish(1,0)
				lo:advance(0.002,0,-2)
			end
			if gIsTyping and IsTypingActive() and gInput.focus == item and math.mod(math.floor(GetTimer()/500),2) == 0 then
				lo:start()
					lo:size(0.004,0.7,-3)
					lo:align(nil,0.5,-2)
					DrawRectangle(lo.x,lo.y,lo.w,lo.h,240,240,240,255)
				lo:finish()
			end
		lo:finish()
	lo:finish(0,1)
	lo:advance(0,0.06,-2)
end
function F_DrawButtonUI(lo,ui,text,item)
	lo:align(0.5,0.5,-2)
	if gInput.focus == item or gInput.hover == item then
		DrawRectangle(lo.x,lo.y,lo.w,lo.h,255,213,3,255)
	else
		DrawRectangle(lo.x,lo.y,lo.w,lo.h,128,107,2,255)
	end
	gInput.boxes[item] = {lo.x,lo.y,lo.w,lo.h}
	lo:start()
		lo:padding(ui.border_line,1)
		DrawRectangle(lo.x,lo.y,lo.w,lo.h,20,20,20,255)
		if lo:space() then
			SetTextFont("Arial")
			SetTextBlack()
			if gInput.focus == item or gInput.hover == item then
				SetTextColor(240,240,240,255)
			else
				SetTextColor(200,200,200,255)
			end
			SetTextAlign("C","C")
			SetTextHeight(lo.h*0.5)
			SetTextClipping(lo.w,lo.h)
			SetTextPosition(lo.x+lo.w/2,lo.y+lo.h/2)
			DrawText(text)
		end
	lo:finish()
end

-- console patch
function IsKeyBeingPressed(key)
	if IsConsoleActive() then
		return false
	end
	return _G.IsKeyBeingPressed(key)
end
function IsKeyPressed(key)
	if IsConsoleActive() then
		return false
	end
	return _G.IsKeyPressed(key)
end

-- disable controls
RegisterLocalEventHandler("ControllerUpdating",function(c)
	if not IsGamePaused() then
		ZeroController(c)
	end
end)
RegisterLocalEventHandler("ControllersUpdated",function()
	if not IsGamePaused() then
		for c = 0,3 do
			ZeroController(c)
		end
	end
end)
