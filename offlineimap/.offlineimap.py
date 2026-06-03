#!/usr/bin/python
import os
import re
import subprocess


def get_keychain_pass(account=None, server=None):
    keychain = os.path.expanduser("~/Library/Keychains/login.keychain")
    cmd = [
        "/usr/bin/security",
        "-v",
        "find-internet-password",
        "-g",
        "-a", account,
        "-s", server,
        keychain,
    ]
    output = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
    outtext = [l for l in output.splitlines()
               if l.startswith(b"password: ")][0].decode()

    return re.match(r'password: "(.*)"', outtext).group(1)
