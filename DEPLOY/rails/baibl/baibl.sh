#!/usr/bin/env zsh
# baibl.sh — Baibl Scripture Rails 8 App
# Usage: zsh baibl.sh
set -euo pipefail

APP_NAME=baibl
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10007
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/verse.rb" && exit 0

log "Baibl — Scripture Reader and Study Platform"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem pg_search
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Book \
  name:string abbreviation:string testament:string \
  chapter_count:integer order_index:integer \
  --no-test-framework

bin/rails generate model Chapter \
  book:references number:integer \
  --no-test-framework

bin/rails generate model Verse \
  chapter:references book:references \
  number:integer content:text \
  --no-test-framework

bin/rails generate model Highlight \
  verse:references user:references \
  color:string note:text \
  --no-test-framework

bin/rails generate model Bookmark \
  verse:references user:references \
  note:text \
  --no-test-framework

bin/rails generate model ReadingPlan \
  name:string description:text \
  duration_days:integer user:references \
  --no-test-framework

bin/rails generate model ReadingPlanDay \
  reading_plan:references day_number:integer \
  book:references chapter_start:integer chapter_end:integer \
  completed_at:datetime \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/book.rb << 'RUBY'
class Book < ApplicationRecord
  has_many :chapters, dependent: :destroy
  has_many :verses, dependent: :destroy

  TESTAMENTS = %w[Old New].freeze

  validates :name, :abbreviation, :testament, presence: true
  validates :testament, inclusion: { in: TESTAMENTS }
  validates :abbreviation, uniqueness: true

  scope :old_testament, -> { where(testament: "Old").order(:order_index) }
  scope :new_testament, -> { where(testament: "New").order(:order_index) }
  scope :ordered,       -> { order(:order_index) }
end
RUBY

cat > app/models/verse.rb << 'RUBY'
class Verse < ApplicationRecord
  include PgSearch::Model

  belongs_to :chapter
  belongs_to :book

  has_many :highlights, dependent: :destroy
  has_many :bookmarks, dependent: :destroy

  validates :number, :content, presence: true
  validates :number, uniqueness: { scope: :chapter_id }

  pg_search_scope :full_text_search,
    against: :content,
    using: { tsearch: { prefix: true, dictionary: "english" } }

  scope :in_chapter, ->(chapter) { where(chapter: chapter).order(:number) }

  def reference
    "#{book.name} #{chapter.number}:#{number}"
  end
end
RUBY

cat > app/models/highlight.rb << 'RUBY'
class Highlight < ApplicationRecord
  belongs_to :verse
  belongs_to :user

  COLORS = %w[yellow green blue pink orange].freeze

  validates :color, inclusion: { in: COLORS }
  validates :verse_id, uniqueness: { scope: :user_id }

  after_create_commit -> { broadcast_replace_to [user, "highlights"] }
end
RUBY

cat > app/models/bookmark.rb << 'RUBY'
class Bookmark < ApplicationRecord
  belongs_to :verse
  belongs_to :user

  validates :verse_id, uniqueness: { scope: :user_id }

  after_create_commit -> { broadcast_append_to [user, "bookmarks"] }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Method
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/scriptures_controller.rb << 'RUBY'
class ScripturesController < ApplicationController
  def index
    @books = Book.ordered
    @daily_verse = Verse.order("RANDOM()").limit(1).first
  end

  def book
    @book     = Book.find_by!(abbreviation: params[:abbreviation])
    @chapters = @book.chapters.order(:number)
  end

  def chapter
    @book    = Book.find_by!(abbreviation: params[:book_abbreviation])
    @chapter = @book.chapters.find_by!(number: params[:number])
    @verses  = @chapter.verses.order(:number).includes(:highlights, :bookmarks)
  end

  def search
    @pagy, @verses = pagy(Verse.full_text_search(params[:q]).includes(:book, :chapter), items: 20)
    render :search
  end
end
RUBY

cat > app/controllers/highlights_controller.rb << 'RUBY'
class HighlightsController < ApplicationController
  before_action :require_authentication

  def create
    verse = Verse.find(params[:verse_id])
    @highlight = Current.user.highlights.find_or_initialize_by(verse: verse)
    @highlight.update!(color: params[:color] || "yellow")
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end

  def destroy
    @highlight = Current.user.highlights.find(params[:id])
    @highlight.destroy!
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end
end
RUBY

