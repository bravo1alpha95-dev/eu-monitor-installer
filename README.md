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
| Community scripts, tests, docs, ROE template | `/opt/eu-ec-detect` | Includes the read-only `hardening-audit.sh` |
| `reports/` | `$prefix/reports` | Mode 0700 |
| Example systemd timer/service | `$prefix/systemd` | Copied only; **not** enabled |
| Wazuh rules (if requested) | `/var/ossec/etc/rules` | Optional decoder is copied only if that directory already exists |

Existing `scope/roe.md` and `scope/inventory.md` at the destination are not overwritten (idempotent with operator data).

The vendored Wazuh rules pass `wazuh-logtest` on `wazuh/wazuh-manager` 4.8.2 through 4.14.10 in the companion [eu-wazuh-detections](https://github.com/bravo1alpha95-dev/eu-wazuh-detections) repository's CI (see [vendor/eu-wazuh-detections/docs/VERSION-MATRIX.md](vendor/eu-wazuh-detections/docs/VERSION-MATRIX.md)). File-integrity rules 100020 and 100021 cannot fire through logtest; they were verified on a live 4.14.10 lab only. Re-validate on your manager before any reload.

## Docker

A helper image runs the **read-only** easy path inside the container. It does not, by default, monitor the host.

```bash
docker compose build
docker compose run --rm eu-collect
```

Reports are written to a named volume. `CONFIRM` is never set in the Compose file.

**Verified 2026-11-13:** `docker compose build` produced `eu-ec-detect-community:local` from `debian:bookworm-slim`, and `docker compose run --rm eu-collect` completed the read-only easy path (exit 0). Preflight allowed collection (ROE is the DRAFT template). The reports volume held a text file and a JSON summary, directory mode 0700, file mode 0600, listening-socket addresses redacted. `CONFIRM` was not in the image environment. Docker Engine 29.9.3 was the official static x86_64 build (Debian apt mirrors were returning HTTP 500 in that environment, so packages were not used); Compose was v5.7.1. The daemon ran with `"iptables": false` because nftables/iptables were not installed on the host; container networking still worked. A `useradd` warning (`uid 10001` greater than `SYS_UID_MAX`) is cosmetic — the `euoperator` user was created and the container ran as 10001.

## After install

```bash
cd /opt/eu-ec-detect
cp -n .env.example .env && chmod 600 .env
# Set EU_SCOPE_CIDR to the authorized range you own (192.0.2.0/24 in the example is a placeholder)
# Fill scope/inventory.md and scope/roe.md
./scripts/easy-run.sh
# Optional, still read-only: CIS-style hardening audit (ignores CONFIRM, never mutates)
sudo ./scripts/hardening-audit.sh
# EU_AUDIT_NO_REPORT=yes ./scripts/hardening-audit.sh   # print only
# EU_AUDIT_FAIL_ON=fail ./scripts/hardening-audit.sh    # exit 2 if any FAIL
```

`scripts/hardening-audit.sh` checks a subset of common CIS-benchmark-style items (SSH, sudoers, firewall, world-writable paths, automatic updates, auditd, and password aging) and prints one `PASS`, `WARN`, or `FAIL` line per finding. It has no apply mode. Run it as root for complete results; anything it cannot read is reported as `WARN`. Reports go under `$prefix/reports/` (directory 0700, files 0600, redacted) unless `EU_AUDIT_NO_REPORT=yes`. This is a subset of CIS items, not a full benchmark or a compliance attestation. See the vendored community `README.md` for the finding table and `EU_AUDIT_ROOT` fixture mode.

Review systemd units in `$prefix/systemd` before you install or enable them yourself.

## Checks

```bash
shellcheck -x install.sh
# From ansible/:
ansible-playbook site.yml --syntax-check
ansible-lint site.yml roles/eu_monitor
python3 tests/test_install.py
# Vendored community checks (run from vendor/eu-ec-detect-community/):
shellcheck -x scripts/*.sh
python3 tests/test_regressions.py
python3 tests/test_hardening_audit.py
```

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 EmpowerU LLC.

Vulnerability reports: see [SECURITY.md](SECURITY.md) and bravo1alpha95@gmail.com.
