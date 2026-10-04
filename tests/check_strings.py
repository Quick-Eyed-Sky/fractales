#!/usr/bin/env python3
"""Checks that every text the app shows has its English translation, with the same
%@ / %ld placeholders, and that no translation is left over.  python3 tests/check_strings.py"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent / "source"
used = set()
for f in root.glob("*.swift"):
    used |= {m.replace("\\'", "'") for m in re.findall(r'\bL\("((?:[^"\\]|\\.)*)"\)', f.read_text())}

def table(path):
    text = re.sub(r"/\*.*?\*/", "", path.read_text(encoding="utf-8"), flags=re.S)
    return dict(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text, flags=re.M))

def placeholders(s):
    return sorted(re.findall(r"%(?:@|l?l?d|\.?\d*f)", s))

en = table(root / "en.lproj" / "Localizable.strings")
errors = [f"missing English text: {k!r}" for k in sorted(used - en.keys())]
errors += [f"unused English text: {k!r}" for k in sorted(en.keys() - used)]
errors += [f"placeholders differ: {k!r} -> {v!r}" for k, v in en.items() if placeholders(k) != placeholders(v)]
for e in errors:
    print(e)
print(f"{len(used)} texts, {len(en)} English translations, {len(errors)} problems")
sys.exit(1 if errors else 0)
