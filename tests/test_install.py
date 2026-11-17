#!/usr/bin/env python3
"""Installer dry-run and ROE-gate regressions. No package installs, no services."""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "install.sh"

AUTHORIZED_ROE = "Status: AUTHORIZED\n" + "\n".join(
    "- " + k + ": test-approved"
    for k in (
        "Authorizer / program",
        "Written permission location",
        "Window (start / end, timezone)",
        "Contact",
        "Operator",
        "Date",
    )
)


class Installer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="eu-install-")
        self.addCleanup(self.tmp.cleanup)
        self.prefix = Path(self.tmp.name) / "prefix"
        self.roe = Path(self.tmp.name) / "roe.md"
        self.env = dict(os.environ)
        self.env.pop("CONFIRM", None)

    def run_install(self, *args, confirm=False, timeout=20):
        env = dict(self.env)
        if confirm:
            env["CONFIRM"] = "yes"
        cmd = ["/bin/bash", str(INSTALL), "--prefix", str(self.prefix), "--roe", str(self.roe), *args]
        return subprocess.run(cmd, cwd=str(ROOT), env=env, text=True, capture_output=True, timeout=timeout)

    def test_dry_run_writes_nothing(self):
        self.roe.write_text(AUTHORIZED_ROE)
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("DRY-RUN", result.stdout)
        self.assertFalse(self.prefix.exists())

    def test_confirm_without_roe_is_refused(self):
        self.roe.write_text("Status: DRAFT\n- Authorizer / program: (fill)\n")
        result = self.run_install(confirm=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.prefix.exists())

    def test_confirm_with_authorized_roe_installs_scripts(self):
        self.roe.write_text(AUTHORIZED_ROE)
        result = self.run_install(confirm=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue((self.prefix / "scripts/easy-run.sh").is_file())
        self.assertTrue(os.access(self.prefix / "scripts/easy-run.sh", os.X_OK))
        self.assertTrue((self.prefix / "scripts/hardening-audit.sh").is_file())
        self.assertTrue(os.access(self.prefix / "scripts/hardening-audit.sh", os.X_OK))
        self.assertTrue((self.prefix / "tests/test_hardening_audit.py").is_file())
        self.assertTrue((self.prefix / "tests/fixtures/hardening/hardened/etc/ssh/sshd_config").is_file())
        self.assertEqual(stat.S_IMODE((self.prefix / "reports").stat().st_mode), 0o700)
        self.assertTrue((self.prefix / "systemd/eu-ec-detect-collect.service").is_file())
        # Second apply is idempotent and keeps a filled ROE.
        filled = self.prefix / "scope/roe.md"
        filled.write_text(AUTHORIZED_ROE + "\n# operator notes\n")
        result = self.run_install(confirm=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("operator notes", filled.read_text())

    def test_wazuh_rules_optional_and_decoder_skipped_without_dir(self):
        self.roe.write_text(AUTHORIZED_ROE)
        rules = Path(self.tmp.name) / "rules"
        result = self.run_install("--with-wazuh-rules", "--wazuh-rules-dir", str(rules), confirm=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue((rules / "eu_ec_detect_rules.xml").is_file())
        self.assertIn("skipped optional decoder", result.stdout)
        self.assertFalse((Path(self.tmp.name) / "decoders").exists())

    def test_symlink_prefix_refused(self):
        self.roe.write_text(AUTHORIZED_ROE)
        target = Path(self.tmp.name) / "outside"
        target.mkdir()
        self.prefix.symlink_to(target)
        result = self.run_install(confirm=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(target.iterdir()), [])

    def test_installed_hardening_audit_is_read_only_on_fixtures(self):
        self.roe.write_text(AUTHORIZED_ROE)
        result = self.run_install(confirm=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        fixture = self.prefix / "tests/fixtures/hardening/hardened"
        before = {path: path.stat().st_mtime_ns for path in fixture.rglob("*") if path.is_file()}
        env = dict(self.env)
        env.update({
            "EU_AUDIT_ROOT": str(fixture.resolve()),
            "EU_AUDIT_NO_REPORT": "yes",
            "CONFIRM": "yes",  # must be ignored; the audit never mutates
        })
        audit = subprocess.run(
            ["/bin/bash", str(self.prefix / "scripts/hardening-audit.sh")],
            cwd=str(self.prefix),
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        self.assertEqual(audit.returncode, 0, audit.stderr + audit.stdout)
        self.assertIn("PASS", audit.stdout)
        self.assertIn("FAIL=0", audit.stdout)
        self.assertFalse(
            any(line.startswith("FAIL") for line in audit.stdout.splitlines()),
            audit.stdout,
        )
        self.assertEqual(
            {path: path.stat().st_mtime_ns for path in fixture.rglob("*") if path.is_file()},
            before,
        )
        # No report files should be created when EU_AUDIT_NO_REPORT=yes
        self.assertEqual(list((self.prefix / "reports").glob("*hardening*")), [])

    def test_help_exits_zero(self):
        result = subprocess.run(["/bin/bash", str(INSTALL), "--help"], cwd=str(ROOT),
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Dry-run", result.stdout)
        self.assertIn("hardening-audit.sh", result.stdout)

    def test_ansible_applies_0750_only_when_creating_prefix(self):
        text = (ROOT / "ansible/roles/eu_monitor/tasks/main.yml").read_text()
        self.assertIn("eu_monitor_prefix_stat", text)
        self.assertIn("when: not eu_monitor_prefix_stat.stat.exists", text)
        self.assertIn('mode: "0750"', text)
        # The prefix create task, not a later unconditional chmod, is gated.
        create = text.split("- name: Create the install prefix", 1)[1]
        create = create.split("- name: Ensure an existing install prefix", 1)[0]
        self.assertIn('mode: "0750"', create)
        self.assertIn("when: not eu_monitor_prefix_stat.stat.exists", create)
        self.assertIn("eu_monitor_rules_dir_stat", text)
        self.assertIn("when: not eu_monitor_rules_dir_stat.stat.exists", text)

    def test_vendored_fim_test_ignores_stale_alerts(self):
        text = (ROOT / "vendor/eu-wazuh-detections/lab/fim-test.sh").read_text()
        self.assertIn("ALERTS_START", text)
        self.assertIn("def new_alerts", text)
        self.assertIn("if os.path.getsize(path) < start:", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
