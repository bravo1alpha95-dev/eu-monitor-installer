#!/usr/bin/env bash
# One-command installer for the EmpowerU community monitoring toolkit.
# Dry-run by default. Copies vendored scripts (and optionally Wazuh rules)
# onto a host you own. Does not install Wazuh packages or start services.
#
# Usage:
#   ./install.sh                          # dry-run (default)
#   ./install.sh --prefix DIR             # destination (default /opt/eu-ec-detect)
#   ./install.sh --with-wazuh-rules       # also copy custom Wazuh rules
#   ./install.sh --wazuh-rules-dir DIR    # rules destination (default /var/ossec/etc/rules)
#   ./install.sh --roe PATH               # ROE file used for the mutation gate
#   CONFIRM=yes ./install.sh [options]    # actually write, requires authorized ROE
#
# After install, scripts/hardening-audit.sh is a read-only CIS-style audit.
# It ignores CONFIRM and never mutates the host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=vendor/eu-ec-detect-community/scripts/lib.sh
source "$ROOT/vendor/eu-ec-detect-community/scripts/lib.sh"

PREFIX=/opt/eu-ec-detect
WITH_WAZUH=0
WAZUH_RULES_DIR=/var/ossec/etc/rules
ROE="${EU_ROE:-$ROOT/vendor/eu-ec-detect-community/scope/roe.md}"
DRY_RUN=1
if [[ "${CONFIRM:-}" == "yes" ]]; then
  DRY_RUN=0
fi

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "[install] ERROR: $1 requires an argument" >&2; exit 1; }
      PREFIX=$2
      shift 2
      ;;
    --with-wazuh-rules)
      WITH_WAZUH=1
      shift
      ;;
    --wazuh-rules-dir)
      [[ $# -ge 2 ]] || { echo "[install] ERROR: $1 requires an argument" >&2; exit 1; }
      WAZUH_RULES_DIR=$2
      shift 2
      ;;
    --roe)
      [[ $# -ge 2 ]] || { echo "[install] ERROR: $1 requires an argument" >&2; exit 1; }
      ROE=$2
      shift 2
      ;;
    *)
      echo "[install] ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Refuse obviously unsafe destinations (symlink prefix, path traversal in args).
case "$PREFIX" in
  ''|-*|*..*)
    echo "[install] ERROR: unsafe --prefix" >&2
    exit 1
    ;;
esac
# Same rule for the rules destination: it decides where root writes rules and
# (via its parent directory) decoders, so no option-like or '..' paths.
case "$WAZUH_RULES_DIR" in
  ''|-*|*..*)
    echo "[install] ERROR: unsafe --wazuh-rules-dir" >&2
    exit 1
    ;;
esac

SRC_SCRIPTS="$ROOT/vendor/eu-ec-detect-community"
SRC_RULES="$ROOT/vendor/eu-wazuh-detections"
[[ -d "$SRC_SCRIPTS/scripts" ]] || { echo "[install] ERROR: missing vendored community scripts" >&2; exit 1; }

echo "[install] Mode: $( [[ $DRY_RUN -eq 1 ]] && echo DRY-RUN || echo APPLY )"
echo "[install] Date: $(iso_date)"
echo "[install] Prefix: $PREFIX"
echo "[install] ROE: $ROE"
echo "[install] Wazuh rules: $( [[ $WITH_WAZUH -eq 1 ]] && echo "yes -> $WAZUH_RULES_DIR" || echo "no" )"

ROE_OK=0
if roe_authorized "$ROE"; then
  ROE_OK=1
  echo "[install] ROE Status: AUTHORIZED"
else
  echo "[install] ROE Status: not AUTHORIZED (DRAFT, missing, or unfilled (fill) fields)"
fi

if [[ $DRY_RUN -eq 0 && $ROE_OK -eq 0 ]]; then
  echo "[install] ERROR: CONFIRM=yes given but ROE is not AUTHORIZED. Refusing to mutate."
  echo "[install] Fill every (fill) field in the ROE, set Status: AUTHORIZED, then re-run."
  exit 1
fi

planned=()
plan() { planned+=("$1"); echo "[install] $( [[ $DRY_RUN -eq 1 ]] && echo "Would: " || echo "Will: " )$1"; }

plan "create $PREFIX (mode 0750) and $PREFIX/reports (mode 0700) if missing"
plan "copy community scripts, scope templates, docs, and tests into $PREFIX"
plan "install systemd unit examples into $PREFIX/systemd (not enabled)"
if [[ $WITH_WAZUH -eq 1 ]]; then
  plan "copy Wazuh custom rules and optional decoders into $WAZUH_RULES_DIR (and the sibling decoders directory when it exists)"
  plan "leave Wazuh packages and manager services untouched"
fi
plan "not download, apt-get install, or systemctl enable anything"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[install] Dry-run only. No files were written."
  echo "[install] Re-run with CONFIRM=yes and an authorized ROE to apply, for example:"
  echo "  CONFIRM=yes $0 --prefix $PREFIX --roe $ROE$( [[ $WITH_WAZUH -eq 1 ]] && echo " --with-wazuh-rules --wazuh-rules-dir $WAZUH_RULES_DIR" )"
  exit 0
