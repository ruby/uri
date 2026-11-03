# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'wpt_url_test_data'

# Runs WPT url/resources/urltestdata.json against URI::WHATWG_PARSER.
#
# The data is fetched from WPT master on every run, unless
# WPT_URLTESTDATA names a local file or another https URL.
#
# Cases listed in urltestdata_exclusions.json are known to fail. They are
# not run as individual tests; instead test_excluded_cases_still_fail
# fails if any of them passes, so the list never claims more than is
# true. Regenerate the list with `rake test:wpt:update_exclusions`.
class WPT::TestURLTestData < Test::Unit::TestCase
  SOURCE = WPT::URLTestData.source
  EXCLUSIONS_PATH = WPT::Exclusions::PATH
  CASES = WPT::URLTestData.load(SOURCE)
  EXCLUSIONS = WPT::Exclusions.load(EXCLUSIONS_PATH)

  def self.label(index, test_case)
    "##{index + 1} #{test_case["input"].inspect} base=#{test_case["base"].inspect}"
  end

  CASES.each_with_index do |test_case, index|
    next if EXCLUSIONS.key?(WPT::URLTestData.key(test_case))
    data(label(index, test_case), test_case)
  end

  def test_case(test_case)
    message = WPT::URLTestData.run(test_case, URI::WHATWG_PARSER)
    flunk(message) if message
  end

  def test_excluded_cases_still_fail
    passing = CASES.select do |test_case|
      EXCLUSIONS.key?(WPT::URLTestData.key(test_case)) &&
        WPT::URLTestData.run(test_case, URI::WHATWG_PARSER).nil?
    end

    assert_empty(
      passing.map { |c| WPT::URLTestData.key(c) },
      "these excluded cases pass now; remove them from #{EXCLUSIONS_PATH} " \
      "(rake test:wpt:update_exclusions)"
    )
    notify("urltestdata: #{CASES.size} cases, #{EXCLUSIONS.size} excluded (source: #{SOURCE})")
  end

  def test_no_stale_exclusions
    assert_empty(
      WPT::Exclusions.stale(EXCLUSIONS, CASES),
      "these exclusions match no case in #{SOURCE}; " \
      "remove them from #{EXCLUSIONS_PATH} (rake test:wpt:update_exclusions)"
    )
  end
end
