# frozen_string_literal: true
require 'json'
require 'uri'
require_relative 'wpt_url_test_data'

module WPT
  # Harness for url/resources/setters_tests.json, which sets one
  # attribute of the URL API on a parsed URL and lists the attributes
  # expected afterwards.
  #
  # The setters map to those of URI: protocol to scheme=, username to
  # user=, password to password=, hostname to host=, port to port=,
  # pathname to path=, search to query= and hash to fragment=. query= and
  # fragment= take the value without the leading "?" or "#" that search
  # and hash strip, and nil for the empty string that removes the
  # component. A value that URI rejects with InvalidComponentError is
  # one that the URL Standard ignores, so the attributes are compared
  # as they are after it.
  module SettersTestData
    DEFAULT_SOURCE = "https://raw.githubusercontent.com/web-platform-tests/wpt/master/url/resources/setters_tests.json"
    EXCLUSIONS_PATH = File.expand_path("setters_tests_exclusions.json", __dir__)
    EXCLUSION_FIELDS = %w[setter href new_value].freeze

    # Setters of the URL API that URI has no counterpart for.
    UNSUPPORTED = {
      "host" => "URI has no setter for a host and a port together",
      "href" => "URI has no setter for the whole URL",
    }.freeze

    module_function

    # WPT_SETTERS (a local path or an https URL) if set, otherwise WPT
    # master.
    def source
      ENV["WPT_SETTERS"] || DEFAULT_SOURCE
    end

    def load(source)
      json = source.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://}) ? URLTestData.fetch(source) : File.read(source)
      flatten(JSON.parse(json))
    end

    # The cases of every setter, each with its "setter".
    def flatten(data)
      data.flat_map do |setter, cases|
        next [] if setter == "comment"
        cases.map { |c| c.merge("setter" => setter) }
      end
    end

    def key(test_case)
      test_case.values_at(*EXCLUSION_FIELDS)
    end

    def supported?(test_case)
      !UNSUPPORTED.key?(test_case["setter"])
    end

    def apply(uri, setter, value)
      case setter
      when "protocol" then uri.scheme = value
      when "username" then uri.user = value
      when "password" then uri.password = value
      when "hostname" then uri.host = value
      when "port" then uri.port = value
      when "pathname" then uri.path = value
      when "search" then uri.query = value.empty? ? nil : value.sub(/\A\?/, "")
      when "hash" then uri.fragment = value.empty? ? nil : value.sub(/\A#/, "")
      else raise ArgumentError, "unsupported setter: #{setter}"
      end
    end

    # Runs +test_case+ with +parser+. Returns nil when it passes, or a
    # message.
    def run(test_case, parser)
      uri = parser.parse(test_case["href"])
      begin
        apply(uri, test_case["setter"], test_case["new_value"])
      rescue URI::InvalidComponentError
        # The URL Standard leaves the URL unchanged.
      end

      actual = URLTestData.components(uri)
      expected = test_case["expected"]
      diffs = expected.keys.select { |k| actual.key?(k) && expected[k] != actual[k] }
      return nil if diffs.empty?
      diffs.map { |k| "#{k}: expected #{expected[k].inspect}, got #{actual[k].inspect}" }.join("\n")
    rescue StandardError => e
      "#{e.class}: #{e.message}"
    end
  end
end
