class_name LogoutRefreshScreen
extends Control

@onready var _flow_state: ClientFlowState = get_node("/root/ClientFlow") as ClientFlowState
@onready var _login_client: LoginClient = %LoginClient


func _ready() -> void:
	_flow_state.submit_background_login_refresh(_login_client)
