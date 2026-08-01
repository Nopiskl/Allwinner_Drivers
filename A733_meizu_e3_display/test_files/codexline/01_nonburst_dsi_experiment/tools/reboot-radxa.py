import argparse
import os
import time

import paramiko


parser = argparse.ArgumentParser()
parser.add_argument("--host", required=True)
parser.add_argument("--user", default="radxa")
parser.add_argument("--known-hosts", required=True)
args = parser.parse_args()

password = os.environ["RADXA_TEST_PASSWORD"]
client = paramiko.SSHClient()
client.load_host_keys(args.known_hosts)
client.set_missing_host_key_policy(paramiko.RejectPolicy())
client.connect(
    args.host,
    username=args.user,
    password=password,
    timeout=10,
    look_for_keys=False,
    allow_agent=False,
)

stdin, stdout, stderr = client.exec_command(
    "sudo -S -p '' /bin/systemctl reboot",
    timeout=10,
)
stdin.write(password + "\n")
stdin.flush()
time.sleep(1)
print("reboot command sent; SSH transport will now be closed", flush=True)
client.close()
