.PHONY: bplan validate build test build_plans build_legats pdfs mail-list

RUBY ?= ruby

bplan: build_plans build_legats test

validate:
	$(RUBY) -Ilib -e 'require "bplan/validate"; Bplan::Validate.validate_all!(Dir.pwd)'

build: build_plans build_legats

build_plans:
	$(RUBY) build_plans.rb

build_legats:
	$(RUBY) build_legats.rb

pdfs:
	$(RUBY) scripts/build_pdfs.rb --all

mail-list:
	$(RUBY) grok_send_legats.rb --list-sendable

test:
	$(RUBY) -Ilib test/validate_test.rb
	$(RUBY) -Ilib test/build_plans_test.rb
	cd rails && bundle exec rails test