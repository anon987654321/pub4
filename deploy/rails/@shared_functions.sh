```zsh
#!/usr/bin/env zsh
# Shared functions for Rails app generators
# master.yml v206 workflow: Extract duplication, DRY, modern zsh

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Generate SCSS variables for Rails application
# Arguments: theme_color [dark_mode] [bg_color] [surface_color] [text_color] [border_color] [spacing]
generate_application_scss() {
  local theme_color="${1:-#0066ff}"
  local dark_mode="${2:-dark}"
  local bg_color="${3:-#ffffff}"
  local surface_color="${4:-#f8f9fa}"
  local text_color="${5:-#1a1a1a}"
  local border_color="${6:-#dadce0}"
  local spacing="${7:-1rem}"
  local -r target="app/assets/stylesheets/application.scss"

  # Enhanced color validation with proper hex length checking
  local color_regex='^(#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})|rgb\(\s*(\d{1,3}\s*,\s*){2}\d{1,3}\s*\)|rgba\(\s*(\d{1,3}\s*,\s*){3}(0|1|0?\.\d+)\s*\)|hsl\(\s*\d{1,3}\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*\)|hsla\(\s*\d{1,3}\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*,\s*(0|1|0?\.\d+)\s*\))$'
  [[ $theme_color =~ $color_regex ]] || {
    print -u2 "Error: Invalid color format '$theme_color'. Use hex (#RRGGBB, #RGB, #RRGGBBAA), rgb(), rgba(), hsl(), or hsla()"
    return 1
  }

  # Validate dark_mode parameter with only relevant options
  [[ $dark_mode == "dark" || $dark_mode == "light" ]] || {
    print -u2 "Error: dark_mode must be 'dark' or 'light', got '$dark_mode'"
    return 1
  }

  # Use realpath for robust path handling
  local target_dir
  if ! target_dir=$(realpath -m "${target:h}"); then
    print -u2 "Error: Failed to resolve target directory path"
    return 1
  fi

  # Create directory if it doesn't exist
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
    print -u2 "Error: Target file $target already exists"
    return 1
  fi

  # Generate SCSS content with conditional dark mode
  local scss_content="// Application SCSS variables
// Generated automatically - do not edit manually

// Theme colors
\$theme-color: $theme_color;
\$background-color: $bg_color;
\$surface-color: $surface_color;
\$text-color: $text_color;
\$border-color: $border_color;
\$spacing: $spacing;"

  # Only add dark mode media query if dark mode is enabled
  if [[ $dark_mode == "dark" ]]; then
    scss_content+="

// Dark mode overrides
@media (prefers-color-scheme: dark) {
  \$background-color: #1a1a1a;
  \$surface-color: #2d2d2d;
  \$text-color: #ffffff;
  \$border-color: #404040;
}"
  fi

  # Write to file with error handling
  if ! printf '%s\n' "$scss_content" > "$target"; then
    print -u2 "Error: Failed to write to $target"
    return 1
  fi

  print "Successfully generated SCSS variables at $target"
}
```
