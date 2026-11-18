# frozen_string_literal: true
require 'json'
require 'uri'

# Harness for running web-platform-tests' url/resources/urltestdata.json
# (https://github.com/web-platform-tests/wpt) against a URI parser.
module WPT
  module URLTestData
    DEFAULT_SOURCE = "https://raw.githubusercontent.com/web-platform-tests/wpt/master/url/resources/urltestdata.json"

    # URL attributes compared against the expectations. "origin" and
    # "searchParams" are not compared: URI has no equivalent of either.
    COMPARED_KEYS = %w[href protocol username password host hostname port pathname search hash].freeze

    module_function

    # The data source: WPT_URLTESTDATA (a local path or an https URL) if
    # set, otherwise WPT master.
    def source
      ENV["WPT_URLTESTDATA"] || DEFAULT_SOURCE
    end

    # Loads the test cases from +source+, a local path or an https URL,
    # dropping the comment strings interleaved in the data.
    def load(source = DEFAULT_SOURCE)
      json = source.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://}) ? fetch(source) : File.read(source)
      data = JSON.parse(json)
      raise ArgumentError, "urltestdata must be a JSON array: #{source}" unless data.is_a?(Array)
      data.grep(Hash)
    end

    def fetch(url)
      uri = URI::RFC3986_PARSER.parse(url)
      raise ArgumentError, "urltestdata must be fetched over https: #{url}" unless uri.is_a?(URI::HTTPS)

      require 'net/http'
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.get(uri.request_uri)
      end
      raise "failed to fetch #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end

    # A test case is identified by its input and base; the pair is unique
    # in urltestdata.json.
    def key(test_case)
      [test_case["input"], test_case["base"]]
    end

    # The URL attributes (as the WHATWG URL API exposes them) of +uri+.
    #
    # URI::Generic keeps the query of an opaque URI inside opaque, after
    # the first "?" (an opaque path cannot contain "?").
    def components(uri)
      port = uri.port && uri.port != uri.default_port ? uri.port.to_s : ""
      hostname = uri.host.to_s
      if uri.opaque
        pathname, question, query = uri.opaque.partition("?")
        query = nil if question.empty?
      else
        pathname = uri.path.to_s
        # The "/." the URL serializer writes before a hostless path that
        # starts with "//" is not part of pathname.
        pathname = pathname[2..-1] if uri.host.nil? && pathname.start_with?("/.//")
        query = uri.query
      end
      {
        "href" => uri.to_s,
        "protocol" => "#{uri.scheme}:",
        "username" => uri.user.to_s,
        "password" => uri.password.to_s,
        "host" => port.empty? ? hostname : "#{hostname}:#{port}",
        "hostname" => hostname,
        "port" => port,
        "pathname" => pathname,
        "search" => query.to_s.empty? ? "" : "?#{query}",
        "hash" => uri.fragment.to_s.empty? ? "" : "##{uri.fragment}",
      }
    end

    # Runs +test_case+ with +parser+. Returns nil when it passes, or a
    # message describing how it failed. Exceptions are reported in the
    # message rather than raised, so one case cannot abort the others.
    def run(test_case, parser)
      input = test_case["input"]
      base = test_case["base"]
      begin
        uri = base ? parser.join(base, input) : parser.parse(input)
      rescue URI::Error => e
        return nil if test_case["failure"]
        return "unexpected #{e.class}: #{e.message}"
      rescue StandardError => e
        return "#{e.class}: #{e.message}"
      end

      return "expected failure, but parsed as #{uri.to_s.inspect}" if test_case["failure"]

      actual = components(uri)
      diffs = COMPARED_KEYS.select { |k| test_case.key?(k) && test_case[k] != actual[k] }
      return nil if diffs.empty?

      diffs.map { |k| "#{k}: expected #{test_case[k].inspect}, got #{actual[k].inspect}" }.join("\n")
    end
  end

  # Harness for url/resources/toascii.json: each case is a host "input"
  # and its expected ASCII "output", or null when parsing fails. As in
  # WPT's toascii.window.js, the input is parsed as the host of
  # "https://<input>/x". (The host and hostname setter checks of that
  # file are not run: URI's setters do not follow the URL Standard.)
  module ToASCIIData
    DEFAULT_SOURCE = "https://raw.githubusercontent.com/web-platform-tests/wpt/master/url/resources/toascii.json"

    module_function

    # WPT_TOASCII (a local path or an https URL) if set, otherwise WPT
    # master.
    def source
      ENV["WPT_TOASCII"] || DEFAULT_SOURCE
    end

    # Runs +test_case+ with +parser+. Returns nil when it passes, or a
    # message.
    def run(test_case, parser)
      output = test_case["output"]
      url_test_case = { "input" => "https://#{test_case["input"]}/x", "base" => nil }
      if output.nil?
        url_test_case["failure"] = true
      else
        url_test_case.merge!("host" => output, "hostname" => output, "pathname" => "/x", "href" => "https://#{output}/x")
      end
      URLTestData.run(url_test_case, parser)
    end
  end

  # The list of urltestdata cases that are known to fail, each with the
  # reason, stored as a JSON array of {"input", "base", "reason"}.
  module Exclusions
    UNCLASSIFIED = "unclassified"
    PATH = File.expand_path("urltestdata_exclusions.json", __dir__)
    # The fields of an entry that identify a case of urltestdata.json.
    FIELDS = %w[input base].freeze

    module_function

    # Returns a Hash of key => reason, where the key is the values of
    # +fields+ in each entry.
    def load(path, fields: FIELDS)
      JSON.parse(File.read(path)).each_with_object({}) do |entry, result|
        key = entry.values_at(*fields)
        reason = entry["reason"]
        raise ArgumentError, "duplicate exclusion: #{key.inspect}" if result.key?(key)
        raise ArgumentError, "exclusion without reason: #{key.inspect}" if reason.nil? || reason.empty?
        result[key] = reason
      end
    end

    def save(path, exclusions, fields: FIELDS)
      entries = exclusions.map { |key, reason| fields.zip(key).to_h.merge("reason" => reason) }
      File.write(path, JSON.pretty_generate(entries) + "\n")
    end

    # Keys of +exclusions+ that no longer match any case in +cases+, with
    # +key+ giving the key of a case.
    def stale(exclusions, cases, key: URLTestData.method(:key))
      exclusions.keys - cases.map(&key)
    end

    # Rebuilds the exclusions from the keys of the currently +failing+
    # cases, keeping known reasons and marking new ones UNCLASSIFIED.
    # Cases that pass now, or that are gone from +cases+, are dropped.
    # The result follows the order of +cases+.
    def update(exclusions, cases, failing, key: URLTestData.method(:key))
      failing = failing.to_a
      cases.map(&key).select { |k| failing.include?(k) }.each_with_object({}) do |k, result|
        result[k] = exclusions.fetch(k, UNCLASSIFIED)
      end
    end
  end
end
