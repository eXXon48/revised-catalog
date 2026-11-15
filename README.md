# revised-catalog

Catalog of CMU-Revised packages. Submission flow: a package repo tag `vN` triggers its CI, which builds an unsigned `.rvp` and publishes it as a GitHub Release. A PR to this repo adds a `repo@tag sha256` line to `catalog.list`. Catalog CI then downloads each listed release, checks its hash, signs it with the release key, builds and signs `catalog.json`, and deploys it to cmu-revised.com. The release key lives only in this repo, as a CI secret.
