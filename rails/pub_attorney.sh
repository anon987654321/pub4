#!/usr/bin/env zsh
set -euo pipefail

# Pubattorney: Legal services platform with document upload, lawyer matching, case management
# Domains: pub.attorney, freehelp.legal

# Port: 12109
APP_NAME="pubattorney"

BASE_DIR="/home/dev/rails"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PORT=12109
source "${SCRIPT_DIR}/__shared/@common.sh"

log "Starting Pubattorney setup"
setup_full_app "$APP_NAME"
command_exists "ruby"

command_exists "node"

command_exists "psql"

command_exists "redis-server"

install_gem "acts_as_tenant"
install_gem "pagy"
install_gem "faker"
install_gem "wicked_pdf"

install_gem "prawn"
bin/rails generate model Lawyer name:string specialty:string bar_number:string bio:text rating:decimal user:references
bin/rails generate model Case title:string description:text status:string category:string user:references lawyer:references
bin/rails generate model Document title:string file:attachment case:references
bin/rails generate scaffold LegalResource title:string content:text category:string published_at:datetime

generate_infinite_scroll_reflex "Case" "cases"
cat <<EOF > app/reflexes/case_match_reflex.rb
class CaseMatchReflex < ApplicationReflex
  def find_lawyers

    case_type = element.dataset[:caseType]

    lawyers = Lawyer.where(specialty: case_type).order(rating: :desc).limit(5)
    cable_ready.replace(
      selector: "#lawyer-matches",
      html: render(partial: "lawyers/matches", locals: {lawyers: lawyers})
    ).broadcast
  end
end
EOF
cat <<EOF > app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!, except: [:index, :show]
  def after_sign_in_path_for(resource)

    dashboard_path
  end
end

EOF
cat <<EOF > app/controllers/cases_controller.rb
class CasesController < ApplicationController
  before_action :set_case, only: [:show, :edit, :update, :destroy]
  def index

    @pagy, @cases = pagy(current_user.cases.order(created_at: :desc)) unless @stimulus_reflex
  end
  def show

    @documents = @case.documents.order(created_at: :desc)
  end
  def new

    @case = Case.new
  end
  def create

    @case = current_user.cases.build(case_params)
    if @case.save
      redirect_to @case, notice: "Case created successfully"

    else
      render :new
    end
  end
  private
  def set_case
    @case = current_user.cases.find(params[:id])
  end

  def case_params

    params.require(:case).permit(:title, :description, :category, :lawyer_id)
  end
end

EOF
cat <<EOF > app/controllers/lawyers_controller.rb
class LawyersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :show]
  def index

    @pagy, @lawyers = pagy(Lawyer.order(rating: :desc)) unless @stimulus_reflex
  end
  def show

    @lawyer = Lawyer.find(params[:id])
    @cases = @lawyer.cases.where(status: "completed").limit(5)
  end

end
EOF
cat <<EOF > app/controllers/documents_controller.rb
class DocumentsController < ApplicationController
  before_action :set_case
  def create

    @document = @case.documents.build(document_params)
    if @document.save
      redirect_to @case, notice: "Document uploaded"

    else
      redirect_to @case, alert: "Upload failed"
    end
  end
  def destroy
    @document = @case.documents.find(params[:id])
    @document.destroy
    redirect_to @case, notice: "Document deleted"

  end
  private
  def set_case
    @case = current_user.cases.find(params[:case_id])
  end

  def document_params

    params.require(:document).permit(:title, :file)
  end
end

EOF
cat <<EOF > config/routes.rb
Rails.application.routes.draw do
  devise_for :users
  root "home#index"

  get "dashboard", to: "cases#index"
  resources :cases do
    resources :documents, only: [:create, :destroy]

  end

  resources :lawyers, only: [:index, :show]

  resources :legal_resources, only: [:index, :show]
end
EOF

# Create ultraminimal professional layout
log "Creating PubAttorney application layout"

