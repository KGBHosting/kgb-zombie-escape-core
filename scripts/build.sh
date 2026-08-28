#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMXX_VERSION="${AMXX_VERSION:-1.8.2}"
BUILD_COMPONENTS="${BUILD_COMPONENTS:-core}"
# Pinned Debian image used by the sibling KGB AMXX repositories. Override only
# for local diagnosis; release builds always use this digest.
DOCKER_IMAGE="${DOCKER_IMAGE:-debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171}"
REAPI_VERSION="${REAPI_VERSION:-5.29.0.358}"
REAPI_URL="${REAPI_URL:-https://github.com/rehlds/ReAPI/releases/download/5.29.0.358/reapi-bin-5.29.0.358.zip}"
REAPI_SHA256="${REAPI_SHA256:-f33a7435540bea8706db3fa948e51a85b511f5b18c383b97402a204dc5419195}"

case "$AMXX_VERSION" in
	1.8 | 1.8.2)
		AMXX_VERSION="1.8.2"
		AMXX_URL="${AMXX_URL:-https://www.amxmodx.org/amxxdrop/1.8/amxmodx-1.8.2-dev-hg34-base.tar.gz}"
		AMXX_SHA256="${AMXX_SHA256:-8a8293df0f9cc4ab1f2040b60e7cbd5ac86ee95c0fda2d40b344f12ed18bc5cc}"
		;;
	1.9)
		AMXX_URL="${AMXX_URL:-https://www.amxmodx.org/amxxdrop/1.9/amxmodx-1.9.0-git5303-base-linux.tar.gz}"
		AMXX_SHA256="${AMXX_SHA256:-1ed6898ced2c1fcf225c288b94effc19917e987b284e42911587738ee3c93699}"
		;;
	1.10)
		AMXX_URL="${AMXX_URL:-https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5479/amxmodx-1.10.0-git5479-base-linux.tar.gz}"
		AMXX_SHA256="${AMXX_SHA256:-425b53256dbad0ddaeb7935f771d07d85b6c146ed7d1e72d815221042030602d}"
		;;
	*)
		printf 'Unsupported AMXX_VERSION: %s\n' "$AMXX_VERSION" >&2
		printf 'Supported values: 1.8.2, 1.9, 1.10\n' >&2
		exit 1
		;;
esac

AMXX_ARCHIVE_NAME="${AMXX_URL##*/}"
AMXX_CACHE_DIR="$ROOT_DIR/.ci/amxx/$AMXX_VERSION"
AMXX_ARCHIVE="$ROOT_DIR/.ci/downloads/$AMXX_VERSION/$AMXX_ARCHIVE_NAME"
DEFAULT_AMXX_DIR="$AMXX_CACHE_DIR/addons/amxmodx/scripting"
AMXX_DIR="${AMXX_DIR:-$DEFAULT_AMXX_DIR}"
REAPI_ARCHIVE_NAME="${REAPI_URL##*/}"
REAPI_CACHE_DIR="$ROOT_DIR/.ci/reapi/$REAPI_VERSION"
REAPI_ARCHIVE="$ROOT_DIR/.ci/downloads/reapi/$REAPI_ARCHIVE_NAME"
DEFAULT_REAPI_INCLUDE_DIR="$REAPI_CACHE_DIR/addons/amxmodx/scripting/include"
REAPI_INCLUDE_DIR="${REAPI_INCLUDE_DIR:-$DEFAULT_REAPI_INCLUDE_DIR}"

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

write_checksum() {
	local artifact="$1"
	local basename
	basename="${artifact##*/}"
	printf '%s  %s\n' "$(hash_file "$artifact")" "$basename" > "$artifact.sha256"
}

verify_amxx_magic() {
	local artifact="$1"
	local magic
	magic="$(LC_ALL=C od -An -tx1 -N4 "$artifact" | tr -d '[:space:]')"
	test "$magic" = "58584d41"
}

verify_archive() {
	test -f "$AMXX_ARCHIVE" && test "$(hash_file "$AMXX_ARCHIVE")" = "$AMXX_SHA256"
}

ensure_amxx() {
	if test -x "$AMXX_DIR/amxxpc" \
		&& test -f "$AMXX_DIR/include/amxmodx.inc" \
		&& test -f "$AMXX_DIR/include/amxmisc.inc" \
		&& test -f "$AMXX_DIR/include/cstrike.inc" \
		&& test -f "$AMXX_DIR/include/fakemeta.inc" \
		&& test -f "$AMXX_DIR/include/fun.inc" \
		&& test -f "$AMXX_DIR/include/hamsandwich.inc"; then
		return
	fi

	if test "$AMXX_DIR" != "$DEFAULT_AMXX_DIR"; then
		printf 'AMXX_DIR is missing required compiler files: %s\n' "$AMXX_DIR" >&2
		exit 1
	fi

	mkdir -p "$(dirname "$AMXX_ARCHIVE")"
	if ! verify_archive; then
		partial_archive="$AMXX_ARCHIVE.part"
		rm -f "$partial_archive"
		curl --fail --location --show-error --silent "$AMXX_URL" --output "$partial_archive"
		if test "$(hash_file "$partial_archive")" != "$AMXX_SHA256"; then
			rm -f "$partial_archive"
			printf 'AMX Mod X archive checksum did not match expected SHA-256.\n' >&2
			exit 1
		fi
		mv "$partial_archive" "$AMXX_ARCHIVE"
	fi

	if ! verify_archive; then
		printf 'AMX Mod X archive checksum did not match expected SHA-256.\n' >&2
		exit 1
	fi

	rm -rf "$AMXX_CACHE_DIR"
	mkdir -p "$AMXX_CACHE_DIR"
	tar -xzf "$AMXX_ARCHIVE" -C "$AMXX_CACHE_DIR"

	if ! test -x "$AMXX_DIR/amxxpc"; then
		printf 'AMX Mod X compiler was not found after extraction.\n' >&2
		exit 1
	fi
}

