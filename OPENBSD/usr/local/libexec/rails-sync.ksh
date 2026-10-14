#!/bin/ksh
# App-owned staged Rails tree synchronizer. It never runs as root and never
# accepts an arbitrary source or destination path from its caller.
set -e
set -o pipefail
PATH=/usr/local/bin:/usr/bin:/bin
export PATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
unset TAR_OPTIONS RUBYOPT RUBYLIB GEM_HOME GEM_PATH BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH

[ "$#" -eq 2 ] || { echo "rails-sync: expected app and fixed mode" >&2; exit 64; }
app=$1
mode=$2
case "$app" in
  brgen|amber|bsdports) ;;
  *) echo "rails-sync: refused unknown app: $app" >&2; exit 64 ;;
esac
case "$mode" in
  app|shared) ;;
  verticals) [ "$app" = brgen ] || { echo "rails-sync: verticals are brgen-only" >&2; exit 64; } ;;
  *) echo "rails-sync: refused unknown mode: $mode" >&2; exit 64 ;;
esac
[ "$(id -un)" = "$app" ] || { echo "rails-sync: must run as the selected app user" >&2; exit 77; }

repo=/home/dev/pub4
rails_root=/home/dev/pub4/RAILS
app_uid=$(id -u)
app_home=/home/$app
app_dir=$app_home/app
[ ! -L /home/dev ] && [ -d /home/dev ] || { echo "rails-sync: /home/dev is not a real directory" >&2; exit 1; }
[ ! -L "$repo" ] && [ -d "$repo" ] || { echo "rails-sync: checkout is missing or symlinked" >&2; exit 1; }
[ ! -L "$rails_root" ] && [ -d "$rails_root" ] || { echo "rails-sync: Rails source root is missing or symlinked" >&2; exit 1; }
[ ! -L "$app_home" ] && [ -d "$app_home" ] && [ "$(stat -f %u "$app_home")" = "$app_uid" ] || {
  echo "rails-sync: app home must be a real app-owned directory" >&2
  exit 1
}
[ ! -L "$app_dir" ] && [ -d "$app_dir" ] && [ "$(stat -f %u "$app_dir")" = "$app_uid" ] || {
  echo "rails-sync: app tree must be a real app-owned directory" >&2
  exit 1
}

