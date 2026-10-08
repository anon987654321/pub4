# frozen_string_literal: true

require "test_helper"

class Marketplace::CategoryTest < ActiveSupport::TestCase
  test "a category without a slug takes one from its name" do
    category = Marketplace::Category.create!(name: "Sykler og deler #{SecureRandom.hex(3)}")

    assert_equal category.name.parameterize, category.slug
    assert_equal category.slug, category.to_param
  end

  test "a given slug is kept rather than rederived" do
    slug = "egen-#{SecureRandom.hex(3)}"

    assert_equal slug, Marketplace::Category.create!(name: "Møbler", slug: slug).slug
  end

  test "two categories cannot share a slug" do
    slug = "delt-#{SecureRandom.hex(3)}"
    Marketplace::Category.create!(name: "Første", slug: slug)
    second = Marketplace::Category.new(name: "Andre", slug: slug)

    assert_not second.valid?
    assert second.errors.added?(:slug, :taken, value: slug)
  end

  test "a category needs a name" do
    category = Marketplace::Category.new(name: "")

    assert_not category.valid?
    assert category.errors.added?(:name, :blank)
    assert category.errors.added?(:slug, :blank)
  end

  test "roots holds only categories with no parent" do
    root = Marketplace::Category.create!(name: "Rot #{SecureRandom.hex(3)}")
    child = Marketplace::Category.create!(name: "Gren #{SecureRandom.hex(3)}", parent: root)

    assert_includes Marketplace::Category.roots, root
    assert_not_includes Marketplace::Category.roots, child
  end

  test "deleting a parent keeps its children as roots" do
    root = Marketplace::Category.create!(name: "Forelder #{SecureRandom.hex(3)}")
    child = Marketplace::Category.create!(name: "Barn #{SecureRandom.hex(3)}", parent: root)

    Marketplace::Category.find(root.id).destroy!

    assert_nil child.reload.parent_id
  end
end