mkdir -p app/views/layouts app/assets/stylesheets
cat <<'LAYOUTEOF' > app/views/layouts/application.html.erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= content_for?(:title) ? yield(:title) : "PubAttorney - Free Legal Help" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : 'Connect with qualified lawyers for free legal consultations' %>">
  <meta name="theme-color" content="#2c3e50">
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
  <header class="site-header">
    <div class="container">
      <nav>
        <div class="logo"><%= link_to "⚖️ PubAttorney", root_path %></div>
        <div class="nav-links">
          <%= link_to "Cases", cases_path, class: "nav-link" %>
          <%= link_to "Resources", legal_resources_path, class: "nav-link" %>
          <% if user_signed_in? %>
            <%= link_to "Profile", "#", class: "nav-link" %>
            <%= button_to "Sign Out", destroy_user_session_path, method: :delete, class: "btn-text" %>
          <% else %>
            <%= link_to "Sign In", new_user_session_path, class: "nav-link" %>
            <%= link_to "Get Help", new_user_registration_path, class: "btn-primary" %>
          <% end %>
        </div>
      </nav>
    </div>
  </header>
  <main>
    <% if notice %><div class="flash flash-notice"><%= notice %></div><% end %>
    <% if alert %><div class="flash flash-alert"><%= alert %></div><% end %>
    <%= yield %>
  </main>
  <footer class="site-footer">
    <div class="container"><p>&copy; <%= Time.current.year %> PubAttorney. <%= link_to "Privacy", "#" %> &middot; <%= link_to "Terms", "#" %></p></div>
  </footer>
