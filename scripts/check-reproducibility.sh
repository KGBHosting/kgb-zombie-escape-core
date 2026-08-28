#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMXX_VERSION="${AMXX_VERSION:-1.8.2}"
TEST_ROOT="$(mktemp -d)"
SOURCE_LIST="$TEST_ROOT/source-files.txt"
SOURCE_ARCHIVE="$TEST_ROOT/source.tar"
trap 'rm -rf "$TEST_ROOT"' EXIT

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

write_manifest() {
	local build_root="$1" scope="$2" output="$3"
	case "$scope" in
		source)
			find "$build_root/src" "$build_root/configs" -type f -print
			;;
		binary)
			find "$build_root/compiled" -type f \( -name '*.amxx' -o -name '*.amxx.sha256' \) -print
			;;
		*)
			printf 'Unknown reproducibility manifest scope: %s\n' "$scope" >&2
			exit 2
			;;
	esac | LC_ALL=C sort | while IFS= read -r path; do
		printf '%s  %s\n' "$(hash_file "$path")" "${path#"$build_root/"}"
	done > "$output"
}

# Materialize only repository inputs into two empty trees. Ignored compiler
# caches and prior compiled outputs cannot influence either build.
(
	cd "$ROOT_DIR"
	git ls-files --cached --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do
		test -f "$path" && printf '%s\n' "$path"
	done > "$SOURCE_LIST"
	tar -cf "$SOURCE_ARCHIVE" -T "$SOURCE_LIST"
)

for build_name in build-one build-two; do
	build_root="$TEST_ROOT/$build_name"
	mkdir -p "$build_root"
	tar -xf "$SOURCE_ARCHIVE" -C "$build_root"
	AMXX_VERSION="$AMXX_VERSION" "$build_root/scripts/build.sh"
	write_manifest "$build_root" source "$TEST_ROOT/$build_name-source.sha256"
	write_manifest "$build_root" binary "$TEST_ROOT/$build_name-binary.sha256"
	test -s "$TEST_ROOT/$build_name-source.sha256"
	test -s "$TEST_ROOT/$build_name-binary.sha256"
done

cmp "$TEST_ROOT/build-one-source.sha256" "$TEST_ROOT/build-two-source.sha256"
cmp "$TEST_ROOT/build-one-binary.sha256" "$TEST_ROOT/build-two-binary.sha256"

FIRST_ROOT="$TEST_ROOT/build-one"
FIRST_ARTIFACT="$FIRST_ROOT/compiled/kgb_zombie_escape.amxx"
FIRST_CHECKSUM="$FIRST_ARTIFACT.sha256"
test "$(hash_file "$FIRST_ARTIFACT")" = "$(awk '{print $1}' "$FIRST_CHECKSUM")"

# Promote one of the two independently verified builds for release upload.
mkdir -p "$ROOT_DIR/compiled"
cp "$FIRST_ARTIFACT" "$FIRST_CHECKSUM" "$ROOT_DIR/compiled/"

printf 'Independent source manifests match: %s\n' "$(hash_file "$TEST_ROOT/build-one-source.sha256")"
printf 'Independent binary manifests match: %s\n' "$(hash_file "$TEST_ROOT/build-one-binary.sha256")"
printf 'Reproducible AMX Mod X %s artifact SHA-256: %s\n' \
	"$AMXX_VERSION" "$(hash_file "$FIRST_ARTIFACT")"
