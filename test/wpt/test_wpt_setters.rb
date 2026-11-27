# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'wpt_setters_test_data'

# Runs WPT url/resources/setters_tests.json against the setters of URIs
# built by URI::WHATWG_PARSER.
#
# The data is fetched from WPT master on every run, unless WPT_SETTERS
# names a local file or another https URL. The cases of setters that URI
# has no counterpart for (WPT::SettersTestData::UNSUPPORTED) are not
# run. Cases listed in setters_tests_exclusions.json are known to fail;
# as for urltestdata.json, the test fails if one of them passes or no
# longer exists. Regenerate the list with
# `rake test:wpt:update_exclusions`.
class WPT::TestSetters < Test::Unit::TestCase
  Setters = WPT::SettersTestData

  SOURCE = Setters.source
  CASES = Setters.load(SOURCE)
  EXCLUSIONS = WPT::Exclusions.load(Setters::EXCLUSIONS_PATH, fields: Setters::EXCLUSION_FIELDS)
  KEY = Setters.method(:key)

  CASES.each_with_index do |test_case, index|
    next unless Setters.supported?(test_case)
    next if EXCLUSIONS.key?(Setters.key(test_case))
    label = "##{index + 1} #{test_case["setter"]} #{test_case["href"].inspect} = #{test_case["new_value"].inspect}"
    data(label, test_case)
  end

  def test_case(test_case)
    message = Setters.run(test_case, URI::WHATWG_PARSER)
    flunk(message) if message
  end

  def test_excluded_cases_still_fail
    passing = CASES.select do |test_case|
      EXCLUSIONS.key?(Setters.key(test_case)) && Setters.run(test_case, URI::WHATWG_PARSER).nil?
    end

    assert_empty(
      passing.map { |c| Setters.key(c) },
      "these excluded cases pass now; remove them from #{Setters::EXCLUSIONS_PATH} " \
      "(rake test:wpt:update_exclusions)"
    )
    unsupported = CASES.count { |c| !Setters.supported?(c) }
    notify("setters_tests: #{CASES.size} cases, #{unsupported} of unsupported setters, " \
           "#{EXCLUSIONS.size} excluded (source: #{SOURCE})")
  end

  def test_no_stale_exclusions
    assert_empty(
      WPT::Exclusions.stale(EXCLUSIONS, CASES, key: KEY),
      "these exclusions match no case in #{SOURCE}; " \
      "remove them from #{Setters::EXCLUSIONS_PATH} (rake test:wpt:update_exclusions)"
    )
  end
end
