```zsh
#!/usr/bin/env zsh
# Shared functions for Rails app generators
# Per master.yml v206 workflow: Extract duplication, DRY, modern zsh

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Generate base application.scss with CSS variables
generate_application_scss() {
  typeset theme_color="${1:-#0066ff}"
  typeset dark_mode="${2:-true}"
  typeset -r target="app/assets/stylesheets/application.scss"

  mkdir -p ${target:h} || return 1
  {
    print -r "/* Generated per master.yml v206 */
:root {
  --primary: ${theme_color};
  --bg: #ffffff;
  --surface: #f8f9fa;
  --text: #1a1a1a;
  --border: #dadce0;
  --spacing: 1rem;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1a1a1a;
    --surface: #2a2a2a;
    --text: #ffffff;
    --border: #3a3a3a;
  }
}"
  } > $target || return 1
}

# Generate secure controller with authentication + authorization
generate_secure_controller() {
  typeset name=$1
  typeset model=${name:l}
  typeset model_class=${(C)name}
  typeset -r target="app/controllers/${model}_controller.rb"

  mkdir -p ${target:h} || return 1
  cat > $target << RUBY || return 1
class ${model_class}Controller < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_${model}, only: [:show, :edit, :update, :destroy]
  before_action :authorize_user!, only: [:edit, :update, :destroy]

  def index
    @pagy, @${model}s = pagy(${model_class}.all.order(created_at: :desc))
  end

  def show
  end

  def new
    @${model} = current_user.${model}s.build
  end

  def create
    @${model} = current_user.${model}s.build(${model}_params)
    if @${model}.save
      redirect_to ${model}s_url
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @${model}.update(${model}_params)
      redirect_to @${model}
    else
      render :edit
    end
  end

  def destroy
    @${model}.destroy
    redirect_to ${model}s_url
  end

  private

  def set_${model}
    @${model} = ${model_class}.find_by(id: params[:id])
    return if @${model}
    redirect_to ${model}s_url, alert: "${model_class} not found."
  end

  def authorize_user!
    return if current_user.admin? || @${model}.user == current_user
    redirect_to ${model}s_url, alert: "Not authorized."
  end

  def ${model}_params
    params.require(:${model}).permit(:title, :content)
  end
end
RUBY
}
```
