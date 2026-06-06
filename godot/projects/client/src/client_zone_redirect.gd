class_name ClientZoneRedirect
extends RefCounted

var zone_id: String = ""
var address: String = ""
var port: int = 0
var transfer_token: String = ""

static func create(
	new_zone_id: String,
	new_address: String,
	new_port: int,
	new_transfer_token: String
) -> ClientZoneRedirect:
	var redirect: ClientZoneRedirect = ClientZoneRedirect.new()
	redirect.zone_id = new_zone_id
	redirect.address = new_address
	redirect.port = new_port
	redirect.transfer_token = new_transfer_token
	return redirect
