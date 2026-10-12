# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# The Norwegian copy says what an action does. Three questions locale_contract_test
# does not ask, each answered from key naming so the check never guesses at meaning:
#
#   Generic verbs. A button or submit key whose value is "Send", "OK" or "Utfør"
#   names no object. Say the verb and the thing: "Send melding".
#   One action, one name. The label of `publish` and the flash of `published`
#   share a verb stem; "Publiser" then "Lagret" teaches the reader two names for one act.
#   Errors that apologise. "Noe gikk galt" says neither what failed nor what to do.
#
# Counts at the time of writing are held as ceilings that only fall, and each hit
# is listed with file:key so a /fix pass can rewrite the copy (nb is the default
# locale; locale files are operator copy, so this test reports and does not edit).
class LocaleCopyContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CEILING = { generic_verb: 1, verb_stem: 0, apology: 2 }.freeze

  GENERIC = ["ok", "okay", "send", "send inn", "utfør", "klikk her", "trykk her", "submit", "klikk", "gjør det", "gå videre"].freeze
  BUTTON_KEY = /(?:\A|\.)(?:submit|button|btn|cta|action|send|save|confirm)(?:_label|_text|_button)?\z|\.(?:buttons|cta|actions)\./
  APOLOGY = /beklager|unnskyld|\bups\b|oops|noe gikk galt|noe gikk feil|uventet feil/i
  FIX = /prøv|sjekk|kontroller|fordi|\bmå\b|velg|fyll|logg inn|på nytt|forsøk|ta kontakt|kontakt/i
  PAIRS = { "publish" => "published", "create" => "created", "delete" => "deleted", "save" => "saved", "send" => "sent",
            "update" => "updated", "add" => "added", "remove" => "removed", "post" => "posted", "submit" => "submitted" }.freeze

  def self.leaves(hash, path = [], out = {})
    hash.each do |key, value|
      if value.is_a?(Hash) then leaves(value, path + [key.to_s], out)
      elsif value.is_a?(String) then out[(path + [key.to_s]).join(".")] = value
      end
    end
    out
  end

  def self.generic_verb(flat)
    flat.select { |key, value| key.match?(BUTTON_KEY) && GENERIC.include?(value.downcase.gsub(/[[:punct:]]/, "").strip) }.keys
  end

  def self.stem_mismatch(flat)
    flat.filter_map do |key, value|
      parent, _, leaf = key.rpartition(".")
      past = PAIRS[leaf] or next
      done = flat[[parent, past].reject(&:empty?).join(".")] or next
      key unless same_stem?(value, done)
    end
  end

  def self.same_stem?(one, other)
    a = one.downcase.scan(/\p{L}+/).first.to_s
    b = other.downcase.scan(/\p{L}+/).first.to_s
    n = [a.size, b.size].min
    n >= 3 && a[0, n - 2] == b[0, n - 2]
  end

  def self.apology(flat)
    flat.select { |key, value| key.match?(/error|fail|problem|wrong|unavailable/) && value.match?(APOLOGY) && !value.match?(FIX) }.keys
  end

  def nb_files
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,__shared,brgen_*,brgen/engines/*}/**/config/locales/**/*nb*.yml"))
       .reject { |file| file.include?("/vendor/") }.sort.uniq
  end

  def hits
    @hits ||= nb_files.each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, found|
      data = YAML.safe_load_file(file, aliases: true) rescue next # scan: intentional — an unreadable file is locale_contract_test's finding
      next unless data.is_a?(Hash) && data["nb"].is_a?(Hash)

      flat = self.class.leaves(data["nb"])
      rel = file.delete_prefix("#{ROOT}/")
      found[:generic_verb] += self.class.generic_verb(flat).map { |key| "#{rel}:#{key}" }
      found[:verb_stem] += self.class.stem_mismatch(flat).map { |key| "#{rel}:#{key}" }
      found[:apology] += self.class.apology(flat).map { |key| "#{rel}:#{key}" }
    end
  end

  def test_detectors_flag_the_bad_and_spare_the_good
    assert_equal ["actions.send"], self.class.generic_verb("actions.send" => "Send")
    assert_empty self.class.generic_verb("actions.send" => "Send melding")
    assert_equal ["x.publish"], self.class.stem_mismatch("x.publish" => "Publiser", "x.published" => "Lagret")
    assert_empty self.class.stem_mismatch("x.publish" => "Publiser", "x.published" => "Publisert")
    assert_empty self.class.stem_mismatch("x.delete" => "Slett", "x.deleted" => "Slettet")
    assert_equal ["errors.server_title"], self.class.apology("errors.server_title" => "Noe gikk galt")
    assert_empty self.class.apology("errors.server_title" => "Noe gikk galt. Prøv igjen om litt.")
  end

  def test_the_glob_finds_the_nb_files
    assert_operator nb_files.size, :>=, 10
  end

  CEILING.each do |name, ceiling|
    define_method("test_#{name}_hits_do_not_grow") do
      found = hits[name]

      assert_operator found.size, :<=, ceiling, "#{name} grew past #{ceiling}:\n#{found.join("\n")}"
    end
  end
end
