# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Security: Gem audit", "bundle exec bundler-audit check"
  step "Security: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Face boot static tests", "node --test test/face_boot.test.mjs"
  step "Web CI probe", "ruby script/ci_web_probe"
  step "Rails tests", "bin/rails test"
end