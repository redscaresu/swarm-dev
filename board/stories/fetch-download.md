---
kind: code
status: ready
epic: binary-fetch
depends_on: []
touches: [bin/lib/binary.sh:binary_download (new, at the file's end), bin/lib/binary.sh:binary_repo (new, at the file's end), bin/lib/binary.sh:BINARY_CANNOT (new, beside binary_download), bin/lib/binary.sh:header comment, tests/binary_fetch_stubs.sh, tests/binary_download_test.sh, docs/port/tests.tsv:tests/binary_download_test.sh row]
estimate_lines: 200
risk: high
---

# binary_download fetches this version's asset and checksum file with gh and checks the SHA-256

Needs no other story.
Adds the download step only. Nothing calls it until fetch-ensure, so no user-visible behaviour and no doc changes; say so in the PR.
Where: bin/lib/binary.sh, a new block at the file's end, after binary_run (:135). The wave's other binary.sh edits are elsewhere: fetch-attest right after binary_find, fetch-build right above binary_path, fetch-find inside binary_find. Rewrite the header (:1-5), which says nothing here downloads; no other wave-1 story touches it.
binary_repo: prints one named constant, redscaresu/swarm-dev, so release-client can change only its body.
BINARY_CANNOT=3, beside binary_download: the named exit code for 'the download cannot work here'. fetch-fallback builds from source on it and on nothing else. Every other failure returns 1.
binary_download <root> <version> <dir>:
- The contract from `bash <root>/scripts/build.sh --list` (scripts/build.sh:8-11): this platform's asset and the checksum file. Keep no copy of the names. No scripts/build.sh, or a list this cannot read: one line, return 1 (a broken install, never a fallback).
- The platform from uname -s and uname -m, mapped to --list's os/arch (Darwin darwin, Linux linux, x86_64 amd64, arm64 and aarch64 arm64). A platform --list lacks: one line, BINARY_CANNOT.
- gh from PATH (fetch-ensure hands it a PATH with no gh-shim folder). No gh: one line, BINARY_CANNOT.
- `gh release download v<version> --repo github.com/<repo> --pattern <asset> --pattern <checksums> --dir <dir>`. The host is named, so GH_HOST never sends it elsewhere. A failure: one line quoting gh's first non-empty stderr line and nothing else of gh's, BINARY_CANNOT. A gh that is not logged in fails here, and its own first line names gh auth login.
- The SHA-256 of <dir>/<asset> (sha256sum, else shasum -a 256, as scripts/build.sh:36-39), compared with the one checksum line whose name field is exactly the asset (`<hex>  <name>` or `<hex> *<name>`). Never a prefix or suffix match. No such line, two of them, or another sum: one line, return 1.
- It writes only inside <dir>, never <root>/swarm. Each line starts `binary: ` and says what to do.
No python3, no curl, no lock, no new SWARM_ or SWARMDEV_ name.
Tests: new tests/binary_fetch_stubs.sh, which every later fetch test sources. It holds a fake release (make test's SWARMDEV_BIN copied as the asset, so wrapper-fixture runs) with its checksum file, and a logging uname stub. It also holds a gh stub that serves only the exact release download it is given (tag, github.com repo, both patterns, --dir), writes the files there, logs each call with its GH_HOST, can fail with a given stderr, and logs and exits 1 on any other arguments. Patterns: tests/binary_build_test.sh:28-36,64-77.
New tests/binary_download_test.sh sources bin/lib/binary.sh, so it adds its docs/port/tests.tsv row (docs/port/README.md says how).
risk high: this is the integrity check on a file every later call runs.

**Done when:**
- With GH_HOST=ghe.example.com set and the stubs first on PATH, binary_download <copy> <version> <dir> returns 0. The gh stub logged exactly one call: release download v<version> --repo github.com/redscaresu/swarm-dev, this platform's asset and SHA256SUMS as patterns, --dir <dir>. <dir>/<asset> is cmp-equal to the fake release.
- A copy whose scripts/build.sh --list names other values (asset swarm-<os>-<arch>-x, checksums SUMS-X): the gh stub sees those two patterns, and the sum is read from SUMS-X.
- Each returns 1 with exactly one stderr line naming the check, and leaves nothing at <copy>/swarm: a wrong sum on the asset's line; a checksum file whose only line names the asset plus a suffix and carries the asset's true SHA-256; a checksum file that names the asset twice; no scripts/build.sh.
- Each returns BINARY_CANNOT with exactly one stderr line: a uname stub reporting Linux riscv64; no gh on PATH; the gh stub failing with stderr 'first line' then 'second line', whose line quotes the first and not the second.
- No case writes outside <dir>: a listing of <copy> before and after each case matches.
- Mutations on a copy, FAIL lines quoted in the PR, each turning a named case red: the sum compare removed (the wrong-sum case); the exact-name match loosened to a prefix (the suffix case); the --list read replaced by today's literal names (the SUMS-X case); the github.com host dropped (the GH_HOST case).
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
