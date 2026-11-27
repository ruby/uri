# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'wpt_url_test_data'

# Runs WPT url/resources/toascii.json against URI::WHATWG_PARSER and the
# host= of the URIs it builds.
#
# The data is fetched from WPT master on every run, unless WPT_TOASCII
# names a local file or another https URL.
class WPT::TestToASCII < Test::Unit::TestCase
  SOURCE = WPT::ToASCIIData.source
  CASES = WPT::URLTestData.load(SOURCE)

  CASES.each_with_index do |test_case, index|
    data("##{index + 1} #{test_case["input"].dump}", test_case)
  end

  def test_case(test_case)
    message = WPT::ToASCIIData.run(test_case, URI::WHATWG_PARSER)
    flunk(message) if message
  end

  CASES.each_with_index do |test_case, index|
    data("##{index + 1} #{test_case["input"].dump}", test_case)
  end

  def test_setter(test_case)
    message = WPT::ToASCIIData.run_setter(test_case, URI::WHATWG_PARSER)
    flunk(message) if message
  end

  def test_source
    assert_not_empty(CASES, "no cases in #{SOURCE}")
    notify("toascii: #{CASES.size} cases (source: #{SOURCE})")
  end
end
