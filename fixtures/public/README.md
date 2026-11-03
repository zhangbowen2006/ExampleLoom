# Pinned public data and reproduction

These are public records used for project-defined transformation tasks. They are
not customer data or an independently administered benchmark. They informed
development; do not describe the resulting accuracy as blind generalization.

| Snapshot | Included records | License |
| --- | --- | --- |
| [IANA tzdb 2025b](https://github.com/eggert/tz/blob/2025b/zone1970.tab) | All 312 non-comment zone1970.tab zone identifiers | Public domain; see iana-LICENSE |
| [Unicode CLDR JSON 48.0.0](https://github.com/unicode-org/cldr-json/blob/48.0.0/cldr-json/cldr-core/availableLocales.json) | All 766 availableLocales.full identifiers | Unicode-3.0; see cldr-LICENSE |
| [github/gitignore at 6bb5af7](https://github.com/github/gitignore/tree/6bb5af7a1b050e5add3a71b6e6365c93498822ac) | All 312 blob paths ending in .gitignore; template contents are not copied | CC0-1.0; see gitignore-LICENSE |

`manifest.json` records full URLs, snapshot versions, retrieval date and SHA-256
for every source/license. `python scripts/import-public-data.py` verifies these
hashes and regenerates all three examples offline. `--refresh` re-downloads the
same pinned bytes and rejects changed hashes. License copies also ship in
`LICENSES/` inside the standalone distribution.

Transforms and expected values are specified using Python operations in that
script, independently of the MoonBit interpreter. No source record is omitted
because a prediction is wrong. Initial labels cover different component counts,
path depths and identifier lengths. The original 3 alphabetic template-name
labels did not disambiguate ASCII-letter extraction from basename truncation:
25 of 309 remaining names were wrong. The fixed interaction policy allows two
additional labels, selected by the engine's highest disagreement score without
examining expected answers. The oracle emulates the user's responses for those
two rows (`C.gitignore`, then `C++.gitignore`); exclude them from held-out counts.
This is an interactive test, not a claim that three labels always suffice.

Run `node scripts/public-data-test.mjs`, then `python scripts/verify-sqlite.py`.
The first preserves learning stats/refinement trace, selects rank 0 without an
oracle candidate search, tests recipe reload and shifted columns, and exports
all CSV rows. The second imports those files with Python csv + SQLite, compares
every field and executes three catalog lookup queries. Browser tests reproduce
the same labeling/refinement/download workflow and compare all exported bytes.
This establishes local integration, not production adoption.
