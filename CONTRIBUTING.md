# Contributing to eu-monitor-installer

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

- Keep the dry-run default and the `CONFIRM=yes` + ROE gate.
- Do not add automatic package installation, GPG-key import, or `systemctl enable`.
- Do not include real hostnames, addresses, or secrets in the example inventory.
- Run `shellcheck -x install.sh`, `ansible-playbook site.yml --syntax-check`, `ansible-lint`, and `python3 tests/test_install.py` before opening a pull request.
- Refresh `vendor/` from the companion repositories and update `vendor/SNAPSHOT.txt` when you intentionally bump the snapshot.

Security issues: [SECURITY.md](SECURITY.md).
