"""Generate reproducible PCRE2 reference outputs for the shared supported subset.

Run using Python pcre2==0.6.0, whose bundled PCRE2 release is recorded below.
Inputs are constructed, not independent benchmark tasks or PCRE conformance.
"""
from pathlib import Path
import json
import re
import itertools
import pcre2
from pcre2 import _cy

patterns = [
    r"(?<=colou?r=)\w+", r"(?<!colou?r=)\w+",
    r"(?<=ID-|REF-)\d+", r"(?<!ID-|REF-)\d+",
    r"(?<=a{1,3})b", r"(?<!a{1,3})b",
    r"(?<=ab|b)x", r"(?<=b|ab)x", r"(?<=甲😀|😀)-\d+",
    r"(?<=(a)|(ba))x", r"(?<=(ba)|(a))x",
    r"(?i:(a)\1)", r"(?i:(?<x>K)\k<x>)", r"(?i:(Σ)\1)",
    r"(?i:(αβ)\1)", r"(?i:(a)\1)b", r"(?i:(a))\1",
    r"(?<=(?:AA|B){1,2})z", r"(?<=.{0,2}#)\d+",
    r"\x{1F600}", r"[\x{41}-\x{5A}]+", r"(?i:\x{212A})",
    r"(?i:(a|aa)\1)", r"(?i:(ab|a)b?\1)", r"(?i:((a)|(aa))\1)",
    r"(?>a|ab)c", r"(?>ab|a)c", r"(?:a|ab)c", r"a*+a", r"a++a", r"a?+a?+a",
    r"a{1,3}+a", r"(?>a*)b", r"(?>(ab|a)+)c", r"(?>(?=a)a)b", r"((?>a|ab)c|abc)",
    r"(?>(a|ab))\1", r"(?:ab|a)++c", r"(?>\d+)foo", r"\d++foo",
    r"(?>a|aa)a", r"(?>aa|a)a", r"(?:a|aa)++a", r"(?>(a?))a",
    r"(?>(a|b)+)a", r"(?>a?)a", r"(?>(?>a|aa)+)a", r"(?:(?>a?))*+b",
    r"(?>(?:))a", r"(?>(a|aa)){1,2}+b", r"(?>(a?))b",
]
# Exercise atomic commitment in combinations of ambiguous alternatives,
# nested captures, empty alternatives and trailing requirements. These cases
# are constructed, not a PCRE conformance suite or an external benchmark.
atomic_bodies = [r'a', r'a?', r'a*', r'(?:a|ab)', r'(?:ab|a)', r'(a|ab)', r'(a?)', r'(?:a|)']
atomic_suffixes = [r'a', r'b', r'a?b', r'(?:ab|a)']
patterns += [fr'(?>{body}){suffix}' for body in atomic_bodies for suffix in atomic_suffixes]
patterns += [fr'(?:{body})++{suffix}' for body in [r'a', r'ab', r'(?:a|ab)', r'(ab|a)'] for suffix in atomic_suffixes]
patterns += [
    r'((?>a)a?b|ab)', r'((?>a)a*b|ab)', r'(?:(?>a?)|ab)b',
    r'(?:(?>ab|a)|a)b', r'(?:(?>a*)|a)b', r'(?:(?>a)?)?a',
    r'(?>a)(a|aa)+', r'(?>a)(aa|a)+', r'((?>a)|aa)(a?)b',
    r'(?:(?>a)|b)+?b', r'(?:(?>a)|b)++a', r'(?>(?=(a))a)\1',
]
texts = [
    "", "color=red colour=blue colr=no", "ID-42 REF-71 XYZ-9", "b ab aab aaab aaaab",
    "abx bax bx xx", "甲😀-12 😀-99 甲-7", "aA", "aB", "KK kK", "Σς σΣ",
    "αβΑΒ", "aaB aAb", "AAz Bz AABz BBBz z", "#7 a#8 ab#9 abc#10", "x\ny#4",
    "aaaa", "aAaA", "AaAA", "abab", "AbAB", "abaA",
    "abc", "ababc", "aaa", "aa", "bbb", "123foo", "123bar", "123456foo",
]
for length in range(1, 6):
    for chars in itertools.product('ab', repeat=length):
        text=''.join(chars)
        if text not in texts:
            texts.append(text)
cases=[]
for pattern in patterns:
    # The Python wrapper enables ALT_BSUX unconditionally, making PCRE2's
    # \x{...} mean literal text. Disable it and UCP using the pinned wrapper's
    # low-level API: PCRE2_UTF remains enabled, while \d/\w stay ASCII.
    pcre2_alt_bsux=0x00000002  # PCRE2 10.47 pcre2.h
    code=_cy.compile(pattern, 0, pcre2_alt_bsux | int(_cy.CompileOption.UCP))
    compiled=pcre2.Pattern(code, pattern, pcre2.ASCII, False)
    for text in texts:
        matches=list(compiled.finditer(text))
        chunks=[]
        end=0
        for match in matches:
            chunks.append(text[end:match.start()])
            parts=[match.group(i) or '' if i <= compiled.groups else '' for i in (0,1,2)]
            chunks.append('<' + '>|<'.join(parts) + '>')
            end=match.end()
        chunks.append(text[end:])
        cases.append({
            "pattern":pattern,"text":text,"full":compiled.fullmatch(text) is not None,
            "matches":[[match.group(i) for i in range(compiled.groups+1)] for match in matches],
            "replacement":''.join(chunks),
        })
# Exercise all pairs in the vendored, versioned simple-fold cycle table.
# PCRE2 computes expected matches independently; using that table to choose
# characters does not claim coverage of mappings absent from the table.
fold_source=Path('internal/regexp/unicode/case_folding.mbt').read_text(encoding='utf-8')
fold_pairs=re.findall(r"'\\u\{([0-9a-fA-F]+)\}': '\\u\{([0-9a-fA-F]+)\}'",fold_source)
assert len(fold_pairs) > 2000
fold_cases=[]
for first,second in fold_pairs:
    a,b=chr(int(first,16)),chr(int(second,16))
    pattern=r'(?i:(\x{' + first + r'})\1)'
    code=_cy.compile(pattern,0,0x00000002 | int(_cy.CompileOption.UCP))
    compiled=pcre2.Pattern(code,pattern,pcre2.ASCII,False)
    fold_cases.append({"pattern":pattern,"text":a+b,"full":compiled.fullmatch(a+b) is not None})
out=Path('artifacts/regex-extended/pcre2-cases.json')
out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes((json.dumps({"wrapper":pcre2.__version__,"pcre2":pcre2.__libpcre2_version__,"options":"UTF, no UCP, no ALT_BSUX, interpreter without JIT","cases":cases,"fold_cases":fold_cases},ensure_ascii=False,indent=2)+'\n').encode())
print(f'Generated {len(cases)} constructed cases and {len(fold_cases)} Unicode fold pairs with PCRE2 {pcre2.__libpcre2_version__}.')
