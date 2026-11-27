# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'normalization_test'

# Tests for the harness that runs Unicode's NormalizationTest.txt. These
# never touch the network.
class NormalizationTest::TestHarness < Test::Unit::TestCase
  TEXT = <<~TXT
    # comment
    @Part0 # Specific cases
    1E0A;1E0A;0044 0307;1E0A;0044 0307; # comment
    @Part1 # Character by character test
    00C5;00C5;0041 030A;00C5;0041 030A;
  TXT

  def test_parse
    cases = NormalizationTest.parse(TEXT)
    assert_equal(2, cases.size)
    assert_equal(["\u{1E0A}", "\u{1E0A}", "D\u{307}", "\u{1E0A}", "D\u{307}"], cases[0][:columns])
    assert_equal(3, cases[0][:line])
    assert_equal("Part0", cases[0][:part])
    assert_equal("Part1", cases[1][:part])
  end

  def test_part1_code_points
    cases = NormalizationTest.parse(TEXT)
    assert_equal([0xC5], NormalizationTest.part1_code_points(cases))
  end

  def test_run_passes
    c = NormalizationTest.parse(TEXT)[0]
    nfc = ->(s) { s == "D\u{307}" ? "\u{1E0A}" : s }
    assert_nil(NormalizationTest.run(c, nfc))
  end

  def test_run_reports_c2_mismatch
    c = NormalizationTest.parse(TEXT)[0]
    message = NormalizationTest.run(c, ->(s) { s })
    assert_match(/NFC\(c3\)/, message)
    assert_match(/expected c2/, message)
  end

  def test_run_reports_c4_mismatch
    c = { columns: ["a", "a", "a", "b", "c"], line: 1, part: "Part0" }
    assert_match(/NFC\(c5\).*expected c4/, NormalizationTest.run(c, ->(s) { s }))
  end

  def test_run_checks_nfkc_when_given
    c = { columns: ["\u{FB03}", "\u{FB03}", "\u{FB03}", "ffi", "ffi"], line: 1, part: "Part1" }
    nfc = ->(s) { s }
    assert_nil(NormalizationTest.run(c, nfc))
    assert_match(/NFKC\(c1\) = FB03, expected c4 = 0066 0066 0069/, NormalizationTest.run(c, nfc, nfc))
    assert_nil(NormalizationTest.run(c, nfc, ->(s) { s == "ffi" ? s : "ffi" }))
  end

  def test_run_reports_exceptions
    c = NormalizationTest.parse(TEXT)[0]
    assert_match(/RuntimeError: boom/, NormalizationTest.run(c, ->(s) { raise "boom" }))
  end

  # The tables of NFC are those of the running Ruby.
  def test_source_defaults_to_the_unicode_version_of_ruby
    assert_equal(
      "https://www.unicode.org/Public/#{RbConfig::CONFIG["UNICODE_VERSION"]}/ucd/NormalizationTest.txt",
      NormalizationTest.default_source
    )
  end
end