verify_reapi_archive() {
	test -f "$REAPI_ARCHIVE" && test "$(hash_file "$REAPI_ARCHIVE")" = "$REAPI_SHA256"
}

ensure_reapi_include() {
	if test -f "$REAPI_INCLUDE_DIR/reapi.inc" \
		&& test -f "$REAPI_INCLUDE_DIR/reapi_gamedll.inc" \
		&& test -f "$REAPI_INCLUDE_DIR/reapi_gamedll_const.inc"; then
		return
	fi

	if test "$REAPI_INCLUDE_DIR" != "$DEFAULT_REAPI_INCLUDE_DIR"; then
		printf 'REAPI_INCLUDE_DIR is missing required include files: %s\n' "$REAPI_INCLUDE_DIR" >&2
		exit 1
	fi

	mkdir -p "$(dirname "$REAPI_ARCHIVE")"
	if ! verify_reapi_archive; then
		partial_reapi_archive="$REAPI_ARCHIVE.part"
		rm -f "$partial_reapi_archive"
		curl --fail --location --show-error --silent "$REAPI_URL" --output "$partial_reapi_archive"
		if test "$(hash_file "$partial_reapi_archive")" != "$REAPI_SHA256"; then
			rm -f "$partial_reapi_archive"
			printf 'ReAPI archive checksum did not match expected SHA-256.\n' >&2
			exit 1
		fi
		mv "$partial_reapi_archive" "$REAPI_ARCHIVE"
	fi

	if ! verify_reapi_archive; then
		printf 'ReAPI archive checksum did not match expected SHA-256.\n' >&2
		exit 1
	fi

	rm -rf "$REAPI_CACHE_DIR"
	mkdir -p "$REAPI_CACHE_DIR"
	unzip -q "$REAPI_ARCHIVE" -d "$REAPI_CACHE_DIR"

	if ! test -f "$REAPI_INCLUDE_DIR/reapi.inc"; then
		printf 'ReAPI include was not found after extraction.\n' >&2
		exit 1
	fi
}

component_source() {
	case "$1" in
	core) printf '%s\n' 'src/kgb_zombie_escape.sma' ;;
	*)
			printf 'Unknown build component: %s\n' "$1" >&2
			printf 'Supported components: core\n' >&2
			exit 1
			;;
	esac
}

if ! command -v docker >/dev/null 2>&1; then
	printf 'Docker is required to compile the 32-bit AMX Mod X plugins.\n' >&2
	exit 1
fi

ensure_amxx
ensure_reapi_include
mkdir -p "$ROOT_DIR/compiled"
printf 'Compiling with AMX Mod X %s\n' "$AMXX_VERSION"

for component in $BUILD_COMPONENTS; do
	source_path="$(component_source "$component")"
	artifact_path="compiled/${source_path##*/}"
	artifact_path="${artifact_path%.sma}.amxx"

	if ! test -f "$ROOT_DIR/$source_path"; then
		printf 'Source for component %s was not found: %s\n' "$component" "$source_path" >&2
		exit 1
	fi

	rm -f "$ROOT_DIR/$artifact_path" "$ROOT_DIR/$artifact_path.sha256"
	compile_log="$(mktemp)"
	compile_status=0
	docker run --rm --pull=missing --platform linux/386 --network none \
		--read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m \
		-v "$ROOT_DIR:/work" \
		-v "$AMXX_DIR:/amxx:ro" \
		-v "$REAPI_INCLUDE_DIR:/reapi/include:ro" \
		-e LD_LIBRARY_PATH=/amxx \
		-w /work \
		"$DOCKER_IMAGE" \
		/amxx/amxxpc "$source_path" -d0 -i/amxx/include -i/reapi/include -o"$artifact_path" \
		2>&1 | tee "$compile_log" || compile_status=$?

	# amxxpc releases can return zero after reporting compilation errors, so the
	# log is an additional mandatory success signal.
	if test "$compile_status" -ne 0 \
		|| grep -Eq ' : (fatal )?error [0-9]+:|^[1-9][0-9]* Errors?\.$' "$compile_log"; then
		rm -f "$compile_log" "$ROOT_DIR/$artifact_path" "$ROOT_DIR/$artifact_path.sha256"
		printf 'Compilation failed for %s.\n' "$source_path" >&2
		exit 1
	fi
	rm -f "$compile_log"

	if ! test -s "$ROOT_DIR/$artifact_path"; then
		printf 'AMX Mod X compiler did not produce %s.\n' "$artifact_path" >&2
		exit 1
	fi
	if ! verify_amxx_magic "$ROOT_DIR/$artifact_path"; then
		rm -f "$ROOT_DIR/$artifact_path" "$ROOT_DIR/$artifact_path.sha256"
		printf 'Compiled artifact does not start with AMXX magic XXMA: %s\n' "$artifact_path" >&2
		exit 1
	fi
	write_checksum "$ROOT_DIR/$artifact_path"
done
