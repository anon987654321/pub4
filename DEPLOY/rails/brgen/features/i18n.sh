#!/usr/bin/env sh
set -euo pipefail

# Immutable constants
readonly APP_DIR="/home/brgen/app"
readonly LOCALE_DIR="${APP_DIR}/config/locales"
readonly MSG_START="==> [i18n] Norwegian (nb) + English (en) locales"
readonly DONE_MSG="==> [i18n] done"

# Preconditions
[ -d "${LOCALE_DIR}" ] || {
  printf 'Error: %s not found\n' "${LOCALE_DIR}" >&2
  exit 1
}
[ -w "${LOCALE_DIR}" ] || {
  printf 'Error: %s not writable\n' "${LOCALE_DIR}" >&2
  exit 1
}

printf '%s\n' "${MSG_START}"

# Write a file atomically, cleaning up on error
write_locale() {
  dest=$1
  tmp=$(mktemp -p "${LOCALE_DIR}" ".tmp.$(basename "${dest}").XXXXXX") || exit 1
  trap 'rm -f "${tmp}"' EXIT INT TERM
  cat >"${tmp}"
  chmod 0644 "${tmp}"
  mv -f "${tmp}" "${dest}"
  trap - EXIT INT TERM
}

generate_locale() {
  case $1 in
    nb)
      write_locale "${LOCALE_DIR}/nb.yml" <<'EOF'
nb:
  brgen:
    app_name: "BRGEN"
    communities: "Lokalsamfunn"
    posts: "Innlegg"
    new_post: "Nytt innlegg"
    upvote: "Stem opp"
    downvote: "Stem ned"
    karma: "Karma"
    comments: "Kommentarer"
    add_comment: "Legg til kommentar"
    posted_by: "Postet av %{user}"
    edit: "Rediger"
    delete: "Slett"
    confirm_delete: "Er du sikker?"
    post_created: "Innlegget ble opprettet."
    post_updated: "Innlegget ble oppdatert."
    post_deleted: "Innlegget ble slettet."
    comment_created: "Kommentar ble lagt til."
    comment_deleted: "Kommentar ble slettet."
    unauthorized: "Ingen tilgang."
EOF
      ;;
    en)
      write_locale "${LOCALE_DIR}/en.yml" <<'EOF'
en:
  brgen:
    app_name: "BRGEN"
    communities: "Communities"
    posts: "Posts"
    new_post: "New post"
    upvote: "Upvote"
    downvote: "Downvote"
    karma: "Karma"
    comments: "Comments"
    add_comment: "Add a comment"
    posted_by: "Posted by %{user}"
    edit: "Edit"
    delete: "Delete"
    confirm_delete: "Are you sure?"
    post_created: "Post created."
    post_updated: "Post updated."
    post_deleted: "Post deleted."
    comment_created: "Comment added."
    comment_deleted: "Comment deleted."
    unauthorized: "Not authorized."
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

generate_locale nb
generate_locale en

printf '%s\n' "${DONE_MSG}"