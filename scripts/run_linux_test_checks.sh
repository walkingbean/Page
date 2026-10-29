#!/usr/bin/env bash
# Re-run the PAGE v0.8.0 Linux checks that docs/BUILD.md and docs/README.md
# describe as commands, plus static facts from docs/RELEASE_NOTES.md and
# docs/TESTCASES.md.
#
#   bash scripts/setup_linux_test_env.sh
#   bash scripts/run_linux_test_checks.sh
#
# Artifacts (logs, summary.txt, summary.json) go to
#   ${PAGE_TEST_ARTIFACTS:-/opt/cursor/artifacts/page-v0.8.0-linux}
#
# This is not the 729-case manual suite. docs/TESTCASES.md is a frozen
# checklist (已运行 / 未运行) with no in-repo runner. GUI, input-method,
# file-manager, reference-project, and physical-audio cases stay blocked
# here. Windows device cases stay deferred to 1.0.0 per the release notes.
# Known v0.8.0 import crashes are recorded, not re-filed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

GODOT_BIN="${GODOT_BIN:-godot}"
ENV_FILE="/opt/page-linux-test-env/godot-env.sh"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
AUDIO_DRIVER="${PAGE_GODOT_AUDIO_DRIVER:-Dummy}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="${PAGE_TEST_ARTIFACTS:-/opt/cursor/artifacts/page-v0.8.0-linux}"
ART="${BASE}/runs/${STAMP}"
mkdir -p "${ART}"
# The artifacts store rejects symlinks, so record the latest run as a path file.
printf '%s\n' "${ART}" > "${BASE}/latest.txt"

RESULTS="${ART}/results.tsv"
printf 'name\tstatus\texit\tdetail\n' > "${RESULTS}"

record() {
  local name="$1" status="$2" exit_code="$3" detail="$4"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${exit_code}" "${detail}" >> "${RESULTS}"
  printf '[page-linux-test] %s %s (exit %s) %s\n' "${status}" "${name}" "${exit_code}" "${detail}"
}

run_logged() {
  local name="$1"
  shift
  local log="${ART}/${name}.log"
  set +e
  "$@" >"${log}" 2>&1
  local code=$?
  set -e
  printf '%s\n' "${code}" > "${ART}/${name}.exit"
  echo "${code}"
}

if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
  record "godot_present" "FAIL" "127" "godot not on PATH; run scripts/setup_linux_test_env.sh"
  echo "godot is not installed" >&2
  exit 1
fi

{
  echo "date_utc=${STAMP}"
  echo "root=${ROOT}"
  echo "commit=$(git -C "${ROOT}" rev-parse HEAD)"
  echo "branch=$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)"
  echo "uname=$(uname -a)"
  echo "user=$(id)"
  echo "python=$(python3 --version 2>&1)"
  echo "godot_bin=$(command -v "${GODOT_BIN}")"
  echo "godot_version=$("${GODOT_BIN}" --version 2>&1 || true)"
  echo "audio_driver=${AUDIO_DRIVER}"
  echo "LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE}"
  echo "GALLIUM_DRIVER=${GALLIUM_DRIVER}"
  if [[ -f "${HOME}/.local/share/godot/export_templates/4.7.1.stable/version.txt" ]]; then
    echo "templates=$(tr -d '[:space:]' < "${HOME}/.local/share/godot/export_templates/4.7.1.stable/version.txt")"
  else
    echo "templates=missing"
  fi
  echo "ffmpeg=$(ffmpeg -version 2>/dev/null | head -n 1 || echo missing)"
  echo "tesseract=$(tesseract --version 2>/dev/null | head -n 1 || echo missing)"
  echo "xvfb=$(command -v xvfb-run || echo missing)"
} > "${ART}/environment.txt"

godot_version="$("${GODOT_BIN}" --version 2>&1 || true)"
case "${godot_version}" in
  4.7.1.stable*) record "godot_version" "PASS" "0" "${godot_version}" ;;
  *) record "godot_version" "FAIL" "1" "${godot_version}" ;;
esac

template_file="${HOME}/.local/share/godot/export_templates/4.7.1.stable/version.txt"
if [[ -f "${template_file}" ]] && [[ "$(tr -d '[:space:]' < "${template_file}")" == "4.7.1.stable" ]] \
  && [[ -f "${HOME}/.local/share/godot/export_templates/4.7.1.stable/linux_release.x86_64" ]] \
  && [[ -f "${HOME}/.local/share/godot/export_templates/4.7.1.stable/windows_release_x86_64.exe" ]]; then
  record "export_templates" "PASS" "0" "4.7.1.stable linux_release.x86_64 + windows_release_x86_64.exe"
