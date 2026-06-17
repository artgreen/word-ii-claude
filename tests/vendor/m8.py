#!/usr/bin/env python3
"""Driver CLI for microM8's MCP control plane (SSE).

Each invocation opens one short-lived MCP session, runs the chained
commands left to right, and exits. Use it to load a binary, run it,
type at it, and read the screen back byte-exactly.

Run it through uv so the mcp client is available without a venv:

    uv run --with mcp python m8.py state screen

Commands (chain as many as you like in one invocation):
  state                 emulator_state (CPU regs + text screen)
  text                  get_text_screen_full: correct in 80-col mode,
                        decodes inverse/MouseText (add 'attrs' for the grid)
  screen                main text page decoded locally, INVERSE as [x]
                        (40-col only; for 80-col use `text`)
  rows                  main text page as plain ASCII (high bit stripped)
  load <file> <hexorg>  write a binary into memory at <hexorg> (1K chunks)
  call <decimal>        type CALL <decimal> + RETURN  (e.g. call 2049 for $801)
  type <text>           paste text. {r}=RETURN {e}=ESC {t}=TAB {sN}=sleep N/10s
  peek <hex> <n>        hex-dump n bytes from <hex>
  poke <hex> <b,b,...>  write decimal bytes at <hex>
  shot <path>           save a JPEG screenshot
  sleep <secs>          pause between chained commands
  reboot                cold reboot
  raw <tool> <json>     call any MCP tool directly

Notes
  - type_text is asynchronous and feeds the emulated keyboard. After
    typing, sleep >=1s (or use {sN}) before reading memory/screen or
    you race the key queue. A program polling $C000 sees the high-bit
    code: send "A" -> it reads $C1, {r} -> $8D, {e} -> $9B.
  - Read the screen with `screen`/`rows` (memory at $0400), not by
    eyeballing get_text_screen: that dump renders inverse glyphs as
    normal video, and the disk-LED overlay scribbles a transient byte
    into the top-left of text page 1.
  - read_memory_range's length parameter is `count`, not `length`.
"""
import asyncio
import re
import sys

PORT = 8080
SSE_URL = f"http://localhost:{PORT}/mcp/sse"


def _texts(result):
    return "\n".join(b.text for b in result.content
                     if getattr(b, "type", None) == "text")


def _rowbase(r):
    return 0x400 + (r % 8) * 0x80 + (r // 8) * 0x28


async def _read_page(s):
    """Return 24 rows x 40 raw screen bytes from text page 1."""
    res = await s.call_tool("read_memory_range",
                            {"address": 0x400, "count": 0x400})
    mem = {}
    for line in _texts(res).splitlines():
        if ":" not in line:
            continue
        addr, rest = line.split(":", 1)
        try:
            a = int(addr.strip(), 16)
        except ValueError:
            continue
        for i, tok in enumerate(rest.split()):
            if tok == "|":
                break
            try:
                mem[a + i] = int(tok, 16)
            except ValueError:
                break
    return [[mem.get(_rowbase(r) + c, 0) for c in range(40)]
            for r in range(24)]


def _render(rows, plain=False):
    out = []
    for r, row in enumerate(rows):
        line = []
        for c in row:
            if c >= 0xA0:                      # normal video
                line.append(chr(c & 0x7F))
            elif c >= 0x80:                    # normal control glyph
                line.append(chr((c & 0x3F) + 0x40))
            elif plain:
                line.append(chr((c & 0x3F) + 0x40)
                            if (c & 0x3F) < 0x20 else chr(c & 0x7F))
            else:                              # inverse/flash: bracket it
                ch = (c & 0x3F) + 0x40 if (c & 0x3F) < 0x20 else (c & 0x3F)
                line.append("[" + chr(ch) + "]")
        out.append(f"{r:2d}|" + "".join(line))
    return "\n".join(out)


async def _type(s, text):
    text = (text.replace("{r}", "\r").replace("{e}", "\x1b")
                .replace("{t}", "\t"))
    for part in re.split(r"(\{s\d+\})", text):
        m = re.fullmatch(r"\{s(\d+)\}", part)
        if m:
            await asyncio.sleep(int(m.group(1)) / 10)
        elif part:
            await s.call_tool("type_text", {"text": part})


async def main(argv):
    import json
    from mcp import ClientSession
    from mcp.client.sse import sse_client
    async with sse_client(SSE_URL) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            i = 0
            while i < len(argv):
                cmd = argv[i]
                if cmd == "state":
                    print(_texts(await s.call_tool("emulator_state", {})))
                elif cmd == "text":
                    # `text` or `text attrs` (per-cell attribute grid)
                    want_attrs = i + 1 < len(argv) and argv[i + 1] == "attrs"
                    if want_attrs:
                        i += 1
                    print(_texts(await s.call_tool(
                        "get_text_screen_full", {"attributes": want_attrs})))
                elif cmd == "screen":
                    print(_render(await _read_page(s)))
                elif cmd == "rows":
                    print(_render(await _read_page(s), plain=True))
                elif cmd == "load":
                    path, addr = argv[i + 1], int(argv[i + 2], 16)
                    i += 2
                    data = open(path, "rb").read()
                    for off in range(0, len(data), 1024):
                        await s.call_tool("write_memory_range", {
                            "address": addr + off,
                            "values": list(data[off:off + 1024])})
                    print(f"loaded {len(data)} bytes at ${addr:04X}")
                elif cmd == "call":
                    i += 1
                    await s.call_tool("type_text",
                                      {"text": f"CALL {int(argv[i])}\r"})
                elif cmd == "type":
                    i += 1
                    await _type(s, argv[i])
                elif cmd == "peek":
                    addr, n = int(argv[i + 1], 16), int(argv[i + 2])
                    i += 2
                    print(_texts(await s.call_tool(
                        "read_memory_range", {"address": addr, "count": n})))
                elif cmd == "poke":
                    addr = int(argv[i + 1], 16)
                    vals = [int(x) for x in argv[i + 2].split(",")]
                    i += 2
                    await s.call_tool("write_memory_range",
                                      {"address": addr, "values": vals})
                    print(f"poked {len(vals)} bytes at ${addr:04X}")
                elif cmd == "shot":
                    i += 1
                    print(_texts(await s.call_tool("screenshot",
                                                   {"path": argv[i]})))
                elif cmd == "sleep":
                    i += 1
                    await asyncio.sleep(float(argv[i]))
                elif cmd == "reboot":
                    print(_texts(await s.call_tool("reboot", {})))
                elif cmd == "raw":
                    tool, args = argv[i + 1], json.loads(argv[i + 2])
                    i += 2
                    print(_texts(await s.call_tool(tool, args)))
                else:
                    print(f"unknown command: {cmd}", file=sys.stderr)
                    return 2
                i += 1
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main(sys.argv[1:])))
