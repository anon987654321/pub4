#!/usr/bin/env zsh
set -euo pipefail

# I18n/Localization setup for Rails 8 apps
# Norwegian + English with fallbacks

setup_i18n() {
  local app_name="${1:-App}"
  local default_locale="${2:-no}"
  
  log "Setting up i18n with default locale: $default_locale"
  
  # Configure i18n in application.rb
  cat >> config/application.rb << RUBY

    # I18n configuration
    config.i18n.default_locale = :${default_locale}
    config.i18n.available_locales = [:no, :en]
    config.i18n.fallbacks = [I18n.default_locale]
    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}')]
RUBY
  
  # Norwegian locale
  mkdir -p config/locales/no
  cat <<'LOCALE' > config/locales/no/no.yml
no:
  app:
    name: "${app_name}"
  
  nav:
    home: "Hjem"
    profile: "Profil"
    sign_in: "Logg inn"
    sign_out: "Logg ut"
    sign_up: "Registrer"
  
  actions:
    save: "Lagre"
    cancel: "Avbryt"
    delete: "Slett"
    edit: "Rediger"
    create: "Opprett"
    update: "Oppdater"
    back: "Tilbake"
    show: "Vis"
    search: "Søk"
  
  confirm: "Er du sikker?"
  
  time:
    formats:
      default: "%d.%m.%Y %H:%M"
      short: "%d.%m.%y"
      long: "%d. %B %Y, %H:%M"
LOCALE
  
  # English locale
  mkdir -p config/locales/en
  cat <<'LOCALE' > config/locales/en/en.yml
en:
  app:
    name: "${app_name}"
  
  nav:
    home: "Home"
    profile: "Profile"
    sign_in: "Sign in"
    sign_out: "Sign out"
    sign_up: "Sign up"
  
  actions:
    save: "Save"
    cancel: "Cancel"
    delete: "Delete"
    edit: "Edit"
    create: "Create"
    update: "Update"
    back: "Back"
    show: "Show"
    search: "Search"
  
  confirm: "Are you sure?"
  
  time:
    formats:
      default: "%Y-%m-%d %H:%M"
      short: "%m/%d/%y"
      long: "%B %d, %Y at %H:%M"
LOCALE
  
  log "✓ I18n configured (no, en) with fallbacks"
}

add_locale_switcher() {
  cat <<'HELPER' >> app/helpers/application_helper.rb

  def locale_switcher
    tag.nav class: "locale-switcher" do
      I18n.available_locales.map do |locale|
        link_to locale.upcase, url_for(locale: locale), 
                class: (I18n.locale == locale ? "active" : "")
      end.join(" | ").html_safe
    end
  end
HELPER
  
  log "✓ Locale switcher helper added"
}
