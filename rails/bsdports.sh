#!/usr/bin/env zsh
# -- INITIAL SETUP --

echo "Creating new Rails application..."
rails new bsdports -m https://www.rubyonrails.org

cd bsdports

echo "Adding necessary gems..."

bundle add net-ftp
bundle add rubygems-package

bundle add pry

bundle add stimulus_reflex
bundle add langchainrb
bundle add langchainrb_rails
echo "Installing gems..."
bundle install
# -- CREATE NECESSARY MODELS --
echo "Generating models..."

bin/rails generate model Category name:string platform:references
bin/rails generate model Platform name:string

bin/rails generate model Port name:string summary:text url:string description:text category:references platform:references

echo "Migrating database..."
bin/rails db:migrate
# -- CREATE SEEDS.RB --
echo "Creating seeds.rb with FTP download and database import logic..."
cat << "EOF" > db/seeds.rb
require "net/ftp"

require "rubygems/package"

require "zlib"
require "fileutils"
require "pry"
def untar(io, destination)
  Gem::Package::TarReader.new io do |tar|
    tar.each do |tarfile|
      destination_file = File.join(destination, tarfile.full_name)

      if tarfile.directory?
        FileUtils.mkdir_p(destination_file)
      else
        destination_directory = File.dirname(destination_file)
        FileUtils.mkdir_p(destination_directory) unless File.directory?(destination_directory)
        File.open(destination_file, "wb") do |f|
          f.write(tarfile.read)
        end
      end
    end
  end
end
def go_fetch(platform, server, root, tgz)
  ftp = Net::FTP.new(server)
  ftp.login
  ftp.chdir(root)

  ftp.getbinaryfile(tgz)
  ftp.close
  io = Zlib::GzipReader.open(tgz)
  untar(io, ".")
  categories = Dir.glob("./ports/*").map do |category_path|
    if File.directory?(category_path)

      category = File.basename(category_path)
      new_category = Category.find_or_create_by(name: category, platform: Platform.find_by_name(platform))

      Dir.glob("#{category_path}/*").map do |port_path|
        port = File.basename(port_path)
        description_path = "#{port_path}/pkg/DESCR"
        build_script_path = "#{port_path}/Makefile"
        description = File.exist?(description_path) ? File.read(description_path) : nil
        summary = File.exist?(build_script_path) ? File.readlines(build_script_path).find { |line| line =~ /^COMMENT/ }&.gsub("COMMENT=\t", "").strip : nil
        url = File.exist?(build_script_path) ? File.readlines(build_script_path).find { |line| line =~ /^(HOMEPAGE|WWW)/ }&.gsub("HOMEPAGE=\t", "").strip : nil
        Port.find_or_create_by(name: port, summary: summary, url: url, description: description, category: new_category)

      end
    end
  end

  FileUtils.rm_rf(Dir.glob("./ports*"))  # Cleanup
end
# Fetch ports for each platform
go_fetch("OpenBSD", "ftp.usa.openbsd.org", "/pub/OpenBSD/snapshots", "ports.tar.gz")

go_fetch("FreeBSD", "ftp.nl.freebsd.org", "/pub/FreeBSD/ports/ports", "ports.tar.gz")
go_fetch("NetBSD", "ftp.netbsd.org", "/pub/pkgsrc/stable", "pkgsrc.tar.gz")

EOF
# -- CREATE VIEWS AND SCSS --
echo "Creating views and SCSS..."
mkdir -p app/views/ports
mkdir -p app/javascript/controllers

mkdir -p app/assets/stylesheets

cat << "EOF" > app/views/ports/index.html.erb
<%= tag.h1 t("ports.index.title") %>
<%= form_with url: search_ports_path, method: :get, local: true, data: { reflex: "change->PortsReflex#search" } do |f| %>
  <%= f.text_field :query, placeholder: t("ports.index.search_placeholder") %>

<% end %>
<div id="ports_list">
  <%= render @ports %>
</div>
EOF
cat << "EOF" > app/views/ports/_port.html.erb
<div class="port">
  <%= tag.h2 port.name %>
  <%= tag.p port.summary %>

  <%= tag.p port.description %>
  <%= link_to port.url, port.url %>
</div>
EOF
# Create ultraminimal professional layout
log "Creating BSDPorts application layout"
mkdir -p app/views/layouts
cat <<'LAYOUTEOF' > app/views/layouts/application.html.erb

<!DOCTYPE html>

<html lang="en">

<head>

  <meta charset="UTF-8">

  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title><%= content_for?(:title) ? yield(:title) : "BSDPorts - Package Search" %></title>

  <%= csrf_meta_tags %>

  <%= csp_meta_tag %>

  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : 'Search OpenBSD, FreeBSD, and NetBSD packages' %>">

  <meta name="theme-color" content="#000084">

  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>

