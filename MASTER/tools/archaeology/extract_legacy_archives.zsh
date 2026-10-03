#!/usr/bin/env zsh
# Extract every tracked .tgz/.tar.gz/.zip from pub, pub2, and pub3.
# Output is outside the source repositories and deduplicated by Git blob SHA.
# Usage: ./extract_legacy_archives.zsh [pub_root] [pub2_root] [pub3_root] [output_root]

set -euo pipefail
setopt null_glob

typeset -r SCRIPT_ROOT=${0:A:h}
typeset -r PUB4_ROOT=${SCRIPT_ROOT}/../../..
typeset PUB_ROOT=${1:-${PUB4_ROOT}/../pub}
typeset PUB2_ROOT=${2:-${PUB4_ROOT}/../pub2}
typeset PUB3_ROOT=${3:-${PUB4_ROOT}/../pub3}
typeset OUT=${4:-${PUB4_ROOT}/ARCHAEOLOGY/extracted}

mkdir -p ${OUT}/by-blob ${OUT}/by-archive

log() { print -r -- "archaeology0: $*"; }

unsafe_members() {
  local archive=$1 member
  local -a members
  if [[ $archive == *.zip ]]; then
    members=( "${(@f)$(unzip -Z1 -- $archive)}" )
  else
    members=( "${(@f)$(tar -tzf $archive)}" )
  fi
  for member in "${members[@]}"; do
    case $member in
      /*|../*|*/../*|*/..|..) print -r -- $member; return 0 ;;
    esac
  done
  return 1
}

extract_one() {
  local repo=$1 archive=$2 relative=$3 blob tmp member
  blob=$(git -C $repo hash-object -- $archive)
  local blob_dir=${OUT}/by-blob/${blob}
  local archive_dir=${OUT}/by-archive/${repo:t}/${relative}
  tmp=${OUT}/.tmp.${blob}.$$

  if [[ -e ${blob_dir}/.extracted ]]; then
    log "reuse ${repo:t}/${relative} blob=${blob}"
  else
    if member=$(unsafe_members $archive); then
      log "REFUSE path traversal repo=${repo:t} archive=${relative} member=${member}"
      return 1
    fi
    rm -rf -- $tmp
    mkdir -p -- $tmp
    case $archive in
      *.zip) unzip -q -- $archive -d $tmp ;;
      *.tgz|*.tar.gz) tar -xzf $archive -C $tmp ;;
      *) rm -rf -- $tmp; return 0 ;;
    esac
    mkdir -p -- $blob_dir
    cp -a -- ${tmp}/. $blob_dir/
    print -r -- "source_repo=${repo}" > ${blob_dir}/SOURCE
    print -r -- "source_path=${relative}" >> ${blob_dir}/SOURCE
    print -r -- "git_blob=${blob}" >> ${blob_dir}/SOURCE
    : > ${blob_dir}/.extracted
    rm -rf -- $tmp
    log "extract ${repo:t}/${relative} blob=${blob}"
  fi
  mkdir -p -- ${archive_dir:h}
  ln -sfn -- ${blob_dir} ${archive_dir}
  print -r -- "${repo:t}\t${relative}\t${blob}\t${archive_dir}" >> ${OUT}/manifest.tsv
}

scan_repo() {
  local repo=$1
  [[ -d ${repo}/.git ]] || { log "missing git repo=${repo}"; return 0; }
  local -a archives=( "${(@f)$(git -C $repo ls-files -- '*.tgz' '*.tar.gz' '*.zip')}" )
  local relative
  for relative in "${archives[@]}"; do
    [[ -n $relative ]] || continue
    extract_one $repo ${repo}/${relative} $relative
  done
}

: > ${OUT}/manifest.tsv
scan_repo $PUB_ROOT
scan_repo $PUB2_ROOT
scan_repo $PUB3_ROOT
log "complete output=${OUT}"