cat > app/controllers/bookmarks_controller.rb << 'RUBY'
class BookmarksController < ApplicationController
  before_action :require_authentication

  def index
    @pagy, @bookmarks = pagy(Current.user.bookmarks.includes(verse: [:book, :chapter]))
  end

  def create
    verse = Verse.find(params[:verse_id])
    @bookmark = Current.user.bookmarks.find_or_create_by!(verse: verse)
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end

  def destroy
    @bookmark = Current.user.bookmarks.find(params[:id])
    @bookmark.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to bookmarks_path }
    end
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "scriptures#index"

  get "scripture",                to: "scriptures#index",   as: :scripture_index
  get "scripture/:abbreviation",  to: "scriptures#book",    as: :scripture_book
  get "scripture/:book_abbreviation/:number", to: "scriptures#chapter", as: :scripture_chapter
  get "search",                   to: "scriptures#search",  as: :scripture_search

  resources :highlights, only: %i[create destroy]
  resources :bookmarks

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Layout ─────────────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #0f0e0b; --surface: #1a1812; --text: #f0ead6;
  --text-dim: #8a7f68; --primary: #c9a96e; --border: rgba(201,169,110,.25);
  --radius: 10px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: "Palatino Linotype", Palatino, Georgia, serif; background: var(--bg); color: var(--text); line-height: 1.85; }