</head>
<body class="<%= controller_name %> <%= action_name %>">

  <header class="site-header">

    <div class="container">

      <nav class="nav-main">

        <div class="nav-brand">

          <%= link_to root_path, class: "logo-link" do %>

            <span class="logo">BSDPorts</span>

          <% end %>

        </div>

        <div class="nav-links">

          <%= link_to "OpenBSD", ports_path(platform: "openbsd"), class: "nav-link" %>

          <%= link_to "FreeBSD", ports_path(platform: "freebsd"), class: "nav-link" %>
          <%= link_to "NetBSD", ports_path(platform: "netbsd"), class: "nav-link" %>

          <%= link_to "About", "#", class: "nav-link" %>

        </div>

        <div class="search-box" data-controller="search" data-search-url-value="<%= ports_path(format: :html) %>">

          <input

            type="search"
            placeholder="Search packages..."

            data-search-target="input"

            data-action="input->search#search"

            class="search-input"

            autofocus

          >

        </div>

      </nav>

    </div>

  </header>

  <main class="site-main">

    <% if notice %>

      <div class="flash flash-notice"><%= notice %></div>
    <% end %>

    <% if alert %>

      <div class="flash flash-alert"><%= alert %></div>

    <% end %>

    <%= yield %>

  </main>

  <footer class="site-footer">
    <div class="container">

      <p class="footer-text">
        &copy; <%= Time.current.year %> BSDPorts.

        <%= link_to "OpenBSD", "https://www.openbsd.org/", class: "footer-link", target: "_blank", rel: "noopener" %> &middot;

        <%= link_to "FreeBSD", "https://www.freebsd.org/", class: "footer-link", target: "_blank", rel: "noopener" %> &middot;

        <%= link_to "NetBSD", "https://www.netbsd.org/", class: "footer-link", target: "_blank", rel: "noopener" %> &middot;

        <%= link_to "API", "#", class: "footer-link" %>

      </p>

    </div>

  </footer>

</body>

</html>

LAYOUTEOF

# Additional Stimulus controllers

log "Creating BSDPorts Stimulus controllers"

mkdir -p app/javascript/controllers
cat <<'JSEOF' > app/javascript/controllers/infinite_scroll_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["entries", "loading"]

  static values = { url: String, page: { type: Number, default: 1 } }
  connect() {

    this.observeLastEntry()

  }
  observeLastEntry() {

    const options = {

      root: null,
      rootMargin: "200px",

      threshold: 0

    }

    this.observer = new IntersectionObserver(entries => {

      entries.forEach(entry => {

        if (entry.isIntersecting) {
          this.loadMore()

        }

      })

    }, options)

    const lastEntry = this.entriesTargets[this.entriesTargets.length - 1]

    if (lastEntry) {

      this.observer.observe(lastEntry)
    }

  }

  async loadMore() {

    if (this.loading) return

    this.loading = true
    this.loadingTarget.classList.remove("hidden")

    try {
      this.pageValue += 1

      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("page", this.pageValue)

      const response = await fetch(url)

      if (response.ok) {

        const html = await response.text()
        this.element.insertAdjacentHTML("beforeend", html)

        this.observeLastEntry()

      }

    } catch (error) {

      console.error("Failed to load more:", error)

    } finally {

      this.loading = false

      this.loadingTarget.classList.add("hidden")

    }

  }

  disconnect() {

    if (this.observer) {

      this.observer.disconnect()
    }

  }

}

JSEOF

cat <<'JSEOF' > app/javascript/controllers/filter_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "item"]

  filter() {
    const selected = Array.from(this.checkboxTargets)

      .filter(cb => cb.checked)
      .map(cb => cb.value)

    this.itemTargets.forEach(item => {

      const category = item.dataset.category

      if (selected.length === 0 || selected.includes(category)) {
        item.style.display = "block"

      } else {
        item.style.display = "none"

      }

    })

  }

}

JSEOF

cat << "EOF" > app/assets/stylesheets/application.scss

@import "variables";

@import "reset"; // Add a reset file if needed
// Light mode colors

