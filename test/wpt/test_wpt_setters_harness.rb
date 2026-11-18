# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'wpt_setters_test_data'

# Tests for the harness that runs WPT url/resources/setters_tests.json.
# These never touch the network.
class WPT::TestSettersHarness < Test::Unit::TestCase
  Setters = WPT::SettersTestData

  def setter_case(setter, href, new_value, expected)
    { "setter" => setter, "href" => href, "new_value" => new_value, "expected" => expected }
  end

  def test_flatten
    data = {
      "comment" => ["a", "b"],
      "port" => [{ "href" => "http://x/", "new_value" => "1", "expected" => { "port" => "1" } }],
      "hash" => [{ "comment" => "c", "href" => "http://x/", "new_value" => "", "expected" => {} }],
    }
    cases = Setters.flatten(data)
    assert_equal(%w[port hash], cases.map { |c| c["setter"] })
    assert_equal("http://x/", cases[0]["href"])
    assert_equal("c", cases[1]["comment"])
  end

  def test_key
    assert_equal(["port", "http://x/", "1"], Setters.key(setter_case("port", "http://x/", "1", {})))
  end

  def test_supported
    %w[protocol username password hostname port pathname search hash].each do |setter|
      assert_true(Setters.supported?(setter_case(setter, "http://x/", "", {})), setter)
    end
    assert_false(Setters.supported?(setter_case("host", "http://x/", "", {})))
    assert_false(Setters.supported?(setter_case("href", "http://x/", "", {})))
  end

  def apply(setter, href, value)
    uri = URI::WHATWG_PARSER.parse(href)
    Setters.apply(uri, setter, value)
    uri.to_s
  end

  def test_apply_maps_the_setters
    assert_equal("https://x/", apply("protocol", "http://x/", "https"))
    assert_equal("http://u@x/", apply("username", "http://x/", "u"))
    assert_equal("http://:p@x/", apply("password", "http://x/", "p"))
    assert_equal("http://y/", apply("hostname", "http://x/", "y"))
    assert_equal("http://x:1/", apply("port", "http://x/", "1"))
    assert_equal("http://x/p", apply("pathname", "http://x/", "p"))
  end

  def test_apply_search
    assert_equal("http://x/?a", apply("search", "http://x/", "?a"))
    assert_equal("http://x/?a", apply("search", "http://x/", "a"))
    assert_equal("http://x/??a", apply("search", "http://x/", "??a"))
    assert_equal("http://x/?", apply("search", "http://x/?q", "?"))
    assert_equal("http://x/", apply("search", "http://x/?q", ""))
  end

  def test_apply_hash
    assert_equal("http://x/#a", apply("hash", "http://x/", "#a"))
    assert_equal("http://x/#a", apply("hash", "http://x/", "a"))
    assert_equal("http://x/##a", apply("hash", "http://x/", "##a"))
    assert_equal("http://x/#", apply("hash", "http://x/#f", "#"))
    assert_equal("http://x/", apply("hash", "http://x/#f", ""))
  end

  def test_apply_unsupported
    assert_raise(ArgumentError) { apply("host", "http://x/", "y") }
  end

  def test_run_passes
    c = setter_case("port", "http://x/", "8080", { "href" => "http://x:8080/", "port" => "8080" })
    assert_nil(Setters.run(c, URI::WHATWG_PARSER))
  end

  def test_run_reports_differences
    c = setter_case("port", "http://x/", "8080", { "href" => "http://x:9090/", "port" => "9090" })
    message = Setters.run(c, URI::WHATWG_PARSER)
    assert_match(/href: expected "http:\/\/x:9090\/", got "http:\/\/x:8080\/"/, message)
    assert_match(/port: expected "9090", got "8080"/, message)
  end

  def test_run_treats_a_rejected_value_as_unchanged
    c = setter_case("port", "http://x/", "abc", { "href" => "http://x/", "port" => "" })
    assert_nil(Setters.run(c, URI::WHATWG_PARSER))
  end

  def test_run_reports_other_exceptions
    parser = Object.new
    def parser.parse(_)
      raise ArgumentError, "boom"
    end
    c = setter_case("port", "http://x/", "1", {})
    assert_match(/ArgumentError: boom/, Setters.run(c, parser))
  end

  def test_exclusions_path
    assert_equal(File.expand_path("setters_tests_exclusions.json", __dir__), Setters::EXCLUSIONS_PATH)
  end
end
