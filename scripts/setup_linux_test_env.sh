#!/usr/bin/env bash
# PAGE Editor v0.8.0 Linux test environment (x86_64).
#
# Installs the toolchain named in docs/BUILD.md, docs/README.md and
# docs/DEPENDENCIES.md:
#   Godot 4.7.1 standard (not .NET) and 4.7.1.stable export templates
#   for Linux x86_64 and Windows x86_64.
# Python 3 (stdlib only) is required by tools/prepare_runtime.py and
# tools/package_release.py. Dialogic 2.0-alpha-20 already lives in
# addons/dialogic; this script does not upgrade it.
#
# Re-run (idempotent):
#   bash scripts/setup_linux_test_env.sh
# Then run the documented headless checks:
#   bash scripts/run_linux_test_checks.sh
#
# Audio: Godot is invoked with --audio-driver Dummy. docs/RELEASE_NOTES.md
# records the v0.8.0 Linux runs as X11 + Mesa llvmpipe + Dummy audio, and
# explicitly does not claim physical speaker output. Do not start PulseAudio
# or ALSA just to satisfy the editor; the Dummy driver needs no sound server.
#
# Display: headless Godot (--headless) does not need a real screen. GUI
# checks use Xvfb, LIBGL_ALWAYS_SOFTWARE=1 and GALLIUM_DRIVER=llvmpipe so
# rendering stays on the software rasterizer named in the release notes.
# That is not a physical GPU and not a desktop input-method session.
set -euo pipefail

GODOT_TAG="4.7.1-stable"
GODOT_VERSION_PREFIX="4.7.1.stable"
TEMPLATE_DIR_NAME="4.7.1.stable"
EDITOR_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
TEMPLATE_TPZ="Godot_v4.7.1-stable_export_templates.tpz"
SUMS_NAME="SHA512-SUMS.txt"
RELEASE_BASE="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"

PREFIX="/opt/page-linux-test-env"
CACHE="${PREFIX}/cache"
EDITOR_BIN="${PREFIX}/Godot_v4.7.1-stable_linux.x86_64"
ENV_FILE="${PREFIX}/godot-env.sh"
TEMPLATE_DEST="${HOME}/.local/share/godot/export_templates/${TEMPLATE_DIR_NAME}"

log() { printf '[page-linux-setup] %s\n' "$*"; }

if ! sudo -n true 2>/dev/null; then
  echo "passwordless sudo is required to install packages and /opt files" >&2
  exit 1
fi

log "installing system packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl unzip xz-utils \
  python3 \
  file binutils \
  libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libxrender1 libxfixes3 \
  libgl1 libglu1-mesa libegl1 \
  libfontconfig1 libfreetype6 \
  libxkbcommon0 libxkbcommon-x11-0 \
  libdbus-1-3 libspeechd2 \
  libasound2t64 libpulse0 libudev1 libatomic1 \
  mesa-utils mesa-vulkan-drivers \
  xvfb xauth \
  ffmpeg \
  fonts-noto-cjk \
  tesseract-ocr tesseract-ocr-eng tesseract-ocr-chi-sim tesseract-ocr-jpn

sudo mkdir -p "${CACHE}"
sudo chown -R "$(id -u):$(id -g)" "${PREFIX}"

download() {
  local name="$1"
  local dest="${CACHE}/${name}"
  if [[ -f "${dest}" ]]; then
    log "cache hit ${name}"
    return 0
  fi
  log "downloading ${name}"
  curl -fL --retry 5 --retry-delay 2 -o "${dest}.partial" "${RELEASE_BASE}/${name}"
  mv "${dest}.partial" "${dest}"
}

checksum_of() {
  local name="$1"
  awk -v n="${name}" '
    {
      file = $2
      sub(/^\*/, "", file)
      if (file == n) { print $1; exit }
    }
  ' "${CACHE}/${SUMS_NAME}"
}

verify_cached() {
  local name="$1"
  local expected actual
  expected="$(checksum_of "${name}")"
  if [[ -z "${expected}" ]]; then
    echo "SHA512 entry missing for ${name}" >&2
    exit 1
  fi
  actual="$(sha512sum "${CACHE}/${name}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "SHA512 mismatch for ${name}" >&2
    echo "expected ${expected}" >&2
    echo "actual   ${actual}" >&2
    exit 1
  fi
  log "SHA512 ok ${name}"
}

download "${SUMS_NAME}"
download "${EDITOR_ZIP}"
download "${TEMPLATE_TPZ}"
verify_cached "${EDITOR_ZIP}"
verify_cached "${TEMPLATE_TPZ}"

