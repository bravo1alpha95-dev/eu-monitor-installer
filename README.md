# eu-monitor-installer

One-command installer for EmpowerU LLC's community access-monitoring toolkit and, optionally, its Wazuh rules pack.

**Defensive only. Owned systems only. Dry-run by default.** This installer copies files. It does **not** install Wazuh packages, open ports, enable systemd timers, or pipe vendor installers to a shell.

Companions:

- [eu-ec-detect-community](https://github.com/bravo1alpha95-dev/eu-ec-detect-community) — scripts and tests (vendored here as a snapshot)
- [eu-wazuh-detections](https://github.com/bravo1alpha95-dev/eu-wazuh-detections) — custom rules (also vendored)
- [eu-security-site](https://github.com/bravo1alpha95-dev/eu-security-site) — documentation site

## One-command entry

From this repository's root:

```bash
# Dry-run (default): print the plan, write nothing
./install.sh

# Optional: include Wazuh rules in the plan
./install.sh --with-wazuh-rules

# Apply, only with an authorized ROE, onto a prefix you choose
CONFIRM=yes ./install.sh --prefix /opt/eu-ec-detect --roe /path/to/authorized-roe.md
```

`CONFIRM=yes` without a completed ROE (`Status: AUTHORIZED` and every `(fill)` field set) is refused. The default vendored `scope/roe.md` is a DRAFT template, so a casual apply will not go through.

Ansible equivalent:

```bash
cd ansible
# Dry-run
ansible-playbook site.yml --check

# Apply
ansible-playbook site.yml -e eu_monitor_confirm=yes -e eu_monitor_roe_path=/path/to/authorized-roe.md
```

Copy `ansible/inventory/hosts.example.yml` to `ansible/inventory/hosts.yml` and replace the `10.0.0.10` placeholder with a host **you own**. The example inventory is not a real target list.

## What gets installed

| Item | Default destination | Notes |
|---|---|---|
| Community scripts, tests, docs, ROE template | `/opt/eu-ec-detect` | Prefix is configurable |
| `reports/` | `$prefix/reports` | Mode 0700 |
| Example systemd timer/service | `$prefix/systemd` | Copied only; **not** enabled |
| Wazuh rules (if requested) | `/var/ossec/etc/rules` | Optional decoder is copied only if that directory already exists |

Existing `scope/roe.md` and `scope/inventory.md` at the destination are not overwritten (idempotent with operator data).

The vendored Wazuh rules have **not** been tested with `wazuh-logtest` against a live manager. Validate them before any manager reload.

## Docker

A helper image runs the **read-only** easy path inside the container. It does not, by default, monitor the host.

```bash
docker compose build
docker compose run --rm eu-collect
```

Reports are written to a named volume. `CONFIRM` is never set in the Compose file. `docker build` was not run in the publishing environment (Docker was not available); the Dockerfile is written for Debian bookworm-slim with GNU sed.

## After install

```bash
cd /opt/eu-ec-detect
cp -n .env.example .env && chmod 600 .env
# Set EU_SCOPE_CIDR to the authorized range you own (10.0.0.0/24 in the example is a placeholder)
# Fill scope/inventory.md and scope/roe.md
./scripts/easy-run.sh
```

Review systemd units in `$prefix/systemd` before you install or enable them yourself.

## Checks

```bash
shellcheck -x install.sh
# From ansible/:
ansible-playbook site.yml --syntax-check
ansible-lint site.yml roles/eu_monitor
python3 tests/test_install.py
```

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 EmpowerU LLC.

Vulnerability reports: see [SECURITY.md](SECURITY.md) and `[CONTACT EMAIL]`.
