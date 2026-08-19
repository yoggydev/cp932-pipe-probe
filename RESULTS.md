# RESULTS

Raw output from real runs. Nothing here is edited except the headings.

---

## ja-JP Windows, Windows PowerShell 5.1 (.NET Framework 4.8)

The machine this repo exists for. `ACP = 932` confirmed.

```
ACP          = 932
utf8-replace : chars=42 FFFD=29 backslash=4
cp932        : chars=26 FFFD=0
NLS 932 sweep: chars=9206 survive-utf8=0 trail0x5C=50
```

The 50-byte input is the fixed CP932 sequence in `cp932_pipe_test.ps1`. Decoded as CP932
it is an ordinary Japanese sentence; decoded as UTF-8 with replacement it is 29 `U+FFFD`
plus four stray `\`.

---

## PowerShell 7.4.6 on Linux (.NET 8) — reference run

```
== environment ==
PSVersion               = 7.4.6
PSEdition               = Core
ANSI code page (ACP)    = unreadable
Console::OutputEncoding = 65001 (utf-8)
Encoding::Default       = 65001

== T1) deterministic CP932 bytes through a pipe ==
bytes written by child   : 50
bytes received by parent : 50
first bytes              : 8F 5C 95 AA 82 C8 97 5C 92 E8 82 F0 8D 5C 90 AC 82 C5 82 AB
                           82 DC 82 B9 82 F1 3A 20 83 5C 81 5B 83 58 82 AA 8C A9 82 C2
                           82 A9 82 E8 82 DC 82 B9 82 F1
pipe delivered unchanged : True

-- decoded as UTF-8 with replacement (what the current code does) --
  chars     = 43
  U+FFFD    = 30
  stray '\' = 4

-- decoded as CP932 from the raw bytes (what the fix should do) --
  chars     = 26
  U+FFFD    = 0

== T2) a real native Windows program's localized error ==
(skipped - cmd.exe does not exist on Linux)

== D) CP932 double-byte sweep ==
double-byte chars enumerated : 9206
  survive utf-8 + replace    : 0
  survive raw bytes + cp932  : 9206

== C) CP932 characters whose SECOND byte is 0x5C ==
count = 50
```

---

## Python 3.11.15 `cp932` codec — reference sweep

Computed directly from the codec tables:

```
double-byte characters enumerated : 9604
  survive utf-8 + errors=replace  : 0      (0.00%)
  survive raw bytes + cp932       : 9604   (100.00%)

U+FFFD produced from the same 50-byte sample : 30

characters whose second byte is 0x5C : 52
―ソЫⅨ噂浬欺圭構蚕十申曾箪貼能表暴予禄兔喀媾彌拿杤歃濬畚秉綵臀藹觸軆鐔饅鷭偆砡纊犾
```

---

## Cross-run comparison

| runtime / table | 2-byte chars | trail `0x5C` | `U+FFFD` from the 50-byte sample |
|---|---|---|---|
| Python 3.11 `cp932` | 9,604 | 52 | 30 |
| .NET Framework 4.8 — Windows PowerShell 5.1, ja-JP | 9,206 | 50 | **29** |
| .NET 8 — PowerShell 7.4, Linux | 9,206 | 50 | 30 |

Two things fell out of this that I did not expect before running it:

1. **.NET's CP932 table is the same on Windows and Linux.** I assumed .NET on Windows
   would defer to the OS NLS tables and produce a third set of numbers. It does not. The
   split is Python vs .NET, not Windows vs Linux.
2. **The same 50 bytes produce a different number of `U+FFFD` depending on the runtime**
   (29 on .NET Framework 4.8, 30 on .NET 8 and on Python 3.11). A UTF-8 replacement
   inconsistency between .NET Framework and .NET Core is a known open issue,
   [dotnet/standard#1679](https://github.com/dotnet/standard/issues/1679). This is a
   measurement of it, not an explanation of it.

The second one is the useful one. `errors="replace"` does not merely lose the original
bytes — the wreckage it leaves is not identical across runtimes, so it cannot be treated
as a stable, detectable form either.
