#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"

echo "==> [i18n] Norwegian (nb) + English (en) locales"
cd "$APP_DIR"

cat > config/locales/nb.yml << 'YAML'
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
YAML

cat > config/locales/en.yml << 'YAML'
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
YAML

echo "==> [i18n] done"
