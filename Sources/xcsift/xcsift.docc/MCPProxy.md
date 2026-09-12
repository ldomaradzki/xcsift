# MCP Proxy

Put xcsift in front of an Xcode MCP server so coding agents receive structured build results instead of build transcripts.

## Overview

`xcsift mcp` is a Model Context Protocol proxy. The coding agent connects to xcsift over stdio, and
xcsift runs the real Xcode MCP server as a child process — by default Xcode's own server, shipped
with Xcode 26 and later and reached through its stdio bridge:

```
agent  ⇄  xcsift mcp  ⇄  xcrun mcpbridge  ⇄  Xcode
```

Xcode's server responds only while MCP is enabled — turn it on in Xcode ▸ Settings ▸ Intelligence,
or headless with `sudo xcrun mcp-server enable`, and check it with `xcrun mcp-server status`. When
the server exits without answering, the proxy says so on stderr instead of leaving the agent with a
silent stream.

Any other stdio MCP server that drives `xcodebuild`, `swift build`, `xcbeautify` or Tuist works the
same way — put its command after `--`.

Every message is forwarded byte for byte, including server-initiated requests, progress
notifications, and protocol versions xcsift has never heard of. Three kinds are not: tool results
that carry build output, `tools/list` results (which gain `xcsift_parse_build_log`), and calls to
that tool, which xcsift answers itself.

### Setup, start to finish

1. **Install xcsift** where it will stay put — `brew install xcsift`. Xcode approves an agent by
   binary and signature, so an installed xcsift is approved once; a locally built one changes
   identity on every rebuild.
2. **Enable Xcode's MCP server**: Xcode ▸ Settings ▸ Intelligence, or headless with
   `sudo xcrun mcp-server enable` followed by `xcrun mcp-server start`. `xcrun mcp-server status`
   reports permission, the running server, and open workspaces. (Observed on Xcode 27; Apple's own
   documentation is the reference for the commands.)
3. **Point the agent at the proxy instead of the bridge.** Where the documented command is
   `claude mcp add --transport stdio xcode -- xcrun mcpbridge`, use:

   ```bash
   xcsift mcp --install
   ```

   That runs `claude mcp add` for you and records the flags given alongside it, so
   `xcsift mcp --install -f toon -w` registers a proxy that runs with those flags. Flags otherwise
   go after `mcp` (`xcsift mcp -f toon -w`), and `xcsift mcp --print-config` prints the JSON for
   clients configured by file.
4. **Approve the agent once.** The first project open or build raises a request for the agent
   `xcsift` and that project's folder — grant it from the Xcode MCP menu bar icon, or with
   `sudo xcrun mcp-server approve <id>`.
5. **Work as before.** The agent sees Xcode's own tools, plus `xcsift_parse_build_log`, and build
   results now carry the warnings Xcode's summary leaves out. `xcsift mcp --verbose` logs each
   rewrite to stderr; `--on-summary off` stops the proxy reading logs at all.

Upgrading xcsift changes its signature, so Xcode asks for approval once more after an upgrade.

### Configuring a client

Print a ready-made snippet:

```bash
xcsift mcp --print-config
```

```json
{
  "mcpServers": {
    "xcode": {
      "command": "xcsift",
      "args": ["mcp", "--", "xcrun", "mcpbridge"]
    }
  }
}
```

### Removing the proxy

```bash
xcsift mcp --uninstall
```

The proxy is configuration, not an installed artefact: what there is to remove is one `mcpServers`
entry. `--uninstall` runs `claude mcp remove` for the name `xcode` in whichever scope holds it, so a
registration made by hand with `claude mcp add` is removed by it too. `--server-name` names another
entry, `--scope local|project|user` confines the change to one scope, and `--install --force`
replaces an existing registration rather than refusing. For a client configured by file, delete the
`mcpServers` entry, or point it back at `xcrun mcpbridge` to keep Xcode's server without the sifting.

Any MCP server that builds with `xcodebuild`, `swift build`, `xcbeautify` or Tuist works the same
way — put its command after `--`:

```bash
xcsift mcp -f toon -- /usr/local/bin/my-xcode-mcp serve
```

## What gets rewritten

Two shapes of upstream output are recognised, and anything else is left exactly as the server wrote
it.

### Raw build transcripts are replaced

A server that returns the `xcodebuild` transcript verbatim is the expensive case. xcsift parses it
and replaces the text with the same structured result the CLI produces — on a failing Xcode 27
build of an iOS app, a transcript of roughly 23 KB came back about fifty times smaller. The shape,
with field order as the encoder emits it:

```json
{
  "status": "failed",
  "summary": { "errors": 1, "warnings": 0, "failed_tests": 0, "linker_errors": 0 },
  "errors": [
    {
      "file": "/Sources/SampleKit/SampleKit.swift",
      "line": 6,
      "message": "cannot convert value of type 'String' to specified type 'Int'"
    }
  ]
}
```

### Summaries gain the diagnostics behind them

A server that summarises the build and writes the full log to disk reports that path in its
response — Xcode's own server does so as `fullLogPath`, inside JSON. xcsift reads that log and
*appends* what the response left out as an extra content block, so the server's own fields survive.

