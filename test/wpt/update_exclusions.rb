# frozen_string_literal: true
# Regenerates urltestdata_exclusions.json from the cases that currently
# fail with URI::WHATWG_PARSER. Known reasons are kept, new failures are
# marked "unclassified", and cases that pass now or no longer exist in
# the data are dropped.
#
# Usage: ruby -Ilib test/wpt/update_exclusions.rb
#        (or rake test:wpt:update_exclusions)
require 'uri'
require_relative 'wpt_url_test_data'

source = WPT::URLTestData.source
path = WPT::Exclusions::PATH

cases = WPT::URLTestData.load(source)
current = File.exist?(path) ? WPT::Exclusions.load(path) : {}
failing = cases.reject { |c| WPT::URLTestData.run(c, URI::WHATWG_PARSER).nil? }.map { |c| WPT::URLTestData.key(c) }
updated = WPT::Exclusions.update(current, cases, failing)
WPT::Exclusions.save(path, updated)

added = (updated.keys - current.keys).size
removed = (current.keys - updated.keys).size
puts "#{source}: #{cases.size} cases, #{cases.size - updated.size} passing, #{updated.size} excluded (+#{added}, -#{removed})"
