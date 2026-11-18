# frozen_string_literal: true
require 'test/unit'
require 'json'
require 'tmpdir'
require 'uri'
require_relative 'wpt_url_test_data'

# Tests for the harness that runs WPT url/resources/urltestdata.json.
# These never touch the network.
class WPT::TestHarness < Test::Unit::TestCase
  # A parser stand-in that records how it was called and returns (or
  # raises) whatever the given block produces.
  class FakeParser
    attr_reader :calls

    def initialize(&block)
      @block = block
      @calls = []
    end

    def parse(input)
      @calls << [:parse, input]
      @block.call(input, nil)
    end

    def join(base, input)
      @calls << [:join, base, input]
      @block.call(input, base)
    end
  end

  def rfc3986(str)
    URI::RFC3986_PARSER.parse(str)
  end

  def passing_case(input, base, uri_str)
    expected = WPT::URLTestData.components(rfc3986(uri_str))
    { "input" => input, "base" => base }.merge(expected)
  end

  # --- components ----------------------------------------------------

  def test_components_of_simple_http_url
    assert_equal(
      {
        "href" => "http://example.com/a",
        "protocol" => "http:",
        "username" => "",
        "password" => "",
        "host" => "example.com",
        "hostname" => "example.com",
        "port" => "",
        "pathname" => "/a",
        "search" => "",
        "hash" => "",
      },
      WPT::URLTestData.components(rfc3986("http://example.com/a"))
    )
  end

  def test_components_with_userinfo
    c = WPT::URLTestData.components(rfc3986("http://user:pass@example.com/"))
    assert_equal("user", c["username"])
    assert_equal("pass", c["password"])
  end

  def test_components_with_user_only
    c = WPT::URLTestData.components(rfc3986("http://user@example.com/"))
    assert_equal("user", c["username"])
    assert_equal("", c["password"])
  end

  def test_components_omit_default_port
    c = WPT::URLTestData.components(rfc3986("http://example.com:80/"))
    assert_equal("", c["port"])
    assert_equal("example.com", c["host"])
  end

  def test_components_keep_non_default_port
    c = WPT::URLTestData.components(rfc3986("http://example.com:8080/"))
    assert_equal("8080", c["port"])
    assert_equal("example.com:8080", c["host"])
  end

  def test_components_keep_port_zero
    c = WPT::URLTestData.components(rfc3986("http://example.com:0/"))
    assert_equal("0", c["port"])
  end

  def test_components_keep_port_for_scheme_without_default_port
    c = WPT::URLTestData.components(rfc3986("foo://example.com:80/"))
    assert_equal("80", c["port"])
  end

  def test_components_keep_ipv6_brackets_in_hostname
    c = WPT::URLTestData.components(rfc3986("http://[::1]:8080/"))
    assert_equal("[::1]", c["hostname"])
    assert_equal("[::1]:8080", c["host"])
  end

  def test_components_without_host
    c = WPT::URLTestData.components(rfc3986("foo:/a"))
    assert_equal("", c["host"])
    assert_equal("", c["hostname"])
  end

  def test_components_query_and_fragment
    c = WPT::URLTestData.components(rfc3986("http://example.com/?q#f"))
    assert_equal("?q", c["search"])
    assert_equal("#f", c["hash"])
  end

  def test_components_empty_query_and_fragment_are_empty_strings
    # WHATWG's search/hash getters return "" for both null and "".
    c = WPT::URLTestData.components(rfc3986("http://example.com/?#"))
    assert_equal("", c["search"])
    assert_equal("", c["hash"])
    assert_equal("http://example.com/?#", c["href"])
  end

  def test_components_opaque_is_pathname
    c = WPT::URLTestData.components(rfc3986("mailto:a@example.com"))
    assert_equal("mailto:", c["protocol"])
    assert_equal("a@example.com", c["pathname"])
  end

  def opaque_uri(opaque, fragment = nil)
    # URI::Generic keeps the query of an opaque URI inside opaque.
    URI::Generic.new("foo", nil, nil, nil, nil, nil, opaque, nil, fragment)
  end

  def test_components_query_inside_opaque_is_search
    c = WPT::URLTestData.components(opaque_uri("bar?q", "f"))
    assert_equal("bar", c["pathname"])
    assert_equal("?q", c["search"])
    assert_equal("#f", c["hash"])
    assert_equal("foo:bar?q#f", c["href"])
  end

  def test_components_empty_query_inside_opaque
    c = WPT::URLTestData.components(opaque_uri("bar?"))
    assert_equal("bar", c["pathname"])
    assert_equal("", c["search"])
  end

  def test_components_opaque_query_containing_question_mark
    c = WPT::URLTestData.components(opaque_uri("bar?a?b"))
    assert_equal("bar", c["pathname"])
    assert_equal("?a?b", c["search"])
  end

  def hostless_uri(path)
    URI::Generic.new("foo", nil, nil, nil, nil, path, nil, nil, nil)
  end

  def test_components_drops_dot_prefix_of_hostless_path
    # The URL serializer writes "/." before a hostless path starting with
    # "//"; pathname does not include it.
    c = WPT::URLTestData.components(hostless_uri("/.//p"))
    assert_equal("//p", c["pathname"])
    assert_equal("foo:/.//p", c["href"])
  end

  def test_components_keeps_other_dot_paths
    assert_equal("/./p", WPT::URLTestData.components(hostless_uri("/./p"))["pathname"])
    assert_equal("/.", WPT::URLTestData.components(hostless_uri("/."))["pathname"])
  end

  def test_components_keeps_dot_prefix_when_host_is_present
    uri = URI::Generic.new("foo", nil, "", nil, nil, "/.//p", nil, nil, nil)
    assert_equal("/.//p", WPT::URLTestData.components(uri)["pathname"])
  end

  def test_components_empty_opaque
    c = WPT::URLTestData.components(opaque_uri(""))
    assert_equal("", c["pathname"])
    assert_equal("", c["search"])
  end

  # --- run -----------------------------------------------------------

  def test_run_without_base_uses_parse
    parser = FakeParser.new { rfc3986("http://example.com/") }
    tc = passing_case("http://example.com/", nil, "http://example.com/")

    assert_nil(WPT::URLTestData.run(tc, parser))
    assert_equal([[:parse, "http://example.com/"]], parser.calls)
  end

  def test_run_with_base_uses_join
    parser = FakeParser.new { rfc3986("http://example.com/b") }
    tc = passing_case("b", "http://example.com/a", "http://example.com/b")

    assert_nil(WPT::URLTestData.run(tc, parser))
    assert_equal([[:join, "http://example.com/a", "b"]], parser.calls)
  end

  def test_run_reports_mismatched_components
    parser = FakeParser.new { rfc3986("http://example.com/x") }
    tc = passing_case("http://example.com/", nil, "http://example.com/")

    message = WPT::URLTestData.run(tc, parser)
    assert_match(/pathname/, message)
    assert_match(/href/, message)
    assert_no_match(/hostname/, message)
  end

  def test_run_ignores_keys_it_does_not_compare
    parser = FakeParser.new { rfc3986("http://example.com/") }
    tc = passing_case("http://example.com/", nil, "http://example.com/")
    tc = tc.merge("origin" => "http://example.com", "searchParams" => "", "comment" => "c")

    assert_nil(WPT::URLTestData.run(tc, parser))
  end

  def test_run_expected_failure_raising_uri_error_passes
    [URI::InvalidURIError, URI::InvalidComponentError].each do |error|
      parser = FakeParser.new { raise error, "bad" }
      tc = { "input" => "http://[/", "base" => nil, "failure" => true }

      assert_nil(WPT::URLTestData.run(tc, parser), error.name)
    end
  end

  def test_run_expected_failure_not_raising_is_reported
    parser = FakeParser.new { rfc3986("http://example.com/") }
    tc = { "input" => "http://[/", "base" => nil, "failure" => true }

    assert_match(/expected failure/, WPT::URLTestData.run(tc, parser))
  end

  def test_run_expected_failure_with_non_uri_error_is_reported
    parser = FakeParser.new { raise NoMethodError, "oops" }
    tc = { "input" => "http://[/", "base" => nil, "failure" => true }

    assert_match(/NoMethodError: oops/, WPT::URLTestData.run(tc, parser))
  end

  def test_run_unexpected_error_is_reported_not_raised
    [URI::InvalidURIError, NoMethodError, ArgumentError].each do |error|
      parser = FakeParser.new { raise error, "boom" }
      tc = passing_case("http://example.com/", nil, "http://example.com/")

      assert_match(/#{error.name}: boom/, WPT::URLTestData.run(tc, parser), error.name)
    end
  end

  # --- load ----------------------------------------------------------

  def with_json_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "urltestdata.json")
      File.write(path, content)
      yield path
    end
  end

  def test_load_from_file_drops_comments
    data = ["comment", { "input" => "a", "base" => nil, "failure" => true }, "another"]
    with_json_file(JSON.generate(data)) do |path|
      assert_equal([data[1]], WPT::URLTestData.load(path))
    end
  end

  def test_load_from_empty_array
    with_json_file("[]") do |path|
      assert_equal([], WPT::URLTestData.load(path))
    end
  end

  def test_load_rejects_non_array
    with_json_file("{}") do |path|
      assert_raise(ArgumentError) { WPT::URLTestData.load(path) }
    end
  end

  def test_load_rejects_invalid_json
    with_json_file("[") do |path|
      assert_raise(JSON::ParserError) { WPT::URLTestData.load(path) }
    end
  end

  def test_load_rejects_non_https_url
    assert_raise(ArgumentError) { WPT::URLTestData.load("http://example.com/urltestdata.json") }
  end

  def test_load_rejects_missing_file
    assert_raise(Errno::ENOENT) { WPT::URLTestData.load("/nonexistent/urltestdata.json") }
  end

  def test_default_source_is_wpt_master
    assert_equal(
      "https://raw.githubusercontent.com/web-platform-tests/wpt/master/url/resources/urltestdata.json",
      WPT::URLTestData::DEFAULT_SOURCE
    )
  end

  def test_source_defaults_to_wpt_master
    env, ENV["WPT_URLTESTDATA"] = ENV["WPT_URLTESTDATA"], nil
    assert_equal(WPT::URLTestData::DEFAULT_SOURCE, WPT::URLTestData.source)
  ensure
    ENV["WPT_URLTESTDATA"] = env
  end

  def test_source_can_be_overridden_by_env
    env, ENV["WPT_URLTESTDATA"] = ENV["WPT_URLTESTDATA"], "/tmp/local.json"
    assert_equal("/tmp/local.json", WPT::URLTestData.source)
  ensure
    ENV["WPT_URLTESTDATA"] = env
  end

  def test_exclusions_path_is_next_to_the_harness
    assert_equal(File.expand_path("urltestdata_exclusions.json", __dir__), WPT::Exclusions::PATH)
  end

  def test_key_identifies_case_by_input_and_base
    assert_equal(["a", nil], WPT::URLTestData.key("input" => "a", "base" => nil, "href" => "x"))
    assert_equal(["a", "b"], WPT::URLTestData.key("input" => "a", "base" => "b"))
  end

  # --- exclusions ----------------------------------------------------

  def test_exclusions_round_trip
    entries = { ["a\t", nil] => "reason 1", ["b", "http://x/"] => "reason 2" }
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exclusions.json")
      WPT::Exclusions.save(path, entries)
      assert_equal(entries, WPT::Exclusions.load(path))
    end
  end

  def test_exclusions_save_writes_reviewable_json
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exclusions.json")
      WPT::Exclusions.save(path, { ["a", nil] => "r" })
      assert_equal(
        [{ "input" => "a", "base" => nil, "reason" => "r" }],
        JSON.parse(File.read(path))
      )
      assert_operator(File.read(path).lines.size, :>, 1, "pretty-printed")
      assert(File.read(path).end_with?("\n"))
    end
  end

  def test_exclusions_load_empty_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exclusions.json")
      File.write(path, "[]")
      assert_equal({}, WPT::Exclusions.load(path))
    end
  end

  def test_exclusions_load_rejects_duplicates
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exclusions.json")
      entry = { "input" => "a", "base" => nil, "reason" => "r" }
      File.write(path, JSON.generate([entry, entry]))
      assert_raise(ArgumentError) { WPT::Exclusions.load(path) }
    end
  end

  def test_exclusions_load_rejects_missing_reason
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exclusions.json")
      [nil, ""].each do |reason|
        File.write(path, JSON.generate([{ "input" => "a", "base" => nil, "reason" => reason }]))
        assert_raise(ArgumentError, reason.inspect) { WPT::Exclusions.load(path) }
      end
    end
  end

  def test_exclusions_stale_lists_entries_not_in_data
    cases = [{ "input" => "a", "base" => nil }]
    exclusions = { ["a", nil] => "r", ["a", "http://x/"] => "r", ["gone", nil] => "r" }

    assert_equal([["a", "http://x/"], ["gone", nil]], WPT::Exclusions.stale(exclusions, cases))
  end

  def test_exclusions_stale_is_empty_when_all_present
    cases = [{ "input" => "a", "base" => nil }]
    assert_equal([], WPT::Exclusions.stale({ ["a", nil] => "r" }, cases))
    assert_equal([], WPT::Exclusions.stale({}, cases))
  end

  def test_exclusions_update
    cases = %w[pass keep new gone_from_list].map { |i| { "input" => i, "base" => nil } }
    failing = [["keep", nil], ["new", nil]]
    current = { ["keep", nil] => "known reason", ["pass", nil] => "fixed now", ["stale", nil] => "old" }

    updated = WPT::Exclusions.update(current, cases, failing)

    assert_equal(
      { ["keep", nil] => "known reason", ["new", nil] => WPT::Exclusions::UNCLASSIFIED },
      updated
    )
  end

  def test_exclusions_update_follows_data_order
    cases = %w[c a b].map { |i| { "input" => i, "base" => nil } }
    failing = [["a", nil], ["b", nil], ["c", nil]]

    assert_equal(
      [["c", nil], ["a", nil], ["b", nil]],
      WPT::Exclusions.update({}, cases, failing).keys
    )
  end

  def test_exclusions_with_other_fields
    fields = %w[setter href new_value]
    entries = { ["port", "http://x/", "1"] => "r" }
    Dir.mktmpdir do |dir|
      path = File.join(dir, "exclusions.json")
      WPT::Exclusions.save(path, entries, fields: fields)
      assert_equal([{ "setter" => "port", "href" => "http://x/", "new_value" => "1", "reason" => "r" }],
                   JSON.parse(File.read(path)))
      assert_equal(entries, WPT::Exclusions.load(path, fields: fields))
    end
  end

  def test_exclusions_stale_and_update_with_another_key
    key = ->(c) { [c["setter"], c["href"]] }
    cases = [{ "setter" => "port", "href" => "a" }, { "setter" => "hash", "href" => "b" }]
    assert_equal([["port", "gone"]], WPT::Exclusions.stale({ ["port", "gone"] => "r", ["port", "a"] => "r" }, cases, key: key))
    assert_equal({ ["hash", "b"] => WPT::Exclusions::UNCLASSIFIED },
                 WPT::Exclusions.update({}, cases, [["hash", "b"]], key: key))
  end
end
