# trust/

Public trust material. No secrets here.

- `root.pub`: the offline ROOT public key (the same key the daemon embeds at build time).
- `keys.json`: `{"format":1,"seq":<u64>,"keys":["<minisign pubkey line>", ...]}`, the list of release keys the daemon trusts. `seq` only goes up.
- `keys.json.minisig`: detached ROOT signature over `keys.json`.

The ROOT secret key stays offline with the owner. To rotate or add a release key: edit `keys.json` (raise `seq`), sign it offline with the root key (`minisign -S -H -s root.key -m keys.json -x keys.json.minisig`), and open a PR with the two files. Catalog CI copies both into the published output and checks the signature against `root.pub` before it finishes.

The RELEASE secret key lives only in the GitHub Environment `release` of this repo (secrets `RELEASE_KEY`, optional `RELEASE_KEY_PASSWORD`), together with the repo variable or secret `STORE_READ_TOKEN` used to fetch the store sources. Until `root.pub` and `keys.json.minisig` exist, the real (push) job fails early; the pull-request dry-run still runs with throwaway keys.
