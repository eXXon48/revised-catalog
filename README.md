# revised-catalog

Catalog of CMU-Revised packages.

## Submission flow

1. A package repo tag `vN` triggers its CI, which builds an UNSIGNED `.rvp` and publishes it as a GitHub Release (exactly one `.rvp` asset).
2. A PR to this repo adds a `repo@tag sha256` line to `catalog.list` (the sha256 of that `.rvp`).
3. A same-repo PR (fork PRs are skipped: no secrets) runs a dry-run: `tools/build.sh` with throwaway keys. It downloads each listed release, checks the hash, signs, and verifies the result. The output is uploaded as an artifact; nothing real is signed.
4. After merge to `main`, the `release` job (GitHub Environment `release`) does the same with the real release key: it signs every package core, builds `catalog.json`, signs it, and uploads `out/`. Deploy to cmu-revised.com is not part of this repo yet.

Optional `meta/<name>.json` (a JSON object) overrides or adds only these entry fields: `title`, `subtitle`, `description`, `icon`, `screenshots`, `permissions`, `changes`. Any other key aborts the build.

## Keys

Two tiers. The offline ROOT key signs `trust/keys.json`, the list of release keys. The RELEASE key signs every package and `catalog.json`; it exists only as a secret of the `release` Environment. Setup and rotation: [`trust/README.md`](trust/README.md).

## Local dry-run

Needs `minisign`, `jq`, `gh` (logged in), and `rvp-pack` / `rvp-verify` built from cmu-re-store:

    RVP_BIN=/path/to/target/release tools/dry-run.sh /tmp/out

Output: `catalog.json(.minisig)`, `keys.json(.minisig)`, `pkgs/*.rvp`. Any failed check aborts with a non-zero exit.
