cd "$BASE_DIR"

doas pkg_add llvm

bundle add langchainrb
bundle add langchainrb_rails
bundle add weaviate-ruby
bundle add replicate-ruby
bundle add replicate-rails

bundle install

