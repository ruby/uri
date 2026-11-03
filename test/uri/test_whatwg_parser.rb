# frozen_string_literal: true
require 'test/unit'
require 'envutil'
require 'stringio'
require 'uri'

class URI::TestWHATWGParser < Test::Unit::TestCase
  def teardown
    URI.parser = URI::RFC3986_PARSER
  end

  # --- constant / default parser -------------------------------------

  def test_whatwg_parser_is_defined_by_requiring_uri
    assert_kind_of(URI::WHATWG_Parser, URI::WHATWG_PARSER)
  end

  def test_default_parser_stays_rfc3986
    assert_same(URI::RFC3986_PARSER, URI::DEFAULT_PARSER)
    assert_same(URI::RFC3986_PARSER, URI::PARSER)
    assert_equal(URI::RFC3986_Parser, URI::Parser)
  end

  def test_whatwg_parser_is_ractor_shareable
    omit "Ractor is not available" unless defined?(Ractor)
    assert(Ractor.shareable?(URI::WHATWG_PARSER))
  end

  def test_whatwg_parser_can_be_instantiated_without_arguments
    # URI.parser= calls Parser.new with no arguments.
    assert_kind_of(URI::WHATWG_Parser, URI::WHATWG_Parser.new)
  end

  # --- URI.parser= switching -----------------------------------------

  def test_parser_switch_to_whatwg
    URI.parser = URI::WHATWG_PARSER

    assert_same(URI::WHATWG_PARSER, URI::PARSER)
    assert_equal(URI::WHATWG_Parser, URI::Parser)
    refute defined?(URI::REGEXP)
    refute defined?(URI::PATTERN)
  end

  def test_parser_switch_does_not_change_default_parser
    URI.parser = URI::WHATWG_PARSER

    assert_same(URI::RFC3986_PARSER, URI::DEFAULT_PARSER)
  end

  def test_parser_switch_back_to_rfc3986
    URI.parser = URI::WHATWG_PARSER
    URI.parser = URI::RFC3986_PARSER

    assert_same(URI::RFC3986_PARSER, URI::PARSER)
    assert_equal(URI::RFC3986_Parser, URI::Parser)
  end

  def test_parser_switch_back_with_default_argument
    URI.parser = URI::WHATWG_PARSER
    URI.parser = URI::RFC2396_PARSER
    URI.parser = URI::WHATWG_PARSER
    URI.send(:parser=)

    assert_same(URI::RFC3986_PARSER, URI::PARSER)
  end

  def test_parser_switch_defines_regexp_constants
    URI.parser = URI::WHATWG_PARSER

    URI::WHATWG_PARSER.regexp.each_pair do |name, re|
      assert_same(re, URI.const_get(name, false), name.to_s)
    end
  end

  def test_uri_parse_uses_whatwg_parser_after_switch
    URI.parser = URI::WHATWG_PARSER

    assert_same(URI::WHATWG_PARSER, URI.parse("http://example.com/").parser)
    assert_same(URI::WHATWG_PARSER, URI("http://example.com/").parser)
  end

  def test_uri_parse_uses_default_parser_without_switch
    assert_same(URI::RFC3986_PARSER, URI.parse("http://example.com/").parser)
  end

  # --- regexp --------------------------------------------------------

  def test_regexp_has_keys_used_by_generic_setters
    %i[SCHEME USERINFO HOST PORT ABS_PATH REL_PATH QUERY FRAGMENT OPAQUE].each do |key|
      assert_kind_of(Regexp, URI::WHATWG_PARSER.regexp[key], key.to_s)
    end
  end

  # --- split / parse / join ------------------------------------------

  def test_split_returns_nine_components
    assert_equal(
      ["http", nil, "example.com", nil, nil, "/", nil, nil, nil],
      URI::WHATWG_PARSER.split("http://example.com/")
    )
  end

  def test_split_rejects_non_string
    assert_raise(URI::InvalidURIError) { URI::WHATWG_PARSER.split(nil) }
    assert_raise(URI::InvalidURIError) { URI::WHATWG_PARSER.split(1) }
  end

  def test_split_accepts_object_responding_to_to_str
    str = Object.new
    def str.to_str; "http://example.com/"; end
    assert_equal("example.com", URI::WHATWG_PARSER.split(str)[2])
  end

  def test_parse_returns_scheme_class_bound_to_whatwg_parser
    uri = URI::WHATWG_PARSER.parse("http://example.com/")

    assert_kind_of(URI::HTTP, uri)
    assert_equal("http://example.com/", uri.to_s)
    assert_same(URI::WHATWG_PARSER, uri.parser)
  end

  def test_join_with_single_argument
    uri = URI::WHATWG_PARSER.join("http://example.com/")

    assert_equal("http://example.com/", uri.to_s)
    assert_same(URI::WHATWG_PARSER, uri.parser)
  end

  def test_join_with_absolute_second_argument
    assert_equal(
      "http://b.example/y",
      URI::WHATWG_PARSER.join("http://a.example/x", "http://b.example/y").to_s
    )
  end

  def test_join_returns_given_uri_object_unchanged
    uri = URI::WHATWG_PARSER.parse("http://example.com/")

    assert_same(uri, URI::WHATWG_PARSER.join(uri))
  end

  # --- convert_to_uri (used by Generic#merge / #route_to) ------------

  def test_convert_to_uri_returns_uri_as_is
    uri = URI::WHATWG_PARSER.parse("http://example.com/")

    assert_same(uri, URI::WHATWG_PARSER.__send__(:convert_to_uri, uri))
  end

  def test_convert_to_uri_parses_string
    uri = URI::WHATWG_PARSER.__send__(:convert_to_uri, "http://example.com/")

    assert_equal("http://example.com/", uri.to_s)
    assert_same(URI::WHATWG_PARSER, uri.parser)
  end

  def test_convert_to_uri_rejects_other_objects
    assert_raise(ArgumentError) { URI::WHATWG_PARSER.__send__(:convert_to_uri, nil) }
    assert_raise(ArgumentError) { URI::WHATWG_PARSER.__send__(:convert_to_uri, 1) }
  end

  # --- RFC2396-compatible methods (obsolete, delegated) --------------

  def test_extract_delegates_to_rfc2396
    EnvUtil.suppress_warning do
      assert_equal(["http://example.com"], URI::WHATWG_PARSER.extract("x http://example.com y"))
      assert_equal([], URI::WHATWG_PARSER.extract("x http://example.com y", ["ftp"]))
      assert_equal(["http://example.com"], URI::WHATWG_PARSER.extract("http://example.com", ["http"]))
    end
  end

  def test_extract_with_block
    EnvUtil.suppress_warning do
      found = []
      URI::WHATWG_PARSER.extract("http://example.com") { |u| found << u }
      assert_equal(["http://example.com"], found)
    end
  end

  def test_make_regexp_delegates_to_rfc2396
    EnvUtil.suppress_warning do
      assert_match(URI::WHATWG_PARSER.make_regexp, "http://example.com")
      assert_match(URI::WHATWG_PARSER.make_regexp(["http"]), "http://example.com")
      assert_no_match(URI::WHATWG_PARSER.make_regexp(["ftp"]), "http://example.com")
    end
  end

  def test_escape_delegates_to_rfc2396
    EnvUtil.suppress_warning do
      assert_equal("a%20b", URI::WHATWG_PARSER.escape("a b"))
      assert_equal("%61b", URI::WHATWG_PARSER.escape("ab", /a/))
    end
  end

  def test_unescape_delegates_to_rfc2396
    EnvUtil.suppress_warning do
      assert_equal("a b", URI::WHATWG_PARSER.unescape("a%20b"))
      assert_equal("a%20b", URI::WHATWG_PARSER.unescape("a%20b", /%41/))
    end
  end

  def test_uri_extract_and_regexp_work_after_switch
    URI.parser = URI::WHATWG_PARSER

    EnvUtil.suppress_warning do
      assert_equal(["http://example.com"], URI.extract("http://example.com"))
      assert_match(URI.regexp, "http://example.com")
    end
  end

  def test_obsolete_methods_warn_when_verbose
    assert_warning(/URI::WHATWG_PARSER\.extract is obsolete/) { URI::WHATWG_PARSER.extract("") }
    assert_warning(/URI::WHATWG_PARSER\.make_regexp is obsolete/) { URI::WHATWG_PARSER.make_regexp }
    assert_warning(/URI::WHATWG_PARSER\.escape is obsolete/) { URI::WHATWG_PARSER.escape("") }
    assert_warning(/URI::WHATWG_PARSER\.unescape is obsolete/) { URI::WHATWG_PARSER.unescape("") }
  end

  def test_obsolete_methods_do_not_warn_when_not_verbose
    verbose, $VERBOSE = $VERBOSE, false
    stderr, $stderr = $stderr, StringIO.new
    URI::WHATWG_PARSER.extract("")
    URI::WHATWG_PARSER.make_regexp
    URI::WHATWG_PARSER.escape("")
    URI::WHATWG_PARSER.unescape("")
    assert_equal("", $stderr.string)
  ensure
    $stderr = stderr
    $VERBOSE = verbose
  end

  # --- preprocessing -------------------------------------------------
  # https://url.spec.whatwg.org/#concept-basic-url-parser (steps 1-3)

  SIMPLE = ["http", nil, "example.com", nil, nil, "/", nil, nil, nil].freeze

  def split(str)
    URI::WHATWG_PARSER.split(str)
  end

  def test_split_strips_leading_and_trailing_spaces
    assert_equal(SIMPLE, split("  http://example.com/  "))
  end

  def test_split_strips_leading_and_trailing_c0_controls
    assert_equal(SIMPLE, split("\x00\x01\x1Fhttp://example.com/\x1F\x0B\x00"))
  end

  def test_split_strips_every_c0_control_and_space_at_both_ends
    all = (0x00..0x20).map(&:chr).join
    assert_equal(SIMPLE, split("#{all}http://example.com/#{all}"))
  end

  def test_split_does_not_strip_just_outside_c0_control_or_space_range
    # U+0021 "!" and U+007F DELETE are not C0 control or space.
    assert_equal("/!", split("http://example.com/!")[5])
    assert_not_equal(SIMPLE, split("http://example.com/\x7F"))
  end

  def test_split_does_not_strip_non_ascii_whitespace
    # U+00A0 NO-BREAK SPACE and U+3000 IDEOGRAPHIC SPACE are kept.
    assert_not_equal(SIMPLE, split("http://example.com/\u00A0"))
    assert_not_equal(SIMPLE, split("http://example.com/\u3000"))
  end

  def test_split_removes_tab_and_newlines_anywhere
    assert_equal(SIMPLE, split("ht\ttp://exa\nmple.com\r/"))
    assert_equal(SIMPLE, split("\r\nhttp://example.com/\t"))
  end

  def test_split_keeps_other_inner_c0_controls_and_spaces
    # Only tab, LF and CR are removed from the inside of the input.
    assert_not_equal(SIMPLE, split("http://example.com/a\x0Bb"))
    assert_not_equal(SIMPLE, split("http://example.com/a\x0Cb"))
    assert_not_equal(SIMPLE, split("http://example.com/a b"))
  end

  def test_split_does_not_modify_its_argument
    str = +"  ht\ttp://example.com/  "
    split(str)
    assert_equal("  ht\ttp://example.com/  ", str)
  end

  def test_split_accepts_frozen_string
    assert_equal(SIMPLE, split(" http://example.com/ ".freeze))
  end

  def test_split_strips_in_linear_time
    # Inner runs of C0 control or space must not cause backtracking.
    pre = ->(n) { "http://example.com/" + " " * n + "a" }
    assert_linear_performance((1..5).map { |i| 10**i }, pre: pre) do |uri|
      split(uri)
    end
  end

  # --- input encoding ------------------------------------------------

  def test_split_accepts_us_ascii_and_binary_ascii_only_input
    assert_equal(SIMPLE, split("http://example.com/".encode("US-ASCII")))
    assert_equal(SIMPLE, split("http://example.com/".b))
  end

  def test_split_converts_other_encodings_to_utf8
    assert_equal(SIMPLE, split("http://example.com/".encode("UTF-16LE")))
    assert_equal(SIMPLE, split(" http://example.com/ ".encode("UTF-16BE")))
  end

  def test_split_returns_utf8_components
    split("http://example.com/".encode("UTF-16LE")).compact.each do |component|
      assert_equal(Encoding::UTF_8, component.encoding, component)
    end
  end

  def test_split_rejects_invalid_byte_sequence
    assert_raise(URI::InvalidURIError) { split("http://example.com/\xFF") }
    assert_raise(URI::InvalidURIError) { split("http://example.com/\xE3\x81") }
  end

  def test_split_rejects_binary_input_with_non_ascii_bytes
    assert_raise(URI::InvalidURIError) { split("http://example.com/\xE3\x81\x82".b) }
  end

  def test_split_rejects_invalid_utf16_input
    # An unpaired high surrogate (U+D800) is not a valid UTF-16 sequence.
    lone_surrogate = ("http://example.com/".encode("UTF-16LE").b + "\x00\xD8".b).force_encoding("UTF-16LE")
    assert_raise(URI::InvalidURIError) { split(lone_surrogate) }
  end
end
