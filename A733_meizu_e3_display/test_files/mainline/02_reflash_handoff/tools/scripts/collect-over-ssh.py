#!/usr/bin/env python3
"""Collect a pre-flash Radxa snapshot over password-authenticated SSH.

The password is read from RADXA_PASSWORD or prompted interactively. It is never
stored in the resulting archive.
"""

from __future__ import annotations

import argparse
import getpass
import hashlib
import os
from pathlib import Path
import re
import sys
import time

import paramiko


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="192.168.0.103")
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", default="radxa")
    parser.add_argument(
        "--remote-script",
        type=Path,
        default=Path(__file__).with_name("remote-collect-preflash.sh"),
    )
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument(
        "--accept-reflashed-host-key",
        action="store_true",
        help=(
            "Do not compare against stale system host keys. Use only after "
            "cross-checking the reflashed board through a trusted channel."
        ),
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def wait_channel(channel: paramiko.Channel, timeout: int) -> tuple[int, str, str]:
    stdout = bytearray()
    stderr = bytearray()
    deadline = time.monotonic() + timeout
    while True:
        while channel.recv_ready():
            stdout.extend(channel.recv(65536))
        while channel.recv_stderr_ready():
            stderr.extend(channel.recv_stderr(65536))
        if channel.exit_status_ready():
            while channel.recv_ready():
                stdout.extend(channel.recv(65536))
            while channel.recv_stderr_ready():
                stderr.extend(channel.recv_stderr(65536))
            return (
                channel.recv_exit_status(),
                stdout.decode("utf-8", errors="replace"),
                stderr.decode("utf-8", errors="replace"),
            )
        if time.monotonic() >= deadline:
            channel.close()
            raise TimeoutError(f"remote command exceeded {timeout} seconds")
        time.sleep(0.05)


def main() -> int:
    args = parse_args()
    password = os.environ.get("RADXA_PASSWORD")
    if password is None:
        password = getpass.getpass(f"Password for {args.user}@{args.host}: ")

    script = args.remote_script.resolve()
    if not script.is_file():
        raise FileNotFoundError(script)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    remote_script = f"/tmp/radxa-preflash-collect-{os.getpid()}.sh"
    remote_prefix = "/tmp/radxa-a733-preflash-current"

    client = paramiko.SSHClient()
    if not args.accept_reflashed_host_key:
        client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.WarningPolicy())
    client.connect(
        args.host,
        port=args.port,
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
        fingerprint = hashlib.sha256(server_key.asbytes()).digest()
        import base64

        print(
            "SERVER_KEY_SHA256="
            + base64.b64encode(fingerprint).decode("ascii").rstrip("=")
        )

        with client.open_sftp() as sftp:
            sftp.put(str(script), remote_script)
            sftp.chmod(remote_script, 0o700)

        command = (
            f"sudo -S -p '' /bin/sh {remote_script} {remote_prefix}"
        )
        channel = transport.open_session()
        channel.exec_command(command)
        channel.sendall((password + "\n").encode("utf-8"))
        rc, stdout, stderr = wait_channel(channel, args.timeout)
        sys.stdout.write(stdout)
        sys.stderr.write(stderr)
        if rc != 0:
            raise RuntimeError(f"remote collector exited with {rc}")

        archive_match = re.search(r"^ARCHIVE=(.+)$", stdout, re.MULTILINE)
        hash_match = re.search(r"^ARCHIVE_SHA256=([0-9a-f]{64})$", stdout, re.MULTILINE)
        if archive_match is None or hash_match is None:
            raise RuntimeError("collector output did not contain archive metadata")

        remote_archive = archive_match.group(1).strip()
        local_archive = args.output_dir / Path(remote_archive).name
        with client.open_sftp() as sftp:
            sftp.get(remote_archive, str(local_archive))

        actual_hash = sha256_file(local_archive)
        expected_hash = hash_match.group(1)
        if actual_hash != expected_hash:
            raise RuntimeError(
                f"archive hash mismatch: expected {expected_hash}, got {actual_hash}"
            )
        print(f"LOCAL_ARCHIVE={local_archive.resolve()}")
        print(f"LOCAL_ARCHIVE_SHA256={actual_hash}")
        return 0
    finally:
        try:
            client.exec_command(f"rm -f -- {remote_script}", timeout=5)
        except Exception:
            pass
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
