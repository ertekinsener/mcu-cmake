#!/usr/bin/env python3
"""On-board smoke test of one H755 example (NUCLEO-H755ZI-Q, any probe-rs probe).

Flashes both images through the example's `flash` target
(mcu_add_flash_target), records a few seconds with sysview-bridge --record
and checks the SystemView stream and the RTT channel 0 log of each core
against EXPECTATIONS. Standard library only.

    smoke.py --example h755zi-freertos --build-dir build/tests/build/h755zi-freertos-debug \\
             --bridge tools/sysview-bridge/target/release/sysview-bridge --work-dir /tmp/smoke
"""

import argparse
import dataclasses
import pathlib
import subprocess
import sys
import time

CHIP = "STM32H755ZITx"
# probe-rs' STM32H755 memory map lacks the CM4 alias of D2 SRAM.
EXTRA_RAM = "0x10000000:0x48000"
CORES = {0: "firmware_cm7.elf", 1: "firmware_cm4.elf"}


@dataclasses.dataclass(frozen=True)
class Expect:
    stream: tuple[str, ...] = ()  # must appear in the SystemView stream
    log: tuple[str, ...] = ()  # must appear in the RTT channel 0 log
    forbidden: tuple[str, ...] = ()  # must not appear in the stream


EXPECTATIONS = {
    "h755zi-freertos": {
        0: Expect(stream=("N=h755zi-freertos cm7,O=FreeRTOS", "checksum", "blink"),
                  log=("cm7: FreeRTOS start", "cm7: blink")),
        1: Expect(stream=("N=h755zi-freertos cm4,O=FreeRTOS", "blink"),
                  log=("cm4: FreeRTOS start", "cm4: blink")),
    },
    "h755zi-threadx": {
        0: Expect(stream=("N=h755zi-threadx cm7,O=ThreadX", "middleware", "blink"),
                  log=("cm7: ThreadX start",
                       "cm7: middleware demo: filex=0 levelx=0 netx=0 usbx=0 guix=0")),
        1: Expect(stream=("N=h755zi-threadx cm4,O=ThreadX", "blink"),
                  log=("cm4: ThreadX start", "cm4: blink")),
    },
    "h755zi-systemview": {
        0: Expect(stream=("N=h755zi-systemview cm7", "filter", "FIR block", "FIR peak"),
                  forbidden=("job overran its period",)),
        1: Expect(stream=("N=h755zi-systemview cm4", "filter", "FIR block", "FIR peak"),
                  forbidden=("job overran its period",)),
    },
}


def run(command: list[str], what: str) -> None:
    print(f"$ {' '.join(command)}", flush=True)
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end="", flush=True)
    if result.returncode != 0:
        sys.exit(f"FAIL: {what} (exit {result.returncode})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--example", required=True, choices=sorted(EXPECTATIONS))
    parser.add_argument("--build-dir", required=True, type=pathlib.Path)
    parser.add_argument("--bridge", required=True, type=pathlib.Path)
    parser.add_argument("--work-dir", required=True, type=pathlib.Path)
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--duration", type=float, default=3.0)
    args = parser.parse_args()

    run([args.cmake, "--build", str(args.build_dir), "--target", "flash"], "flash")
    time.sleep(1.0)  # let both cores boot and initialize RTT

    targets = []
    for core, elf in CORES.items():
        targets += ["--target", f"{core}:{args.build_dir / elf}"]
    run([str(args.bridge), "--chip", CHIP, "--ram", EXTRA_RAM, *targets,
         "--record", str(args.work_dir), "--duration", str(args.duration)], "record")

    failures = []
    for core, expect in EXPECTATIONS[args.example].items():
        stream = (args.work_dir / f"core{core}.bin").read_bytes()
        log = (args.work_dir / f"core{core}.log").read_bytes()
        if not stream:
            failures.append(f"core {core}: empty SystemView stream")
        for text in expect.stream:
            if text.encode() not in stream:
                failures.append(f"core {core}: {text!r} missing in the SystemView stream")
        for text in expect.log:
            if text.encode() not in log:
                failures.append(f"core {core}: {text!r} missing in the RTT log")
        for text in expect.forbidden:
            count = stream.count(text.encode())
            if count:
                failures.append(f"core {core}: {text!r} found {count} times")
        print(f"core {core}: stream {len(stream)} bytes, log {len(log)} bytes")

    for failure in failures:
        print(f"FAIL: {failure}")
    if failures:
        return 1
    print(f"PASS: {args.example}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