fi

# --- apply ---
# Copies below drop the checkout owner: when run as root, installed scripts and
# Wazuh rules must not stay writable by whoever cloned this repository.
copy_tree() {
  local src=$1 dest=$2
  if [[ -L "$dest" ]]; then
    echo "[install] ERROR: destination is a symlink: $dest" >&2
    return 1
  fi
  mkdir -p "$dest"
  # Directory-only copy; skip existing destination files that look like filled operator data.
  local rel path
  while IFS= read -r -d '' path; do
    rel="${path#"$src"/}"
    if [[ -d "$path" ]]; then
      mkdir -p "$dest/$rel"
      continue
    fi
    if [[ "$rel" == scope/roe.md || "$rel" == scope/inventory.md || "$rel" == .env ]]; then
      if [[ -e "$dest/$rel" && ! -L "$dest/$rel" ]]; then
        echo "[install] Keeping existing operator file: $dest/$rel"
        continue
      fi
    fi
    if [[ -L "$dest/$rel" ]]; then
      echo "[install] ERROR: refusing to overwrite symlink $dest/$rel" >&2
      return 1
    fi
    mkdir -p "$(dirname "$dest/$rel")"
    cp -a --no-preserve=ownership "$path" "$dest/$rel"
  done < <(find "$src" -mindepth 1 -print0)
}

# Create prefix first; refuse a symlink or a non-directory.
if [[ -L "$PREFIX" || ( -e "$PREFIX" && ! -d "$PREFIX" ) ]]; then
  echo "[install] ERROR: $PREFIX must be a real directory" >&2
  exit 1
fi
# Only a prefix this run creates gets mode 0750 (as the plan says); an existing
# directory such as /opt keeps its mode so other users are not locked out.
if [[ ! -d "$PREFIX" ]]; then
  mkdir -p "$PREFIX"
  chmod 750 "$PREFIX"
fi

copy_tree "$SRC_SCRIPTS" "$PREFIX"

# Entrypoints must be executable after copy (some filesystems drop the bit).
for s in 00_preflight.sh 10_collect.sh 20_apply.sh anomaly-checks.sh easy-run.sh hardening-audit.sh; do
  chmod 755 "$PREFIX/scripts/$s"
done
chmod 755 "$PREFIX/scripts/lib.sh"

if [[ -d "$ROOT/systemd" ]]; then
  mkdir -p "$PREFIX/systemd"
  cp -a --no-preserve=ownership "$ROOT/systemd/." "$PREFIX/systemd/"
fi

prepare_reports_dir "$PREFIX/reports"

if [[ $WITH_WAZUH -eq 1 ]]; then
  if [[ -L "$WAZUH_RULES_DIR" || ( -e "$WAZUH_RULES_DIR" && ! -d "$WAZUH_RULES_DIR" ) ]]; then
    echo "[install] ERROR: $WAZUH_RULES_DIR must be a real directory" >&2
    exit 1
  fi
  mkdir -p "$WAZUH_RULES_DIR"
  cp -a --no-preserve=ownership "$SRC_RULES/rules/eu_ec_detect_rules.xml" "$WAZUH_RULES_DIR/eu_ec_detect_rules.xml"
  # Decoders go next to rules only when a decoders directory already exists
  # (typical Wazuh layout: /var/ossec/etc/decoders). Never invent a sibling
  # under a test prefix unless asked.
  decoder_dest="$(dirname "$WAZUH_RULES_DIR")/decoders"
  if [[ -d "$decoder_dest" && ! -L "$decoder_dest" ]]; then
    cp -a --no-preserve=ownership "$SRC_RULES/decoders/eu_ec_detect_decoders.xml" "$decoder_dest/eu_ec_detect_decoders.xml"
    echo "[install] Wrote $decoder_dest/eu_ec_detect_decoders.xml"
  else
    echo "[install] INFO: no decoders directory at $decoder_dest; skipped optional decoder copy."
    echo "[install] Rules do not depend on the optional decoder."
  fi
  echo "[install] Wrote $WAZUH_RULES_DIR/eu_ec_detect_rules.xml"
  echo "[install] Validate with wazuh-logtest on your manager before reload. Rules were tested on Wazuh 4.14.10 only."
fi

echo "[install] Installed community toolkit at $PREFIX"
echo "[install] Next steps (manual):"
echo "  1. cd $PREFIX && cp -n .env.example .env && chmod 600 .env"
echo "  2. Edit .env (set EU_SCOPE_CIDR), scope/inventory.md, and scope/roe.md."
echo "  3. Run $PREFIX/scripts/easy-run.sh (read-only collection)."
echo "  4. Optionally run $PREFIX/scripts/hardening-audit.sh (read-only CIS-style audit; ignores CONFIRM)."
echo "  5. Systemd units, if you use them, are examples in $PREFIX/systemd — review, then install and enable yourself."
echo "  6. No packages were installed and no services were started."
exit 0
