#!/usr/bin/env python3
# Generates a .gclient file for flutter/flutter at a specific commit.
# Usage: python3 gclient_config.py <flutter_commit_sha>
# Output: .gclient content printed to stdout

import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <flutter_commit_sha>", file=sys.stderr)
    sys.exit(1)

commit = sys.argv[1].strip()

print(f'''solutions = [
  {{
    "managed": False,
    "name": ".",
    "url": "https://github.com/flutter/flutter.git@{commit}",
    "custom_deps": {{}},
    "deps_file": "DEPS",
    "safesync_url": "",
    "custom_vars": {{
      "download_android_deps": False,
      "download_emsdk": False,
      "download_linux_deps": False,
      "download_windows_deps": False,
    }},
  }},
]''')
