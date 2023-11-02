-- derpy's script server: account system - derpy54320 & SWEGTA
api = GetScriptNetworkTable()

-- globals
-- gAccounts is setup by F_Load
gPlayers = {} -- see account:signup
gPlayerIps = {}
gProtectFile = false -- failed to save, so prevent future backups

-- api
function api.all_players() -- returns an iterator for all signed in players
	local player,pd
	return function()
		player,pd = next(gPlayers,player)
		while player do
			if pd.account then
				return player,pd.username
			end
			player,pd = next(gPlayers,player)
		end
	end
end
function api.get_player_username(player) -- can also be used to check if a player signed in
	local pd = gPlayers[player]
	if pd and pd.account then
		return pd.username
	end
end
function api.is_player_role(player,role)
	local pd = gPlayers[player]
	if pd and pd.account and pd.account.roles then
		for _,v in ipairs(pd.account.roles) do
			if v == role then
				return true
			end
		end
	end
	return false
end

-- server commands
SetCommand("check_account",function(user)
	local ad = gAccounts[user]
	if ad then
		local output
		for id,pd in pairs(gPlayers) do
			if pd.account == ad then
				output = "\""..GetPlayerName(id).."\" (id: "..id..", ip: "..GetPlayerIp(id)..")"
				break
			end
		end
		PrintOutput("Account exists.\n - player: "..(output or "not signed in").."\n - roles: "..(ad.roles and table.concat(ad.roles,", ") or "<none>"))
	elseif user then
		PrintOutput("Account does not exist.")
	else
		PrintWarning("No username specified.")
	end
end,false,"Usage: check_account <user>\nCheck if an account exists, is being used, and what roles it has.")
SetCommand("check_accounts",function(limit)
	local list = {}
	local count = 0
	local accounts = ""
	local bytes = string.len(PackTable(gAccounts))
	for user in pairs(gAccounts) do
		count = count + 1
		list[count] = user
	end
	if bytes < 1024 then
		bytes = bytes.." B"
	else
		bytes = string.format("~%.0f KiB",bytes)
	end
	limit = tonumber(limit)
	if limit then
		table.sort(list,function(a,b)
			return string.lower(a) < string.lower(b)
		end)
		for i,user in ipairs(list) do
			if i > limit then
				break
			end
			accounts = accounts.."\n"..user
		end
	end
	PrintOutput("There are "..count.." accounts, taking up "..bytes.." in accounts.bin."..accounts)
end,false,"Usage: check_accounts [count]\nPrint statistics related to accounts, and optionally list accounts in alphabetical order.")
SetCommand("delete_account",function(user)
	local backup = gAccounts[user]
	if not backup then
		user = F_GetUsernameFromString(user)
		backup = gAccounts[user]
	end
	if backup then
		gAccounts[user] = nil
		if F_Backup() and F_Save() then
			if F_LogoutAccount(backup) then
				PrintOutput("Deleted account! Consider restarting \"account\" scripts to let them sign back up.")
			else
				PrintOutput("Deleted account!")
			end
			if not RunLocalEvent("account:deleteAccount",user) then
				PrintWarning("At least one script failed to delete account data, try to /verify_accounts.")
			end
		else
			gAccounts[user] = backup
		end
	else
		PrintWarning("Account does not exist.")
	end
end,false,"Usage: delete_account <user>\nDelete a specific account.")
SetCommand("demote_account",function(user,role)
	local ad = gAccounts[user]
	if not ad then
		user = F_GetUsernameFromString(user)
		ad = gAccounts[user]
	end
	if ad then
		local backup = ad.roles and {unpack(ad.roles)}
		if not (backup and F_RemoveRole(ad,role)) then
			PrintWarning("Account does not have role.")
			return
		end
		if F_Backup() and F_Save() then
			for id,pd in pairs(gPlayers) do
				if pd.account == ad then
					RunLocalEvent("account:playerUpdatedRoles",id)
					break
				end
			end
			PrintOutput("Demoted account!")
		else
			ad.roles = backup
		end
	else
		PrintWarning("Account does not exist.")
	end
end,false,"Usage: demote_account <user> [role]\nStrip an account of a specific role or of all roles.")
function F_RemoveRole(ad,role)
	if ad.roles then
		if not role then
			ad.roles = nil
			return true
		end
		for i,v in ipairs(ad.roles) do
			if v == role then
				table.remove(ad.roles,i)
				return true
			end
		end
	end
	return false