else
  record "export_templates" "FAIL" "1" "4.7.1.stable Linux/Windows templates missing"
fi

plugin_version="$(awk -F= '/^version=/ {print $2}' addons/dialogic/plugin.cfg | tr -d '"')"
case "${plugin_version}" in
  *2.0-Alpha-20*|*2.0-alpha-20*) record "dialogic_version" "PASS" "0" "${plugin_version}" ;;
  *) record "dialogic_version" "FAIL" "1" "${plugin_version:-missing}" ;;
esac

product_version="$(tr -d '[:space:]' < VERSION.txt)"
if [[ "${product_version}" == "0.8.0" ]]; then
  record "product_version" "PASS" "0" "VERSION.txt=0.8.0"
else
  record "product_version" "FAIL" "1" "VERSION.txt=${product_version}"
fi

font="asset/fonts/NotoSansCJKsc-Regular.otf"
expected_font="2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b"
actual_font="$(sha256sum "${font}" | awk '{print $1}')"
if [[ "${actual_font}" == "${expected_font}" ]]; then
  record "noto_font_sha256" "PASS" "0" "${actual_font}"
else
  record "noto_font_sha256" "FAIL" "1" "expected ${expected_font} actual ${actual_font}"
fi

python3 - <<'PY' > "${ART}/frozen-testcases.txt"
import pathlib
text = pathlib.Path("docs/TESTCASES.md").read_text()
shared, rest = text.split("## Linux 专用", 1)
linux, windows = rest.split("## Windows 专用", 1)

def statuses(section, prefix, columns):
    ran = not_ran = rows = 0
    for line in section.splitlines():
        if not line.startswith(prefix):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        rows += 1
        for cell in cells[-columns:]:
            if cell == "已运行":
                ran += 1
            elif cell == "未运行":
                not_ran += 1
    return rows, ran, not_ran

