package main

import (
	"container/heap"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sync/atomic"
	"syscall"
	"time"
)

type directionProfile struct {
	Delay       time.Duration `json:"delay"`
	Jitter      time.Duration `json:"jitter"`
	LossPercent float64       `json:"loss_percent"`
}

type proxyConfig struct {
	ListenAddress string           `json:"listen_address"`
	ListenPort    int              `json:"listen_port"`
	TargetAddress string           `json:"target_address"`
	TargetPort    int              `json:"target_port"`
	Upstream      directionProfile `json:"upstream"`
	Downstream    directionProfile `json:"downstream"`
	Seed          int64            `json:"seed"`
	ReadyFile     string           `json:"ready_file,omitempty"`
	StatsFile     string           `json:"stats_file,omitempty"`
}

type directionCounters struct {
	received   atomic.Uint64
	forwarded  atomic.Uint64
	dropped    atomic.Uint64
	sendErrors atomic.Uint64
}

type counterSnapshot struct {
	Received   uint64 `json:"received"`
	Forwarded  uint64 `json:"forwarded"`
	Dropped    uint64 `json:"dropped"`
	SendErrors uint64 `json:"send_errors"`
}

type proxyStats struct {
	StartedAt  string          `json:"started_at"`
	StoppedAt  string          `json:"stopped_at"`
	Client     string          `json:"client,omitempty"`
	Config     proxyConfig     `json:"config"`
	Upstream   counterSnapshot `json:"upstream"`
	Downstream counterSnapshot `json:"downstream"`
}

type packetDirection int

const (
	upstream packetDirection = iota
	downstream
)

type scheduledPacket struct {
	payload   []byte
	dest      *net.UDPAddr
	direction packetDirection
	sendAt    time.Time
	sequence  uint64
}

type packetQueue []scheduledPacket

func (q packetQueue) Len() int { return len(q) }

func (q packetQueue) Less(i, j int) bool {
	if q[i].sendAt.Equal(q[j].sendAt) {
		return q[i].sequence < q[j].sequence
	}
	return q[i].sendAt.Before(q[j].sendAt)
}

func (q packetQueue) Swap(i, j int) { q[i], q[j] = q[j], q[i] }

func (q *packetQueue) Push(value any) {
	*q = append(*q, value.(scheduledPacket))
}

func (q *packetQueue) Pop() any {
	old := *q
	last := len(old) - 1
	value := old[last]
	*q = old[:last]
	return value
}

type udpProxy struct {
	config     proxyConfig
	connection *net.UDPConn
	target     *net.UDPAddr
	client     *net.UDPAddr
	random     *rand.Rand
	packets    chan scheduledPacket
	sequence   uint64
	startedAt  time.Time
	upstream   directionCounters
	downstream directionCounters
}

