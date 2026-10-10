#!/usr/bin/env python3
"""检查 shell 脚本里 $var 后面是否紧跟多字节字符。

bash 3.2 + `set -u` 会把 `$var` 之后紧跟的非 ASCII 字节当成变量名的一部分，
从而报 `unbound variable`。必须写成 `${var}`。

用法：python3 scripts/check-multibyte-vars.py FILE...
退出码：0 干净，1 发现问题。
"""
import re
import sys

PATTERN = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7f])')


def main(paths: list[str]) -> int:
    bad = False
    for path in paths:
        try:
            text = open(path, encoding="utf-8").read()
        except OSError as exc:
            print(f"{path}: cannot read: {exc}", file=sys.stderr)
            bad = True
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for match in PATTERN.finditer(line):
                name = match.group(0)[1:]
                print(
                    f"{path}:{lineno}: bare {match.group(0)} is immediately "
                    f"followed by non-ASCII text; write ${{{name}}} instead"
                )
                bad = True
    if not bad:
        print("no bare $var before multibyte text")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