</body>
</html>
LAYOUTEOF
cat <<'CSSEOF' > app/assets/stylesheets/application.css
:root{--primary:#2c3e50;--bg:#fafafa;--text:#212121;--border:#e0e0e0}

*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,sans-serif;color:var(--text);background:var(--bg);line-height:1.6;min-height:100vh;display:flex;flex-direction:column}
.container{max-width:1200px;margin:0 auto;padding:0 1rem}
.site-header{background:white;border-bottom:1px solid var(--border);padding:1rem 0}
.site-header nav{display:flex;justify-content:space-between;align-items:center}
.logo{font-size:1.5rem;font-weight:600;text-decoration:none;color:var(--text)}
.nav-links{display:flex;gap:1rem;align-items:center}
.nav-link{text-decoration:none;color:var(--text)}
main{flex:1;padding:2rem 0}
.flash{padding:1rem;margin:1rem auto;max-width:1200px;border-radius:4px}
.flash-notice{background:#e8f5e9;color:#2e7d32}
.flash-alert{background:#ffebee;color:#c62828}
.btn-primary{background:var(--primary);color:white;padding:.5rem 1rem;border-radius:4px;text-decoration:none}
.site-footer{background:white;border-top:1px solid var(--border);padding:2rem 0;text-align:center;color:#666}
CSSEOF
cat <<EOF > app/views/home/index.html.erb
<div class="hero">

  <h1>Free Legal Help</h1>
  <p>Connect with qualified lawyers for free consultations</p>

  <%= link_to "Get Started", new_user_registration_path, class: "btn btn-primary" %>
</div>
<div class="features">
  <div class="feature">
    <h3>Find Lawyers</h3>
    <p>Browse our network of licensed attorneys</p>

  </div>
  <div class="feature">
    <h3>Case Management</h3>
    <p>Track your cases and documents in one place</p>
  </div>
  <div class="feature">
    <h3>Free Resources</h3>
    <p>Access legal guides and templates</p>
  </div>
</div>
<div class="recent-lawyers">
  <h2>Featured Lawyers</h2>
  <% Lawyer.order(rating: :desc).limit(6).each do |lawyer| %>
    <div class="lawyer-card">

      <h4><%= lawyer.name %></h4>
      <p><%= lawyer.specialty %></p>
      <p>Rating: <%= lawyer.rating %>/5</p>
      <%= link_to "View Profile", lawyer_path(lawyer) %>
    </div>
  <% end %>
</div>
EOF
cat <<EOF > app/views/cases/index.html.erb
<h1>My Cases</h1>
<%= link_to "New Case", new_case_path, class: "btn btn-primary" %>
<div id="cases-container" data-controller="infinite-scroll">

  <% @cases.each do |legal_case| %>
    <div class="case-card">

      <h3><%= link_to legal_case.title, case_path(legal_case) %></h3>

      <p><%= legal_case.description.truncate(100) %></p>
      <span class="status <%= legal_case.status %>"><%= legal_case.status %></span>
      <% if legal_case.lawyer %>
        <p>Lawyer: <%= legal_case.lawyer.name %></p>
      <% end %>
    </div>
  <% end %>
</div>
EOF
cat <<EOF > app/views/cases/show.html.erb
<div class="case-detail">
  <h1><%= @case.title %></h1>
  <div class="case-info">

    <p><strong>Status:</strong> <%= @case.status %></p>
    <p><strong>Category:</strong> <%= @case.category %></p>
    <p><strong>Description:</strong><br><%= @case.description %></p>

  </div>
  <% if @case.lawyer %>
    <div class="assigned-lawyer">
      <h3>Assigned Lawyer</h3>
      <%= link_to @case.lawyer.name, lawyer_path(@case.lawyer) %>

    </div>
  <% else %>
    <div data-controller="case-match" data-case-type="<%= @case.category %>">
      <button data-action="click->case-match#findLawyers">Find Matching Lawyers</button>
      <div id="lawyer-matches"></div>
    </div>
  <% end %>
  <div class="documents">
    <h3>Documents</h3>
    <%= form_with model: [@case, Document.new], local: true do |f| %>
      <%= f.text_field :title, placeholder: "Document title" %>

      <%= f.file_field :file %>
      <%= f.submit "Upload" %>
    <% end %>
    <% @documents.each do |doc| %>
      <div class="document">
        <%= link_to doc.title, rails_blob_path(doc.file) %>
        <%= button_to "Delete", case_document_path(@case, doc), method: :delete %>

      </div>
    <% end %>
  </div>
</div>
EOF
cat <<EOF > app/views/lawyers/index.html.erb
<h1>Find a Lawyer</h1>
<div class="search-filters">
  <!-- Add search/filter form here -->

</div>
<div id="lawyers-container" data-controller="infinite-scroll">

  <% @lawyers.each do |lawyer| %>
    <div class="lawyer-card">
      <h3><%= link_to lawyer.name, lawyer_path(lawyer) %></h3>

      <p><%= lawyer.specialty %></p>
      <p>Bar #: <%= lawyer.bar_number %></p>
      <p>Rating: <%= lawyer.rating %>/5</p>
      <p><%= lawyer.bio.truncate(150) %></p>
    </div>
  <% end %>
</div>
EOF
generate_all_stimulus_controllers
cat <<EOF > app/assets/stylesheets/application.css
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;

  margin: 0;

  padding: 0;
  background: #f5f5f5;
}
.hero {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 80px 20px;

  text-align: center;
}
.hero h1 {
  font-size: 3em;
  margin: 0;
}

.btn {
  display: inline-block;
  padding: 12px 24px;
  border-radius: 4px;

  text-decoration: none;
  transition: all 0.3s;
}
.btn-primary {
  background: white;
  color: #667eea;
  font-weight: bold;

}
.features {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 30px;

  padding: 60px 20px;
  max-width: 1200px;
  margin: 0 auto;
}
.feature {
  background: white;
  padding: 30px;
  border-radius: 8px;

  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}
.lawyer-card, .case-card {
  background: white;
  padding: 20px;
  margin: 10px 0;

  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}
.status {
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 0.85em;

  font-weight: bold;
}
.status.open { background: #fef3c7; color: #92400e; }
.status.in_progress { background: #dbeafe; color: #1e40af; }
.status.completed { background: #d1fae5; color: #065f46; }
EOF

log "Pubattorney setup complete on PORT=$PORT"
log "Domains: pub.attorney, freehelp.legal"
log "Run: cd /home/dev/rails/$APP_NAME && bin/rails server -p $PORT"
