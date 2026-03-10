```zsh
#!/usr/bin/env zsh
# Shared functions for Rails app generators
# master.yml v206 workflow: Extract duplication, DRY, modern zsh

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Generate base application.scss with CSS variables
# Usage: generate_application_scss <theme_color> <dark_mode>
generate_application_scss() {
  local theme_color="${1:-#0066ff}"
  local dark_mode="${2:-true}"
  local -r target="app/assets/stylesheets/application.scss"

  # Validate color format (accepts both uppercase and lowercase hex)
  [[ $theme_color =~ ^#[0-9A-Fa-f]{6}$ ]] || {
    print -u2 "Error: Invalid color format. Use hex format (#RRGGBB or #rrggbb)"
    return 1
  }

  # Validate dark_mode parameter
  [[ $dark_mode == "true" || $dark_mode == "false" ]] || {
    print -u2 "Error: dark_mode must be 'true' or 'false'"
    return 1
  }

  # Create target directory with error handling
  if ! mkdir -p "${target:h}"; then
    print -u2 "Error: Failed to create directory ${target:h}"
    return 1
  fi

  # Generate CSS content
  local css_content="/* Generated per master.yml v206 */
:root {
  --primary: ${theme_color};
  --bg: #ffffff;
  --surface: #f8f9fa;
  --text: #1a1a1a;
  --border: #dadce0;
  --spacing: 1rem;
}"

  if [[ $dark_mode == "true" ]]; then
    css_content+="
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1a1a1a;
    --surface: #2a2a2a;
    --text: #ffffff;
    --border: #3a3a3a;
  }
}"
  fi

  # Write to file with error handling
  if ! print -r -- "$css_content" > "$target"; then
    print -u2 "Error: Failed to write to $target"
    return 1
  fi

  return 0
}

# Generate secure controller with authentication + authorization
# Usage: generate_secure_controller <model_name>
generate_secure_controller() {
  local name=$1
  [[ -z $name ]] && { print -u2 "Error: Model name required"; return 1 }

  # Validate model name format (allows mixed case and underscores)
  [[ $name =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || {
    print -u2 "Error: Invalid model name format. Must start with letter and contain only letters, numbers, and underscores"
    return 1
  }

  local model=${name:l}
  local model_class=${(C)name}
  local -r target="app/controllers/${model}_controller.rb"

  # Create target directory with error handling
  if ! mkdir -p "${target:h}"; then
    print -u2 "Error: Failed to create directory ${target:h}"
    return 1
  fi

  # Generate controller content
  local controller_content="class ${model_class}Controller < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_${model}, only: [:show, :edit, :update, :destroy]
  before_action :authorize_user!, only: [:edit, :update, :destroy]

  def index
    @pagy, @${model}s = pagy(${model_class}.all)
  end

  def show
  end

  def new
    @${model} = ${model_class}.new
  end

  def create
    @${model} = current_user.${model}s.build(${model}_params)

    if @${model}.save
      redirect_to @${model}, notice: '${model_class} was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @${model}.update(${model}_params)
      redirect_to @${model}, notice: '${model_class} was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @${model}.destroy
    redirect_to ${model}s_url, notice: '${model_class} was successfully destroyed.'
  end

  private

  def set_${model}
    @${model} = ${model_class}.find(params[:id])
  end

  def ${model}_params
    params.require(:${model}).permit(:title, :content) # Update with actual attributes
  end

  def authorize_user!
    return if current_user.admin? || @${model}.user == current_user
    redirect_to root_path, alert: 'Not authorized to perform this action.'
  end
end"

  # Write to file with error handling
  if ! print -r -- "$controller_content" > "$target"; then
    print -u2 "Error: Failed to write to $target"
    return 1
  fi

  return 0
}
```
