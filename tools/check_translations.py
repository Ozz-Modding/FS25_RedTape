"""Check translation format strings against English.

A translation with a stray '%' or extra placeholders makes string.format throw in game
(e.g. issue #143: the grant button silently did nothing in Hungarian).

English is the reference. If the English text contains a format specifier or '%%', the key
is assumed to go through string.format, and every translation must:
  - only use specifiers Lua understands (no positional '%1$s', no bare '%'),
  - not use more specifiers than English (string.format would run out of arguments),
  - use the same specifier types, in the same order, as English.
English texts with a bare '%' (e.g. "5% tax", "50% of") are displayed raw and are skipped.

Using fewer placeholders than English is allowed: string.format ignores extra arguments, and
translations legitimately drop e.g. the English plural suffix in "month%s". Pass --verbose to
list those.

Usage: python tools/check_translations.py [--verbose]   (exits 1 if any errors are found)
"""
import glob
import os
import re
import sys

LANG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "languages")

TEXT = re.compile(r'<text\s+name="([^"]+)"\s+text="([^"]*)"')
# The space flag is deliberately not accepted: "50% of" would otherwise read as a valid '% o'.
VALID_SPEC = re.compile(r'%[-+#0]*\d{0,2}(?:\.\d{0,2})?[cdiouxXeEfgGqsaA]')


def load(path):
    with open(path, encoding="utf-8") as f:
        return dict(TEXT.findall(f.read()))


def parse(text):
    """Return (specs, bad) where bad lists any '%' sequence Lua would reject."""
    specs, bad = [], []
    i = 0
    while i < len(text):
        if text[i] != "%":
            i += 1
            continue
        if text.startswith("%%", i):
            i += 2
            continue
        m = VALID_SPEC.match(text, i)
        if m:
            specs.append(m.group(0)[-1])
            i = m.end()
        else:
            bad.append(text[i:i + 6])
            i += 1
    return specs, bad


def is_formatted(text):
    specs, bad = parse(text)
    return not bad and (specs or "%%" in text)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    en = load(os.path.join(LANG_DIR, "l10n_en.xml"))
    errors, warnings = [], []

    for path in sorted(glob.glob(os.path.join(LANG_DIR, "l10n_*.xml"))):
        lang = os.path.basename(path)
        if lang == "l10n_en.xml":
            continue
        for key, text in load(path).items():
            en_text = en.get(key)
            if en_text is None or not is_formatted(en_text):
                continue
            en_specs, _ = parse(en_text)
            specs, bad = parse(text)
            where = f"{lang} {key}"
            if bad:
                errors.append(f"{where}: invalid format sequence(s) {bad} - use '%%' for a literal percent sign")
            elif len(specs) > len(en_specs):
                errors.append(f"{where}: {len(specs)} placeholders but English supplies {len(en_specs)}")
            elif specs != en_specs[:len(specs)]:
                errors.append(f"{where}: placeholder types {specs} do not match English {en_specs}")
            elif len(specs) < len(en_specs):
                warnings.append(f"{where}: {len(specs)} of {len(en_specs)} placeholders used")

    if "--verbose" in sys.argv:
        for w in warnings:
            print(f"note: {w}")
    for e in errors:
        print(f"ERROR: {e}")
    print(f"{len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
