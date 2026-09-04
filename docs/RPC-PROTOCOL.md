# Chharizard RPC Protocol

External processes can control Chharizard by exchanging JSON files in `data/rpc/`. This is the same command surface the UI uses (`Commands.run(name, args)`) — anything you can click in Chharizard, you can call over RPC.

## Transport (v5.5.0)

- **Inbox:** `data/rpc/inbox/<filename>.json` — client writes here to send a request
- **Outbox:** `data/rpc/outbox/<id>.json` — Chharizard writes response here after processing
- **Poll interval:** 250ms
- **Rate limit:** 10 requests/second (excess deferred to next tick, not dropped)
- **Auto-cleanup:** Chharizard deletes inbox files immediately after read. Client is expected to delete outbox files after read.

**Upgrade note:** v5.5.1 will add a named-pipe transport for real-time latency. The JSON protocol below stays identical — same request/response shape, different transport. Clients written today keep working; they just switch from file I/O to pipe I/O.

## Request format

```json
{
  "id": "any-unique-string",
  "cmd": "modules.set",
  "args": { "char": "Chharzilla", "enabled": ["vitals", "target"] }
}
```

- **`id`** (optional): correlation ID. Chharizard writes the response to `outbox/<id>.json`. Omit → auto-generated `resp_<timestamp>.json`.
- **`cmd`** (required): command name. See [Command reference](#command-reference) below.
- **`args`** (optional): object of arguments for the command. Shape depends on the command.

## Response format

Success:
```json
{
  "id": "any-unique-string",
  "cmd": "modules.set",
  "ok": true,
  "data": [...],
  "ts": "2026-09-04 12:34:56"
}
```

Failure:
```json
{
  "id": "any-unique-string",
  "cmd": "modules.set",
  "ok": false,
  "error": "unknown command: modules.blort",
  "ts": "2026-09-04 12:34:56"
}
```

## Command reference (v5.5.0)

| Command             | Args                              | Returns                                                    |
|---------------------|-----------------------------------|------------------------------------------------------------|
| `rpc.ping`          | —                                 | `"pong"`                                                   |
| `rpc.status`        | —                                 | `{running, inbox, outbox, inboxPending, outboxUnread, ...}` |
| `roster.list`       | —                                 | `["Chharzilla", ...]`                                       |
| `roster.add`        | `{name}`                          | `"Chharzilla"`                                              |
| `roster.remove`     | `{name}`                          | `"Chharzilla"`                                              |
| `modules.list`      | `{char?}`                         | list of enabled modules (or full map)                       |
| `modules.set`       | `{char, enabled: []}`             | new enabled list                                            |
| `state.get`         | `{key}`                           | value                                                       |
| `state.all`         | —                                 | entire state map                                            |
| `log.tail`          | `{lines?}`                        | last N log lines                                            |
| `launcher.start`    | —                                 | exe path launched                                           |
| `launcher.char`     | `{name}`                          | character launched (respects per-char framework)            |
| `launcher.all`      | —                                 | count of characters launched                                |
| `update.check`      | —                                 | `{tag, name, body, published_at, zip_url}`                  |
| `update.apply`      | `{url?}`                          | true on success                                             |
| `tune.apply`        | —                                 | true (launches elevated PS)                                 |
| `tune.revert`       | —                                 | true (launches elevated PS)                                 |
| `tune.status`       | —                                 | `{applied, backup, log}`                                    |
| `tune.log`          | `{lines?}`                        | last N tuner log lines                                      |

## Client examples

### Python

```python
import json, os, time, uuid

CHZ = r"C:\Users\<you>\Documents\Chharizard\data\rpc"

def rpc(cmd, args=None, timeout_sec=5):
    req_id = str(uuid.uuid4())
    payload = {"id": req_id, "cmd": cmd, "args": args or {}}
    inbox = os.path.join(CHZ, "inbox", f"{req_id}.json")
    outbox = os.path.join(CHZ, "outbox", f"{req_id}.json")
    with open(inbox, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        if os.path.exists(outbox):
            with open(outbox, "r", encoding="utf-8") as f:
                resp = json.load(f)
            os.remove(outbox)
            return resp
        time.sleep(0.1)
    raise TimeoutError(f"RPC timeout after {timeout_sec}s: {cmd}")

# Usage
print(rpc("rpc.ping"))                                # {'ok': True, 'data': 'pong', ...}
print(rpc("roster.list"))                             # {'ok': True, 'data': [...], ...}
print(rpc("modules.set", {"char": "Chharzilla",
                          "enabled": ["vitals", "target"]}))
```

### PowerShell

```powershell
$chz = "$env:USERPROFILE\Documents\Chharizard\data\rpc"

function Invoke-ChharizardRPC($cmd, $args) {
    $id = [Guid]::NewGuid().ToString()
    $req = @{ id = $id; cmd = $cmd; args = $args } | ConvertTo-Json -Compress
    $inbox  = Join-Path $chz "inbox\$id.json"
    $outbox = Join-Path $chz "outbox\$id.json"
    Set-Content -LiteralPath $inbox -Value $req -Encoding UTF8
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $outbox) {
            $resp = Get-Content -LiteralPath $outbox -Raw | ConvertFrom-Json
            Remove-Item -LiteralPath $outbox
            return $resp
        }
        Start-Sleep -Milliseconds 100
    }
    throw "RPC timeout: $cmd"
}

Invoke-ChharizardRPC "rpc.ping"
Invoke-ChharizardRPC "roster.list"
Invoke-ChharizardRPC "launcher.char" @{ name = "Chharzilla" }
```

### Node.js

```js
const fs = require('fs/promises');
const path = require('path');
const { randomUUID } = require('crypto');

const CHZ = String.raw`C:\Users\<you>\Documents\Chharizard\data\rpc`;

async function rpc(cmd, args = {}, timeoutMs = 5000) {
    const id = randomUUID();
    const payload = JSON.stringify({ id, cmd, args });
    const inbox = path.join(CHZ, 'inbox', `${id}.json`);
    const outbox = path.join(CHZ, 'outbox', `${id}.json`);
    await fs.writeFile(inbox, payload, 'utf8');
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            const text = await fs.readFile(outbox, 'utf8');
            await fs.unlink(outbox);
            return JSON.parse(text);
        } catch { /* not there yet */ }
        await new Promise(r => setTimeout(r, 100));
    }
    throw new Error(`RPC timeout: ${cmd}`);
}

(async () => {
    console.log(await rpc('rpc.ping'));
    console.log(await rpc('roster.list'));
})();
```

## Discord bot integration pattern

The future Discord wiki-bot will:
1. Run as a separate Python process
2. On Discord command (`/chharizard modules Chharzilla`), call `rpc("modules.list", {"char": "Chharzilla"})`
3. Format the RPC response as a Discord embed
4. Post it back to the channel

No changes to Chharizard core needed. The bot is just another RPC client.

## AI plugin pattern

The future Chharbot AI plugin will:
1. Load as an `.ahk` file in `Chharizard/src/plugins/`
2. Subscribe to state events: `Events.on("state:changed", ...)`
3. Emit commands back through the dispatcher: `Commands.run("modules.set", {...})`

Since AI runs in-process, it doesn't need RPC — it uses the same dispatcher directly. RPC is for OUT-OF-PROCESS clients (Discord, external Python scripts, curl).

## Security notes

- Only files in `data/rpc/inbox/` are processed. Chharizard does NOT scan other directories.
- Any process with write access to your Chharizard folder can send commands. This is the same as any process with your user account's file access — RPC does not increase attack surface materially.
- **Do not expose `data/rpc/` over a network share** to untrusted users.
- Rate limit: 10 requests/second. Excess is deferred to the next 250ms tick, not dropped.
