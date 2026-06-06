package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"movement-test/orchestrator/internal/orchestrator"
)

func main() {
	cfg := orchestrator.DefaultConfig()
	flag.StringVar(&cfg.ListenAddress, "listen-address", cfg.ListenAddress, "address to bind")
	flag.IntVar(&cfg.GameServerPort, "game-server-port", cfg.GameServerPort, "port for zone/game server websocket connections")
	flag.IntVar(&cfg.ClientPort, "client-port", cfg.ClientPort, "port for client login websocket connections")
	flag.IntVar(&cfg.HealthPort, "health-port", cfg.HealthPort, "port for health and readiness checks")
	flag.StringVar(&cfg.DefaultZoneID, "default-zone", cfg.DefaultZoneID, "zone id used for initial character entry")
	flag.DurationVar(&cfg.TransferTTL, "transfer-ttl", cfg.TransferTTL, "transfer token lifetime")
	flag.DurationVar(&cfg.HeartbeatInterval, "heartbeat-interval", cfg.HeartbeatInterval, "game server heartbeat interval")
	flag.DurationVar(&cfg.HeartbeatTimeout, "heartbeat-timeout", cfg.HeartbeatTimeout, "game server heartbeat timeout")
	flag.DurationVar(&cfg.LoginRetryInterval, "login-retry-interval", cfg.LoginRetryInterval, "delay before retrying queued character selections")
	flag.Parse()

	svc := orchestrator.NewService(cfg, log.New(os.Stdout, "", log.LstdFlags|log.LUTC))

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := svc.Start(ctx); err != nil {
		log.Fatalf("orchestrator stopped: %v", err)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := svc.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown error: %v", err)
	}
}
