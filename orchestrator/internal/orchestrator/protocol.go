package orchestrator

const (
	TypeZoneRegister                 = "zone_register"
	TypeZoneTransferRequest          = "zone_transfer_request"
	TypePreparePlayer                = "prepare_player"
	TypePreparePlayerAck             = "prepare_player_ack"
	TypeZoneTransferResponse         = "zone_transfer_response"
	TypeHeartbeat                    = "heartbeat"
	TypeHeartbeatAck                 = "heartbeat_ack"
	TypeLoginRequest                 = "login_request"
	TypeLoginResponse                = "login_response"
	TypeLoginFailure                 = "login_failure"
	TypeCharacterSelectRequest       = "character_select_request"
	TypeCharacterSelectFailure       = "character_select_failure"
	TypeZoneRedirect                 = "zone_redirect"
	TypeCharacterDisconnectedReserve = "character_disconnected_reserve"
	TypeCharacterDisconnectedClear   = "character_disconnected_clear"
)

type Message struct {
	Type string `json:"type"`

	ZoneID         string `json:"zone_id,omitempty"`
	Address        string `json:"address,omitempty"`
	Port           int    `json:"port,omitempty"`
	MaxPlayers     int    `json:"max_players,omitempty"`
	CurrentPlayers int    `json:"current_players,omitempty"`

	FromZoneID     string      `json:"from_zone_id,omitempty"`
	ToZoneID       string      `json:"to_zone_id,omitempty"`
	PeerID         int64       `json:"peer_id,omitempty"`
	EntrySpawnPath string      `json:"entry_spawn_path,omitempty"`
	PlayerState    PlayerState `json:"player_state,omitempty"`
	TransferToken  string      `json:"transfer_token,omitempty"`
	TargetAddress  string      `json:"target_address,omitempty"`
	TargetPort     int         `json:"target_port,omitempty"`
	Accepted       bool        `json:"accepted,omitempty"`
	Reason         string      `json:"reason,omitempty"`
	PingID         int64       `json:"ping_id,omitempty"`
	Username       string      `json:"username,omitempty"`
	CharacterID    int64       `json:"character_id,omitempty"`
	DisplayName    string      `json:"display_name,omitempty"`
	VisualModelID  string      `json:"visual_model_id,omitempty"`
	ExpiresUnix    int64       `json:"expires_unix,omitempty"`
	Characters     []Character `json:"characters,omitempty"`
}

type PlayerState struct {
	PosX          float64 `json:"pos_x,omitempty"`
	PosY          float64 `json:"pos_y,omitempty"`
	PosZ          float64 `json:"pos_z,omitempty"`
	VelX          float64 `json:"vel_x,omitempty"`
	VelY          float64 `json:"vel_y,omitempty"`
	VelZ          float64 `json:"vel_z,omitempty"`
	RotY          float64 `json:"rot_y,omitempty"`
	HP            int     `json:"hp,omitempty"`
	MaxHP         int     `json:"max_hp,omitempty"`
	Mana          int     `json:"mana,omitempty"`
	MaxMana       int     `json:"max_mana,omitempty"`
	Stamina       int     `json:"stamina,omitempty"`
	MaxStamina    int     `json:"max_stamina,omitempty"`
	Condition     string  `json:"condition,omitempty"`
	DisplayName   string  `json:"display_name,omitempty"`
	VisualModelID string  `json:"visual_model_id,omitempty"`
	CharacterID   int64   `json:"character_id,omitempty"`
}

type Character struct {
	CharacterID int64  `json:"character_id"`
	DisplayName string `json:"display_name"`
	ZoneID      string `json:"zone_id"`
	ModelName   string `json:"model_name"`
	Level       int    `json:"level"`
}
