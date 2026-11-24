# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'idna_test_v2'

# Runs Unicode's IdnaTestV2.txt against URI::WHATWG_Parser::IDNA.to_ascii.
#
# The data is fetched for the Unicode version of the generated data
# (lib/uri/whatwg_parser/idna_data.rb), unless IDNA_TEST_V2 names a
# local file or another https URL. The cases that succeed with a code
# point that the running Ruby does not know are not run.
class IDNATestV2::TestConformance < Test::Unit::TestCase
  SOURCE = IDNATestV2.source
  CASES = IDNATestV2.load(SOURCE)

  CASES.each do |test_case|
    next unless IDNATestV2.expectation(test_case)
    data("line #{test_case[:line]} #{test_case[:source].dump}", test_case)
  end

  def test_case(test_case)
    message = IDNATestV2.run(test_case, URI::WHATWG_Parser::IDNA.method(:to_ascii))
    flunk(message) if message
  end

  def test_source
    assert_not_empty(CASES, "no cases in #{SOURCE}")
    unknown = CASES.count { |c| IDNATestV2.unknown_to_ruby?(c) && IDNATestV2.expectation(c).nil? }
    notify("IdnaTestV2: #{CASES.size} cases, #{unknown} not run for code points unknown to " \
           "Ruby #{RUBY_VERSION} (Unicode #{RbConfig::CONFIG["UNICODE_VERSION"]}) (source: #{SOURCE})")
  end

  # Fails when Unicode has released a newer version than the generated
  # data, so that the scheduled run reports it.
  def test_idna_data_is_the_latest_unicode_version
    current = IDNATestV2.unicode_version
    latest = IDNATestV2.latest_unicode_version(WPT::URLTestData.fetch(IDNATestV2::LATEST_README))
    assert(
      !IDNATestV2.newer?(latest, current),
      "Unicode #{latest} is out; the IDNA data is #{current}. " \
      "Regenerate it with `UNICODE_VERSION=#{latest} rake idna:generate`."
    )
  end
end
