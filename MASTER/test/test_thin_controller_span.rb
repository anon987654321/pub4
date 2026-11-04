# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"

# THIN_CONTROLLER measured an action by counting keywords, so every modifier
# `if`/`unless` and endless `def x = ...` opened a block no `end` closed: a
# 17-line CommentsController#create read as ~100 lines and ran to the file's end.
class TestThinControllerSpan < Minitest::Test
  SOURCE = <<~RUBY
    class CommentsController < ApplicationController
      def create
        return head :forbidden unless allowed?
        @comment = Comment.new(comment_params)
        redirect_to root_path if @comment.save
      end

      def allowed? = Current.user.present?

      def destroy
        head :ok
      end
    end
  RUBY

  def laws = Master::Review::Scan::Laws

  def test_a_method_ends_at_its_own_end
    lines = SOURCE.lines
    assert_equal 6, laws.method_body_end_line(lines, 1), "create spans lines 2..6"
    assert_equal 8, laws.method_body_end_line(lines, 7), "an endless def is one line"
    assert_equal 12, laws.method_body_end_line(lines, 9)
  end

  def test_a_short_action_with_guard_clauses_is_not_fat
    padded = SOURCE.sub("  def destroy\n", "  def destroy\n#{"    x = 1 if y\n" * 45}")
    law = ::Law.definitions.fetch(:THIN_CONTROLLER)
    findings = law.scan(padded, file: "/repo/app/controllers/comments_controller.rb")
    lines = findings.map(&:line)
    refute_includes lines, 2, "create was measured past its end"
    assert_includes lines, 10, "the padded destroy is still fat"
  end
end
