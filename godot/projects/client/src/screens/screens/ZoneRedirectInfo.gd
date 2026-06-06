class_name ZoneRedirectInfo
extends RefCounted

const Proto = preload("res://projects/common/src/proto/packets.gd")

var zone_id: String = ""
var address: String = ""
var port: int = 0
var transfer_token: String = ""


static func create(
		new_zone_id: String,
		new_address: String,
		new_port: int,
		new_transfer_token: String) -> ZoneRedirectInfo:
	var info: ZoneRedirectInfo = ZoneRedirectInfo.new()
	info.zone_id = new_zone_id
	info.address = new_address
	info.port = new_port
	info.transfer_token = new_transfer_token
	return info


static func from_proto(proto: Proto.ZoneRedirect) -> ZoneRedirectInfo:
	if proto == null:
		return null
	return ZoneRedirectInfo.create(
			proto.get_zone_id(),
			proto.get_address(),
			int(proto.get_port()),
			proto.get_transfer_token())