end
SetCommand("promote_account",function(user,role,trap)
	local ad = gAccounts[user]
	if not ad then
		user = F_GetUsernameFromString(user)
		ad = gAccounts[user]
	end
	if not role then
		PrintWarning("No role specified.")
	elseif string.find(role,"[^%w_]") then
		PrintWarning("Role contains a forbidden character.")
	elseif trap then
		PrintWarning("Role can only be one word.")
	elseif ad then
		local backup = F_BackupAccount(ad)
		role = string.lower(role)
		if ad.roles then
			for _,v in ipairs(ad.roles) do
				if v == role then
					PrintWarning("Account already has role.")
					return
				end
			end
		else
			ad.roles = {}
		end
		table.insert(ad.roles,role)
		table.sort(ad.roles)
		if F_Backup() and F_Save() then
			for id,pd in pairs(gPlayers) do
				if pd.account == ad then
					RunLocalEvent("account:playerUpdatedRoles",id)
					break
				end
			end
			PrintOutput("Promoted account!")
		else
			gAccounts[user] = backup
		end
	else
		PrintWarning("Account does not exist.")
	end
end,false,"Usage: promote_account <user> <role>\nGive an account some role that other scripts can check for.")
SetCommand("reset_accounts",function() -- use this instead of trying to delete accounts.bin
	local backup = gAccounts
	gAccounts = {} -- [user] = data (see F_CreateAccount)
	if F_Backup() and F_Save() then
		local failed = false
		for id,pd in pairs(gPlayers) do
			F_LogoutPlayer(id,pd)
		end
		if next(gPlayers) then
			PrintOutput("Reset all account data! Consider restarting \"account\" scripts to let players sign back in.")
		else
			PrintOutput("Reset all account data!")
		end
		for user in pairs(backup) do
			if not RunLocalEvent("account:deleteAccount",user) then
				failed = true
			end
		end
		if failed then
			PrintWarning("At least one script failed to delete account data, try to /verify_accounts.")
		end
	else
		gAccounts = backup
	end
end,false,"Usage: reset_accounts\nReset all account data, totally destroying every account.")
SetCommand("unlimit_accounts",function(player) -- use when you or an admin must make many accounts at once
	local pd = gPlayers[tonumber(player)]
	if pd then
		pd.unlimited = true
	elseif player then
		PrintWarning("Unknown player ID, try again without arguments to list players.")
	elseif next(gPlayers) then
		local list = {}
		for id in pairs(gPlayers) do
			table.insert(list,{id,GetPlayerIp(id).." / \""..GetPlayerName(id).."\""})
		end
		table.sort(list,function(a,b)
			return a[1] < b[1]
		end)
		for i,v in ipairs(list) do
			list[i] = "("..v[1]..") "..v[2]
		end
		PrintWarning("Use one of the following player IDs with this command.\n\t"..table.concat(list,"\n\t"))
	else
		PrintWarning("No players are currently in the server.")
	end
end,false,"Usage: unlimit_accounts <player_id>\nTemporarily allow a player to make as many accounts as they want.")
SetCommand("verify_accounts",function()
	if RunLocalEvent("account:verifyAccounts",function(check)
		return gAccounts[check] ~= nil
	end) then
		PrintOutput("Verified accounts!")
	else
		PrintWarning("At least one script failed to verify account data.")
	end
end,false,"Usage: verify_accounts\nTell all running scripts to verify their account data and cleanup anything related to deleted accounts.")

-- load / save
function F_Load()
	local status,result = pcall(LoadTable,"accounts.bin")
	if status then
		gAccounts = result
	else
		PrintError("Failed to load account data. If this issue persists, accounts.bin may be corrupted.",0)
		StopCurrentScriptCollection()
	end
end
function F_Save()
	-- after changing something in gAccounts, you should call F_Backup then F_Save if the backup was successful
	-- if either of those functions fail, you should revert any changes you made
	if pcall(function()
		SaveTable("accounts.bin",gAccounts)
	end) then
		return true
	end
	PrintError("Failed to save account data. No account data will be saved from this point, and you should stop the server to restore backup.bin by renaming it to accounts.bin.")
	gProtectFile = true
	return false
