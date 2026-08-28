#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/src/kgb_zombie_escape.sma"
CONFIG="$ROOT_DIR/configs/kgb_zombie_escape.cfg.example"
LICENSE_FILE="$ROOT_DIR/LICENSE"

require_string() {
	local file="$1"
	local expected="$2"
	if ! grep -Fq "$expected" "$file"; then
		printf 'Missing required capability in %s: %s\n' "${file#"$ROOT_DIR/"}" "$expected" >&2
		exit 1
	fi
}

test -s "$SOURCE"
test -s "$CONFIG"
test -s "$LICENSE_FILE"
require_string "$SOURCE" 'SPDX-License-Identifier: GPL-3.0-or-later'
require_string "$SOURCE" '#define PLUGIN_VERSION "0.1.3"'
require_string "$SOURCE" '#include <reapi>'
require_string "$SOURCE" 'get_cvar_pointer("mp_round_infinite")'
require_string "$SOURCE" 'contain(round_infinite, "b") == -1 || contain(round_infinite, "f") == -1'
require_string "$SOURCE" 'if (!g_round_active || g_infection_started || !get_pcvar_num(g_cvar_enabled))'
require_string "$SOURCE" 'remove_task(TASK_BEGIN_INFECTION)'
require_string "$SOURCE" 'set_task(delay, "respawn_as_zombie", TASK_RESPAWN_BASE + victim)'
require_string "$SOURCE" 'ExecuteHamB(Ham_CS_RoundRespawn, id)'
require_string "$SOURCE" 'if (!g_round_active || !g_infection_started || g_round_ending)'
require_string "$SOURCE" 'set_task(0.1, "reconcile_roles_deferred", g_reconcile_task_id)'
require_string "$SOURCE" 'scheduled_round_serial != g_round_serial'
require_string "$SOURCE" 'if (humans > 0 && zombies == 0)'
require_string "$SOURCE" 'rg_round_end(1.0, WINSTATUS_CTS, ROUND_CTS_WIN)'
require_string "$SOURCE" 'rg_round_end(1.0, WINSTATUS_TERRORISTS, ROUND_TERRORISTS_WIN)'
require_string "$CONFIG" 'mp_round_infinite "bf"'
require_string "$LICENSE_FILE" 'GNU GENERAL PUBLIC LICENSE'

if grep -Eq 'precache_(model|sound|generic)' "$SOURCE"; then
	printf 'Custom asset precache detected; the core release must stay stock-assets-only.\n' >&2
	exit 1
fi

if test -n "${VERSION_TAG:-}"; then
	expected_version="${VERSION_TAG#v}"
	if test "$expected_version" = "$VERSION_TAG"; then
		printf 'VERSION_TAG must start with v: %s\n' "$VERSION_TAG" >&2
		exit 1
	fi
	require_string "$SOURCE" "#define PLUGIN_VERSION \"$expected_version\""
fi

python3 "$ROOT_DIR/scripts/check-role-reconciliation.py"

printf 'Zombie Escape source capability and version checks passed.\n'
