# Source Tree

## Source

- `README.md`, `OPERATOR.md`, `RELEASE.md`, `TODO.md`
- `integrity_gate.rb`
- `verify_deploy_identity.rb`
- `master.json`
- `openbsd/`
- `rails/`
- `tools/`
- `archive/`
- `quarantine/`

## Local Or Generated

- VPS `/etc/*.env`
- VPS `/home/<app>/app`
- VPS `/home/<app>/shared`
- Rails `tmp/`, `log/`, `storage/`
- Rails `public/assets/`
- node_modules except committed lockfiles
- generated media under tools unless explicitly source

Do not copy live local state back into git unless it is a deliberate config/template change.