main { max-width: 820px; margin: 0 auto; padding: 2rem 1.5rem; }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 1.25rem 2rem; display: flex; align-items: center; justify-content: space-between; }
.logo { font-size: 1.5rem; color: var(--primary); font-variant: small-caps; }
.verse-block { background: var(--surface); border: 1px solid var(--border); border-left: 3px solid var(--primary); border-radius: var(--radius); padding: 1.75rem 2rem; margin-bottom: 1.5rem; }
.verse-ref { font-size: .78rem; color: var(--primary); letter-spacing: .08em; text-transform: uppercase; margin-bottom: .75rem; font-family: system-ui, sans-serif; }
.verse-text { font-style: italic; font-size: 1.1rem; }
.verse-text .verse-num { font-size: .75rem; color: var(--primary); vertical-align: super; margin-right: .2rem; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
CSS

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/scriptures app/views/highlights app/views/bookmarks

write_shared_partials
write_auth_views

cat > app/views/scriptures/index.html.erb << 'ERB'
<% content_for :title, "Scripture" %>
<nav class="book-nav">
  <% @books.each do |book| %>
    <%= link_to book.abbreviation, scripture_book_path(book.abbreviation), title: book.name %>
  <% end %>
</nav>
<% if @books.any? %>
  <p class="dim">Select a book to begin reading.</p>
<% end %>
ERB

cat > app/views/scriptures/book.html.erb << 'ERB'
<% content_for :title, @book.name %>
<h1><%= @book.name %></h1>
<nav class="chapter-nav">
  <% @chapters.each do |chapter| %>
    <%= link_to chapter.number, scripture_chapter_path(@book.abbreviation, chapter.number) %>
  <% end %>
</nav>
ERB

cat > app/views/scriptures/chapter.html.erb << 'ERB'
<% content_for :title, "#{@book.name} #{@chapter.number}" %>
<header>
  <h1><%= @book.name %> <%= @chapter.number %></h1>
  <nav>
    <% if @prev_chapter %>
      <%= link_to "← #{@book.abbreviation} #{@prev_chapter}", scripture_chapter_path(@book.abbreviation, @prev_chapter) %>
    <% end %>
    <%= link_to @book.name, scripture_book_path(@book.abbreviation) %>
    <% if @next_chapter %>
      <%= link_to "#{@book.abbreviation} #{@next_chapter} →", scripture_chapter_path(@book.abbreviation, @next_chapter) %>
    <% end %>
  </nav>
</header>
<div class="verse-block">
  <% @verses.each do |verse| %>
    <span id="v<%= verse.number %>" class="verse" data-controller="verse" data-verse-id="<%= verse.id %>">
      <sup class="verse-num"><%= verse.number %></sup>
      <span class="verse-text"><%= verse.content %></span>
      <% if authenticated? %>
        <% highlight = @highlights[verse.id] %>
        <% bookmark  = @bookmarks[verse.id] %>
        <%= button_to highlight ? "★" : "☆", highlights_path(verse_id: verse.id), method: highlight ? :delete : :post, params: highlight ? { id: highlight.id } : {}, class: "verse-action #{"active" if highlight}", data: { turbo_stream: true } %>
        <%= button_to bookmark ? "🔖" : "📌", bookmark ? bookmark_path(bookmark) : bookmarks_path(verse_id: verse.id), method: bookmark ? :delete : :post, class: "verse-action #{"active" if bookmark}", data: { turbo_stream: true } %>
      <% end %>
    </span>
  <% end %>
</div>
ERB

cat > app/views/scriptures/search.html.erb << 'ERB'
<% content_for :title, "Search" %>
<%= form_with url: scripture_search_path, method: :get do |f| %>
  <%= f.search_field :q, value: @query, placeholder: "Search scripture…", autofocus: true, class: "search" %>
  <%= f.submit "Search" %>
<% end %>
<% if @results %>
  <p class="dim"><%= @results.size %> results for "<%= @query %>"</p>
  <% @results.each do |verse| %>
    <div class="verse-block">
      <p class="verse-ref"><%= verse.book.abbreviation %> <%= verse.chapter.number %>:<%= verse.number %></p>
      <p class="verse-text"><%= verse.content %></p>
    </div>
  <% end %>
<% end %>
ERB

cat > app/views/bookmarks/index.html.erb << 'ERB'
<% content_for :title, "Bookmarks" %>
<h1>Bookmarks</h1>
<% if @bookmarks.any? %>
  <% @bookmarks.each do |bookmark| %>
    <div class="verse-block" id="<%= dom_id(bookmark) %>">
      <p class="verse-ref"><%= link_to "#{bookmark.verse.book.abbreviation} #{bookmark.verse.chapter.number}:#{bookmark.verse.number}", scripture_chapter_path(bookmark.verse.book.abbreviation, bookmark.verse.chapter.number) %></p>
      <p class="verse-text"><%= bookmark.verse.content %></p>
      <% if bookmark.note.present? %><p class="dim"><%= bookmark.note %></p><% end %>
      <%= button_to "Remove", bookmark, method: :delete, class: "verse-action" %>
    </div>
  <% end %>
  <%= @pagy.series_nav if @pagy.pages > 1 %>
<% else %>
  <p class="dim">No bookmarks yet. Bookmark verses while reading.</p>
<% end %>
ERB

cat > app/views/highlights/create.turbo_stream.erb << 'ERB'
<%= turbo_stream.replace "highlight_#{@highlight.verse_id}", partial: "highlights/toggle", locals: { verse: @highlight.verse, highlight: @highlight } %>
ERB

cat > app/views/highlights/destroy.turbo_stream.erb << 'ERB'
<%= turbo_stream.replace "highlight_#{@highlight.verse_id}", partial: "highlights/toggle", locals: { verse: @highlight.verse, highlight: nil } %>
ERB

# ── SCSS additions ───────────────────────────────────────────────────────────
cat >> app/assets/stylesheets/application.css << 'CSS'
.book-nav { display: flex; flex-wrap: wrap; gap: .35rem; margin-bottom: 1.5rem; }
.book-nav a { padding: .25rem .5rem; background: var(--surface); border: 1px solid var(--border); border-radius: 4px; font-size: .8rem; color: var(--primary); }
.book-nav a:hover { background: var(--primary); color: var(--bg); text-decoration: none; }
.chapter-nav { display: flex; flex-wrap: wrap; gap: .35rem; }
.chapter-nav a { width: 2.2rem; text-align: center; padding: .25rem; background: var(--surface); border: 1px solid var(--border); border-radius: 4px; color: var(--primary); font-size: .9rem; }
.verse { display: block; margin-bottom: .75rem; position: relative; }
.verse-action { background: none; border: none; cursor: pointer; color: var(--text-dim); font-size: .8rem; padding: 0 .2rem; }
.verse-action.active { color: var(--primary); }
.search { width: 100%; max-width: 480px; padding: .5rem .75rem; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); color: var(--text); font-size: 1rem; }
.dim { color: var(--text-dim); font-size: .85rem; }
nav { display: flex; gap: 1rem; align-items: center; margin: 1rem 0; }
h1, h2 { margin-bottom: .75rem; color: var(--primary); }
CSS

write_layout "Baibl"
write_falcon_config "$APP_PORT"
configure_production

# ── rc.d service ───────────────────────────────────────────────────────────
install_rcd baibl "$APP_DIR" "$APP_PORT" baibl

log_ok "Baibl setup complete — start: doas rcctl start baibl"
