# trust-dev/

Dev counterpart of `trust/`, used only by the `publish-dev` job (branch `develop`). No secrets here.

- `root.pub`: the dev ROOT public key; must equal `daemon/trust/root-dev.pub` in cmu-re-store at `RVP_STORE_REV`.
- `keys.json` + `keys.json.minisig`: dev release keys, signed by the dev root (same format and `seq` rule as `trust/`).

Dev and prod roots never mix: a daemon built from a `dev/v*` tag trusts only this root.
