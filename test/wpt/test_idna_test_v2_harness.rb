# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'idna_test_v2'

# Tests for the harness that runs Unicode's IdnaTestV2.txt. These never
# touch the network.
class IDNATestV2::TestHarness < Test::Unit::TestCase
  def parse(text)
    IDNATestV2.parse(text)
  end

  def test_parse_skips_comments_and_blank_lines
    cases = parse(<<~'TXT')
      # comment

      fass.de; ; ; ; ; ;  # fass.de
    TXT
    assert_equal(1, cases.size)
    assert_equal("fass.de", cases[0][:source])
    assert_equal(3, cases[0][:line])
  end

  def test_parse_blank_columns_inherit
    c = parse("Fa\\u00DF.de; fa\\u00DF.de; ; ; ; ;  # x\n")[0]
    # toAsciiN is the toUnicode value; its status is the toUnicode status.
    assert_equal("fa\u00DF.de", c[:to_ascii])
    assert_equal([], c[:status])
  end

  def test_parse_blank_to_unicode_is_the_source
    c = parse("fass.de; ; ; ; ; ;\n")[0]
    assert_equal("fass.de", c[:to_ascii])
  end

  def test_parse_explicit_values
    c = parse("fa\\u00DF.de; ; ; xn--fa-hia.de; ; fass.de;  # x\n")[0]
    assert_equal("xn--fa-hia.de", c[:to_ascii])
    assert_equal([], c[:status])
  end

  def test_parse_status_inherits_from_to_unicode
    c = parse("a.-b.; ; [V3]; ; ; ;\n")[0]
    assert_equal(%w[V3], c[:status])
  end

  def test_parse_status_of_to_ascii
    c = parse("a.-b.; ; [V3]; ; [V3, A4_2]; ;\n")[0]
    assert_equal(%w[V3 A4_2], c[:status])
  end

  def test_parse_explicit_empty_status
    c = parse("a; ; [X4_2]; ; []; ;\n")[0]
    assert_equal([], c[:status])
  end

  def test_parse_empty_string
    c = parse("\"\"; ; [X4_2]; ; [A4_1, A4_2]; ;  #\n")[0]
    assert_equal("", c[:source])
    assert_equal("", c[:to_ascii])
  end

  def test_unescape
    assert_equal("a\u0308b", IDNATestV2.unescape("a\\u0308b"))
    assert_equal("\u{1F600}", IDNATestV2.unescape("\\x{1F600}"))
    assert_equal("\u00E4", IDNATestV2.unescape("\u00E4"))
  end

  def test_unescape_surrogate_is_nil
    assert_nil(IDNATestV2.unescape("a\\uD800b"))
  end

  def test_expectation_success
    c = { source: "fa\u00DF.de", to_ascii: "xn--fa-hia.de", status: [] }
    assert_equal({ value: "xn--fa-hia.de" }, IDNATestV2.expectation(c))
  end

  def test_expectation_failure
    c = { source: "a\u05D0", to_ascii: "xn--a-0hc", status: %w[B5 B6] }
    assert_equal({ failure: true }, IDNATestV2.expectation(c))
  end

  def test_expectation_ignores_statuses_of_disabled_checks
    c = { source: "a.-b.", to_ascii: "a.-b.", status: %w[V2 V3 U1 A4_1 A4_2 X4_2] }
    assert_equal({ value: "a.-b." }, IDNATestV2.expectation(c))
  end

  def test_expectation_is_nil_for_a_surrogate
    assert_nil(IDNATestV2.expectation({ source: nil, to_ascii: nil, status: %w[A3] }))
  end

  def test_expectation_is_nil_without_an_ascii_result
    # Only ignored errors, but the file has no ToASCII value to compare.
    c = { source: "\u00E4-.de", to_ascii: "\u00E4-.de", status: %w[V3] }
    assert_nil(IDNATestV2.expectation(c))
  end

  def test_run_passes
    c = { source: "fa\u00DF.de", to_ascii: "xn--fa-hia.de", status: [] }
    assert_nil(IDNATestV2.run(c, ->(d) { "xn--fa-hia.de" }))
  end

  def test_run_reports_a_wrong_value
    c = { source: "fa\u00DF.de", to_ascii: "xn--fa-hia.de", status: [] }
    assert_match(/expected "xn--fa-hia.de", got "fass.de"/, IDNATestV2.run(c, ->(d) { "fass.de" }))
  end

  def test_run_reports_an_unexpected_failure
    c = { source: "fa\u00DF.de", to_ascii: "xn--fa-hia.de", status: [] }
    assert_match(/unexpected failure/, IDNATestV2.run(c, ->(d) { nil }))
  end

  def test_run_reports_an_unexpected_success
    c = { source: "a\u05D0", to_ascii: "xn--a-0hc", status: %w[B5] }
    assert_match(/expected failure/, IDNATestV2.run(c, ->(d) { "xn--a-0hc" }))
  end

  def test_run_reports_exceptions
    c = { source: "a", to_ascii: "a", status: [] }
    assert_match(/RuntimeError: boom/, IDNATestV2.run(c, ->(d) { raise "boom" }))
  end

  def test_latest_unicode_version_from_readme
    readme = <<~TXT
      # Unicode Standard Data Files & Charts

      This directory contains final data files and charts for version 18.0.0 of the
      Unicode Character Database and for the synchronized Unicode Technical Standards.
    TXT
    assert_equal("18.0.0", IDNATestV2.latest_unicode_version(readme))
  end

  def test_latest_unicode_version_without_a_version
    assert_raise(RuntimeError) { IDNATestV2.latest_unicode_version("no version here") }
  end

  def test_newer_unicode_version
    assert_equal(true, IDNATestV2.newer?("18.1.0", "18.0.0"))
    assert_equal(true, IDNATestV2.newer?("19.0.0", "18.0.0"))
    assert_equal(true, IDNATestV2.newer?("18.0.10", "18.0.9"))
    assert_equal(false, IDNATestV2.newer?("18.0.0", "18.0.0"))
    assert_equal(false, IDNATestV2.newer?("17.0.0", "18.0.0"))
  end

  def test_source_defaults_to_the_version_of_the_data
    assert_equal(
      "https://www.unicode.org/Public/#{IDNATestV2.unicode_version}/idna/IdnaTestV2.txt",
      IDNATestV2.default_source
    )
  end
end
