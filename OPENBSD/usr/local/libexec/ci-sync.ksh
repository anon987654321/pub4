#!/bin/ksh
# Root-owned code, deliberately executed with the selected app's UID and groups.
# All file mutation is app-scoped; this script must never run as root.
set -e
set -o pipefail
PATH=/usr/local/bin:/usr/bin:/bin
export PATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
unset TAR_OPTIONS RUBYOPT RUBYLIB GEM_HOME GEM_PATH

[ "$#" -eq 1 ] || { echo "ci-sync: expected one app name" >&2; exit 64; }
app=$1
case "$app" in
  brgen|amber|bsdports) ;;
  *) echo "ci-sync: refused unknown app: $app" >&2; exit 64 ;;
esac
[ "$(id -un)" = "$app" ] || { echo "ci-sync: must run as the selected app user" >&2; exit 77; }

repo=/home/dev/pub4
src=$repo/RAILS/$app
app_home=/home/$app
app_dir=$app_home/app
mirror=$app_home/pub4-rails
shared_src=$repo/RAILS/__shared
shared_dir=$app_home/__shared
uid=$(id -u)

[ -d "$repo/.git" ] && [ ! -L "$repo" ] || { echo "ci-sync: checkout is missing or a symlink" >&2; exit 1; }
[ -d "$src" ] && [ ! -L "$src" ] || { echo "ci-sync: Rails source tree is missing or a symlink" >&2; exit 1; }
[ -d "$app_home" ] && [ ! -L "$app_home" ] || { echo "ci-sync: app home is missing or a symlink" >&2; exit 1; }
[ -d "$app_dir" ] && [ ! -L "$app_dir" ] || { echo "ci-sync: app directory is missing or a symlink" >&2; exit 1; }
[ "$(stat -f %u "$app_home")" = "$uid" ] && [ "$(stat -f %u "$app_dir")" = "$uid" ] || {
  echo "ci-sync: app home and destination must be owned by $app" >&2
  exit 1
}

mkdir -p "$mirror"
[ ! -L "$mirror" ] && [ "$(stat -f %u "$mirror")" = "$uid" ] || {
  echo "ci-sync: mirror must be a real directory owned by $app" >&2
  exit 1
}

# The CI mirror contains the exact tracked tree, not ignored local bundles.
rm -rf "$mirror/RAILS"
git -C "$repo" archive HEAD RAILS | tar xf - -C "$mirror"
if git -C "$repo" cat-file -e HEAD:MASTER/tools 2>/dev/null; then
  rm -rf "$mirror/MASTER/tools"
  git -C "$repo" archive HEAD MASTER/tools | tar xf - -C "$mirror"
fi
mkdir -p "$mirror/MASTER/data" "$mirror/MASTER/lib"
rm -f "$mirror/MASTER/data/tokens.yml" "$mirror/MASTER/data/laws.yml"
git -C "$repo" archive HEAD MASTER/data/tokens.yml | tar xf - -C "$mirror"
rm -rf "$mirror/MASTER/lib/operator"
git -C "$repo" archive HEAD MASTER/lib/operator | tar xf - -C "$mirror"
for rel in MASTER/lib/boot/paths.rb MASTER/lib/ground/swallow.rb \
           MASTER/lib/io/exec.rb MASTER/lib/ops/process_spawn.rb \
           MASTER/lib/trace/dmesg.rb MASTER/lib/trace/logging.rb \
           MASTER/lib/voice/playback.rb; do
  git -C "$repo" archive HEAD "$rel" | tar xf - -C "$mirror"
done

# Remove each mirrored directory before re-extraction so deleted files cannot
# survive forever. Preserve generated public/assets across the public/ refresh.
for dir_rel in test app lib config bin db engines public vendor/javascript; do
  [ -d "$src/$dir_rel" ] || continue
  if [ "$dir_rel" = public ] && [ -d "$app_dir/public/assets" ]; then
    [ ! -L "$app_dir/public/assets" ] || {
      echo "ci-sync: refusing public/assets symlink" >&2
      exit 1
    }
    rm -rf "$app_dir/.assets-carry"
    mv "$app_dir/public/assets" "$app_dir/.assets-carry"
    rm -rf "$app_dir/public"
    mkdir -p "$app_dir/public"
    mv "$app_dir/.assets-carry" "$app_dir/public/assets"
    continue
  fi
  rm -rf "$app_dir/$dir_rel"
done
[ -d "$src/engines" ] || rm -rf "$app_dir/engines"

for rel in test app lib config bin db engines public vendor/javascript \
           Gemfile Gemfile.lock config.ru Rakefile .rubocop.yml .ruby-version; do
  [ -e "$src/$rel" ] || continue
  tar cf - -C "$src" "$rel" | tar xf - -C "$app_dir"
done
for file in "$src"/*.sh; do
  [ -f "$file" ] || continue
  name=$(basename "$file")
  tar cf - -C "$src" "$name" | tar xf - -C "$app_dir"
done

[ -d "$shared_src" ] && [ ! -L "$shared_src" ] || {
  echo "ci-sync: shared source tree is missing or a symlink" >&2
  exit 1
}
if [ -e "$shared_dir" ] || [ -L "$shared_dir" ]; then
  [ -d "$shared_dir" ] && [ ! -L "$shared_dir" ] &&
    [ "$(stat -f %u "$shared_dir")" = "$uid" ] || {
      echo "ci-sync: shared destination must be a real app-owned directory" >&2
      exit 1
    }
  rm -rf "$shared_dir"
fi
mkdir -p "$shared_dir"
tar cf - -C "$shared_src" . | tar xf - -C "$shared_dir"

# Brgen's vertical Rails engines are sibling path gems in the copy-tree.
if [ "$app" = brgen ]; then
  for vertical in "$repo"/RAILS/brgen_*/; do
    [ -d "$vertical" ] || continue
    [ ! -L "$vertical" ] || { echo "ci-sync: refusing vertical symlink" >&2; exit 1; }
    name=$(basename "$vertical")
    destination="$app_home/$name"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      [ -d "$destination" ] && [ ! -L "$destination" ] &&
        [ "$(stat -f %u "$destination")" = "$uid" ] || {
          echo "ci-sync: vertical destination is not app-owned: $destination" >&2
          exit 1
        }
      rm -rf "$destination"
    fi
    mkdir -p "$destination"
    tar cf - -C "$vertical" . | tar xf - -C "$destination"
  done
fi

echo "ci-sync: refreshed tracked CI mirror and $app copy-tree as $app"
