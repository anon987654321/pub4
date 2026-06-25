#!/bin/sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
git_dir="${root}/.git"
if [ ! -d "${git_dir}" ]; then
  echo "install-hooks: no .git in ${root}" >&2
  exit 1
fi
hook="${git_dir}/hooks/pre-commit"
cat > "${hook}" <<'HOOK'
#!/bin/sh
root="$(git rev-parse --show-toplevel 2>/dev/null)"
exec "${root}/MASTER/bin/audit" --profile critical
HOOK
chmod 755 "${hook}"
echo "install-hooks: wrote ${hook}"