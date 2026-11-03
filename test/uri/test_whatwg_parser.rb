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

  # --- scheme --------------------------------------------------------
  # https://url.spec.whatwg.org/#scheme-start-state
  # https://url.spec.whatwg.org/#scheme-state
  # https://url.spec.whatwg.org/#no-scheme-state

  def test_split_lowercases_scheme
    assert_equal("http", split("HTTP://example.com/")[0])
    assert_equal("https", split("HtTpS://example.com/")[0])
    assert_equal("foo", split("FOO:bar")[0])
  end

  def test_split_scheme_may_contain_digits_plus_hyphen_and_dot
    assert_equal("a+b-c.d0", split("a+b-c.d0:x")[0])
    assert_equal("a9", split("a9:x")[0])
  end

  def test_split_single_letter_scheme
    assert_equal("a", split("a:x")[0])
    assert_equal("z", split("Z:x")[0])
  end

  def test_split_scheme_letter_boundaries
    # "A", "Z", "a", "z" start a scheme; "@", "[", "`", "{" (their
    # neighbours in ASCII) do not.
    %w[A Z a z].each { |c| assert_equal(c.downcase, split("#{c}:x")[0], c) }
    ["@", "[", "`", "{"].each { |c| assert_raise(URI::InvalidURIError, c) { split("#{c}a:x") } }
  end

  def test_split_scheme_digit_boundaries
    # "0" and "9" may follow the first letter; "/" (before "0") may not.
    assert_equal("a0", split("a0:x")[0])
    assert_equal("a9", split("a9:x")[0])
    assert_raise(URI::InvalidURIError) { split("a/:x") }
  end

  def test_split_scheme_must_start_with_letter
    %w[1a:x +a:x -a:x .a:x].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_scheme_rejects_other_characters
    ["a_b:x", "a b:x", "a%62:x", "a!b:x"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_scheme_rejects_non_ascii_letters
    # U+212A KELVIN SIGN lowercases to "k" with Unicode case mapping, but
    # it is not an ASCII alpha.
    ["é:x", "aé:x", "K:x", "Khttp:x"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_without_scheme_fails_without_base
    ["example.com", "/path", "//example.com/", "?q", "#f", "", "   ", ":", ":foo"].each do |input|
      assert_raise(URI::InvalidURIError, input.inspect) { split(input) }
    end
  end

  def test_parse_without_scheme_fails
    assert_raise(URI::InvalidURIError) { URI::WHATWG_PARSER.parse("example.com") }
  end

  def test_split_uses_first_colon_as_scheme_delimiter
    assert_equal(["foo", "bar:baz"], split("foo:bar:baz").values_at(0, 6))
  end

  def test_split_special_schemes_are_hierarchical
    %w[http https ws wss ftp].each do |scheme|
      assert_equal(
        [scheme, nil, "example.com", nil, nil, "/", nil, nil, nil],
        split("#{scheme}://example.com/"),
        scheme
      )
    end
  end

  def test_split_file_scheme_is_hierarchical
    # file is a special scheme. Its own states (file state, file host
    # state, ...) are not implemented yet.
    assert_equal(["file", nil], split("FILE:///tmp/a").values_at(0, 6))
  end

  def test_split_non_special_scheme_with_opaque_path
    assert_equal(["foo", nil, nil, nil, nil, nil, "bar", nil, nil], split("foo:bar"))
  end

  def test_split_non_special_scheme_with_empty_opaque_path
    assert_equal(["foo", nil, nil, nil, nil, nil, "", nil, nil], split("foo:"))
  end

  def test_split_non_special_scheme_with_path
    assert_equal(["foo", nil, nil, nil, nil, "/bar", nil, nil, nil], split("foo:/bar"))
  end

  def test_split_non_special_scheme_with_authority
    assert_equal(["foo", nil, "host", nil, nil, "/bar", nil, nil, nil], split("foo://host/bar"))
  end

  def test_split_scheme_that_only_resembles_a_special_one_is_non_special
    # "http" is special only as the whole scheme.
    assert_equal("httpx", split("httpx:bar")[0])
    assert_equal("bar", split("httpx:bar")[6])
    assert_equal("bar", split("htt:bar")[6])
  end

  def test_parse_non_special_opaque_round_trip
    assert_equal("foo:bar", URI::WHATWG_PARSER.parse("foo:bar").to_s)
    assert_equal("foo:", URI::WHATWG_PARSER.parse("foo:").to_s)
  end

  # --- authority -----------------------------------------------------
  # https://url.spec.whatwg.org/#special-authority-slashes-state
  # https://url.spec.whatwg.org/#special-authority-ignore-slashes-state
  # https://url.spec.whatwg.org/#path-or-authority-state
  # https://url.spec.whatwg.org/#authority-state
  # https://url.spec.whatwg.org/#host-state

  USERINFO, HOST, PORT, PATH, OPAQUE = 1, 2, 3, 5, 6

  def test_split_special_authority_ignores_any_number_of_slashes
    ["http:example.com/", "http:/example.com/", "http://example.com/",
     "http:///example.com/", "http:////example.com/"].each do |input|
      assert_equal("example.com", split(input)[HOST], input)
    end
  end

  def test_split_special_authority_treats_backslash_as_slash
    ["http:\\\\example.com/", "http:/\\example.com/", "http:\\/example.com/",
     "http:\\example.com/"].each do |input|
      assert_equal("example.com", split(input)[HOST], input)
    end
  end

  def test_split_ignoring_slashes_applies_to_every_special_scheme
    %w[https ws wss ftp].each do |scheme|
      assert_equal("example.com", split("#{scheme}:example.com/")[HOST], scheme)
      assert_equal("example.com", split("#{scheme}:\\\\example.com/")[HOST], scheme)
    end
  end

  def test_split_non_special_needs_exactly_two_slashes_for_authority
    assert_equal([nil, "/host/x"], split("foo:/host/x").values_at(HOST, PATH))
    assert_equal(["", "/x"], split("foo:///x").values_at(HOST, PATH))
    assert_equal(["host", "/x"], split("foo://host/x").values_at(HOST, PATH))
  end

  def test_split_non_special_does_not_treat_backslash_as_slash
    assert_equal([nil, "\\\\host"], split("foo:\\\\host").values_at(HOST, OPAQUE))
    assert_equal([nil, "/\\host"], split("foo:/\\host").values_at(HOST, PATH))
  end

  def test_split_special_authority_ends_at_slash_question_hash_or_backslash
    %w[/ ? # \\].each do |c|
      assert_equal("host", split("http://host#{c}x")[HOST], c)
    end
  end

  def test_split_non_special_authority_ends_at_slash_question_or_hash
    %w[/ ? #].each do |c|
      assert_equal("host", split("foo://host#{c}x")[HOST], c)
    end
  end

  def test_split_authority_at_end_of_input
    assert_equal("host", split("http://host")[HOST])
    assert_equal("host", split("foo://host")[HOST])
  end

  def test_split_userinfo
    assert_equal(["user:pass", "host"], split("http://user:pass@host/").values_at(USERINFO, HOST))
  end

  def test_split_userinfo_username_only
    assert_equal("user", split("http://user@host/")[USERINFO])
  end

  def test_split_userinfo_empty_password_is_dropped
    assert_equal("user", split("http://user:@host/")[USERINFO])
  end

  def test_split_userinfo_password_only
    assert_equal(":pass", split("http://:pass@host/")[USERINFO])
  end

  def test_split_userinfo_empty_is_nil
    assert_nil(split("http://@host/")[USERINFO])
    assert_nil(split("http://:@host/")[USERINFO])
  end

  def test_split_userinfo_splits_at_last_at_sign
    # Every "@" but the last one belongs to the userinfo, as "%40".
    assert_equal(["a%40b", "host"], split("http://a@b@host/").values_at(USERINFO, HOST))
    assert_equal("a%40b%40c", split("http://a@b@c@host/")[USERINFO])
  end

  def test_split_userinfo_splits_password_at_first_colon
    assert_equal("a%40b:c", split("http://a@b:c@host/")[USERINFO])
  end

  def test_split_userinfo_in_non_special_url
    assert_equal(["user:pass", "host"], split("foo://user:pass@host/").values_at(USERINFO, HOST))
  end

  def test_split_at_sign_after_authority_is_not_userinfo
    ["http://host/a@b", "http://host?a@b", "http://host#a@b"].each do |input|
      assert_equal([nil, "host"], split(input).values_at(USERINFO, HOST), input)
    end
  end

  def test_split_backslash_ends_special_authority_before_at_sign
    assert_equal([nil, "user"], split("http://user\\@host/").values_at(USERINFO, HOST))
  end

  def test_split_host_and_port
    assert_equal(["host", "8080"], split("http://host:8080/").values_at(HOST, PORT))
    assert_equal(["host", "8080"], split("http://u:p@host:8080/").values_at(HOST, PORT))
  end

  def test_split_without_port
    assert_nil(split("http://host/")[PORT])
  end

  def test_split_colon_inside_brackets_is_not_port_delimiter
    assert_equal(["[::1]", "8080"], split("http://[::1]:8080/").values_at(HOST, PORT))
    assert_equal(["[::1]", nil], split("http://[::1]/").values_at(HOST, PORT))
  end

  def test_split_brackets_in_userinfo_do_not_affect_port
    assert_equal(["u[", "host", "8080"], split("http://u[@host:8080/").values_at(USERINFO, HOST, PORT))
  end

  def test_split_special_url_needs_host
    ["http://", "http:///", "http:", "http:/", "http://?q", "http://#f", "http:\\\\"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_userinfo_without_host_fails
    ["http://user@/", "http://@/", "http://user@", "http://u:p@", "foo://@", "foo://user@/"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_port_without_host_fails
    ["http://:80/", "foo://:80/", "http://u@:80/"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_non_special_url_may_have_empty_host
    assert_equal("", split("foo://")[HOST])
    assert_equal("", split("foo:///")[HOST])
    assert_equal("", split("foo://?q")[HOST])
  end

  def test_split_file_host_may_be_empty
    # Interim behaviour until the file states are implemented.
    assert_equal(["", "/tmp/a"], split("file:///tmp/a").values_at(HOST, PATH))
    assert_equal(["host", "/a"], split("file://host/a").values_at(HOST, PATH))
    assert_equal(["host", "/a"], split("file:\\\\host/a").values_at(HOST, PATH))
    assert_equal([nil, "/a"], split("file:/a").values_at(HOST, PATH))
  end

  # --- host: domain -------------------------------------------------
  # https://url.spec.whatwg.org/#concept-host-parser
  # https://url.spec.whatwg.org/#concept-domain-to-ascii

  def test_split_domain_is_ascii_lowercased
    assert_equal("example.com", split("http://EXAMPLE.COM/")[HOST])
    assert_equal("example.com", split("http://ExAmPlE.cOm/")[HOST])
  end

  def test_split_domain_is_percent_decoded
    assert_equal("example.com", split("http://ex%61mple.com/")[HOST])
    assert_equal("example.com", split("http://ex%41mple.com/")[HOST])
    assert_equal("example.com", split("http://example%2ecom/")[HOST])
    assert_equal("example.com", split("http://example%2Ecom/")[HOST])
  end

  def test_split_domain_percent_decoded_to_forbidden_code_point_fails
    %w[%25 %2F %20 %00 %3A %40 %3C %7C %7F %01].each do |encoded|
      assert_raise(URI::InvalidURIError, encoded) { split("http://a#{encoded}b/") }
    end
  end

  def test_split_domain_with_invalid_percent_sequence_fails
    # "%" not followed by two hex digits is left alone, and "%" is a
    # forbidden domain code point.
    ["http://a%zzb/", "http://a%/", "http://a%4/", "http://a%4g/"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_domain_with_forbidden_code_point_fails
    ["\x00", " ", "<", ">", "[", "]", "^", "|", "%", "\x01", "\x1F", "\x7F"].each do |c|
      assert_raise(URI::InvalidURIError, c.dump) { split("http://a#{c}b/") }
    end
  end

  def test_split_domain_code_point_boundaries
    # U+0020 SPACE and U+007F DELETE are forbidden; U+0021 "!" and U+007E
    # "~" next to them are not.
    assert_equal("a!b", split("http://a!b/")[HOST])
    assert_equal("a~b", split("http://a~b/")[HOST])
  end

  def test_split_domain_allows_other_ascii_punctuation
    assert_equal("a$&'()*+,;=_-b", split("http://a$&'()*+,;=_-b/")[HOST])
  end

  def test_split_domain_with_empty_labels
    assert_equal(".", split("http://./")[HOST])
    assert_equal("..", split("http://../")[HOST])
    assert_equal("a..b", split("http://a..b/")[HOST])
    assert_equal("example.com.", split("http://example.com./")[HOST])
  end

  def test_split_domain_rules_apply_to_every_special_scheme
    %w[https ws wss ftp].each do |scheme|
      assert_equal("example.com", split("#{scheme}://EX%41MPLE.com/")[HOST], scheme)
      assert_raise(URI::InvalidURIError, scheme) { split("#{scheme}://a b/") }
    end
  end

  def test_split_ascii_xn_label_is_lowercased
    # Interim: Punycode validation of "xn--" labels is not implemented.
    assert_equal("xn--9ca.example", split("http://XN--9CA.example/")[HOST])
  end

  def test_split_non_ascii_domain_is_left_as_is
    # Interim behaviour until domain to ASCII (UTS #46) is implemented.
    assert_equal("é.example", split("http://é.example/")[HOST])
    assert_equal("%C3%A9.example", split("http://%C3%A9.example/")[HOST])
  end

  def test_split_bracketed_host_must_end_with_bracket
    ["http://[::1/", "http://[/", "http://[::1]x/", "foo://[::1/"].each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  # --- host: IPv4 ---------------------------------------------------
  # https://url.spec.whatwg.org/#ends-in-a-number-checker
  # https://url.spec.whatwg.org/#concept-ipv4-parser
  # https://url.spec.whatwg.org/#ipv4-number-parser
  # https://url.spec.whatwg.org/#concept-ipv4-serializer

  def host(input)
    split(input)[HOST]
  end

  def assert_ipv4_failure(*inputs)
    inputs.each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_ipv4_dotted_decimal
    assert_equal("192.168.0.1", host("http://192.168.0.1/"))
    assert_equal("0.0.0.0", host("http://0.0.0.0/"))
    assert_equal("255.255.255.255", host("http://255.255.255.255/"))
  end

  def test_split_ipv4_octal_and_hex_parts
    assert_equal("192.168.0.1", host("http://0300.0250.0.01/"))
    assert_equal("192.168.0.1", host("http://0xc0.0xA8.0X0.0x1/"))
    assert_equal("192.168.0.1", host("http://0xC0.0250.0.1/"))
  end

  def test_split_ipv4_number_prefix_only
    # "0x" alone is 0; "0" and "00" are 0.
    assert_equal("0.0.0.0", host("http://0x/"))
    assert_equal("0.0.0.0", host("http://0X/"))
    assert_equal("0.0.0.0", host("http://0/"))
    assert_equal("0.0.0.0", host("http://00/"))
    assert_equal("1.0.0.0", host("http://1.0x.0.00/"))
  end

  def test_split_ipv4_one_part
    assert_equal("192.168.0.1", host("http://3232235521/"))
    assert_equal("192.168.0.1", host("http://0xc0a80001/"))
  end

  def test_split_ipv4_two_parts
    # The last part fills the remaining three bytes.
    assert_equal("192.168.0.1", host("http://192.11010049/"))
  end

  def test_split_ipv4_three_parts
    # The last part fills the remaining two bytes.
    assert_equal("192.168.0.1", host("http://192.168.1/"))
  end

  def test_split_ipv4_trailing_dot_is_ignored_once
    assert_equal("1.2.3.4", host("http://1.2.3.4./"))
    assert_equal("0.0.0.1", host("http://1./"))
    # With two trailing dots the last label is still empty, so it does not
    # end in a number and is a domain.
    assert_equal("1.2.3.4..", host("http://1.2.3.4../"))
  end

  def test_split_ipv4_more_than_four_parts_fails
    assert_ipv4_failure("http://1.2.3.4.5/", "http://1.2.3.4.5./", "http://0.0.0.0.0/")
  end

  def test_split_ipv4_empty_part_fails
    assert_ipv4_failure("http://1..2/", "http://.1/", "http://1.2..3/")
  end

  def test_split_ipv4_non_last_part_boundaries
    assert_equal("255.0.0.0", host("http://255.0.0.0/"))
    assert_ipv4_failure("http://256.0.0.0/", "http://0.256.0.0/", "http://0.0.256.0/")
    assert_ipv4_failure("http://0x100.0.0.0/", "http://0400.0.0.0/")
  end

  def test_split_ipv4_last_part_boundaries
    assert_equal("0.0.0.255", host("http://0.0.0.255/"))
    assert_ipv4_failure("http://0.0.0.256/")

    assert_equal("1.2.255.255", host("http://1.2.65535/"))
    assert_ipv4_failure("http://1.2.65536/")

    assert_equal("1.255.255.255", host("http://1.16777215/"))
    assert_ipv4_failure("http://1.16777216/")

    assert_equal("255.255.255.255", host("http://4294967295/"))
    assert_equal("255.255.255.255", host("http://0xffffffff/"))
    assert_equal("255.255.255.255", host("http://037777777777/"))
    assert_ipv4_failure("http://4294967296/", "http://0x100000000/", "http://040000000000/")
  end

  def test_split_ipv4_huge_numbers_fail
    assert_ipv4_failure("http://99999999999999999999999999/", "http://1.2.3.99999999999999999999/",
                        "http://0x#{"f" * 100}/")
  end

  def test_split_ipv4_leading_zeros
    assert_equal("0.0.0.1", host("http://#{"0" * 1000}1/"))
    assert_equal("0.0.0.1", host("http://0x#{"0" * 1000}1/"))
  end

  def test_split_ipv4_invalid_digits_fail
    # "08" and "09" are octal; "+", "-", "_" and spaces are not digits.
    assert_ipv4_failure("http://08/", "http://09/", "http://1.08/", "http://0xg.1/", "http://0x0x1.1/",
                        "http://+1.2.3.4/", "http://-1.2.3.4/", "http://1_0.1/", "http://1e1.1/")
  end

  def test_split_ends_in_a_number_but_not_ipv4_fails
    assert_ipv4_failure("http://example.1/", "http://foo.09/", "http://foo.0x/", "http://example.1./",
                        "http://foo.0x1f/")
  end

  def test_split_not_ending_in_a_number_is_a_domain
    assert_equal("1.example", host("http://1.example/"))
    assert_equal("foo.0xg", host("http://foo.0xg/"))
    assert_equal("1.2.3.4a", host("http://1.2.3.4a/"))
    assert_equal("1..", host("http://1../"))
    assert_equal("0x1.example", host("http://0x1.example/"))
  end

  def test_split_ipv4_after_percent_decoding
    assert_equal("1.2.3.4", host("http://%31.%32.%33.%34/"))
    assert_equal("127.0.0.1", host("http://%30x7f.1/"))
  end

  def test_split_ipv4_for_every_special_scheme
    %w[https ws wss ftp].each do |scheme|
      assert_equal("127.0.0.1", host("#{scheme}://0x7f.1/"), scheme)
    end
  end

  def test_split_opaque_host_is_not_parsed_as_ipv4
    assert_equal("0x7f.1", host("foo://0x7f.1/"))
    assert_equal("1.2.3.08", host("foo://1.2.3.08/"))
  end

  def test_parse_serializes_ipv4_host
    assert_equal("http://127.0.0.1/", URI::WHATWG_PARSER.parse("http://0x7f.1/").to_s)
  end

  def test_split_ipv4_in_linear_time
    pre = ->(n) { "http://1.2.3." + "9" * n + "/" }
    assert_linear_performance((2..5).map { |i| 10**i }, pre: pre) do |uri|
      assert_raise(URI::InvalidURIError) { split(uri) }
    end
  end

  # --- host: IPv6 ---------------------------------------------------
  # https://url.spec.whatwg.org/#concept-ipv6-parser
  # https://url.spec.whatwg.org/#concept-ipv6-serializer

  def ipv6(address, scheme = "http")
    host("#{scheme}://[#{address}]/")
  end

  def assert_ipv6_failure(*addresses)
    addresses.each do |address|
      assert_raise(URI::InvalidURIError, address) { split("http://[#{address}]/") }
    end
  end

  def test_split_ipv6_loopback_and_unspecified
    assert_equal("[::1]", ipv6("::1"))
    assert_equal("[::1]", ipv6("0:0:0:0:0:0:0:1"))
    assert_equal("[::]", ipv6("::"))
    assert_equal("[::]", ipv6("0:0:0:0:0:0:0:0"))
  end

  def test_split_ipv6_full_address_is_kept
    assert_equal("[2001:db8:85a3:8d3:1319:8a2e:370:7348]", ipv6("2001:db8:85a3:8d3:1319:8a2e:370:7348"))
  end

  def test_split_ipv6_is_lowercased_without_leading_zeros
    assert_equal("[abcd::ef]", ipv6("ABCD::EF"))
    assert_equal("[1:db8::]", ipv6("0001:0db8::"))
    assert_equal("[ffff::]", ipv6("FFFF::"))
  end

  def test_split_ipv6_compression_position
    assert_equal("[1::]", ipv6("1::"))
    assert_equal("[::1:2]", ipv6("::1:2"))
    assert_equal("[1:2::3:4]", ipv6("1:2::3:4"))
    assert_equal("[::1:2:3:4:5:6]", ipv6("0:0:1:2:3:4:5:6"))
    assert_equal("[1:2:3:4:5:6::]", ipv6("1:2:3:4:5:6:0:0"))
  end

  def test_split_ipv6_compresses_longest_zero_run
    assert_equal("[1:0:0:2::3]", ipv6("1:0:0:2:0:0:0:3"))
    assert_equal("[1::2:0:0:3]", ipv6("1:0:0:0:2:0:0:3"))
  end

  def test_split_ipv6_compresses_first_of_equally_long_zero_runs
    assert_equal("[1::2:0:0:3:4]", ipv6("1:0:0:2:0:0:3:4"))
  end

  def test_split_ipv6_does_not_compress_single_zero
    assert_equal("[1:0:2:3:4:5:6:7]", ipv6("1:0:2:3:4:5:6:7"))
    assert_equal("[1:2:3:4:5:6:7:0]", ipv6("1:2:3:4:5:6:7::"))
    assert_equal("[0:1:2:3:4:5:6:7]", ipv6("::1:2:3:4:5:6:7"))
  end

  def test_split_ipv6_piece_boundaries
    assert_equal("[1:2:3:4:5:6:7:ffff]", ipv6("1:2:3:4:5:6:7:ffff"))
    assert_ipv6_failure("10000::", "1:2:3:4:5:6:7:10000", "00000::")
  end

  def test_split_ipv6_piece_count_boundaries
    # 8 pieces, or fewer with "::".
    assert_ipv6_failure("1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7:8::", "::1:2:3:4:5:6:7:8")
  end

  def test_split_ipv6_invalid_colons_fail
    assert_ipv6_failure("", ":", ":1", "1:", "1::2::3", ":::", "::1::", "1:::2", "1:2:3:4:5:6:7:8:")
  end

  def test_split_ipv6_invalid_characters_fail
    assert_ipv6_failure("g::", "::1 ", "::1%25eth0", "%3A%3A1", "::-1", "é::")
  end

  def test_split_ipv6_embedded_ipv4
    assert_equal("[::ffff:102:304]", ipv6("::ffff:1.2.3.4"))
    assert_equal("[::102:304]", ipv6("::1.2.3.4"))
    assert_equal("[1:2:3:4:5:6:102:304]", ipv6("1:2:3:4:5:6:1.2.3.4"))
    assert_equal("[::]", ipv6("::0.0.0.0"))
  end

  def test_split_ipv6_embedded_ipv4_number_boundaries
    assert_equal("[::102:3ff]", ipv6("::1.2.3.255"))
    assert_equal("[::102:300]", ipv6("::1.2.3.0"))
    assert_ipv6_failure("::1.2.3.256", "::256.1.2.3")
  end

  def test_split_ipv6_embedded_ipv4_must_have_four_decimal_parts
    assert_ipv6_failure("::1.2.3", "::1.2.3.4.5", "::1.2..3", "::.1.2.3", "::1.2.3.", "::1.2.3.4x",
                        "::a.b.c.d", "::0x1.2.3.4", "::1.2.3.4:5")
  end

  def test_split_ipv6_embedded_ipv4_rejects_leading_zero
    assert_ipv6_failure("::1.2.3.04", "::01.2.3.4", "::1.2.3.00")
  end

  def test_split_ipv6_embedded_ipv4_position
    # The IPv4 address takes the last two pieces.
    assert_ipv6_failure("1:2:3:4:5:6:7:1.2.3.4", "1.2.3.4", "1.2.3.4::")
  end

  def test_split_ipv6_embedded_ipv4_number_too_long_fails
    # The leading hex piece is re-read as decimal.
    assert_ipv6_failure("::1234.1.2.3", "::12345.1.2.3")
  end

  def test_split_ipv6_in_non_special_url
    assert_equal("[::1]", ipv6("0:0::1", "foo"))
    assert_raise(URI::InvalidURIError) { split("foo://[x]/") }
  end

  def test_split_ipv6_with_port
    assert_equal(["[::1]", "8080"], split("http://[0::1]:8080/").values_at(HOST, PORT))
  end

  def test_parse_serializes_ipv6_host
    uri = URI::WHATWG_PARSER.parse("http://[0:0::1]/")
    assert_equal("http://[::1]/", uri.to_s)
    assert_equal("::1", uri.hostname)
  end

  # --- port ---------------------------------------------------------
  # https://url.spec.whatwg.org/#port-state

  def port(input)
    split(input)[PORT]
  end

  def assert_port_failure(*inputs)
    inputs.each do |input|
      assert_raise(URI::InvalidURIError, input) { split(input) }
    end
  end

  def test_split_port
    assert_equal("8080", port("http://h:8080/"))
    assert_equal("8080", port("http://u:p@h:8080/"))
  end

  def test_split_empty_port_is_nil
    assert_nil(port("http://h:/"))
    assert_nil(port("http://h:"))
    assert_nil(port("http://h:?q"))
    assert_nil(port("foo://h:/"))
  end

  def test_split_default_port_is_nil
    { "http" => 80, "https" => 443, "ws" => 80, "wss" => 443, "ftp" => 21 }.each do |scheme, default|
      assert_nil(port("#{scheme}://h:#{default}/"), scheme)
    end
  end

  def test_split_default_port_of_another_scheme_is_kept
    assert_equal("443", port("http://h:443/"))
    assert_equal("80", port("https://h:80/"))
    assert_equal("80", port("ftp://h:80/"))
    assert_equal("21", port("http://h:21/"))
  end

  def test_split_non_special_scheme_has_no_default_port
    assert_equal("80", port("foo://h:80/"))
    assert_equal("443", port("foo://h:443/"))
  end

  def test_split_port_leading_zeros_are_removed
    assert_equal("8080", port("http://h:0008080/"))
    assert_equal("80", port("foo://h:0080/"))
    assert_nil(port("http://h:00080/"))
    assert_equal("1", port("http://h:#{"0" * 1000}1/"))
    assert_equal("0", port("http://h:000/"))
  end

  def test_split_port_boundaries
    assert_equal("0", port("http://h:0/"))
    assert_equal("1", port("http://h:1/"))
    assert_equal("65535", port("http://h:65535/"))
    assert_port_failure("http://h:65536/", "http://h:99999/", "http://h:100000/", "foo://h:65536/")
  end

  def test_split_huge_port_fails
    assert_port_failure("http://h:#{"9" * 100}/", "http://h:1#{"0" * 100}/")
  end

  def test_split_port_must_be_digits
    assert_port_failure("http://h:8a/", "http://h:a/", "http://h:-1/", "http://h:+1/", "http://h: 1/",
                        "http://h:1 /", "http://h:1_0/", "http://h:0x10/", "http://h:1:2/", "http://h:1.0/",
                        "http://h:\uFF11/", "foo://h:8a/")
  end

  def test_split_port_ends_at_authority_end
    %w[/ ? #].each do |c|
      assert_equal("8080", port("http://h:8080#{c}x"), c)
      assert_equal("8080", port("foo://h:8080#{c}x"), c)
    end
    assert_equal("8080", port("http://h:8080\\x"))
  end

  def test_split_non_special_port_does_not_end_at_backslash
    assert_port_failure("foo://h:8080\\x")
  end

  def test_split_port_with_ipv6_host
    assert_equal("8080", port("http://[::1]:8080/"))
    assert_nil(port("http://[::1]:80/"))
  end

  def test_parse_port
    assert_equal(8080, URI::WHATWG_PARSER.parse("http://h:8080/").port)
    assert_equal("http://h:8080/", URI::WHATWG_PARSER.parse("http://h:08080/").to_s)
  end

  def test_parse_default_port_is_omitted
    uri = URI::WHATWG_PARSER.parse("http://h:80/")
    assert_equal("http://h/", uri.to_s)
    assert_equal(80, uri.port)
  end

  def test_split_port_in_linear_time
    pre = ->(n) { "http://h:" + "9" * n + "/" }
    assert_linear_performance((2..5).map { |i| 10**i }, pre: pre) do |uri|
      assert_raise(URI::InvalidURIError) { split(uri) }
    end
  end

  # --- query and fragment -------------------------------------------
  # https://url.spec.whatwg.org/#path-state
  # https://url.spec.whatwg.org/#query-state
  # https://url.spec.whatwg.org/#fragment-state
  # https://url.spec.whatwg.org/#cannot-be-a-base-url-path-state

  QUERY, FRAGMENT = 7, 8

  def test_split_query_and_fragment
    assert_equal(["/p", "q", "f"], split("http://h/p?q#f").values_at(PATH, QUERY, FRAGMENT))
  end

  def test_split_query_only
    assert_equal(["/p", "q", nil], split("http://h/p?q").values_at(PATH, QUERY, FRAGMENT))
  end

  def test_split_fragment_only
    assert_equal(["/p", nil, "f"], split("http://h/p#f").values_at(PATH, QUERY, FRAGMENT))
  end

  def test_split_empty_query_and_fragment_are_kept
    assert_equal(["", nil], split("http://h/p?").values_at(QUERY, FRAGMENT))
    assert_equal([nil, ""], split("http://h/p#").values_at(QUERY, FRAGMENT))
    assert_equal(["", ""], split("http://h/p?#").values_at(QUERY, FRAGMENT))
  end

  def test_split_question_mark_after_hash_is_part_of_fragment
    assert_equal([nil, "f?q"], split("http://h/p#f?q").values_at(QUERY, FRAGMENT))
  end

  def test_split_query_and_fragment_split_at_first_delimiter
    assert_equal("a?b", split("http://h/p?a?b")[QUERY])
    assert_equal("a#b", split("http://h/p#a#b")[FRAGMENT])
    assert_equal(["a?b", "c#d?e"], split("http://h/p?a?b#c#d?e").values_at(QUERY, FRAGMENT))
  end

  def test_split_query_and_fragment_right_after_host
    assert_equal(["h", "q", nil], split("http://h?q").values_at(HOST, QUERY, FRAGMENT))
    assert_equal(["h", nil, "f"], split("http://h#f").values_at(HOST, QUERY, FRAGMENT))
    assert_equal(["h", "8080", "q"], split("http://h:8080?q").values_at(HOST, PORT, QUERY))
  end

  def test_split_hash_ends_authority_before_at_sign
    assert_equal([nil, "u", "@host/"], split('http://u#@host/').values_at(USERINFO, HOST, FRAGMENT))
  end

  def test_split_backslash_in_query_and_fragment_is_kept
    assert_equal(["a\\b", "c\\d"], split("http://h/?a\\b#c\\d").values_at(QUERY, FRAGMENT))
  end

  def test_split_query_and_fragment_in_non_special_url
    assert_equal(["h", "/p", "q", "f"], split("foo://h/p?q#f").values_at(HOST, PATH, QUERY, FRAGMENT))
    assert_equal([nil, "/p", "q", "f"], split("foo:/p?q#f").values_at(HOST, PATH, QUERY, FRAGMENT))
    assert_equal(["", "q"], split("foo://?q").values_at(HOST, QUERY))
  end

  def test_split_query_and_fragment_in_file_url
    assert_equal(["/a", "q", "f"], split("file:///a?q#f").values_at(PATH, QUERY, FRAGMENT))
  end

  # An opaque URI keeps its query inside opaque, as URI::RFC3986_Parser
  # does, since URI::Generic does not serialize the query of an opaque URI.

  def test_split_opaque_path_with_query_and_fragment
    assert_equal(["bar?q", nil, "f"], split("foo:bar?q#f").values_at(OPAQUE, QUERY, FRAGMENT))
  end

  def test_split_opaque_path_with_fragment_containing_question_mark
    assert_equal(["bar", nil, "f?q"], split("foo:bar#f?q").values_at(OPAQUE, QUERY, FRAGMENT))
  end

  def test_split_opaque_path_with_empty_query_and_fragment
    assert_equal(["bar?", nil, ""], split("foo:bar?#").values_at(OPAQUE, QUERY, FRAGMENT))
  end

  def test_split_empty_opaque_path_with_query_or_fragment
    assert_equal(["?q", nil], split("foo:?q").values_at(OPAQUE, FRAGMENT))
    assert_equal(["", "f"], split("foo:#f").values_at(OPAQUE, FRAGMENT))
  end

  def test_split_opaque_path_space_before_query_or_fragment_is_encoded
    # Only the space right before "?" or "#" is encoded, so it survives
    # the stripping of trailing spaces when the URL is reparsed.
    assert_equal("a%20?q", split("foo:a ?q")[OPAQUE])
    assert_equal("a %20", split("foo:a  #f")[OPAQUE])
    assert_equal("a  %20?", split("foo:a   ?")[OPAQUE])
  end

  def test_split_opaque_path_other_spaces_are_kept
    assert_equal("a  b?q", split("foo:a  b?q")[OPAQUE])
    assert_equal("a b", split("foo:a b")[OPAQUE])
  end

  def test_split_opaque_path_trailing_spaces_are_stripped
    # by the preprocessing, as they are at the end of the input.
    assert_equal("a", split("foo:a  ")[OPAQUE])
  end

  def test_split_space_in_query_or_fragment_of_opaque_url_is_not_encoded_here
    assert_equal("a? b", split("foo:a? b")[OPAQUE])
    assert_equal(" b", split("foo:a# b")[FRAGMENT])
  end

  def test_parse_round_trip_with_query_and_fragment
    %w[http://h/p?q#f http://h/p?# foo:bar?q#f foo:bar?# foo://h/p?q#f].each do |input|
      assert_equal(input, URI::WHATWG_PARSER.parse(input).to_s, input)
    end
  end

  def test_parse_query_and_fragment
    uri = URI::WHATWG_PARSER.parse("http://h/p?q#f")
    assert_equal(["q", "f"], [uri.query, uri.fragment])
  end

  # --- path ---------------------------------------------------------
  # https://url.spec.whatwg.org/#path-start-state
  # https://url.spec.whatwg.org/#path-state
  # https://url.spec.whatwg.org/#single-dot-path-segment
  # https://url.spec.whatwg.org/#double-dot-path-segment
  # https://url.spec.whatwg.org/#url-serializing (the "/." prefix)

  def path(input)
    split(input)[PATH]
  end

  def test_split_special_empty_path_is_slash
    assert_equal("/", path("http://h"))
    assert_equal("/", path("http://h?q"))
    assert_equal("/", path("http://h#f"))
    assert_equal("/", path("http://h:8080"))
  end

  def test_split_special_path
    assert_equal("/", path("http://h/"))
    assert_equal("/a/b", path("http://h/a/b"))
    assert_equal("/a/b/", path("http://h/a/b/"))
  end

  def test_split_special_path_treats_backslash_as_slash
    assert_equal("/a/b", path("http://h\\a\\b"))
    assert_equal("/a/b/c", path("http://h/a\\b/c"))
    assert_equal("/", path("http://h\\"))
  end

  def test_split_path_keeps_empty_segments
    assert_equal("//a//b", path("http://h//a//b"))
    assert_equal("///", path("http://h///"))
  end

  def test_split_single_dot_segments_are_removed
    assert_equal("/a/b", path("http://h/a/./b"))
    assert_equal("/a", path("http://h/./a"))
    assert_equal("/a/", path("http://h/a/./"))
    assert_equal("/a/b", path("http://h/a/././b"))
  end

  def test_split_trailing_single_dot_keeps_slash
    assert_equal("/a/", path("http://h/a/."))
    assert_equal("/", path("http://h/."))
  end

  def test_split_double_dot_segments_remove_previous_segment
    assert_equal("/a/c", path("http://h/a/b/../c"))
    assert_equal("/", path("http://h/a/../"))
    assert_equal("/c", path("http://h/a/b/../../c"))
  end

  def test_split_trailing_double_dot_keeps_slash
    assert_equal("/a/", path("http://h/a/b/.."))
    assert_equal("/", path("http://h/a/.."))
    assert_equal("/", path("http://h/.."))
  end

  def test_split_double_dot_does_not_go_above_root
    assert_equal("/a", path("http://h/../a"))
    assert_equal("/a", path("http://h/../../a"))
    assert_equal("/", path("http://h/a/../../.."))
  end

  def test_split_double_dot_removes_empty_segment
    assert_equal("/a/", path("http://h/a//.."))
    assert_equal("//b", path("http://h//a/../b"))
  end

  def test_split_percent_encoded_single_dot
    assert_equal("/a/b", path("http://h/a/%2e/b"))
    assert_equal("/a/b", path("http://h/a/%2E/b"))
    assert_equal("/a/", path("http://h/a/%2e"))
  end

  def test_split_percent_encoded_double_dot
    [".%2e", "%2e.", "%2e%2e", ".%2E", "%2E.", "%2E%2E", "%2e%2E"].each do |dots|
      assert_equal("/a/c", path("http://h/a/b/#{dots}/c"), dots)
      assert_equal("/a/", path("http://h/a/b/#{dots}"), dots)
    end
  end

  def test_split_segments_that_only_resemble_dots_are_kept
    ["...", "a.", ".a", "..a", "a..", "%2e%2e%2e", "%2", "%2ex", "%2f", ". ", "%252e"].each do |segment|
      assert_equal("/#{segment}/b", path("http://h/#{segment}/b"), segment)
    end
  end

  def test_split_dot_segments_with_backslash_in_special_url
    assert_equal("/b", path("http://h/a\\..\\b"))
    assert_equal("/a/", path("http://h/a\\."))
  end

  def test_split_dot_segments_before_query_and_fragment
    assert_equal(["/", "q"], split("http://h/a/..?q").values_at(PATH, QUERY))
    assert_equal(["/a/", "f"], split("http://h/a/.#f").values_at(PATH, FRAGMENT))
    assert_equal(["/a/", "q"], split("http://h/a/%2e?q").values_at(PATH, QUERY))
  end

  def test_split_dot_segments_in_every_special_scheme
    %w[https ws wss ftp].each do |scheme|
      assert_equal("/b", path("#{scheme}://h/a/../b"), scheme)
      assert_equal("/", path("#{scheme}://h"), scheme)
    end
  end

  def test_split_non_special_empty_path_stays_empty
    assert_equal("", path("foo://h"))
    assert_equal("", path("foo://h?q"))
    assert_equal("/", path("foo://h/"))
  end

  def test_split_non_special_dot_segments
    assert_equal("/b", path("foo://h/a/../b"))
    assert_equal("/a/b", path("foo:/a/./b"))
    assert_equal("/", path("foo:/a/.."))
    assert_equal("/a/", path("foo:/a/."))
    assert_equal("/b", path("foo:/%2e%2e/b"))
  end

  def test_split_non_special_does_not_treat_backslash_as_separator
    assert_equal("/a\\..\\b", path("foo://h/a\\..\\b"))
    assert_equal("/a/..\\b", path("foo://h/a/..\\b"))
  end

  def test_split_hostless_path_starting_with_two_slashes_gets_dot_prefix
    assert_equal("/.//p", path("foo:/..//p"))
    assert_equal("/.//p", path("foo:/.//p"))
    assert_equal("/.//p", path("foo:/a/..//p"))
    assert_equal("/.//", path("foo:/.//"))
  end

  def test_split_no_dot_prefix_when_not_needed
    assert_equal("/", path("foo:/./"))
    assert_equal("/p", path("foo:/./p"))
    assert_equal("//p", path("foo://h/..//p"))
    assert_equal("//p", path("foo:///..//p"))
  end

  def test_parse_dot_prefix_round_trips
    uri = URI::WHATWG_PARSER.parse("foo:/..//p")
    assert_equal("foo:/.//p", uri.to_s)
    assert_equal("foo:/.//p", URI::WHATWG_PARSER.parse(uri.to_s).to_s)
  end

  def test_split_file_path_dot_segments
    # Interim until the file states (and Windows drive letters) are
    # implemented.
    assert_equal("/b", path("file:///a/../b"))
    assert_equal("/b", path("file:/a/../b"))
  end

  def test_split_path_in_linear_time
    pre = ->(n) { "http://h" + "/a/.." * n + "/b" }
    assert_linear_performance((1..4).map { |i| 10**i }, pre: pre) do |uri|
      split(uri)
    end
  end

  # --- host: opaque host ---------------------------------------------
  # https://url.spec.whatwg.org/#concept-opaque-host-parser

  def test_split_opaque_host_is_not_lowercased
    assert_equal("EXAMPLE.com", split("foo://EXAMPLE.com/")[HOST])
  end

  def test_split_opaque_host_is_not_percent_decoded
    assert_equal("ex%61mple", split("foo://ex%61mple/")[HOST])
    assert_equal("a%zzb", split("foo://a%zzb/")[HOST])
    assert_equal("a%", split("foo://a%/")[HOST])
  end

  def test_split_opaque_host_with_forbidden_host_code_point_fails
    ["\x00", " ", "<", ">", "[", "]", "^", "|"].each do |c|
      assert_raise(URI::InvalidURIError, c.dump) { split("foo://a#{c}b/") }
    end
  end

  def test_split_opaque_host_percent_encodes_c0_controls_and_non_ascii
    assert_equal("a%01b", split("foo://a\x01b/")[HOST])
    assert_equal("a%1Fb", split("foo://a\x1Fb/")[HOST])
    assert_equal("a%7Fb", split("foo://a\x7Fb/")[HOST])
    assert_equal("a%C2%80b", split("foo://a\u0080b/")[HOST])
    assert_equal("%C3%A9", split("foo://é/")[HOST])
    assert_equal("%F0%9F%98%80", split("foo://\u{1F600}/")[HOST])
  end

  def test_split_opaque_host_keeps_printable_ascii
    assert_equal("a!~%$b", split("foo://a!~%$b/")[HOST])
  end

  def test_split_authority_in_linear_time
    pre = ->(n) { "http:" + "/" * n + "a@" * n + "host/" }
    assert_linear_performance((1..4).map { |i| 10**i }, pre: pre) do |uri|
      split(uri)
    end
  end
end