archive_tracked_tree() {
  source_dir=$1
  target=$2
  source_rel=${source_dir#"$rails_root"/}
  case "$source_rel" in
    "$app"|__shared|brgen_[A-Za-z0-9_]*) ;;
    *) echo "rails-sync: refused source tree: $source_rel" >&2; return 1 ;;
  esac
  archive_root=$target/.archive.$
  [ ! -e "$archive_root" ] && [ ! -L "$archive_root" ] || {
    echo "rails-sync: refusing stale archive path: $archive_root" >&2
    return 1
  }
  mkdir "$archive_root"
  if ! git -c safe.directory="$repo" -C "$repo" archive HEAD "RAILS/$source_rel" | tar xf - -C "$archive_root"; then
    rm -rf "$archive_root"
    echo "rails-sync: Git archive failed for RAILS/$source_rel" >&2
    return 1
  fi
  tree=$archive_root/RAILS/$source_rel
  [ -d "$tree" ] && [ ! -L "$tree" ] || {
    rm -rf "$archive_root"
    echo "rails-sync: tracked source tree is missing: RAILS/$source_rel" >&2
    return 1
  }
  for entry in "$tree"/* "$tree"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    mv "$entry" "$target/" || {
      rm -rf "$archive_root"
      echo "rails-sync: could not stage tracked entry: $entry" >&2
      return 1
    }
  done
  rm -rf "$archive_root"
}
sync_tree_stage() {
  source_dir=$1
  target=$2
  preserve_state=$3
  [ ! -L "$source_dir" ] && [ -d "$source_dir" ] || {
    echo "rails-sync: source is missing or symlinked: $source_dir" >&2
    return 1
  }

  parent=$(dirname "$target")
  base=$(basename "$target")
  stage=$parent/.$base.sync.$$
  previous=$parent/.$base.previous.$$
  if [ -e "$stage" ] || [ -L "$stage" ] || [ -e "$previous" ] || [ -L "$previous" ]; then
    echo "rails-sync: refusing stale staging path for $target" >&2
    return 1
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    [ ! -L "$target" ] && [ -d "$target" ] && [ "$(stat -f %u "$target")" = "$app_uid" ] || {
      echo "rails-sync: destination must be a real app-owned directory: $target" >&2
      return 1
    }
  fi

  if [ "$preserve_state" = yes ] && [ -d "$target" ]; then
    for state in storage log; do
      state_path=$target/$state
      if [ -e "$state_path" ] || [ -L "$state_path" ]; then
        [ ! -L "$state_path" ] && [ -d "$state_path" ] &&
          [ "$(stat -f %u "$state_path")" = "$app_uid" ] || {
            echo "rails-sync: runtime state must be a real app-owned directory: $state_path" >&2
            return 1
          }
      fi
    done
    if [ -e "$target/public" ] || [ -L "$target/public" ]; then
      [ ! -L "$target/public" ] && [ -d "$target/public" ] &&
        [ "$(stat -f %u "$target/public")" = "$app_uid" ] || {
          echo "rails-sync: public path must be a real app-owned directory" >&2
          return 1
        }
      if [ -e "$target/public/assets" ] || [ -L "$target/public/assets" ]; then
        [ ! -L "$target/public/assets" ] && [ -d "$target/public/assets" ] &&
          [ "$(stat -f %u "$target/public/assets")" = "$app_uid" ] || {
            echo "rails-sync: generated assets must be a real app-owned directory" >&2
            return 1
          }
      fi
    fi
  fi

  mkdir "$stage"
  if ! archive_tracked_tree "$source_dir" "$stage"; then
    rm -rf "$stage"
    echo "rails-sync: source archive failed; destination left untouched" >&2
    return 1
  fi
  find "$stage" -name '._*' -type f -exec rm -f {} \;

  target_existed=0
  storage_carried=0
  log_carried=0
  assets_carried=0
  if [ -e "$target" ]; then
    mv "$target" "$previous" || { rm -rf "$stage"; return 1; }
    target_existed=1
  fi

  if [ "$preserve_state" = yes ] && [ "$target_existed" -eq 1 ]; then
    for state in storage log; do
      if [ -d "$previous/$state" ]; then
        if [ -e "$stage/$state" ] || [ -L "$stage/$state" ]; then
          rm -rf "$stage/$state" || {
            [ -d "$previous" ] && mv "$previous" "$target"
            rm -rf "$stage"
            return 1
          }
        fi
        if ! mv "$previous/$state" "$stage/$state"; then
          [ "$storage_carried" -eq 1 ] && mv "$stage/storage" "$previous/storage"
          [ "$log_carried" -eq 1 ] && mv "$stage/log" "$previous/log"
          mv "$previous" "$target"
          rm -rf "$stage"
          echo "rails-sync: could not preserve runtime state: $state" >&2
          return 1
        fi
        if [ "$state" = storage ]; then storage_carried=1; fi
        if [ "$state" = log ]; then log_carried=1; fi
      fi
    done

    if [ -d "$previous/public/assets" ]; then
      if [ -L "$stage/public" ]; then
        [ "$storage_carried" -eq 1 ] && mv "$stage/storage" "$previous/storage"
        [ "$log_carried" -eq 1 ] && mv "$stage/log" "$previous/log"
        mv "$previous" "$target"
        rm -rf "$stage"
        echo "rails-sync: staged public path is a symlink" >&2
        return 1
      fi
      [ -d "$stage/public" ] || mkdir -p "$stage/public"
      if [ -e "$stage/public/assets" ] || [ -L "$stage/public/assets" ]; then
        rm -rf "$stage/public/assets" || {
          [ "$storage_carried" -eq 1 ] && mv "$stage/storage" "$previous/storage"
          [ "$log_carried" -eq 1 ] && mv "$stage/log" "$previous/log"
          mv "$previous" "$target"
          rm -rf "$stage"
          return 1
        }
      fi
      if ! mv "$previous/public/assets" "$stage/public/assets"; then
        [ "$storage_carried" -eq 1 ] && mv "$stage/storage" "$previous/storage"
        [ "$log_carried" -eq 1 ] && mv "$stage/log" "$previous/log"
        mv "$previous" "$target"
        rm -rf "$stage"
        echo "rails-sync: could not preserve compiled assets" >&2
        return 1
      fi
      assets_carried=1
    fi
  fi

  if ! mv "$stage" "$target"; then
    if [ "$assets_carried" -eq 1 ]; then
      mkdir -p "$previous/public"
      mv "$stage/public/assets" "$previous/public/assets"
    fi
    [ "$storage_carried" -eq 1 ] && mv "$stage/storage" "$previous/storage"
    [ "$log_carried" -eq 1 ] && mv "$stage/log" "$previous/log"
    [ "$target_existed" -eq 1 ] && mv "$previous" "$target"
    rm -rf "$stage"
    echo "rails-sync: activation failed; previous tree restored" >&2
    return 1
  fi

  [ "$target_existed" -eq 0 ] || rm -rf "$previous"
  echo "rails-sync: activated $target"
}

case "$mode" in
  app)
    sync_tree_stage "$rails_root/$app" "$app_dir" yes
    ;;
  shared)
    sync_tree_stage "$rails_root/__shared" "$app_home/__shared" no
    ;;
  verticals)
    for source_dir in "$rails_root"/brgen_*/; do
      [ -d "$source_dir" ] || continue
      [ ! -L "$source_dir" ] || { echo "rails-sync: refusing symlinked vertical" >&2; exit 1; }
      name=$(basename "$source_dir")
      case "$name" in
        brgen_[A-Za-z0-9_]*) ;;
        *) echo "rails-sync: refused vertical name: $name" >&2; exit 1 ;;
      esac
      sync_tree_stage "$source_dir" "$app_home/$name" no
    done
    ;;
esac
