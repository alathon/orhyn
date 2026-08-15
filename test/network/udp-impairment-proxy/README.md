# UDP Impairment Proxy

This test-only executable forwards raw UDP datagrams between one client and one
server endpoint. It applies independent upstream and downstream delay, jitter,
and deterministic packet loss beneath ENet, allowing ENet's own reliability and
ordering behavior to remain under test.

Run one proxy per client. The first non-server endpoint to send a datagram is
treated as that proxy's client for the lifetime of the process.

The impaired E2E runner builds and configures the proxy automatically:

```sh
make e2e-impaired
```

Use `go run . --help` in this directory for individual flags. `--ready-file`
and `--stats-file` produce JSON artifacts for process coordination and failure
diagnostics.
