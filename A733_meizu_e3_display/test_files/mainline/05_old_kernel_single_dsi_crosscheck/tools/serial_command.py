import argparse
import os
import sys
import time

import serial


def read_for(port, seconds):
    deadline = time.monotonic() + seconds
    data = bytearray()
    while time.monotonic() < deadline:
        chunk = port.read(4096)
        if chunk:
            data.extend(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
    return bytes(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM4")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--user", default=os.environ.get("RADXA_SERIAL_USER", "radxa"))
    parser.add_argument("--command", required=True)
    args = parser.parse_args()

    with serial.Serial(args.port, args.baud, timeout=0.15) as uart:
        uart.write(b"\n")
        initial = read_for(uart, 1.5)

        if b"login:" in initial:
            uart.write(args.user.encode("utf-8") + b"\n")
            prompt = read_for(uart, 1.5)
            if b"Password:" in prompt:
                password = os.environ.get("RADXA_SERIAL_PASSWORD")
                if not password:
                    raise RuntimeError("Set RADXA_SERIAL_PASSWORD for serial login")
                uart.write(password.encode("utf-8") + b"\n")
                read_for(uart, 2.0)

        uart.write(args.command.encode("utf-8") + b"\n")
        read_for(uart, 15.0)


if __name__ == "__main__":
    main()
