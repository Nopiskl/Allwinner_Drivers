#!/usr/bin/env python3
"""Run a local shell script on the Radxa board over password-authenticated SSH.

The password is read from RADXA_PASSWORD.  The helper deliberately does not
persist host keys; it prints the connected key fingerprint so each reflashed
image remains auditable in the run log.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
from pathlib import Path
import sys

import paramiko


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("script", type=Path)
    parser.add_argument("--host", default="192.168.0.103")
    parser.add_argument("--user", default="radxa")
    parser.add_argument("--sudo", action="store_true")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument(
        "--output",
        type=Path,
        help="Also save combined stdout/stderr to this UTF-8 file.",
    )
    parser.add_argument(
        "--put",
        action="append",
        default=[],
        metavar="LOCAL:REMOTE",
        help="Upload a file before running the script (repeatable).",
    )
    parser.add_argument(
        "--get",
        action="append",
        default=[],
        metavar="REMOTE:LOCAL",
        help="Download a file after running the script (repeatable).",
    )
    args = parser.parse_args()

    password = os.environ.get("RADXA_PASSWORD")
    if password is None:
        raise SystemExit("RADXA_PASSWORD is not set")
    script = args.script.read_text(encoding="utf-8")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.WarningPolicy())
    client.connect(
        args.host,
        username=args.user,
        password=password,
        look_for_keys=False,
        allow_agent=False,
        timeout=10,
        auth_timeout=10,
        banner_timeout=10,
    )
    try:
        transport = client.get_transport()
        if transport is None:
            raise RuntimeError("SSH transport was not established")
        server_key = transport.get_remote_server_key()
        digest = hashlib.sha256(server_key.asbytes()).digest()
        fingerprint = base64.b64encode(digest).decode("ascii").rstrip("=")
        print(f"SERVER_KEY={server_key.get_name()} SHA256:{fingerprint}")

        if args.put:
            with client.open_sftp() as sftp:
                for item in args.put:
                    local, separator, remote = item.partition(":")
                    if not separator or not local or not remote:
                        raise ValueError(f"invalid --put value: {item!r}")
                    sftp.put(str(Path(local)), remote)
                    print(f"UPLOADED={Path(local).resolve()} -> {remote}")

        command = "/bin/bash -se"
        if args.sudo:
            command = "sudo -S -p '' /bin/bash -se"
        stdin, stdout, stderr = client.exec_command(command, timeout=args.timeout)
        if args.sudo:
            stdin.write(password + "\n")
        stdin.write(script)
        if not script.endswith("\n"):
            stdin.write("\n")
        stdin.channel.shutdown_write()
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        rc = stdout.channel.recv_exit_status()
        if args.output is not None:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(out + err, encoding="utf-8")
        if args.get:
            with client.open_sftp() as sftp:
                for item in args.get:
                    remote, separator, local = item.partition(":")
                    if not separator or not remote or not local:
                        raise ValueError(f"invalid --get value: {item!r}")
                    local_path = Path(local)
                    local_path.parent.mkdir(parents=True, exist_ok=True)
                    sftp.get(remote, str(local_path))
                    print(f"DOWNLOADED={remote} -> {local_path.resolve()}")
        sys.stdout.write(out)
        sys.stderr.write(err)
        return rc
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
