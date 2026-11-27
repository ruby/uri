# frozen_string_literal: true
# Regenerates urltestdata_exclusions.json and setters_tests_exclusions.json
# from the cases that currently fail with URI::WHATWG_PARSER. Known
# reasons are kept, new failures are marked "unclassified", and cases
# that pass now or no longer exist in the data are dropped.
#
# Usage: ruby -Ilib test/wpt/update_exclusions.rb
#        (or rake test:wpt:update_exclusions)
require 'uri'
require_relative 'wpt_url_test_data'
require_relative 'wpt_setters_test_data'

def update_exclusions(source:, path:, cases:, key:, fields:)
  current = File.exist?(path) ? WPT::Exclusions.load(path, fields: fields) : {}
  failing = cases.reject { |c| yield(c).nil? }.map(&key)
  updated = WPT::Exclusions.update(current, cases, failing, key: key)
  WPT::Exclusions.save(path, updated, fields: fields)

  added = (updated.keys - current.keys).size
  removed = (current.keys - updated.keys).size
  puts "#{source}: #{cases.size} cases, #{cases.size - updated.size} passing, #{updated.size} excluded (+#{added}, -#{removed})"
end

source = WPT::URLTestData.source
update_exclusions(
  source: source, path: WPT::Exclusions::PATH, cases: WPT::URLTestData.load(source),
  key: WPT::URLTestData.method(:key), fields: WPT::Exclusions::FIELDS
) { |c| WPT::URLTestData.run(c, URI::WHATWG_PARSER) }

setters = WPT::SettersTestData
source = setters.source
update_exclusions(
  source: source, path: setters::EXCLUSIONS_PATH, cases: setters.load(source).select { |c| setters.supported?(c) },
  key: setters.method(:key), fields: setters::EXCLUSION_FIELDS
) { |c| setters.run(c, URI::WHATWG_PARSER) }
