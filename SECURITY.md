# Security Considerations — eu-monitor-installer

## Reporting vulnerabilities

Please report security issues privately to **[CONTACT EMAIL]**. Do not open a public issue for a vulnerability, and do not attach production evidence, secrets, or personally identifiable information.

## Design

- Dry-run (or Ansible `--check`) is the default. Actual writes require `CONFIRM=yes` / `eu_monitor_confirm=yes` **and** a completed ROE with `Status: AUTHORIZED`.
- The installer copies vendored files. It does not download vendor packages, import GPG keys, enable systemd timers, or restart a Wazuh manager.
- Destinations that are symlinks are refused.
- Filled `scope/roe.md` and `scope/inventory.md` at the destination are not overwritten.
- Report directories are mode 0700. The install prefix is mode 0750.
- The Docker image runs as a non-root user, drops capabilities, and uses a read-only root filesystem. It collects from the container, not the host, unless you add bind mounts after review.

## Residual risks

- A completed ROE is an authorization record, not proof that the host is in scope. Confirm `EU_SCOPE_CIDR` and the inventory yourself.
- Ansible `become` is off by default. Escalating to write under `/opt` or `/var/ossec` is an operator decision.
- Vendored snapshots can drift from the companion repositories. Check `vendor/SNAPSHOT.txt`.
- The Wazuh rules this installer can copy are untested against a live manager.
