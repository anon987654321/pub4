#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

APP_DIR="/home/brgen/app"
LOCALE_DIR="${APP_DIR}/config/locales"
MSG_START="==> [i18n] Norwegian (nb) + English (en) locales"

# Fail fast if locale directory missing or not writable
[[ -d "$LOCALE_DIR" ]] || { echo "Error: $LOCALE_DIR not found" >&2; exit 1; }
[[ -w "$LOCALE_DIR" ]] || { echo "Error: $LOCALE_DIR not writable" >&2; exit 1; }

echo "$MSG_START"

generate_locale() {
  local lang=$1
  case $lang in    nb) YAML='
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
' ;;
    en) YAML='
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
' ;;
    *) return 1 ;;
  esac

  printf "%s\n" "$YAML" >"$LOCALE_DIR/${lang}.yml"
}

generate_locale nb
generate_locale en
echo "==> [i18n] done"