With Xcode's server this fills a concrete gap: `BuildProject` returns structured errors but **never
the warnings**, so a build that only warns comes back as `{"errors":[],…}` and its warnings live
only in the log. Measured on a real Xcode 27 build of an iOS app:

| Response | Proxy | Result |
|----------|-------|--------|
| Build succeeded, 2 warnings in the log | appends | both warnings with file and line (+1 059 chars) |
| Build failed, error already in the response | untouched | nothing to add |
| `RunAllTests`, per-test results enumerated | untouched | the server ran the tests; it is the authority |

Appending is gated, not filtered: xcsift appends the sifted result only when the log carries at
least one diagnostic the response does not, so a response that already says everything is left
alone — but a response missing one warning receives the whole result, known errors included. Two
differences are normalised before that comparison, both observed against Xcode's server: it
capitalises the compiler's message, and xcsift attributes a diagnostic to its target
(`… (in target 'A' from project 'B')`). A response that enumerates per-test results is left alone
entirely (see **Limits**).

Use `--on-summary` to change that:

| Value | Behaviour |
|-------|-----------|
| `append` | Keep the response, append the sifted result when the log adds something (default) |
| `replace` | Replace the response with the sifted result, keeping the log path |
| `off` | Never read referenced logs |

## The xcsift_parse_build_log tool

The proxy advertises one extra tool alongside the upstream server's own, so an agent can ask for the
complete diagnostics behind any build log:

```json
{ "name": "xcsift_parse_build_log", "arguments": { "path": "~/Library/Logs/xcode-mcp/…/build.log", "warnings": true } }
```

| Argument | Meaning |
|----------|---------|
| `path` | Path to the build log. A leading `~` is expanded. |
| `format` | `json` or `toon`; defaults to the proxy's format. |
| `warnings` | Include the full warning list. |
| `build_info` | Include per-target phases, timing and dependencies. |

Pass `--no-inject-tools` to advertise nothing extra. If the upstream server happens to provide a
tool of the same name, it keeps it: xcsift neither advertises a second one nor intercepts the call.

## Options

The parsing and formatting flags are the same ones the pipeline uses — `--format`, `--warnings`,
`--build-info`, `--executable`, `--slow-threshold`, `--xcbeautify` — and `.xcsift.toml` is honoured,
so a project's defaults apply in both modes. Two config values have no meaning over MCP and are
ignored (`quiet`, `exit_on_failure`), and `format = "github-actions"` is refused: override it with
`-f json`. Proxy-specific options:

| Option | Default | Meaning |
|--------|---------|---------|
| `--on-summary` | `append` | What to do with a summarised response that references a log |
| `--inject-tools` / `--no-inject-tools` | on | Advertise `xcsift_parse_build_log` |
| `--build-tool-pattern` | `(?i)(build\|test\|run\|archive\|clean\|compile\|package)` | Tool names whose referenced logs may be read; an invalid regex is refused at startup |
| `--min-raw-lines` | `12` | Line count before output carrying two or more weak build markers counts as a transcript |
| `--max-log-size` | `64` | Largest log to parse, in megabytes (1–4096) |
| `--verbose` | off | Log proxy activity to stderr, including the logs it declined to parse and why |

## Xcode's server approves agents by binary

Xcode identifies an agent by the binary that connects and its code signature, so with the proxy in
place that agent is `xcsift`. The first build or project open raises an approval request — grant it
from the Xcode MCP menu bar icon, or with `sudo xcrun mcp-server approve <id>`. Approve the
*installed* xcsift (`/usr/local/bin/xcsift`, or the Homebrew one): an ad-hoc signature changes with
every rebuild, and a rebuilt binary is a new agent that has to be approved again. `xcrun mcp-server
status` lists the permitted agents and folders.

## Limits

- **Test aggregates from a console transcript are not offered against a server's own counts.**
  Xcode's console log interleaves XCTest and Swift Testing events across several bundles, and
  xcsift's totals for that shape do not yet match the run. Failures parsed from a log are still
  appended when the response says nothing about tests.
- **A message too large to buffer is never decoded**, so a raw transcript returned inline above
  4 MiB passes through unsifted. Sifting resumes with the next message.
- **Only unmistakable transcripts are sifted from tools that are not build-shaped.** A tool whose
  name does not match `--build-tool-pattern` has its output replaced only when it carries a
  terminal phase marker, and its referenced logs are never read — a source file quoting `: error: `
  must not be mistaken for a failed build.
- **`structuredContent` is left as the server wrote it.** A server that returns both structured
  content and text may end up with the two disagreeing after a rewrite.
- **Batched requests pass through.** JSON-RPC batches are forwarded rather than rewritten.

## Behaviour worth relying on

- **Nothing is lost when parsing fails.** If the text is not build output, or the parse finds
  nothing, the original response is forwarded unchanged.
- **Large messages stream through.** Messages too large to buffer (screenshots, video, base64
  payloads) are copied byte for byte rather than decoded.
- **The upstream exit status is the proxy's.** The server's stderr is inherited untouched, so its
  own logging still reaches the client.
- **Shutdown follows the specification.** When the client closes its stream the server's stdin is
  closed, then SIGTERM, then SIGKILL, so a server that ignores a closed stdin does not outlive the
  proxy.
