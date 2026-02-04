# MASTER v50.0 Makefile
# OpenBSD-style, no rake needed

.PHONY: all install test lint clean help

all: help

install:
	bundle install --path vendor/bundle

run:
	./bin/cli

test:
	bundle exec ruby -Ilib -Itest -e 'Dir["test/**/*_test.rb"].each { |f| require "./#{f}" }'

lint:
	bundle exec rubocop lib/ bin/

lint-fix:
	bundle exec rubocop lib/ bin/ --auto-correct

clean:
	rm -rf vendor/bundle .bundle Gemfile.lock

help:
	@echo "MASTER v50.0"
	@echo ""
	@echo "Usage:"
	@echo "  make install   Install dependencies"
	@echo "  make run       Start CLI"
	@echo "  make test      Run tests"
	@echo "  make lint      Check style"
	@echo "  make lint-fix  Auto-fix style"
	@echo "  make clean     Remove deps"
