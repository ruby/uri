# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'normalization_test'

# Runs Unicode's NormalizationTest.txt against
# URI::WHATWG_Parser::NFC.normalize and normalize_kc.
#
# The data is fetched for the Unicode version of the running Ruby, whose
# tables NFC uses, unless NORMALIZATION_TEST names a local file or
# another https URL.
class NormalizationTest::TestConformance < Test::Unit::TestCase
  SOURCE = NormalizationTest.source
  CASES = NormalizationTest.load(SOURCE)
  NFC = URI::WHATWG_Parser::NFC.method(:normalize)
  NFKC = URI::WHATWG_Parser::NFC.method(:normalize_kc)

  # One test per part: a test per line would make test-unit spend most
  # of the time on its own bookkeeping.
  CASES.group_by { |c| c[:part] }.each do |part, cases|
    data(part, cases)
  end

  def test_part(cases)
    # Array#filter_map needs Ruby 2.7.
    failures = cases.map do |test_case|
      message = NormalizationTest.run(test_case, NFC, NFKC)
      "line #{test_case[:line]}: #{message}" if message
    end.compact
    assert_empty(failures, "#{failures.size} of #{cases.size} cases failed")
  end

  def test_code_points_outside_part1_are_unchanged
    listed = NormalizationTest.part1_code_points(CASES).each_with_object({}) { |c, h| h[c] = true }
    changed = (0..0x10FFFF).reject do |c|
      (0xD800..0xDFFF).cover?(c) || listed[c] || (NFC.call(s = [c].pack("U")) == s && NFKC.call(s) == s)
    end
    assert_empty(changed.map { |c| format("U+%04X", c) })
  end

  def test_source
    assert_not_empty(CASES, "no cases in #{SOURCE}")
    notify("NormalizationTest: #{CASES.size} cases (source: #{SOURCE})")
  end
end