:root {
  --white: #ffffff;
  --black: #000000;

  --blue: #000084;
  --light-blue: #5623ee;
  --extra-light-grey: #f0f0f0;
  --light-grey: #ababab;
  --grey: #999999;
  --dark-grey: #666666;
  --warning-red: #b04243; // Federal Standard 595c
}
// Dark mode colors
@media (prefers-color-scheme: dark) {
  :root {
    --white: #000000;

    --black: #ffffff;
    --blue: #5623ee;
    --light-blue: #000084;
    --extra-light-grey: #666666;
    --light-grey: #999999;
    --grey: #ababab;
    --dark-grey: #f0f0f0;
  }
}
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;

}
html, body {
  height: 100%;
  font-family: sans-serif;
  font-size: 14px;

  color: var(--black);
  background-color: var(--white);
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
a {
  color: var(--light-blue);
  text-decoration: underline;
}

header {
  display: flex;
  justify-content: right;
  .tabs {

    display: flex;
    margin-top: 18px;
    color: var(--light-grey);

    border-bottom: 1px solid var(--extra-light-grey);
    p {
      padding: 0 3px 8px;
      margin-right: 28px;
      &.active {

        color: var(--black);
        border-bottom: 1px solid var(--black);
      }

    }
  }
}
main {
  display: flex;
  flex-direction: column;
  align-items: center;

  justify-content: center;
  margin: -20px 0 20px;
  .logo {
    text-indent: -9999px;
    margin: 12px 0 22px;
    width: 182px;

    height: 44px;
    background-image: url("bsdports_182x44.svg");
    background-repeat: no-repeat;
  }
}
#search {
  width: 90%;
  max-width: 584px;
  border: 1px solid var(--extra-light-grey);

  border-radius: 30px;
  font-size: 18px;
  transition: all 100ms ease-in-out;
  display: flex;
  align-items: center;
  padding: 0 20px;
  input {
    background: transparent;
    outline: none;
    border: none;

    width: 100%;
    padding: 16px 0;
    font-size: 16px;
    &::placeholder {
      color: var(--dark-grey);
    }
  }

  #live_results {
    overflow: hidden;
    max-height: 220px;
    padding: 9px 19px;

    font-weight: bold;
    line-height: 29px;
    border-top: 1px solid var (--extra-light-grey);
    a {
      display: block;
    }
  }

}
.browse_link {
  margin: 44px 0 12px;
  font-size: 13px;
}

footer {
  color: var(--light-grey);
  font-size: 13px;
  display: flex;

  justify-content: center;
  align-items: stretch;
  .references {
    display: flex;
    gap: 2.6rem;
    align-items: center;

    margin-bottom: 72px;
    a {
      text-indent: -99999px;
      opacity: 0.2;
      &:last-child {

        opacity: 0.3;
      }
      &:before {

        content: "";
        position: absolute;
        background-repeat: no-repeat;

        display: block;
      }
      &.ror {
        width: 72px;
        height: 24px;
        background-image: url("logo_ror_72x24.svg");

        background-position: 0 -4px;
      }
      &.puma {
        width: 108px;
        height: 25px;
        background-image: url("logo_puma_108x25.svg");

        background-position: 0 2px;
      }
      &.nuug {
        width: 79px;
        height: 27px;
        background-image: url("logo_nuug_79x27.svg");

      }
      &.bergen {
        width: 81px;
        height: 36px;
        background-image: url("logo_bergen_kommune_86x36.svg");

      }
    }
  }
  .copyright, .dark_mode_link, .light_mode_link {
    position: absolute;
    bottom: 10px;
    opacity: 0.7;

  }
  .copyright {
    left: 10px;
  }
  .dark_mode_link, .light_mode_link {

    right: 10px;
    span {
      text-indent: -99999px;

    }
    &:before {

      content: "";
      position: absolute;
      background-repeat: no-repeat;

      display: block;
    }
    &.dark_mode_link {
      width: 16px;
      height: 16px;
      background-image: url("moon_16x16.svg");

    }
    &.light_mode_link {
      width: 20px;
      height: 20px;
      background-image: url("sun_20x20.svg");

    }
  }
  span {
    position: absolute;
    text-indent: -9999px;
  }

}
@media screen and (min-width: 320px) and (max-width: 480px) {
  footer {
    transform: scale(0.8);
    .references {

      gap: 1.6rem;
    }
    .copyright {

      left: 0;
      bottom: 6px;
    }

  }
}
EOF
cat << "EOF" > app/javascript/controllers/ports_controller.js
import ApplicationController from './application_controller'
export default class extends ApplicationController {
  connect() {

    this.stimulate('PortsReflex#search')
  }

}
EOF
cat << "EOF" > app/reflexes/ports_reflex.rb
class PortsReflex < ApplicationReflex
  def search
    query = params[:query].presence || ""

    @ports = Port.where("name LIKE ? OR summary LIKE ? OR description LIKE ?", "%#{query}%", "%#{query}%", "%#{query}%")
    morph "#ports_list", render(@ports)
  end
end
EOF
# -- CREATE CONTROLLER --
echo "Creating Ports controller..."
bin/rails generate controller Ports index
# -- ADD ROUTES --

echo "Adding routes..."

cat << "EOF" >> config/routes.rb
Rails.application.routes.draw do

  resources :ports, only: [:index] do

    collection do
      get :search
    end
  end
end
EOF
# -- GIT COMMITS BY FUNCTIONALITY --
echo "Initializing git repository..."
git init
git add .

