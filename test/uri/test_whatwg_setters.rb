# frozen_string_literal: false
require 'test/unit'
require 'uri'

# Setters of URIs built by URI::WHATWG_PARSER follow the setters of the
# URL Standard (https://url.spec.whatwg.org/#api), except that a value
# the URL Standard ignores raises URI::InvalidComponentError instead of
# leaving the URI silently unchanged.
class URI::TestWHATWGSetters < Test::Unit::TestCase
  def url(str)
    URI::WHATWG_PARSER.parse(str)
  end

  def assert_set(expected, str, attribute, value)
    uri = url(str)
    uri.public_send("#{attribute}=", value)
    assert_equal(expected, uri.to_s, "#{str.dump}.#{attribute} = #{value.inspect}")
  end

  def assert_rejected(str, attribute, value)
    uri = url(str)
    assert_raise(URI::InvalidComponentError, "#{str.dump}.#{attribute} = #{value.inspect}") do
      uri.public_send("#{attribute}=", value)
    end
    assert_equal(url(str).to_s, uri.to_s, "unchanged after #{attribute} = #{value.inspect}")
  end

  # --- which URIs ----------------------------------------------------

  def test_rfc3986_uris_keep_their_setters
    uri = URI::RFC3986_PARSER.parse("http://example.com/")
    assert_raise(URI::InvalidComponentError) { uri.host = "\u{65E5}\u{672C}\u{8A9E}.jp" }
    assert_raise(URI::InvalidComponentError) { uri.port = "8080abc" }
  end

  def test_dup_keeps_the_setters
    uri = url("http://example.com/").dup
    uri.host = "\u{E9}"
    assert_equal("http://xn--9ca/", uri.to_s)
  end

  def test_marshal_keeps_the_setters
    uri = Marshal.load(Marshal.dump(url("http://example.com/")))
    uri.host = "\u{E9}"
    assert_equal("http://xn--9ca/", uri.to_s)
  end

  def test_merged_uri_keeps_the_setters
    uri = url("http://example.com/a") + "b"
    uri.host = "\u{E9}"
    assert_equal("http://xn--9ca/b", uri.to_s)
  end

  def test_merge_bang
    uri = url("http://example.com/a/b")
    uri.merge!("../c?q#f")
    assert_equal("http://example.com/c?q#f", uri.to_s)
  end

  def test_merge_bang_on_an_opaque_path
    uri = url("mailto:x")
    uri.merge!("#f")
    assert_equal("mailto:x#f", uri.to_s)
  end

  def test_merge_bang_on_a_non_special_uri
    uri = url("foo://h/a/b")
    uri.merge!("c")
    assert_equal("foo://h/a/c", uri.to_s)
  end

  def test_the_value_is_returned
    uri = url("http://example.com/")
    assert_equal(8080, (uri.port = 8080))
  end

  # --- scheme= (protocol setter) -------------------------------------

  def test_scheme
    assert_set("https://example.com/", "http://example.com/", :scheme, "https")
    assert_set("https://example.com/", "http://example.com/", :scheme, "HTTPS")
    assert_set("wss://example.com/", "http://example.com/", :scheme, "wss")
    assert_set("bar://h/", "foo://h/", :scheme, "bar")
  end

  def test_scheme_up_to_a_colon
    assert_set("https://example.com/", "http://example.com/", :scheme, "https:foo")
  end

  def test_scheme_strips_tabs_and_newlines
    assert_set("https://example.com/", "http://example.com/", :scheme, "ht\ttp\ns")
  end

  def test_scheme_with_invalid_code_points
    assert_rejected("http://example.com/", :scheme, "")
    assert_rejected("http://example.com/", :scheme, "ht tp")
    assert_rejected("http://example.com/", :scheme, "1http")
    assert_rejected("http://example.com/", :scheme, "\u{E9}")
  end

  def test_scheme_between_special_and_not_special
    assert_rejected("http://example.com/", :scheme, "foo")
    assert_rejected("foo://example.com/", :scheme, "http")
  end

  def test_scheme_file_with_credentials_or_port
    assert_rejected("http://u@example.com/", :scheme, "file")
    assert_rejected("http://example.com:8080/", :scheme, "file")
    assert_set("file://example.com/", "http://example.com/", :scheme, "file")
  end

  def test_scheme_from_file_with_an_empty_host
    assert_rejected("file:///p", :scheme, "http")
    assert_set("http://h/p", "file://h/p", :scheme, "http")
  end

  def test_scheme_drops_the_new_default_port
    uri = url("http://example.com:443/")
    uri.scheme = "https"
    assert_equal("https://example.com/", uri.to_s)
    assert_equal(443, uri.port)
    assert_equal(443, uri.default_port)
  end

  def test_scheme_keeps_another_port
    assert_set("https://example.com:8080/", "http://example.com:8080/", :scheme, "https")
    # http://example.com/ has no port, not port 80.
    assert_set("https://example.com/", "http://example.com/", :scheme, "https")
  end

  def test_scheme_keeps_the_class
    uri = url("http://example.com/")
    uri.scheme = "https"
    assert_kind_of(URI::HTTP, uri)
  end

  # --- user= and password= -------------------------------------------

  def test_user
    assert_set("http://me@example.com/", "http://example.com/", :user, "me")
    assert_set("http://me:p@example.com/", "http://u:p@example.com/", :user, "me")
  end

  def test_user_is_percent_encoded
    assert_set("http://a%20b%40c%3A@example.com/", "http://example.com/", :user, "a b@c:")
    assert_set("http://%C3%A9@example.com/", "http://example.com/", :user, "\u{E9}")
  end

  def test_user_keeps_tabs
    assert_set("http://a%09b@example.com/", "http://example.com/", :user, "a\tb")
  end

  def test_empty_user
    assert_set("http://example.com/", "http://u@example.com/", :user, "")
    assert_set("http://:p@example.com/", "http://u:p@example.com/", :user, "")
    assert_set("http://example.com/", "http://u@example.com/", :user, nil)
  end

  def test_password
    assert_set("http://u:p@example.com/", "http://u@example.com/", :password, "p")
    assert_set("http://:p@example.com/", "http://example.com/", :password, "p")
    assert_set("http://u:a%20b%40%3A@example.com/", "http://u@example.com/", :password, "a b@:")
  end

  def test_empty_password
    assert_set("http://u@example.com/", "http://u:p@example.com/", :password, "")
    assert_set("http://example.com/", "http://:p@example.com/", :password, nil)
  end

  def test_credentials_without_a_host
    assert_rejected("file:///p", :user, "u")
    assert_rejected("file://h/p", :password, "p")
    assert_rejected("foo:///p", :user, "u")
    assert_rejected("foo:/p", :password, "p")
    assert_rejected("mailto:x", :user, "u")
  end

  # --- host= (hostname setter) ---------------------------------------

  def test_host
    assert_set("http://example.org/p", "http://example.com/p", :host, "example.org")
    assert_set("http://example.org/p", "http://example.com/p", :host, "EXAMPLE.org")
    assert_set("http://127.0.0.1/", "http://example.com/", :host, "0x7f.1")
    assert_set("http://[::1]/", "http://example.com/", :host, "[0:0::1]")
  end

  def test_host_to_ascii
    assert_set("http://xn--wgv71a119e.jp/", "http://example.com/", :host, "\u{65E5}\u{672C}\u{8A9E}.jp")
  end

  def test_host_keeps_the_port
    assert_set("http://example.org:8080/", "http://example.com:8080/", :host, "example.org")
  end

  def test_host_with_a_port
    assert_rejected("http://example.com/", :host, "example.org:8080")
  end

  def test_host_up_to_a_path_query_or_fragment
    assert_set("http://a/p", "http://example.com/p", :host, "a/b")
    assert_set("http://a/p", "http://example.com/p", :host, "a?b")
    assert_set("http://a/p", "http://example.com/p", :host, "a#b")
    assert_set("http://a/p", "http://example.com/p", :host, "a\\b")
  end

  def test_host_strips_tabs_and_newlines
    assert_set("http://example.org/", "http://example.com/", :host, "exa\tmple.o\nrg")
  end

  def test_invalid_host
    assert_rejected("http://example.com/", :host, "a b")
    assert_rejected("http://example.com/", :host, "a%")
    assert_rejected("http://example.com/", :host, "[::1")
    assert_rejected("http://example.com/", :host, "a\u{200C}b")
  end

  def test_empty_host_of_a_special_uri
    assert_rejected("http://example.com/", :host, "")
    assert_rejected("http://example.com/", :host, nil)
    assert_rejected("http://example.com/", :host, "/a")
  end

  def test_host_of_a_non_special_uri
    assert_set("foo://example.org/p", "foo://example.com/p", :host, "example.org")
    assert_set("foo://%C3%A9/p", "foo://example.com/p", :host, "\u{E9}")
    assert_rejected("foo://example.com/p", :host, "a\\b")
  end

  def test_empty_host_of_a_non_special_uri
    assert_set("foo:///p", "foo://example.com/p", :host, "")
    assert_rejected("foo://u@example.com/p", :host, "")
    assert_rejected("foo://example.com:8080/p", :host, "")
  end

  def test_host_of_an_opaque_path
    assert_rejected("mailto:x", :host, "example.com")
  end

  def test_host_of_a_file_uri
    assert_set("file://example.com/p", "file:///p", :host, "example.com")
    assert_set("file:///p", "file://example.com/p", :host, "localhost")
    assert_set("file:///p", "file://example.com/p", :host, "")
    assert_rejected("file:///p", :host, "example.com:8080")
  end

  def test_hostname_wraps_ipv6
    uri = url("http://example.com/")
    uri.hostname = "::1"
    assert_equal("http://[::1]/", uri.to_s)
  end

  # --- port= ---------------------------------------------------------

  def test_port
    assert_set("http://example.com:8080/", "http://example.com/", :port, 8080)
    assert_set("http://example.com:8080/", "http://example.com/", :port, "8080")
    assert_set("http://example.com:0/", "http://example.com/", :port, 0)
  end

  def test_port_boundaries
    assert_set("http://example.com:65535/", "http://example.com/", :port, 65535)
    assert_rejected("http://example.com/", :port, 65536)
    assert_rejected("http://example.com/", :port, "99999999999999999999")
  end

  def test_port_up_to_a_non_digit
    assert_set("http://example.com:8080/", "http://example.com/", :port, "8080abc")
    assert_set("http://example.com:8080/", "http://example.com/", :port, "8080/x")
  end

  def test_port_strips_tabs_and_newlines
    assert_set("http://example.com:8080/", "http://example.com/", :port, "80\t8\n0")
  end

  def test_port_without_digits
    assert_rejected("http://example.com/", :port, "abc")
    assert_rejected("http://example.com/", :port, " 8080")
    assert_rejected("http://example.com/", :port, -1)
  end

  def test_default_port
    uri = url("http://example.com:8080/")
    uri.port = 80
    assert_equal("http://example.com/", uri.to_s)
    assert_equal(80, uri.port)
  end

  def test_empty_port
    assert_set("http://example.com/", "http://example.com:8080/", :port, "")
    assert_set("http://example.com/", "http://example.com:8080/", :port, nil)
    assert_set("foo://example.com/", "foo://example.com:8080/", :port, nil)
  end

  def test_port_of_only_tabs_and_newlines
    # Only the empty string removes the port; tabs and newlines are
    # removed afterwards and leave no digits.
    assert_rejected("http://example.com:8080/", :port, "\n\t")
  end

  def test_port_without_a_host
    assert_rejected("file://example.com/", :port, 8080)
    assert_rejected("foo:///p", :port, 8080)
    assert_rejected("foo:/p", :port, 8080)
  end

  # --- path= (pathname setter) ---------------------------------------

  def test_path
    assert_set("http://example.com/a/b", "http://example.com/x", :path, "/a/b")
    assert_set("http://example.com/a", "http://example.com/x", :path, "a")
    assert_set("http://example.com/", "http://example.com/x", :path, "")
  end

  def test_path_is_normalized_and_percent_encoded
    assert_set("http://example.com/b", "http://example.com/x", :path, "/a/../b")
    assert_set("http://example.com/a%20b", "http://example.com/x", :path, "a b")
    assert_set("http://example.com/a%3Fb%23c", "http://example.com/x", :path, "a?b#c")
  end

  def test_path_keeps_query_and_fragment
    assert_set("http://example.com/a?q#f", "http://example.com/x?q#f", :path, "a")
  end

  def test_path_backslashes
    assert_set("http://example.com/a/b", "http://example.com/x", :path, "\\a\\b")
    assert_set("foo://h/\\a", "foo://h/x", :path, "\\a")
  end

  def test_path_of_a_non_special_uri
    assert_set("foo://h/a", "foo://h/x", :path, "a")
    assert_set("foo://h", "foo://h/x", :path, "")
    assert_set("foo:/", "foo:/x", :path, "")
    assert_set("foo:/.//a", "foo:/x", :path, "//a")
  end

  def test_path_of_a_file_uri
    assert_set("file:///C:/a", "file:///x", :path, "C|/a")
  end

  def test_path_of_an_opaque_path
    assert_rejected("mailto:x", :path, "y")
  end

  # --- query= (search setter) ----------------------------------------

  def test_query
    assert_set("http://example.com/?a=b", "http://example.com/", :query, "a=b")
    assert_set("http://example.com/?a%20b", "http://example.com/?x", :query, "a b")
    assert_set("http://example.com/?", "http://example.com/?x", :query, "")
  end

  def test_query_keeps_a_leading_question_mark
    assert_set("http://example.com/??a", "http://example.com/", :query, "?a")
  end

  def test_query_percent_encoding
    assert_set("http://example.com/?%27%23", "http://example.com/", :query, "'#")
    assert_set("foo://h/?'%23", "foo://h/", :query, "'#")
    assert_set("http://example.com/?%C3%A9", "http://example.com/", :query, "\u{E9}")
  end

  def test_query_strips_tabs_and_newlines
    assert_set("http://example.com/?ab", "http://example.com/", :query, "a\tb\n")
  end

  def test_query_removed
    assert_set("http://example.com/#f", "http://example.com/?q#f", :query, nil)
  end

  def test_query_of_an_opaque_path
    assert_set("mailto:x?a", "mailto:x", :query, "a")
    assert_set("mailto:x", "mailto:x?q", :query, nil)
  end

  def test_query_removed_from_an_opaque_path_ending_with_a_space
    # The space before "?" was encoded when parsed, so it stays.
    assert_set("sc:a%20", "sc:a ?q", :query, nil)
  end

  # --- fragment= (hash setter) ---------------------------------------

  def test_fragment
    assert_set("http://example.com/#a", "http://example.com/", :fragment, "a")
    assert_set("http://example.com/#a%20b%60", "http://example.com/#x", :fragment, "a b`")
    assert_set("http://example.com/#a#b", "http://example.com/", :fragment, "a#b")
    assert_set("http://example.com/#", "http://example.com/#x", :fragment, "")
  end

  def test_fragment_strips_tabs_and_newlines
    assert_set("http://example.com/#ab", "http://example.com/", :fragment, "a\tb\n")
  end

  def test_fragment_removed
    assert_set("http://example.com/?q", "http://example.com/?q#f", :fragment, nil)
  end

  def test_fragment_removed_from_an_opaque_path_ending_with_a_space
    assert_set("sc:a%20", "sc:a #f", :fragment, nil)
  end
end
