```zsh
#!/usr/bin/env zsh
# Shared functions for Rails app generators
# master.yml v206 workflow: Extract duplication, DRY, modern zsh

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Generate [text_color] [border_color] [spacing]
generate_application_scss() {
  local theme_color="${1:-#0066ff}"
  local dark_mode="${2:-dark}"
  local bg_color="${3:-#ffffff}"
  local surface_color="${4:-#f8f9fa}"
  local text_color="${5:-#1a1a1a}"
  local border_color="${6:-#dadce0}"
  local spacing="${7:-1rem}"
  local -r target="app/assets/stylesheets/application.scss"

  # Validate color format (accepts hex, rgb, rgba, hsl, hsla)
  local color_regex='^(#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})|rgb\(\s*(\d{1,3}\s*,\s*){2}\d{1,3}\s*\)|rgba\(\s*(\d{1,3}\s*,\s*){3}(0|1|0?\.\d+)\s*\)|hsl\(\s*\d{1,3}\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*\)|hsla\(\s*\d{1,3}\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*,\s*(0|1|0?\.\d+)\s*\))$'
  [[ $theme_color =~ $color_regex ]] || {
    print -u2 "Error: Invalid color format '$theme_color'. Use hex (#RRGGBB, #RGB), rgb(), rgba(), hsl(), or hsla()"
    return 1
  }

  # Validate dark_mode parameter
  [[ $dark_mode == "dark" || $dark_mode == "light" || $dark_mode == "auto" || $dark_mode == "system" ]] || {
    print -u2 "Error: dark_mode must be 'dark', 'light', 'auto', or 'system', got '$dark_mode'"
    return 1
  }

  # Sanitize and validate target path
  target_dir="${target:h}"
  [[ $target_dir == /* ]] || target_dir="${PWD}/${target_dir}"
  target_dir="${target_dir:A}"

  # Check if target directory exists and is writable
  if [[ ! -d $target_dir ]]; then
    if ! mkdir -p "$target_dir"; then
      print -u2 "Error: Failed to create directory $target_dir"
      return 1
    fi
  elif [[ ! -w $target_dir ]]; then
    print -u2 "Error: Directory $target_dir is not writable"
    return 1
  fi

  # Check if target file already exists
  if [[ -f $target ]]; then
    print -u2 "Error: Target file $target already exists. Refusing to overwrite."
    return 1
  fi

  # Generate CSS content using printf for safety
  local css_content
  css_content=$(printf '/* Generated per master.yml v206 */
:root {
  --primary: %s;
  --bg: %s;
  --surface: %s;
  --text: %s;
  --border: %s;
  --spacing: %s;
}
' "$theme_color" "$bg_color" "$surface_color" "$text_color" "$border_color" "$spacing")

  if [[ $dark_mode == "dark" || $dark_mode == "auto" || $dark_mode == "system" ]]; then
    css_content+=$(printf '
@media (prefers-color-scheme: dark) {
  :root {
    --bg: %s;
    --surface: %s;
    --text: %s;
    --border: %s;
  }
}
' "#1a1a1a" "#2d2d2d" "#ffffff" "#404040")
  fi

  # Write content to file
  if ! printf '%s\n' "$css_content" > "$target"; then
    print -u2 "Error: Failed to write to $target"
    return 1
  fi

  print "Successfully generated $target"
}
```