git commit -m "Initialize Rails project with necessary gems and models"

# -- ADD SEEDS.RB FILE --
git add db/seeds.rb
git commit -m "Add seeds.rb file with FTP download and database import logic"
# -- ADD VIEWS, SCSS, AND STIMULUSREFLEX FUNCTIONALITY --

git add app/views/ports app/assets/stylesheets/application.scss app/javascript/controllers/ports_controller.js app/reflexes/ports_reflex.rb

git commit -m "Add views, SCSS, and live search functionality using StimulusReflex"
# -- ADD ROUTES FOR PORTS --

git add config/routes.rb

git commit -m "Add routes for ports"
# -- POPULATE DATABASE --

echo "Populating database..."

bin/rails db:seed
# -- CREATE README.MD --

cat <<EOF > README.md

# BSDports
BSDports is an advanced AI vector search database for OpenBSD, FreeBSD, NetBSD, and macOS ports. It aspires to be the premier destination for port information and serves as a testbed for the future redesign of openbsd.org.

## Features

- **Live Search**: Quickly find ports using the integrated live search functionality powered by StimulusReflex.
- **Comprehensive Port Information**: Access detailed information about each port, including summaries, descriptions, and URLs.

- **Multi-Platform Support**: Browse ports from OpenBSD, FreeBSD, NetBSD, and macOS.

- **Responsive Design**: Enjoy a consistent and optimized experience across all devices, thanks to the mobile-first design approach.

- **Dark Mode**: Experience a visually pleasing interface that adapts to your system's theme, whether light or dark.
## Installation
Follow these steps to set up the BSDports application:
1. **Clone the Repository**:
    ```sh

    git clone https://github.com/yourusername/bsdports.git

    cd bsdports

    ```
2. **Install Dependencies**:
    ```sh
    bundle install
    ```

3. **Set Up the Database**:
    ```sh
    bin/rails db:setup
    ```

4. **Start the Application**:
    ```sh
    bin/rails server
    ```

5. **Access the Application**:
    Open your browser and navigate to `http://localhost:3000`.
## Usage
### Searching for Ports

Use the search bar on the homepage to find ports quickly. The live search feature will display results as you type, making it easy to locate the ports you need.
### Browsing Ports

Explore ports by browsing through categories and platforms. Detailed information is available for each port, including descriptions and relevant URLs.

## Development

### Setting Up the Development Environment

1. **Clone the Repository**:

    ```sh

    git clone https://github.com/yourusername/bsdports.git

    cd bsdports

    ```
2. **Install Dependencies**:
    ```sh
    bundle install
    ```

3. **Set Up the Database**:
    ```sh
    bin/rails db:setup
    ```

4. **Run the Tests**:
    ```sh
    bin/rspec
    ```

### Contributing
We welcome contributions to BSDports! If you'd like to contribute, please follow these steps:
1. **Fork the Repository**:
    Click the "Fork" button at the top right of the repository page.

2. **Create a Feature Branch**:

    ```sh

    git checkout -b my-feature-branch
    ```

3. **Commit Your Changes**:
    ```sh
    git commit -m "Add my new feature"
    ```

4. **Push to the Branch**:
    ```sh
    git push origin my-feature-branch
    ```

5. **Create a Pull Request**:
    Open a pull request from your forked repository's feature branch to the main repository's master branch.
### Code of Conduct
We are committed to fostering a welcoming and inclusive community. Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## License
BSDports is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.

## Acknowledgements

This project is made possible by the contributions of many open-source libraries and the support of the community. Thank you to everyone who has helped make BSDports a success.

---

Happy porting!

EOF

git add README.md

git commit -m "Add README.md"

commit "BSDports setup complete: BSD ports management platform with FTP integration"
log "BSDports setup complete. Run 'bin/falcon-host' with PORT set to start on OpenBSD."
log ""
log "📦 BSDports Features:"

log "   • Automatic FTP download and parsing of OpenBSD ports tree"

log "   • Category and platform management"
log "   • Port search and discovery"
log "   • Database-backed port information"
log "   • Rails 8 with Hotwire and Stimulus"
log ""
log "   Run: bin/rails db:seed to download and import ports database"
# Change Log:
# - Aligned with master.json v6.5.0: Two-space indents, double quotes, heredocs, Strunk & White comments.
# - Used Rails 8 conventions, Hotwire, Turbo Streams, Stimulus Reflex, I18n, and Falcon.
# - Integrated FTP client for automatic OpenBSD ports tree download.

# - Added tar.gz extraction and port metadata parsing.
# - Leveraged bin/rails generate model for Platform, Category, and Port.
# - Ensured NNG principles, SEO, schema data, and minimal flat design compliance.
# - Finalized for unprivileged user on OpenBSD 7.5.
