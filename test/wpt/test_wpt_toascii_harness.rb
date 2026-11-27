# frozen_string_literal: true
require 'test/unit'
require 'uri'
require_relative 'wpt_url_test_data'

# Tests for the harness that runs WPT url/resources/toascii.json. These
# never touch the network.
class WPT::TestToASCIIHarness < Test::Unit::TestCase
  ToASCII = WPT::ToASCIIData

  # A parser stand-in that parses with RFC3986_PARSER after replacing the
  # host as the block says, or raises when the block returns nil.
  class FakeParser
    attr_reader :inputs

    def initialize(&block)
      @block = block
      @inputs = []
    end

    def parse(input)
      @inputs << input
      host = @block.call(input[%r{\Ahttps://(.*)/x\z}m, 1])
      raise URI::InvalidURIError, "fake failure" unless host
      URI::RFC3986_PARSER.parse("https://#{host}/x")
    end
  end

  def test_run_parses_the_input_as_the_host_of_an_https_url
    parser = FakeParser.new { |host| host }
    ToASCII.run({ "input" => "example.com", "output" => "example.com" }, parser)
    assert_equal(["https://example.com/x"], parser.inputs)
  end

  def test_run_passes
    parser = FakeParser.new { "xn--fa-hia.de" }
    assert_nil(ToASCII.run({ "input" => "fa\u{DF}.de", "output" => "xn--fa-hia.de" }, parser))
  end

  def test_run_reports_a_wrong_host
    parser = FakeParser.new { "fass.de" }
    message = ToASCII.run({ "input" => "fa\u{DF}.de", "output" => "xn--fa-hia.de" }, parser)
    assert_match(/host: expected "xn--fa-hia.de", got "fass.de"/, message)
    assert_match(%r{href: expected "https://xn--fa-hia.de/x", got "https://fass.de/x"}, message)
  end

  def test_run_reports_an_unexpected_failure
    parser = FakeParser.new { nil }
    message = ToASCII.run({ "input" => "a", "output" => "a" }, parser)
    assert_match(/unexpected URI::InvalidURIError/, message)
  end

  def test_run_passes_an_expected_failure
    parser = FakeParser.new { nil }
    assert_nil(ToASCII.run({ "input" => "a\u{200C}b", "output" => nil }, parser))
  end

  def test_run_reports_an_unexpected_success
    parser = FakeParser.new { |host| host }
    message = ToASCII.run({ "input" => "a", "output" => nil }, parser)
    assert_match(%r{expected failure, but parsed as "https://a/x"}, message)
  end

  def test_run_reports_other_exceptions
    parser = Object.new
    def parser.parse(_)
      raise ArgumentError, "boom"
    end
    assert_match(/ArgumentError: boom/, ToASCII.run({ "input" => "a", "output" => "a" }, parser))
  end

  # A parser stand-in whose URIs set the host as the block says, or
  # raise InvalidComponentError when the block returns nil.
  class FakeSetterParser
    FakeURI = Struct.new(:host, :setter) do
      def host=(value)
        host = setter.call(value)
        raise URI::InvalidComponentError, "fake rejection" unless host
        self[:host] = host
      end
    end

    attr_reader :inputs

    def initialize(&block)
      @block = block
      @inputs = []
    end

    def parse(input)
      @inputs << input
      FakeURI.new(input[%r{\Ahttps://(.*)/x\z}, 1], @block)
    end
  end

  def test_run_setter_sets_the_input_as_the_host_of_an_https_url
    values = []
    parser = FakeSetterParser.new { |value| values << value; value }
    ToASCII.run_setter({ "input" => "example.com", "output" => "example.com" }, parser)
    assert_equal(["https://x/x"], parser.inputs)
    assert_equal(["example.com"], values)
  end

  def test_run_setter_passes
    parser = FakeSetterParser.new { "xn--fa-hia.de" }
    assert_nil(ToASCII.run_setter({ "input" => "fa\u{DF}.de", "output" => "xn--fa-hia.de" }, parser))
  end

  def test_run_setter_reports_a_wrong_host
    parser = FakeSetterParser.new { "fass.de" }
    message = ToASCII.run_setter({ "input" => "fa\u{DF}.de", "output" => "xn--fa-hia.de" }, parser)
    assert_equal('hostname setter: expected "xn--fa-hia.de", got "fass.de"', message)
  end

  def test_run_setter_reports_an_unexpected_rejection
    parser = FakeSetterParser.new { nil }
    message = ToASCII.run_setter({ "input" => "a", "output" => "a" }, parser)
    assert_equal('hostname setter: expected "a", got "x"', message)
  end

  # The setter ignores a host that fails to parse, so the host stays "x".
  def test_run_setter_passes_an_expected_failure
    parser = FakeSetterParser.new { nil }
    assert_nil(ToASCII.run_setter({ "input" => "a\u{200C}b", "output" => nil }, parser))
  end

  def test_run_setter_reports_an_unexpected_success
    parser = FakeSetterParser.new { |value| value }
    message = ToASCII.run_setter({ "input" => "a", "output" => nil }, parser)
    assert_equal('hostname setter: expected "x", got "a"', message)
  end

  def test_run_setter_reports_other_exceptions
    parser = FakeSetterParser.new { raise ArgumentError, "boom" }
    message = ToASCII.run_setter({ "input" => "a", "output" => "a" }, parser)
    assert_equal("hostname setter: unexpected ArgumentError: boom", message)
  end

  def test_source
    assert_equal(ToASCII::DEFAULT_SOURCE, ToASCII.source) unless ENV["WPT_TOASCII"]
    assert_match(%r{\Ahttps://.*/url/resources/toascii\.json\z}, ToASCII::DEFAULT_SOURCE)
  end
end
