cd "$BASE_DIR"

gem install bundler --user-install
gem install rails --user-install

bundle config set --local path "$HOME/.local"

rails33 new $APP --database=postgresql --javascript=esbuild --css=sass --assets=propshaft

cd $APP

git init
bundle install
yarn install

commit_to_git "Initial commit: Generate Rails app with PostgreSQL, Esbuild, SASS, and Propshaft."

