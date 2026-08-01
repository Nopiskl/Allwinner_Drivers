import argparse
import datetime
import signal
import sys

import serial


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM4")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    running = True

    def stop(_signum, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    with serial.Serial(args.port, args.baud, timeout=0.2) as uart:
        with open(args.output, "ab", buffering=0) as log:
            marker = (
                f"\n\n===== capture started "
                f"{datetime.datetime.now(datetime.timezone.utc).isoformat()} "
                f"{args.port}@{args.baud} =====\n"
            ).encode("ascii")
            log.write(marker)
            while running:
                data = uart.read(4096)
                if data:
                    log.write(data)

    return 0


if __name__ == "__main__":
    sys.exit(main())
