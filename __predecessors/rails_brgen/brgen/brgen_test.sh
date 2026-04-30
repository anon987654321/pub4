
# -- TEST SETUP --

echo "Creating RSpec test suite..."

bundle add rspec-rails
bin/rails generate rspec:install

cat <<EOF > spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  it "is valid with valid attributes" do
    user = User.new(username: "TestUser", email: "test@example.com", password: "password")
    expect(user).to be_valid
  end

  it "is not valid without a username" do
    user = User.new(email: "test@example.com", password: "password")
    expect(user).to_not be_valid
  end
end
EOF

cat <<EOF > spec/models/post_spec.rb
require 'rails_helper'

RSpec.describe Post, type: :model do
  it "is valid with valid attributes" do
    user = User.create(username: "TestUser", email: "test@example.com", password: "password")
    community = Main::Community.create(name: "Test Community", description: "A test community")
    post = Main::Post.new(title: "Test Post", content: "This is a test post", user: user, community: community)
    expect(post).to be_valid
  end

  it "is not valid without a title" do
    post = Main::Post.new(content: "This is a test post")
    expect(post).to_not be_valid
  end
end
EOF

cat <<EOF > spec/models/comment_spec.rb
require 'rails_helper'

RSpec.describe Comment, type: :model do
  it "is valid with valid attributes" do
    user = User.create(username: "TestUser", email: "test@example.com", password: "password")
    community = Main::Community.create(name: "Test Community", description: "A test community")
    post = Main::Post.create(title: "Test Post", content: "This is a test post", user: user, community: community)
    comment = Main::Comment.new(content: "This is a test comment", user: user, post: post)
    expect(comment).to be_valid
  end

  it "is not valid without content" do
    comment = Main::Comment.new
    expect(comment).to_not be_valid
  end
end
EOF

cat <<EOF > spec/rails_helper.rb
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  config.fixture_path = "\#{::Rails.root}/spec/fixtures"
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
EOF

cat <<EOF > spec/spec_helper.rb
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.profile_examples = 10
  config.order = :random

  Kernel.srand config.seed
end
EOF

echo "RSpec tests have been set up. Run 'bundle exec rspec' to execute tests."

commit_to_git "Set up RSpec and initial test cases for User, Post, and Comment models."