end
function F_Backup()
	if not gProtectFile then
		if pcall(function()
			local source,bytes = OpenFile("accounts.bin","rb")
			local destination = OpenFile("backup.bin","wb")
			WriteFile(destination,ReadFile(source,bytes))
			CloseFile(destination)
			CloseFile(source)
		end) then
			return true
		end
		PrintWarning("Failed to backup account data before saving. The operation that was meant to be saved will be reverted.")
	end
	return false
end

-- player connection
RegisterNetworkEventHandler("account:started",function(player)
	local pd = gPlayers[gPlayer]
	local ip = GetPlayerIp(player)
	local cfg = GetScriptConfig()
	if not gPlayerIps[ip] then
		local data = {
			signups = GetConfigNumber(cfg,"max_signups_per_ip"), -- if not nil, a limit for signups
			logins = GetConfigNumber(cfg,"max_logins_per_ip"), -- if not nil, a limit for logins
		}
		gPlayerIps[ip] = data
	end
	if pd then
		F_LogoutPlayer(player,pd) -- in case they double sign in because of script timing
	end
	gPlayers[player] = {
		-- account = {} when they are logged in
		-- username = "username" when they are logged in
		-- unlimited = true when /unlimit_accounts is used
	}
end)
RegisterLocalEventHandler("PlayerDropped",function(player)
	local pd = gPlayers[player]
	if pd then
		gPlayers[player] = nil
		F_LogoutPlayer(player,pd)
	end
end)

-- account signup
RegisterNetworkEventHandler("account:signup",function(player,user,hash,salt)
	if type(user) ~= "string" or type(hash) ~= "userdata" or type(salt) ~= "string" then
		KickPlayer(player,"bad signup arguments")
	elseif gPlayers[player] then
		local status,reason = F_CanPlayerSignup(player)
		if status then
			status,reason = F_CanUsernameSignup(user)
			if status then
				status = F_CreateAccount(player,user,hash,salt)
				if not status then
					reason = "Server failed, try again later."
				end
			end
		end
		if status then
			if GetConfigBoolean(GetScriptConfig(),"log_user_signup") then
				PrintOutput("\""..GetPlayerName(player).."\" (id: "..player..", ip: "..GetPlayerIp(player)..") has created the account \""..user.."\".")
			end
			SendNetworkEvent(player,"account:signup") -- no argument = success
		else
			SendNetworkEvent(player,"account:signup",reason) -- argument = failure
		end
	end
end)
function F_CanPlayerSignup(player)
	if not gPlayers[player].unlimited then
		local data = gPlayerIps[GetPlayerIp(player)]
		if data.signups and data.signups < 1 then
			return false,"You may not create more accounts, use an existing one."
		end
	end
	return true
end
function F_CanUsernameSignup(user)
	local cfg = GetScriptConfig()
	local max_length = GetConfigNumber(cfg,"max_username_length")
	local char_filter = GetConfigString(cfg,"use_character_filter")
	local prof_filter = GetConfigNumber(cfg,"use_profanity_filter")
	if F_GetUsernameFromString(user) then
		return false,"Username is taken."
	elseif string.len(user) < 1 or (max_length and string.len(user) > max_length) or (char_filter and string.find(user,char_filter)) then
		return false,"Username is not allowed."
	elseif prof_filter then
		if not net.profanity then
			PrintWarning("Signup failed because \"profanity\" scripts are not running.")
			return false,"Server failed, try again later."
		elseif net.profanity.is_dirty_str(user,prof_filter) then
			return false,"Username is not allowed."
		end
	end
	return true
end
function F_CreateAccount(player,user,hash,salt)
	local ip = GetPlayerIp(player)
	local ad = {ip,hash,salt} -- for storage efficiency, these 3 basic things are put into the array part ([1], [2], and [3])
	if not next(gAccounts) then
		local roles = {}
		for role in AllConfigStrings(GetScriptConfig(),"promote_1st_account") do
			table.insert(roles,role)
		end
		if roles[1] then
			ad.roles = roles
		end
	end
	gAccounts[user] = ad
	if F_Backup() and F_Save() then
		local data = gPlayerIps[ip]
		if data.signups then
			local cooldown = GetConfigNumber(GetScriptConfig(),"max_signups_cooldown")
			data.signups = data.signups - 1
			if cooldown then
				CreateThread(function()
					Wait(cooldown * 60000)
					data.signups = data.signups + 1
				end)
			end
		end
		return true
	end
	PrintWarning("Signup failed because the data could not be saved.")
	gAccounts[user] = nil
	return false