if [[ ! -x "${EDITOR_BIN}" ]] || ! "${EDITOR_BIN}" --version 2>/dev/null | grep -q "^${GODOT_VERSION_PREFIX}"; then
  log "installing Godot editor"
  rm -rf "${CACHE}/editor-unpack"
  mkdir -p "${CACHE}/editor-unpack"
  unzip -q -o "${CACHE}/${EDITOR_ZIP}" -d "${CACHE}/editor-unpack"
  unpacked="$(find "${CACHE}/editor-unpack" -type f -name 'Godot_v4.7.1-stable_linux.x86_64' | head -n 1)"
  if [[ -z "${unpacked}" ]]; then
    echo "Godot editor binary not found in ${EDITOR_ZIP}" >&2
    exit 1
  fi
  install -m 755 "${unpacked}" "${EDITOR_BIN}"
fi

sudo ln -sfn "${EDITOR_BIN}" /usr/local/bin/godot
sudo ln -sfn "${EDITOR_BIN}" /usr/local/bin/godot4

version_line="$("${EDITOR_BIN}" --version)"
case "${version_line}" in
  ${GODOT_VERSION_PREFIX}*) ;;
  *)
    echo "unexpected Godot version: ${version_line}" >&2
    exit 1
    ;;
esac

if [[ ! -f "${TEMPLATE_DEST}/version.txt" ]] || [[ "$(tr -d '[:space:]' < "${TEMPLATE_DEST}/version.txt")" != "${TEMPLATE_DIR_NAME}" ]] \
  || [[ ! -f "${TEMPLATE_DEST}/linux_release.x86_64" ]] || [[ ! -f "${TEMPLATE_DEST}/windows_release_x86_64.exe" ]]; then
  log "installing export templates into ${TEMPLATE_DEST}"
  rm -rf "${CACHE}/templates-unpack" "${TEMPLATE_DEST}"
  mkdir -p "${CACHE}/templates-unpack"
  unzip -q -o "${CACHE}/${TEMPLATE_TPZ}" -d "${CACHE}/templates-unpack"
  version_file="$(find "${CACHE}/templates-unpack" -type f -name version.txt | head -n 1)"
  if [[ -z "${version_file}" ]]; then
    echo "export template version.txt not found" >&2
    exit 1
  fi
  mkdir -p "${TEMPLATE_DEST}"
  cp -a "$(dirname "${version_file}")"/. "${TEMPLATE_DEST}/"
fi

installed_template="$(tr -d '[:space:]' < "${TEMPLATE_DEST}/version.txt")"
if [[ "${installed_template}" != "${TEMPLATE_DIR_NAME}" ]]; then
  echo "export templates are ${installed_template}, expected ${TEMPLATE_DIR_NAME}" >&2
  exit 1
fi
for required in linux_release.x86_64 linux_debug.x86_64 windows_release_x86_64.exe windows_debug_x86_64.exe; do
  if [[ ! -f "${TEMPLATE_DEST}/${required}" ]]; then
    echo "missing export template ${required}" >&2
    exit 1
  fi
done

rm -rf "${CACHE}/editor-unpack" "${CACHE}/templates-unpack"

missing_libs="$(ldd "${EDITOR_BIN}" | awk '/not found/ {print $1}')"
if [[ -n "${missing_libs}" ]]; then
  echo "Godot is missing shared libraries:" >&2
  echo "${missing_libs}" >&2
  exit 1
fi

cat > "${ENV_FILE}" <<'EOF'
# Source before PAGE / Godot test commands on this VM.
# Dummy audio matches docs/RELEASE_NOTES.md: do not treat a successful
# headless run as proof that a sound card or speakers were exercised.
# llvmpipe matches the documented X11 + Mesa software rasterizer.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export PAGE_GODOT_AUDIO_DRIVER=Dummy
EOF

# Keep copies outside the git checkout so a Cloud Agent image that
# predates this commit can still re-run setup and the Linux checks.
install -m 755 "$0" "${PREFIX}/setup_linux_test_env.sh"
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${script_dir}/run_linux_test_checks.sh" ]]; then
  install -m 755 "${script_dir}/run_linux_test_checks.sh" "${PREFIX}/run_linux_test_checks.sh"
fi

log "Godot ${version_line}"
log "templates ${TEMPLATE_DEST} (${installed_template})"
log "python $(python3 --version)"
log "audio driver: Dummy (see ${ENV_FILE})"
log "display for GUI checks: Xvfb + llvmpipe"
log "done"
