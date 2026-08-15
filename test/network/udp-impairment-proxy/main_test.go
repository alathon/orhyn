package main

import (
	"context"
	"math/rand"
	"net"
	"testing"
	"time"
)

func TestImpairedDelayIsDeterministicAndBounded(t *testing.T) {
	profile := directionProfile{
		Delay:  200 * time.Millisecond,
		Jitter: 40 * time.Millisecond,
	}
	left := rand.New(rand.NewSource(42))
	right := rand.New(rand.NewSource(42))

	for range 100 {
		leftDelay := impairedDelay(profile, left)
		rightDelay := impairedDelay(profile, right)
		if leftDelay != rightDelay {
			t.Fatalf("same seed produced different delays: %s != %s", leftDelay, rightDelay)
		}
		if leftDelay < 160*time.Millisecond || leftDelay > 240*time.Millisecond {
			t.Fatalf("delay outside expected bounds: %s", leftDelay)
		}
	}
}

func TestShouldDropBoundaryPercentages(t *testing.T) {
	random := rand.New(rand.NewSource(1))
	if shouldDrop(0, random) {
		t.Fatal("zero percent loss dropped a packet")
	}
	if !shouldDrop(100, random) {
		t.Fatal("one hundred percent loss forwarded a packet")
	}
}

func TestUDPProxyForwardsBothDirections(t *testing.T) {
	target, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0})
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()

	proxy, err := newUDPProxy(proxyConfig{
		ListenAddress: "127.0.0.1",
		TargetAddress: "127.0.0.1",
		TargetPort:    target.LocalAddr().(*net.UDPAddr).Port,
		Seed:          7,
	})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- proxy.run(ctx)
	}()

	client, err := net.DialUDP("udp", nil, proxy.connection.LocalAddr().(*net.UDPAddr))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	defer client.Close()
	deadline := time.Now().Add(2 * time.Second)
	client.SetDeadline(deadline)
	target.SetDeadline(deadline)

	if _, err := client.Write([]byte("upstream")); err != nil {
		cancel()
		t.Fatal(err)
	}
	buffer := make([]byte, 128)
	size, proxyAddress, err := target.ReadFromUDP(buffer)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	if got := string(buffer[:size]); got != "upstream" {
		cancel()
		t.Fatalf("target received %q", got)
	}

	if _, err := target.WriteToUDP([]byte("downstream"), proxyAddress); err != nil {
		cancel()
		t.Fatal(err)
	}
	size, err = client.Read(buffer)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	if got := string(buffer[:size]); got != "downstream" {
		cancel()
		t.Fatalf("client received %q", got)
	}

	cancel()
	if err := <-done; err != nil {
		t.Fatalf("proxy shutdown failed: %v", err)
	}
	stats := proxy.stats()
	if stats.Upstream.Forwarded != 1 || stats.Downstream.Forwarded != 1 {
		t.Fatalf("unexpected forwarding stats: %+v", stats)
	}
}
