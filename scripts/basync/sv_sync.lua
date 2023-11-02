-- server sync
basync = GetScriptNetworkTable()

-- globals
gPlayers = {}
gNetIds = {}

-- network id functions
function basync.generate_net_id(object)
	local id = table.getn(gNetIds) + 1
	gNetIds[id] = object
	return id
end
function basync.ping_net_id(id) -- call after sending the net id to clients to make them respond to the new net id before they can use it
	for player,unknown in pairs(gPlayers) do
		SendNetworkEvent(player,"basync:networkId",id)
		unknown[id] = true
	end
end
function basync.get_net_id(player,id)
	local unknown = gPlayers[player]
	if unknown and not unknown[id] then
		return gNetIds[id]
	end
end
function basync.release_net_id(id)
	for _,unknown in pairs(gPlayers) do
		unknown[id] = nil
	end
	gNetIds[id] = nil
end

-- player network events
RegisterNetworkEventHandler("basync:initPlayer",function(player)
	SendNetworkEvent(player,"basync:setRate",GetServerHz())
	gPlayers[player] = {}
end)
RegisterNetworkEventHandler("basync:networkId",function(player,id)
	local unknown = gPlayers[player]
	if unknown then
		unknown[id] = nil
	end
end)
RegisterNetworkEventHandler("basync:kickMe",function(player,reason)
	if gPlayers[player] then
		if type(reason) == "string" then
			return KickPlayer(player,"your script misbehaved ("..reason..")")
		end
		return KickPlayer(player,"your script misbehaved (?)")
	end
end)
RegisterLocalEventHandler("PlayerDropped",function(player)
	gPlayers[player] = nil
end)