end

-- account login
RegisterNetworkEventHandler("account:login",function(player,user,hash)
	-- the client first sends this event WITHOUT a pass, then again WITH a pass after the server gives salt.
	if type(user) ~= "string" or (hash ~= nil and type(hash) ~= "userdata") then
		KickPlayer(player,"bad login arguments")
	elseif gPlayers[player] then
		local ad = gAccounts[user]
		if not ad then
			user = F_GetUsernameFromString(user)
			ad = gAccounts[user]
		end
		if hash then
			local status,reason = F_CanPlayerLogin(player,user,hash)
			if status then
				F_LoginPlayer(player,user)
				if GetConfigBoolean(GetScriptConfig(),"log_user_signup") then
					PrintOutput("\""..GetPlayerName(player).."\" (id: "..player..", ip: "..GetPlayerIp(player)..") signed into \""..user.."\".")
				end
				SendNetworkEvent(player,"account:login",true) -- no reason = success
				SendNetworkEvent(player,"account:setuser",user)
				RunLocalEvent("account:playerSignedIn",player,user)
				RunLocalEvent("account:playerUpdatedRoles",player)
			else
				SendNetworkEvent(player,"account:login",true,reason) -- reason = failure
			end
		elseif ad then
			SendNetworkEvent(player,"account:login",false,ad[3]) -- give them the salt so they can hash the password
		else
			SendNetworkEvent(player,"account:login",false,"") -- account doesn't exist, but give a salt anyway so they don't know
		end
	end
end)
function F_CanPlayerLogin(player,user,hash)
	local ad = gAccounts[user]
	local data = gPlayerIps[GetPlayerIp(player)]
	if data.logins and data.logins < 1 then
		return false,"You have been locked out, try again later."
	elseif gPlayers[player].account then
		return false,"You are already signed in."
	end
	if not ad or hash ~= ad[2] then
		F_FailedLogin(data)
		if data.logins then
			if data.logins == 1 then
				return false,"Wrong username or password, you have 1 attempt left."
			end
			return false,"Wrong username or password, you have "..data.logins.." attempts left."
		end
		return false,"Wrong username or password, try again."
	end
	for _,pd in pairs(gPlayers) do
		if pd.account == ad then
			F_FailedLogin(data)
			return false,"Account already in use."
		end
	end
	return true
end
function F_FailedLogin(data)
	if data.logins then -- consume login attempt
		local cooldown = GetConfigNumber(GetScriptConfig(),"max_logins_cooldown")
		data.logins = data.logins - 1
		if cooldown then
			CreateThread(function()
				Wait(cooldown * 60000)
				data.logins = data.logins + 1
			end)
		end
	end
end
function F_LoginPlayer(player,user)
	local ad = gAccounts[user]
	local pd = gPlayers[player]
	if pd.account ~= ad then
		pd.account = ad
		pd.username = user
		-- account:playerSignedIn is run after account:setuser so any sent network events will be AFTER the account UI is turned off
	end
end

-- account utility
function F_BackupAccount(ad)
	local result = {}
	for k,v in pairs(ad) do
		if type(v) == "table" then
			result[k] = F_BackupAccount(v)
		else
			result[k] = v
		end
	end
	return result
end
function F_LogoutAccount(ad)
	for id,pd in pairs(gPlayers) do
		if pd.account == ad then
			F_LogoutPlayer(id,pd)
			return true
		end
	end
	return false
end
function F_LogoutPlayer(player,pd,skip)
	if not skip and gPlayers[player] then
		SendNetworkEvent(player,"account:setuser")
	end
	if pd.account then
		pd.account = nil
		pd.username = nil
		RunLocalEvent("account:playerSignedOut",player)
		if gPlayers[player] then
			RunLocalEvent("account:playerUpdatedRoles",player)
		end
	end
end
function F_GetUsernameFromString(str) -- usernames *are* case-sensitive in Lua, but should usually be in-sensitive to the user
	str = string.lower(str)
	for user in pairs(gAccounts) do
		if string.lower(user) == str then
			return user
		end
	end
end

-- script cleanup
RegisterLocalEventHandler("ScriptShutdown",function(script)
	if script == GetCurrentScript() then
		RunLocalEvent("account:scriptStopping")
		for id,pd in pairs(gPlayers) do
			F_LogoutPlayer(id,pd)
		end
	end
end)

-- initialize
F_Load()
