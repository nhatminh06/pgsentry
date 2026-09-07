# HAProxy or writable route unavailable

## Meaning and impact

`PgSentryHAProxyDown` means the metrics/service endpoint is unavailable. `PgSentryNoWritableBackend` means HAProxy has no healthy primary backend. These are client-path incidents; PostgreSQL may still have a healthy leader. First confirm there is exactly one primary.

```bash
make patroni-verify PROFILE=full
ssh pgsentry@192.168.130.31 'systemctl status haproxy; sudo haproxy -c -f /etc/haproxy/haproxy.cfg; journalctl -u haproxy --since -15m'
ssh pgsentry@192.168.130.31 "printf 'show stat\n' | sudo socat - UNIX-CONNECT:/run/haproxy/admin.sock"
make haproxy-verify PROFILE=full
```

Check Patroni `/primary` health responses, HAProxy configuration, socket state, and port 5000. Restore or reload HAProxy only after validation. Do not manually promote PostgreSQL to fix a routing failure or bypass HAProxy with uncontrolled writes. Verify one UP writable backend and a routed query. Escalate if HAProxy and direct Patroni role observations disagree. See [M4](../m4-patroni-haproxy.md).