func main() {
	config := parseFlags()
	if err := validateConfig(config); err != nil {
		log.Fatal(err)
	}

	proxy, err := newUDPProxy(config)
	if err != nil {
		log.Fatal(err)
	}

	configJSON, _ := json.Marshal(config)
	log.Printf("UDP impairment proxy ready: %s", configJSON)
	if err := writeJSON(config.ReadyFile, map[string]any{
		"ok":             true,
		"listen_address": proxy.connection.LocalAddr().String(),
		"target_address": proxy.target.String(),
		"seed":           config.Seed,
	}); err != nil {
		proxy.connection.Close()
		log.Fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	err = proxy.run(ctx)
	stop()

	if statsErr := writeJSON(config.StatsFile, proxy.stats()); statsErr != nil {
		log.Printf("could not write proxy stats: %v", statsErr)
	}
	statsJSON, _ := json.Marshal(proxy.stats())
	log.Printf("UDP impairment proxy stopped: %s", statsJSON)
	if err != nil && !errors.Is(err, net.ErrClosed) {
		log.Fatal(err)
	}
}

func parseFlags() proxyConfig {
	config := proxyConfig{}
	flag.StringVar(&config.ListenAddress, "listen-address", "127.0.0.1", "address on which to accept client UDP datagrams")
	flag.IntVar(&config.ListenPort, "listen-port", 0, "port on which to accept client UDP datagrams")
	flag.StringVar(&config.TargetAddress, "target-address", "127.0.0.1", "zone server UDP address")
	flag.IntVar(&config.TargetPort, "target-port", 0, "zone server UDP port")
	flag.DurationVar(&config.Upstream.Delay, "up-delay", 0, "base client-to-server delay")
	flag.DurationVar(&config.Upstream.Jitter, "up-jitter", 0, "maximum client-to-server delay variation")
	flag.Float64Var(&config.Upstream.LossPercent, "up-loss-percent", 0, "client-to-server packet loss percentage")
	flag.DurationVar(&config.Downstream.Delay, "down-delay", 0, "base server-to-client delay")
	flag.DurationVar(&config.Downstream.Jitter, "down-jitter", 0, "maximum server-to-client delay variation")
	flag.Float64Var(&config.Downstream.LossPercent, "down-loss-percent", 0, "server-to-client packet loss percentage")
	flag.Int64Var(&config.Seed, "seed", 1, "deterministic random seed")
	flag.StringVar(&config.ReadyFile, "ready-file", "", "optional JSON readiness file")
	flag.StringVar(&config.StatsFile, "stats-file", "", "optional JSON shutdown statistics file")
	flag.Parse()
	return config
}

func validateConfig(config proxyConfig) error {
	if config.ListenPort < 0 || config.ListenPort > 65535 {
		return fmt.Errorf("listen port must be between 0 and 65535")
	}
	if config.TargetPort <= 0 || config.TargetPort > 65535 {
		return fmt.Errorf("target port must be between 1 and 65535")
	}
	if config.Upstream.Delay < 0 || config.Downstream.Delay < 0 {
		return fmt.Errorf("delay cannot be negative")
	}
	if config.Upstream.Jitter < 0 || config.Downstream.Jitter < 0 {
		return fmt.Errorf("jitter cannot be negative")
	}
	if config.Upstream.LossPercent < 0 || config.Upstream.LossPercent > 100 ||
		config.Downstream.LossPercent < 0 || config.Downstream.LossPercent > 100 {
		return fmt.Errorf("loss percentage must be between 0 and 100")
	}
	return nil
}

func newUDPProxy(config proxyConfig) (*udpProxy, error) {
	listen, err := net.ResolveUDPAddr("udp", net.JoinHostPort(config.ListenAddress, fmt.Sprint(config.ListenPort)))
	if err != nil {
		return nil, fmt.Errorf("resolve listen address: %w", err)
	}
	target, err := net.ResolveUDPAddr("udp", net.JoinHostPort(config.TargetAddress, fmt.Sprint(config.TargetPort)))
	if err != nil {
		return nil, fmt.Errorf("resolve target address: %w", err)
	}
	connection, err := net.ListenUDP("udp", listen)
	if err != nil {
		return nil, fmt.Errorf("listen for UDP datagrams: %w", err)
	}

	return &udpProxy{
		config:     config,
		connection: connection,
		target:     target,
		random:     rand.New(rand.NewSource(config.Seed)),
		packets:    make(chan scheduledPacket, 4096),
		startedAt:  time.Now().UTC(),
	}, nil
}

func (p *udpProxy) run(ctx context.Context) error {
	runCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	schedulerDone := make(chan struct{})
	go func() {
		defer close(schedulerDone)
		p.schedule(runCtx)
	}()
	go func() {
		<-runCtx.Done()
		p.connection.Close()
	}()

	buffer := make([]byte, 64*1024)
	for {
		size, source, err := p.connection.ReadFromUDP(buffer)
		if err != nil {
			cancel()
			<-schedulerDone
			if ctx.Err() != nil {
				return nil
			}
			return err
		}

		direction, destination, profile, counters, ok := p.route(source)
		if !ok {
			continue
		}
		counters.received.Add(1)
		if shouldDrop(profile.LossPercent, p.random) {
			counters.dropped.Add(1)
			continue
		}

		payload := append([]byte(nil), buffer[:size]...)
		p.sequence++
		packet := scheduledPacket{
			payload:   payload,
			dest:      cloneUDPAddr(destination),
			direction: direction,
			sendAt:    time.Now().Add(impairedDelay(profile, p.random)),
			sequence:  p.sequence,
		}
		select {
		case p.packets <- packet:
		case <-runCtx.Done():
			<-schedulerDone
			return nil
		}
	}
}

func (p *udpProxy) route(source *net.UDPAddr) (packetDirection, *net.UDPAddr, directionProfile, *directionCounters, bool) {
	if sameUDPAddr(source, p.target) {
		if p.client == nil {
			return downstream, nil, p.config.Downstream, &p.downstream, false
		}
		return downstream, p.client, p.config.Downstream, &p.downstream, true
	}

	if p.client == nil {
		p.client = cloneUDPAddr(source)
		log.Printf("learned client endpoint: %s", p.client)
	} else if !sameUDPAddr(source, p.client) {
		log.Printf("ignoring datagram from unexpected client endpoint: %s", source)
		return upstream, nil, p.config.Upstream, &p.upstream, false
	}
	return upstream, p.target, p.config.Upstream, &p.upstream, true
}

func (p *udpProxy) schedule(ctx context.Context) {
	queue := &packetQueue{}
	heap.Init(queue)

	for {
		if queue.Len() == 0 {
			select {
			case packet := <-p.packets:
				heap.Push(queue, packet)
			case <-ctx.Done():
				return
			}
			continue
		}

		next := (*queue)[0]
		wait := time.Until(next.sendAt)
		if wait <= 0 {
			heap.Pop(queue)
			p.forward(next)
			continue
		}

		timer := time.NewTimer(wait)
		select {
		case packet := <-p.packets:
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			heap.Push(queue, packet)
		case <-timer.C:
		case <-ctx.Done():
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			return
		}
	}
}

func (p *udpProxy) forward(packet scheduledPacket) {
	_, err := p.connection.WriteToUDP(packet.payload, packet.dest)
	counters := &p.upstream
	if packet.direction == downstream {
		counters = &p.downstream
	}
	if err != nil {
		counters.sendErrors.Add(1)
		log.Printf("could not forward UDP datagram to %s: %v", packet.dest, err)
		return
	}
	counters.forwarded.Add(1)
}

func (p *udpProxy) stats() proxyStats {
	client := ""
	if p.client != nil {
		client = p.client.String()
	}
	return proxyStats{
		StartedAt:  p.startedAt.Format(time.RFC3339Nano),
		StoppedAt:  time.Now().UTC().Format(time.RFC3339Nano),
		Client:     client,
		Config:     p.config,
		Upstream:   snapshotCounters(&p.upstream),
		Downstream: snapshotCounters(&p.downstream),
	}
}

func snapshotCounters(counters *directionCounters) counterSnapshot {
	return counterSnapshot{
		Received:   counters.received.Load(),
		Forwarded:  counters.forwarded.Load(),
		Dropped:    counters.dropped.Load(),
		SendErrors: counters.sendErrors.Load(),
	}
}

func shouldDrop(lossPercent float64, random *rand.Rand) bool {
	if lossPercent <= 0 {
		return false
	}
	if lossPercent >= 100 {
		return true
	}
	return random.Float64()*100 < lossPercent
}

func impairedDelay(profile directionProfile, random *rand.Rand) time.Duration {
	if profile.Jitter == 0 {
		return profile.Delay
	}
	span := int64(profile.Jitter)*2 + 1
	offset := time.Duration(random.Int63n(span)) - profile.Jitter
	delay := profile.Delay + offset
	if delay < 0 {
		return 0
	}
	return delay
}

func sameUDPAddr(left, right *net.UDPAddr) bool {
	return left != nil && right != nil && left.Port == right.Port && left.IP.Equal(right.IP)
}

func cloneUDPAddr(address *net.UDPAddr) *net.UDPAddr {
	if address == nil {
		return nil
	}
	return &net.UDPAddr{
		IP:   append(net.IP(nil), address.IP...),
		Port: address.Port,
		Zone: address.Zone,
	}
}

func writeJSON(path string, value any) error {
	if path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create directory for %s: %w", path, err)
	}
	encoded, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("encode %s: %w", path, err)
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(path, encoded, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}
