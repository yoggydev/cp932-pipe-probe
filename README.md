# cp932-pipe-probe

A small PowerShell harness that measures what happens to **CP932 (Japanese Windows ANSI)**
bytes when a pipe is decoded as UTF-8 with `errors="replace"`.

No Python, no install. Windows PowerShell 5.1 or PowerShell 7. Runs in about two seconds.

I wrote this because upstream bug reports about this class of failure keep being filed
from one CJK locale and fixed without anyone checking the others. I have a
Japanese-locale Windows machine, so I can check the ja-JP side.

---

## Run it

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\cp932_pipe_test.ps1
```

Console output is ASCII only — a script that measures mojibake should not be able to
become a victim of it. The full result, including the Japanese text, is written to
`cp932_pipe_test_result.txt` as UTF-8 with BOM.

---

## What it measures

| | | needs real ja-JP Windows |
|---|---|---|
| **T1** | A child process writes a known CP932 byte sequence to stderr. The parent reads the raw bytes and decodes them two ways. | no (deterministic) |
| **T2** | A real native Windows program's localized error, captured as raw bytes. | yes (needs the Japanese UI language) |
| **C** | Every CP932 double-byte character whose **second byte is `0x5C`**. | no |
| **D** | Full sweep of the CP932 double-byte space: how many characters survive each decode path. | no |

T1 is the useful one. It needs no language pack, so it produces the same bytes on any
Windows, and it isolates the decode step from everything else.

---

## The part people miss: `0x5C`

CP932 trail bytes are `0x40`–`0x7E` and `0x80`–`0xFC`. `0x5C` is in that range, and
`0x5C` is also the backslash.

So a CP932 character whose second byte is `0x5C` does **not** turn into `U+FFFD` when the
stream is decoded as UTF-8 with replacement. It leaves a **stray backslash** behind.

The T1 sequence in this repo is an ordinary Japanese sentence chosen because four of its
characters have `0x5C` as the trail byte:

```
8F5C   975C   8D5C   835C
```

Decoded as UTF-8 with replacement, those four become `\`. That is why this failure is so
often filed as a path bug, a quoting bug, or a shell-escaping bug — and why the encoding
is never suspected.

---

## Results

Measured on a Japanese-locale Windows machine, **`ACP = 932` confirmed**, Windows
PowerShell 5.1. Raw console output is in [`RESULTS.md`](RESULTS.md).

### T1 — the same 50 bytes of CP932, decoded two ways

| decode path | chars | `U+FFFD` | stray `\` |
|---|---|---|---|
| `UTF-8` with replacement | 42 | 29 | **4** |
| raw bytes → `CP932` | 26 | 0 | — |

The four backslashes are the whole point. They are not corruption artefacts that look
like corruption — they are corruption artefacts that look like *punctuation*.

### The replacement output is not even stable across runtimes

The identical 50 bytes, decoded as UTF-8 with replacement:

| runtime | `U+FFFD` produced |
|---|---|
| .NET Framework 4.8 (Windows PowerShell 5.1, ja-JP) | **29** |
| .NET 8 (PowerShell 7.4, Linux) | 30 |
| Python 3.11 | 30 |

Same input, different output. A UTF-8 replacement inconsistency between .NET Framework
and .NET Core is a known open issue
([dotnet/standard#1679](https://github.com/dotnet/standard/issues/1679)); this is a
measurement of it, not an explanation of it.

The practical consequence is worth stating plainly: once `errors="replace"` has run, you
cannot recover the original bytes, **and you cannot even rely on what the damage looks
like**. It is not a stable, parseable form of failure. It is just loss.

### C / D — the CP932 double-byte space

The count depends on **whose CP932 table you ask**:

| table | double-byte chars | survive `UTF-8`+replace | chars with trail byte `0x5C` |
|---|---|---|---|
| Python 3.11 `cp932` | 9,604 | 0 | 52 |
| .NET (Windows **and** Linux) | 9,206 | 0 | 50 |

**Correction to an earlier draft of this README:** I expected the Windows number to differ
from the Linux one, on the assumption that .NET on Windows would defer to the OS NLS
tables. It does not. .NET carries its own CP932 table and gives 9,206 on both platforms.
The real split is **Python vs .NET**, not Windows vs Linux. I only found that out by
running it.

This matters for anyone fixing the bug in Python: Python's `cp932` is the *more*
permissive of the two, recognising 398 two-byte sequences that .NET's table rejects. A
Python-side `cp932` fallback is therefore not the narrower option.

> **Careful with these numbers.** They are measured per character *in isolation*. In a real
> byte stream, a CP932 character followed by other bytes can occasionally form a valid
> UTF-8 sequence. Do not restate this as "every byte in every stream".

---

## Why `errors="replace"` is the specific problem

`replace` is not a safety net here. It is the step that destroys the evidence:

```python
subprocess.Popen(args, text=True, encoding="utf-8", errors="replace")
```

`text=True` decodes at the pipe level, so the original bytes are gone by the time any
caller sees the string. A fallback decode cannot recover them afterwards, because there
is nothing left to decode.

Collecting raw bytes and choosing the decoder afterwards costs nothing and keeps the
option open.

---

## License

MIT. See [`LICENSE`](LICENSE).

## Author

Yoggy — [@yoggydev](https://github.com/yoggydev)

Measurements were taken by me on my own Japanese-locale Windows machine.
The harness and this README were drafted with Claude.
