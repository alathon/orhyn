package orchestrator

import "time"

type Config struct {
	ListenAddress      string
	GameServerPort     int
	ClientPort         int
	HealthPort         int
	DefaultZoneID      string
	TransferTTL        time.Duration
	HeartbeatInterval  time.Duration
	HeartbeatTimeout   time.Duration
	LoginRetryInterval time.Duration
}

func DefaultConfig() Config {
	return Config{
		ListenAddress:      "0.0.0.0",
		GameServerPort:     9000,
		ClientPort:         9001,
		HealthPort:         9100,
		DefaultZoneID:      "mvp",
		TransferTTL:        30 * time.Second,
		HeartbeatInterval:  5 * time.Second,
		HeartbeatTimeout:   15 * time.Second,
		LoginRetryInterval: 3 * time.Second,
	}
}
