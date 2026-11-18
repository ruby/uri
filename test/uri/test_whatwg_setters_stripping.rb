# frozen_string_literal: false
require 'test/unit'
require 'uri'

# A port of WPT url/url-setters-stripping.any.js: which C0 controls the
# setters of a WHATWG URI strip (tab, LF and CR) and which they keep or
# reject, at the start, in the middle and at the end of the value.
#
# The cases of the host setter (URI has no setter for a host with a
# port) and of searchParams (URI has no equivalent) are not ported. A
# value rejected with URI::InvalidComponentError leaves the URI
# unchanged, as the URL Standard does.
class URI::TestWHATWGSettersStripping < Test::Unit::TestCase
  SCHEMES = ["https", "wpt++"].freeze
  # As in WPT, only these C0 controls are tested: user agents treat the
  # others like U+0000 or U+001F.
  CODE_POINTS = [0x00, 0x09, 0x0A, 0x0D, 0x1F].freeze
  STRIPPED = [0x09, 0x0A, 0x0D].freeze

  def self.url_string(scheme: "https", username: "username", password: "password", host: "host",
                      port: "8000", pathname: "path", search: "query", hash: "fragment")
    "#{scheme}://#{username}:#{password}@#{host}:#{port}/#{pathname}?#{search}##{hash}"
  end

  # encodeURIComponent of a C0 control.
  def self.encode(char)
    format("%%%02X", char.ord)
  end

  def self.reference(code_point)
    format("U+%04X", code_point)
  end

  def self.affixed(char)
    [["leading", char + "test"], ["middle", "te" + char + "st"], ["trailing", "test" + char]]
  end

  # Defines a test that sets +attribute+ to +value+ on the URL of
  # +scheme+, expecting the URL of +expected_parts+ afterwards.
  def self.define_case(name, scheme, attribute, value, expected_parts)
    define_method("test_#{name} (#{scheme}:)") do
      uri = URI::WHATWG_PARSER.parse(self.class.url_string(scheme: scheme))
      begin
        uri.public_send("#{attribute}=", value)
      rescue URI::InvalidComponentError
        # Left unchanged.
      end
      assert_equal(self.class.url_string(scheme: scheme, **expected_parts), uri.to_s)
    end
  end

  SCHEMES.each do |scheme|
    CODE_POINTS.each do |code_point|
      char = code_point.chr
      stripped = STRIPPED.include?(code_point)
      ref = reference(code_point)
      new_scheme = scheme == "https" ? "http" : "wpt--"
      expected_scheme = stripped ? new_scheme : scheme

      define_case("scheme with leading #{ref}", scheme, :scheme, char + new_scheme, scheme: expected_scheme)
      define_case("scheme with #{ref} before inserted colon", scheme, :scheme, new_scheme + char, scheme: expected_scheme)

      # No stripping.
      [[:user, :username], [:password, :password]].each do |attribute, part|
        affixed(char).each do |type, value|
          expected = value.sub(char, encode(char))
          define_case("#{attribute} with #{type} #{ref}", scheme, attribute, value, part => expected)
        end
      end

      affixed(char).each do |type, value|
        expected =
          if code_point == 0x00 || (scheme == "https" && code_point == 0x1F)
            "host"
          elsif stripped
            "test"
          else
            value.sub(char, scheme == "https" ? char : encode(char))
          end
        define_case("host with #{type} #{ref}", scheme, :host, value, host: expected)
      end

      define_case("port with leading #{ref}", scheme, :port, char + "9000", port: stripped ? "9000" : "8000")
      define_case("port with middle #{ref}", scheme, :port, "90" + char + "00", port: stripped ? "9000" : "90")
      define_case("port with trailing #{ref}", scheme, :port, "9000" + char, port: "9000")

      [[:path, :pathname], [:query, :search], [:fragment, :hash]].each do |attribute, part|
        affixed(char).each do |type, value|
          expected = stripped ? "test" : value.sub(char, encode(char))
          define_case("#{attribute} with #{type} #{ref}", scheme, attribute, value, part => expected)
        end
      end
    end
  end
end