shared_rows, shared_linux_ran, shared_linux_not = statuses(shared, "| C-", 2)
# Recount windows column separately.
win_ran = win_not = 0
for line in shared.splitlines():
    if not line.startswith("| C-"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    cell = cells[-1]
    if cell == "已运行":
        win_ran += 1
    elif cell == "未运行":
        win_not += 1
linux_rows, linux_ran, linux_not = statuses(linux, "| LNX-", 1)
win_rows, win_only_ran, win_only_not = statuses(windows, "| WIN-", 1)
# shared statuses() counted both platform columns into shared_linux_*.
# Recompute the Linux column only.
lin_ran = lin_not = 0
for line in shared.splitlines():
    if not line.startswith("| C-"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    cell = cells[-2]
    if cell == "已运行":
        lin_ran += 1
    elif cell == "未运行":
        lin_not += 1
print(f"shared_rows={shared_rows}")
print(f"shared_linux_ran={lin_ran}")
print(f"shared_linux_not={lin_not}")
print(f"shared_windows_ran={win_ran}")
print(f"shared_windows_not={win_not}")
print(f"linux_rows={linux_rows} ran={linux_ran} not={linux_not}")
print(f"windows_rows={win_rows} ran={win_only_ran} not={win_only_not}")
print(f"total_cases={shared_rows + linux_rows + win_rows}")
print("note=frozen checklist in source; this run did not re-execute these cases")
PY
if grep -q 'shared_linux_ran=625' "${ART}/frozen-testcases.txt" \
  && grep -q 'shared_linux_not=84' "${ART}/frozen-testcases.txt" \
  && grep -q 'linux_rows=10 ran=0 not=10' "${ART}/frozen-testcases.txt" \
  && grep -q 'total_cases=729' "${ART}/frozen-testcases.txt"; then
  record "frozen_testcase_inventory" "PASS" "0" "729 cases; Linux shared 625 ran / 84 not; Linux-only 0/10; not re-executed"
else
  record "frozen_testcase_inventory" "FAIL" "1" "checklist counts diverged from docs/RELEASE_NOTES.md; see frozen-testcases.txt"
fi

# Reference project used for native round-trips is an external zip, not in Source.
if [[ -f "${PAGE_REFERENCE_PROJECT:-}" ]]; then
  record "reference_project" "PASS" "0" "${PAGE_REFERENCE_PROJECT}"
else
  record "reference_project" "BLOCKED" "0" "dialogic2alpha20_godot4.7.1.zip is not in the source tree; native round-trip cases were not run"
fi

record "manual_gui_suite" "BLOCKED" "0" "no automated runner for the 729-case checklist; real IME and file-manager cases need a desktop session"
record "physical_audio" "BLOCKED" "0" "Dummy audio driver only; speaker output was not validated"
record "windows_device" "BLOCKED" "0" "release notes defer Windows device tests to 1.0.0; export is not device verification"

import_once() {
  local label="$1"
  local path="$2"
  local code
  code="$(run_logged "${label}" "${GODOT_BIN}" --headless --audio-driver "${AUDIO_DRIVER}" --editor --path "${path}" --import)"
  local errors
  errors="$(grep -c -E 'SCRIPT ERROR|Parse Error|signal 11|SIGSEGV|corrupted top size|unaligned tcache' "${ART}/${label}.log" || true)"
  echo "${code} ${errors}"
}

import_path="${ROOT}"
read -r import_code import_errors < <(import_once "import-1" "${import_path}")
if [[ "${import_code}" -ne 0 ]]; then
  record "import_attempt_1" "FAIL" "${import_code}" "known intermittent NotoSansCJK import crash is documented in docs/BUILD.md; cache discarded"
  rm -rf "${import_path}/.godot"
  read -r import_code import_errors < <(import_once "import-2" "${import_path}")
fi

if [[ "${import_code}" -eq 0 ]]; then
  record "godot_import" "PASS" "0" "headless editor import exited 0; marker_lines=${import_errors}"
else
  record "godot_import" "FAIL" "${import_code}" "clean import failed after retry; see import-1.log and import-2.log. Not continuing with a failed cache."
  # Documented diagnostic only, on a copy, and only after clean retries fail.
  # docs/BUILD.md: do not change the official project to hide the crash.
  diag="${ART}/diagnostic-single-thread"
  mkdir -p "${diag}"
  python3 - <<PY
import pathlib, shutil
src = pathlib.Path("${import_path}")
dst = pathlib.Path("${diag}/project")
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst, ignore=shutil.ignore_patterns(".git", ".godot", "builds"), symlinks=False)
project = dst / "project.godot"
text = project.read_text()
needle = "export/convert_text_resources_to_binary=false\n"
insert = needle + "import/use_multiple_threads=false\n"
if needle not in text:
    raise SystemExit("editor section anchor missing")
project.write_text(text.replace(needle, insert, 1))
PY
  read -r diag_code diag_errors < <(import_once "import-diagnostic" "${diag}/project")
  if [[ "${diag_code}" -eq 0 ]]; then
    record "import_diagnostic_single_thread" "PASS" "0" "copy-only project.godot import/use_multiple_threads=false; official tree was not modified"
  else
    record "import_diagnostic_single_thread" "FAIL" "${diag_code}" "single-thread diagnostic import also failed"
  fi
fi

if [[ "${import_code}" -eq 0 ]]; then
  brand_code="$(run_logged "branding-check" "${GODOT_BIN}" --headless --audio-driver "${AUDIO_DRIVER}" --path "${ROOT}" --script res://tools/apply_branding.gd -- --check)"
  if [[ "${brand_code}" -eq 0 ]] && grep -q "BRANDING_CHECK_RESULT: synchronized" "${ART}/branding-check.log"; then
    record "branding_check" "PASS" "0" "synchronized"
  else
    record "branding_check" "FAIL" "${brand_code}" "see branding-check.log"
  fi

  apply_code="$(run_logged "branding-apply" "${GODOT_BIN}" --headless --audio-driver "${AUDIO_DRIVER}" --path "${ROOT}" --script res://tools/apply_branding.gd)"
  if [[ "${apply_code}" -eq 0 ]] && grep -q "BRANDING_APPLY_RESULT:" "${ART}/branding-apply.log"; then
    record "branding_apply" "PASS" "0" "$(grep BRANDING_APPLY_RESULT "${ART}/branding-apply.log" | tail -n 1)"
  else
    record "branding_apply" "FAIL" "${apply_code}" "see branding-apply.log"
  fi

  prep_code="$(run_logged "prepare-runtime" python3 tools/prepare_runtime.py)"
  if [[ "${prep_code}" -eq 0 ]]; then
    record "prepare_runtime" "PASS" "0" "$(tail -n 1 "${ART}/prepare-runtime.log")"
  else
    record "prepare_runtime" "FAIL" "${prep_code}" "see prepare-runtime.log"
  fi

  if [[ "${prep_code}" -eq 0 ]]; then
    linux_code="$(run_logged "export-linux" "${GODOT_BIN}" --headless --audio-driver "${AUDIO_DRIVER}" --path "${ROOT}" --export-release "Linux")"
    win_code="$(run_logged "export-windows" "${GODOT_BIN}" --headless --audio-driver "${AUDIO_DRIVER}" --path "${ROOT}" --export-release "Windows Desktop")"
    if [[ "${linux_code}" -eq 0 && -f builds/linux/PAGE_Editor.x86_64 ]]; then
      record "export_linux" "PASS" "0" "builds/linux/PAGE_Editor.x86_64"
    else
      record "export_linux" "FAIL" "${linux_code}" "see export-linux.log"
    fi
    if [[ "${win_code}" -eq 0 && -f builds/windows/PAGE_Editor.exe ]]; then
      record "export_windows" "PASS" "0" "builds/windows/PAGE_Editor.exe static export only"
    else
      record "export_windows" "FAIL" "${win_code}" "see export-windows.log"
    fi
  fi
fi

if [[ -f builds/linux/PAGE_Editor.x86_64 ]]; then
  chmod +x builds/linux/PAGE_Editor.x86_64
  ldd builds/linux/PAGE_Editor.x86_64 > "${ART}/linux-binary-ldd.txt" || true
  if grep -q "not found" "${ART}/linux-binary-ldd.txt"; then
    record "linux_binary_libs" "FAIL" "1" "unresolved libraries; see linux-binary-ldd.txt"
  else
    record "linux_binary_libs" "PASS" "0" "ldd resolved"
  fi
  smoke_code="$(run_logged "linux-binary-smoke" timeout 60 xvfb-run -a -s "-screen 0 1280x800x24" \
    ./builds/linux/PAGE_Editor.x86_64 --headless --audio-driver "${AUDIO_DRIVER}" --quit)"
  if [[ "${smoke_code}" -eq 0 ]]; then
    record "linux_binary_smoke" "PASS" "0" "xvfb + llvmpipe + Dummy audio, --headless --quit"
  else
    record "linux_binary_smoke" "FAIL" "${smoke_code}" "see linux-binary-smoke.log; headless quit is not the LNX-01 desktop case"
  fi
  record "lnx01_desktop" "BLOCKED" "0" "LNX-01 requires a real graphical desktop session, not xvfb --headless"
else
  record "linux_binary_libs" "BLOCKED" "0" "Linux export was not produced"
  record "linux_binary_smoke" "BLOCKED" "0" "Linux export was not produced"
fi

if [[ -f builds/linux/PAGE_Editor.x86_64 && -f builds/windows/PAGE_Editor.exe ]]; then
  deliver="${ART}/deliverables"
  mkdir -p "${deliver}"
  pack_code="$(run_logged "package-release" python3 tools/package_release.py --output "${deliver}" --date 2026-10-29)"
  if [[ "${pack_code}" -eq 0 ]]; then
    record "package_release" "PASS" "0" "${deliver}"
  else
    record "package_release" "FAIL" "${pack_code}" "see package-release.log"
  fi
fi

# Software GL probe. Failure here does not fail product logic; it records the display stack.
gl_code="$(run_logged "glxinfo" xvfb-run -a -s "-screen 0 1280x800x24" glxinfo -B)"
if [[ "${gl_code}" -eq 0 ]] && grep -qi llvmpipe "${ART}/glxinfo.log"; then
  record "llvmpipe" "PASS" "0" "Xvfb glxinfo reports llvmpipe"
else
  record "llvmpipe" "FAIL" "${gl_code}" "see glxinfo.log"
fi

python3 - <<PY
import json
from pathlib import Path
art = Path(${ART@Q})
rows = []
for line in (art / "results.tsv").read_text().splitlines()[1:]:
    name, status, exit_code, detail = line.split("\t", 3)
    rows.append({"name": name, "status": status, "exit": int(exit_code) if exit_code.lstrip("-").isdigit() else exit_code, "detail": detail})
counts = {}
for row in rows:
    counts[row["status"]] = counts.get(row["status"], 0) + 1
summary = {
    "stamp": ${STAMP@Q},
    "commit": "$(git rev-parse HEAD)",
    "counts": counts,
    "checks": rows,
}
(art / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
lines = [
    f"PAGE v0.8.0 Linux check summary {summary['stamp']}",
    f"commit {summary['commit']}",
    "counts " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())),
    "",
]
for row in rows:
    lines.append(f"{row['status']:7} {row['name']}: {row['detail']}")
text = "\n".join(lines) + "\n"
(art / "summary.txt").write_text(text)
print(text)
PY

fail_count="$(awk -F'\t' 'NR>1 && $2=="FAIL" {c++} END {print c+0}' "${RESULTS}")"
if [[ "${fail_count}" -ne 0 ]]; then
  exit 1
fi
