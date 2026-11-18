# frozen_string_literal: true
require_relative "whatwg_parser/punycode"
require_relative "whatwg_parser/nfc"
require_relative "whatwg_parser/idna"

# A require in a non-main Ractor is not safe before Ruby 4.0, which runs
# it in the main Ractor. Where Ractors are available before that, the
# Unicode data, otherwise loaded on first use, is loaded here.
if defined?(Ractor) && (RUBY_VERSION.split(".").map(&:to_i) <=> [4, 0]) < 0
  URI::WHATWG_Parser::IDNA.load_data
  URI::WHATWG_Parser::NFC.load_tables
end

module URI
  # A parser for the WHATWG URL Standard (https://url.spec.whatwg.org/).
  #
  # It is not the default parser. Use it explicitly with
  # URI::WHATWG_PARSER.parse, or switch to it with
  # <tt>URI.parser = URI::WHATWG_PARSER</tt>.
  class WHATWG_Parser # :nodoc:
    # A URL record (https://url.spec.whatwg.org/#concept-url). +path+ is an
    # Array of segments, or a String for an opaque path. +port+ is an
    # Integer, or nil when it is empty or the scheme's default port.
    URLRecord = Struct.new(:scheme, :username, :password, :host, :port, :path, :query, :fragment) # :nodoc:

    # Returns [scheme, userinfo, host, port, registry, path, opaque, query,
    # fragment], the same contract as URI::RFC3986_Parser#split.
    def split(uri) # :nodoc:
      begin
        uri = uri.to_str
      rescue NoMethodError
        raise InvalidURIError, "bad URI (is not URI?): #{uri.inspect}"
      end
      to_components(basic_parse(uri))
    end

    def parse(uri) # :nodoc:
      build(split(uri))
    end

    # Resolves each of +uris+ after the first against the result so far,
    # as the URL Standard's basic URL parser does with a base URL.
    def join(*uris) # :nodoc:
      uris[1..-1].inject(convert_to_uri(uris[0])) do |base, uri|
        reference = uri.is_a?(URI::Generic) ? uri.to_s : String.try_convert(uri)
        raise ArgumentError, "bad argument (expected URI object or URI string)" unless reference
        build(to_components(basic_parse(reference, url_record(base))))
      end
    end

    # Component syntax used by URI::Generic's setters is shared with
    # URI::RFC3986_Parser.
    def regexp # :nodoc:
      RFC3986_PARSER.regexp
    end

    # Compatibility for RFC2396 parser
    def extract(str, schemes = nil, &block) # :nodoc:
      warn "URI::WHATWG_PARSER.extract is obsolete. Use URI::RFC2396_PARSER.extract explicitly.", uplevel: 1 if $VERBOSE
      RFC2396_PARSER.extract(str, schemes, &block)
    end

    # Compatibility for RFC2396 parser
    def make_regexp(schemes = nil) # :nodoc:
      warn "URI::WHATWG_PARSER.make_regexp is obsolete. Use URI::RFC2396_PARSER.make_regexp explicitly.", uplevel: 1 if $VERBOSE
      RFC2396_PARSER.make_regexp(schemes)
    end

    # Compatibility for RFC2396 parser
    def escape(str, unsafe = nil) # :nodoc:
      warn "URI::WHATWG_PARSER.escape is obsolete. Use URI::RFC2396_PARSER.escape explicitly.", uplevel: 1 if $VERBOSE
      unsafe ? RFC2396_PARSER.escape(str, unsafe) : RFC2396_PARSER.escape(str)
    end

    # Compatibility for RFC2396 parser
    def unescape(str, escaped = nil) # :nodoc:
      warn "URI::WHATWG_PARSER.unescape is obsolete. Use URI::RFC2396_PARSER.unescape explicitly.", uplevel: 1 if $VERBOSE
      escaped ? RFC2396_PARSER.unescape(str, escaped) : RFC2396_PARSER.unescape(str)
    end

    private

    # basic URL parser, with an optional +base+ URL record.
    def basic_parse(input, base = nil)
      input = preprocess(to_utf8(input))

      scheme, rest = parse_scheme(input)
      relative = scheme.nil?
      if relative
        # no scheme state
        raise InvalidURIError, "missing scheme: #{input.dump}" unless base
        if base.path.is_a?(String) && !rest.start_with?("#")
          raise InvalidURIError, "relative reference to a URL with an opaque path: #{input.dump}"
        end
        scheme = base.scheme
        # The file state handles a reference relative to a file URL.
        relative = false if scheme == "file"
      elsif base && scheme == base.scheme && scheme != "file" && SPECIAL_SCHEMES.key?(scheme)
        # special relative or authority state: two slashes start an
        # authority; anything else is relative to the base.
        relative = !rest.match?(TWO_SLASHES)
      end

      # Every state before the fragment state ends at the first "#", and
      # every state before the query state at the first "?" before it.
      rest, query, fragment = split_query_and_fragment(rest)

      url = URLRecord.new(scheme, "", "", nil, nil, [], nil, nil)
      special = SPECIAL_SCHEMES.key?(scheme)
      # query state and fragment state
      url.query = query && utf8_percent_encode(query, special ? SPECIAL_QUERY_PERCENT_ENCODE_SET : QUERY_PERCENT_ENCODE_SET)
      url.fragment = fragment && utf8_percent_encode(fragment, FRAGMENT_PERCENT_ENCODE_SET)

      if relative
        parse_relative(url, rest, base, special)
      elsif scheme == "file"
        parse_file(url, rest, base&.scheme == "file" ? base : nil)
      elsif special
        # special authority slashes state and special authority ignore
        # slashes state: skip any run of "/" or "\\".
        parse_authority(url, rest.sub(SPECIAL_AUTHORITY_SLASHES, ""), true)
      elsif rest.start_with?("/")
        # path or authority state
        if rest.start_with?("//")
          parse_authority(url, rest[2..-1], false)
        else
          url.path = parse_path(rest, false)
        end
      else
        url.path = parse_opaque_path(rest, query || fragment)
      end
      url
    end

    # relative state and relative slash state. +rest+ is the input after
    # any scheme, without query and fragment, which +url+ already has.
    def parse_relative(url, rest, base, special)
      if base.path.is_a?(String)
        # no scheme state, for a base with an opaque path: only a
        # fragment may be given.
        url.path = base.path
        url.query = base.query
        return
      end

      if rest.start_with?("/") || (special && rest.start_with?("\\"))
        # relative slash state
        if special && rest.match?(TWO_SLASHES)
          return parse_authority(url, rest.sub(SPECIAL_AUTHORITY_SLASHES, ""), true)
        elsif !special && rest.start_with?("//")
          return parse_authority(url, rest[2..-1], false)
        end
        copy_authority(url, base)
        url.path = parse_path(rest, special)
      else
        copy_authority(url, base)
        if rest.empty?
          # c is EOF, "?" or "#": the base path, and the base query unless
          # a query is given.
          url.path = base.path.dup
          url.query = base.query if url.query.nil?
        else
          path = base.path.dup
          shorten(path, false)
          url.path = parse_path(rest, special, path)
        end
      end
    end

    # file state, file slash state and file host state. +base+ is the
    # base URL if it is a file URL. +rest+ is the input after any scheme,
    # without query and fragment, which +url+ already has.
    def parse_file(url, rest, base)
      url.host = ""
      if rest.start_with?("/", "\\")
        rest = rest[1..-1]
        # file slash state
        return parse_file_host(url, rest[1..-1]) if rest.start_with?("/", "\\")
        if base
          url.host = base.host
          if !starts_with_windows_drive_letter?(rest) && normalized_windows_drive_letter?(base.path[0])
            url.path = [base.path[0]]
          end
        end
        url.path = parse_path(rest, true, url.path, file: true, start: false)
      elsif base
        url.host = base.host
        url.path = base.path.dup
        if rest.empty?
          # c is EOF, "?" or "#": the base query too, unless a query is given.
          url.query = base.query if url.query.nil?
        else
          if starts_with_windows_drive_letter?(rest)
            url.path = []
          else
            shorten(url.path, true)
          end
          url.path = parse_path(rest, true, url.path, file: true, start: false)
        end
      else
        url.path = parse_path(rest, true, [], file: true, start: false)
      end
    end

    # file host state. +rest+ starts after the two slashes.
    def parse_file_host(url, rest)
      host_end = rest.index(SPECIAL_PATH_SEPARATOR) || rest.size
      buffer = rest[0, host_end]
      if windows_drive_letter?(buffer)
        # The buffer is not a host but the start of the path.
        url.path = parse_path(rest, true, [], file: true, start: false)
        return
      end
      url.host = file_host(buffer)
      url.path = parse_path(rest[host_end..-1], true, [], file: true)
    end

    # The host of a file URL, which is empty for an empty +buffer+ or
    # localhost.
    def file_host(buffer)
      return "" if buffer.empty?
      host = parse_host(buffer, true)
      host == "localhost" ? "" : host
    end

    # https://url.spec.whatwg.org/#windows-drive-letter
    def windows_drive_letter?(string)
      string.match?(WINDOWS_DRIVE_LETTER)
    end

    def normalized_windows_drive_letter?(string)
      string.to_s.match?(NORMALIZED_WINDOWS_DRIVE_LETTER)
    end

    # https://url.spec.whatwg.org/#start-with-a-windows-drive-letter
    def starts_with_windows_drive_letter?(string)
      string.match?(STARTS_WITH_WINDOWS_DRIVE_LETTER)
    end

    # shorten a URL's path: a file URL's path that is only a normalized
    # Windows drive letter is kept.
    def shorten(path, file)
      return if file && path.size == 1 && normalized_windows_drive_letter?(path[0])
      path.pop
    end

    def copy_authority(url, base)
      url.username = base.username
      url.password = base.password
      url.host = base.host
      url.port = base.port
    end

    # Creates the URI object for +components+.
    #
    # Scheme-specific classes are used only for the schemes in
    # SCHEMES_WITH_CLASS, whose rules agree with the URL Standard; any
    # other scheme gets URI::Generic. (URI::FTP rewrites the path by RFC
    # 1738 rules, URI::MailTo validates the opaque part, and URI::LDAP
    # omits its default port.)
    #
    # The query is set afterwards with URI::Generic#set_query, as the
    # constructor would re-escape it by RFC 3986 rules with
    # URI::Generic#query=.
    def build(components)
      *components, query, fragment = components
      arguments = [*components, nil, fragment, self]
      uri = SCHEMES_WITH_CLASS.include?(components[0]) ? URI.for(*arguments) : Generic.new(*arguments)
      uri.__send__(:set_query, query) if query
      uri.__send__(:whatwg_url!)
      uri
    end

    # The URL record as the components of URI::RFC3986_Parser#split.
    def to_components(url)
      userinfo =
        if url.password.empty?
          url.username.empty? ? nil : url.username
        else
          "#{url.username}:#{url.password}"
        end
      port = url.port&.to_s

      if url.path.is_a?(String)
        # The query is kept inside opaque, as URI::RFC3986_Parser does,
        # since URI::Generic does not serialize the query of an opaque URI.
        opaque = url.query ? "#{url.path}?#{url.query}" : url.path
        [url.scheme, userinfo, url.host, port, nil, nil, opaque, nil, url.fragment]
      else
        path = serialize_path(url.path)
        # The URL serializer writes "/." before a hostless path that would
        # otherwise start with "//", so it is not mistaken for an
        # authority when reparsed.
        path = "/.#{path}" if url.host.nil? && url.path.size > 1 && url.path[0].empty?
        [url.scheme, userinfo, url.host, port, nil, path, nil, url.query, url.fragment]
      end
    end

    # The URL record of +uri+. The components of a URI that this parser
    # built are those of a URL record, already serialized, so the record
    # is rebuilt from them, the reverse of #to_components; any other URI
    # is parsed. The strings are copied, as a URI built from the record
    # must not share them with +uri+.
    def url_record(uri)
      return basic_parse(uri.to_s) unless uri.__send__(:whatwg_url?)

      scheme = uri.scheme.dup
      port = uri.port == SPECIAL_SCHEMES[scheme] ? nil : uri.port
      url = URLRecord.new(scheme, uri.user.to_s.dup, uri.password.to_s.dup, uri.host&.dup, port, nil,
                          uri.query&.dup, uri.fragment&.dup)
      if uri.opaque
        path, question, query = uri.opaque.partition("?")
        url.path = path
        url.query = question.empty? ? nil : query
      else
        path = uri.path
        path = path[2..-1] if url.host.nil? && path.start_with?("/.//")
        # Each segment follows a "/".
        url.path = path.split("/", -1).drop(1)
      end
      url
    end

    def split_query_and_fragment(rest)
      rest, hash, fragment = rest.partition("#")
      fragment = nil if hash.empty?
      rest, question, query = rest.partition("?")
      query = nil if question.empty?
      [rest, query, fragment]
    end

    # opaque path state: code points in the C0 control percent-encode set
    # are percent-encoded, and a space right before "?" or "#" (when
    # +followed+ by a query or fragment) is written as "%20".
    def parse_opaque_path(input, followed)
      opaque = utf8_percent_encode(input, C0_CONTROL_PERCENT_ENCODE_SET)
      followed ? opaque.sub(TRAILING_SPACE, "%20") : opaque
    end

    # https://url.spec.whatwg.org/#special-scheme
    SPECIAL_SCHEMES = {
      "ftp" => 21,
      "file" => nil,
      "http" => 80,
      "https" => 443,
      "ws" => 80,
      "wss" => 443,
    }.freeze # :nodoc:

    SCHEMES_WITH_CLASS = %w[http https ws wss file].freeze # :nodoc:

    # scheme start state and scheme state: an ASCII alpha followed by
    # ASCII alphanumerics, "+", "-" or ".", up to the first ":".
    SCHEME = /\A[A-Za-z][A-Za-z0-9+\-.]*:/ # :nodoc:

    SPECIAL_AUTHORITY_SLASHES = %r{\A[/\\]*} # :nodoc:
    # Two of "/" or "\\", which start an authority in a special URL.
    TWO_SLASHES = %r{\A[/\\]{2}} # :nodoc:
    WINDOWS_DRIVE_LETTER = /\A[A-Za-z][:|]\z/ # :nodoc:
    NORMALIZED_WINDOWS_DRIVE_LETTER = /\A[A-Za-z]:\z/ # :nodoc:
    STARTS_WITH_WINDOWS_DRIVE_LETTER = %r{\A[A-Za-z][:|](?:\z|[/\\?#])} # :nodoc:
    AUTHORITY_END = %r{[/?#]} # :nodoc:
    SPECIAL_AUTHORITY_END = %r{[/?#\\]} # :nodoc:

    # https://url.spec.whatwg.org/#forbidden-host-code-point
    FORBIDDEN_HOST_CODE_POINT = %r{[\x00\t\n\r #/:<>?@\[\\\]^|]} # :nodoc:
    # https://url.spec.whatwg.org/#forbidden-domain-code-point
    # (forbidden host code points, C0 controls, "%" and U+007F DELETE)
    FORBIDDEN_DOMAIN_CODE_POINT = %r{[\x00-\x20#/:<>?@\[\\\]^|%\x7F]} # :nodoc:
    # Percent-encode sets, https://url.spec.whatwg.org/#percent-encoded-bytes.
    # Each one adds to the previous one; [^\x00-\x7E] is every code point
    # greater than U+007E.
    #
    # C0 controls and code points greater than U+007E
    C0_CONTROL_PERCENT_ENCODE_SET = /[\x00-\x1F]|[^\x00-\x7E]/ # :nodoc:
    # + U+0020 SPACE, U+0022 ("), U+003C (<), U+003E (>), U+0060 (`)
    FRAGMENT_PERCENT_ENCODE_SET = /[\x00-\x20"<>`]|[^\x00-\x7E]/ # :nodoc:
    # C0 control set + U+0020 SPACE, U+0022 ("), U+0023 (#), U+003C (<), U+003E (>)
    QUERY_PERCENT_ENCODE_SET = /[\x00-\x20"#<>]|[^\x00-\x7E]/ # :nodoc:
    # query set + U+0027 (')
    SPECIAL_QUERY_PERCENT_ENCODE_SET = /[\x00-\x20"#<>']|[^\x00-\x7E]/ # :nodoc:
    # query set + U+003F (?), U+005E (^), U+0060 (`), U+007B ({), U+007D (})
    PATH_PERCENT_ENCODE_SET = /[\x00-\x20"#<>?^`{}]|[^\x00-\x7E]/ # :nodoc:
    # path set + U+002F (/), U+003A (:), U+003B (;), U+003D (=), U+0040 (@),
    # U+005B ([) to U+005E (^), U+007C (|)
    USERINFO_PERCENT_ENCODE_SET = %r{[\x00-\x20"#<>?^`{}/:;=@\[\\\]|]|[^\x00-\x7E]} # :nodoc:
    PERCENT_ENCODED_BYTE = /%[0-9A-Fa-f]{2}/ # :nodoc:

    ASCII_DIGITS = /\A[0-9]+\z/ # :nodoc:
    ASCII_DIGIT = /\A[0-9]\z/ # :nodoc:
    ASCII_HEX_DIGIT = /\A[0-9A-Fa-f]\z/ # :nodoc:
    IPV4_NUMBER_DIGITS = {
      8 => /\A[0-7]+\z/,
      10 => /\A[0-9]+\z/,
      16 => /\A[0-9A-Fa-f]+\z/,
    }.freeze # :nodoc:
    LEADING_ZEROS = /\A0+/ # :nodoc:
    # 2**32 - 1 has 11 digits in octal, 10 in decimal and 8 in hex.
    IPV4_NUMBER_MAX_DIGITS = 11 # :nodoc:

    MAX_PORT = 2**16 - 1 # :nodoc:
    PORT_MAX_DIGITS = MAX_PORT.to_s.size # :nodoc:

    TRAILING_SPACE = / \z/ # :nodoc:
    SPECIAL_PATH_SEPARATOR = %r{[/\\]} # :nodoc:
    DOUBLE_DOT_SEGMENTS = ["..", ".%2e", "%2e.", "%2e%2e"].freeze # :nodoc:

    NOT_C0_CONTROL_OR_SPACE = /[^\x00-\x20]/ # :nodoc:
    ASCII_TAB_OR_NEWLINE = "\t\n\r" # :nodoc:

    # The URL Standard parses a string of Unicode scalar values.
    def to_utf8(input)
      raise InvalidURIError, "invalid byte sequence: #{input.dump}" unless input.valid_encoding?
      input.encode(Encoding::UTF_8)
    rescue EncodingError
      raise InvalidURIError, "cannot be converted to UTF-8: #{input.dump}"
    end

    # basic URL parser, steps 1-3: strip leading and trailing C0 control
    # or space, then remove all ASCII tab or newline.
    #
    # The ends are found with index/rindex rather than an anchored
    # regexp such as /[\x00-\x20]+\z/, which backtracks quadratically on
    # long inner runs of spaces.
    def preprocess(input)
      first = input.index(NOT_C0_CONTROL_OR_SPACE) or return +""
      last = input.rindex(NOT_C0_CONTROL_OR_SPACE)
      input[first..last].delete(ASCII_TAB_OR_NEWLINE)
    end

    # scheme start state and scheme state. Returns the ASCII-lowercased
    # scheme and the rest of +input+ after the ":", or nil and +input+
    # when there is no scheme.
    def parse_scheme(input)
      scheme = input[SCHEME] or return [nil, input]
      [scheme.chop.downcase, input[scheme.size..-1]]
    end

    # authority state, host state, port state and the path after them.
    # +rest+ starts right after the slashes preceding the authority.
    def parse_authority(url, rest, special)
      authority_end = rest.index(special ? SPECIAL_AUTHORITY_END : AUTHORITY_END) || rest.size
      authority = rest[0, authority_end]
      remainder = rest[authority_end..-1]

      url.username, url.password, host_and_port = split_userinfo(authority)
      host, port = split_host_and_port(host_and_port)
      raise InvalidURIError, "missing host: #{rest.dump}" if host.empty? && (special || port)
      url.host = host.empty? ? host : parse_host(host, special)
      url.port = parse_port(port, url.scheme) if port
      url.path = parse_path(remainder, special)
    end

    # path start state (unless +start+ is false) and path state. Returns
    # the list of path segments, appended to +path+ (the shortened base
    # path of a relative reference). +file+ applies the Windows drive
    # letter rules of file URLs.
    def parse_path(input, special, path = [], file: false, start: true)
      separator = special ? SPECIAL_PATH_SEPARATOR : "/"
      if start
        # path start state: a special URL always has a path, even an
        # empty one; another URL has one only if anything follows the
        # authority.
        return path if input.empty? && !special
        input = input[1..-1] if input.start_with?("/") || (special && input.start_with?("\\"))
      end

      buffers = input.split(separator, -1)
      buffers = [""] if buffers.empty?
      buffers.each_with_index.with_object(path) do |(buffer, i), segments|
        buffer = utf8_percent_encode(buffer, PATH_PERCENT_ENCODE_SET)
        # Whether this segment is ended by the end of the path rather
        # than by a separator.
        last = i == buffers.size - 1
        if double_dot_segment?(buffer)
          shorten(segments, file)
          segments << "" if last
        elsif single_dot_segment?(buffer)
          segments << "" if last
        else
          if file && segments.empty? && windows_drive_letter?(buffer)
            buffer = "#{buffer[0]}:"
          end
          segments << buffer
        end
      end
    end

    def serialize_path(segments)
      segments.map { |segment| "/#{segment}" }.join
    end

    # https://url.spec.whatwg.org/#single-dot-path-segment
    def single_dot_segment?(buffer)
      buffer == "." || buffer.downcase == "%2e"
    end

    # https://url.spec.whatwg.org/#double-dot-path-segment
    def double_dot_segment?(buffer)
      DOUBLE_DOT_SEGMENTS.include?(buffer.downcase)
    end

    # authority state, on "@": the last "@" ends the userinfo, and every
    # earlier one is part of it, as "%40". The first ":" separates the
    # username from the password. Returns the percent-encoded username
    # and password, and the rest.
    def split_userinfo(authority)
      at = authority.rindex("@") or return ["", "", authority]
      host_and_port = authority[at + 1..-1]
      raise InvalidURIError, "missing host after userinfo: #{authority.dump}" if host_and_port.empty?

      username, _, password = authority[0, at].gsub("@", "%40").partition(":")
      [utf8_percent_encode(username, USERINFO_PERCENT_ENCODE_SET),
       utf8_percent_encode(password, USERINFO_PERCENT_ENCODE_SET),
       host_and_port]
    end

    # host state: the first ":" outside "[...]" starts the port.
    def split_host_and_port(host_and_port)
      inside_brackets = false
      host_and_port.each_char.with_index do |c, i|
        case c
        when "[" then inside_brackets = true
        when "]" then inside_brackets = false
        when ":"
          return [host_and_port[0, i], host_and_port[i + 1..-1]] unless inside_brackets
        end
      end
      [host_and_port, nil]
    end

    # port state. +input+ is everything between the ":" and the end of
    # the authority. Returns the port, or nil when it is empty or the
    # scheme's default port.
    #
    # A port with more significant digits than 65535 has is rejected
    # without converting it.
    def parse_port(input, scheme)
      return nil if input.empty?
      raise InvalidURIError, "invalid port: #{input.dump}" unless input.match?(ASCII_DIGITS)

      port = port_number(input)
      raise InvalidURIError, "port out of range: #{input.dump}" if port > MAX_PORT
      port == SPECIAL_SCHEMES[scheme] ? nil : port
    end

    # The number that +digits+, ASCII digits, represent. A number with
    # more significant digits than MAX_PORT is MAX_PORT + 1 instead of
    # being converted.
    def port_number(digits)
      digits = digits.sub(LEADING_ZEROS, "")
      digits.size > PORT_MAX_DIGITS ? MAX_PORT + 1 : digits.to_i
    end

    # host parser
    def parse_host(input, special)
      if input.start_with?("[")
        raise InvalidURIError, "unterminated IPv6 address: #{input.dump}" unless input.end_with?("]")
        return "[#{serialize_ipv6(parse_ipv6(input[1..-2]))}]"
      end
      return parse_opaque_host(input) unless special

      ascii_domain = domain_to_ascii(percent_decode(input))
      raise InvalidURIError, "invalid host: #{input.dump}" unless ascii_domain
      return serialize_ipv4(parse_ipv4(ascii_domain)) if ends_in_a_number?(ascii_domain)
      ascii_domain
    end

    # domain to ASCII (the domain parser) with beStrict false. Returns nil
    # on failure.
    #
    # An ASCII domain is lowercased without Unicode ToASCII, so an "xn--"
    # label in it is not validated.
    def domain_to_ascii(domain)
      result = domain.ascii_only? ? domain.downcase : IDNA.to_ascii(domain)
      return nil if result.nil? || result.empty? || result.match?(FORBIDDEN_DOMAIN_CODE_POINT)
      result
    end

    # ends in a number checker
    def ends_in_a_number?(input)
      parts = input.split(".", -1)
      if parts.last.empty?
        return false if parts.size == 1
        parts.pop
      end
      last = parts.last
      return true if last.match?(ASCII_DIGITS)
      !parse_ipv4_number(last).nil?
    end

    # IPv4 parser
    def parse_ipv4(input)
      parts = input.split(".", -1)
      parts.pop if parts.last.empty? && parts.size > 1
      raise InvalidURIError, "invalid IPv4 address: #{input.dump}" if parts.size > 4

      numbers = parts.map do |part|
        parse_ipv4_number(part) or raise InvalidURIError, "invalid IPv4 address: #{input.dump}"
      end
      last = numbers.pop
      if numbers.any? { |n| n > 255 } || last >= 256**(4 - numbers.size)
        raise InvalidURIError, "invalid IPv4 address: #{input.dump}"
      end

      numbers.each_with_index.inject(last) { |ipv4, (n, i)| ipv4 + n * 256**(3 - i) }
    end

    # IPv4 number parser. Returns nil on failure.
    #
    # Any value of 2**32 or more makes the IPv4 parser fail, so a number
    # with more significant digits than 2**32 - 1 has in any radix is
    # returned as 2**32 instead of being converted.
    def parse_ipv4_number(input)
      return nil if input.empty?

      radix = 10
      if input.size >= 2 && input.start_with?("0x", "0X")
        input = input[2..-1]
        radix = 16
      elsif input.size >= 2 && input.start_with?("0")
        input = input[1..-1]
        radix = 8
      end
      return 0 if input.empty?
      return nil unless input.match?(IPV4_NUMBER_DIGITS.fetch(radix))

      digits = input.sub(LEADING_ZEROS, "")
      return 2**32 if digits.size > IPV4_NUMBER_MAX_DIGITS
      digits.to_i(radix)
    end

    # IPv6 parser. Follows the standard's algorithm step by step, reading
    # +input+ one code point at a time with +pointer+.
    def parse_ipv6(input)
      failure = -> { raise InvalidURIError, "invalid IPv6 address: #{"[#{input}]".dump}" }
      failure.() unless input.ascii_only?

      address = [0] * 8
      piece_index = 0
      compress = nil
      pointer = 0
      c = -> { input[pointer] }

      if c.() == ":"
        failure.() unless input[pointer + 1] == ":"
        pointer += 2
        piece_index += 1
        compress = piece_index
      end

      while c.()
        failure.() if piece_index == 8

        if c.() == ":"
          failure.() if compress
          pointer += 1
          piece_index += 1
          compress = piece_index
          next
        end

        value = length = 0
        while length < 4 && c.()&.match?(ASCII_HEX_DIGIT)
          value = value * 0x10 + c.().hex
          pointer += 1
          length += 1
        end

        if c.() == "."
          failure.() if length == 0
          pointer -= length
          failure.() if piece_index > 6

          numbers_seen = 0
          while c.()
            ipv4_piece = nil
            if numbers_seen > 0
              failure.() unless c.() == "." && numbers_seen < 4
              pointer += 1
            end
            failure.() unless c.()&.match?(ASCII_DIGIT)
            while c.()&.match?(ASCII_DIGIT)
              number = c.().to_i
              if ipv4_piece.nil?
                ipv4_piece = number
              elsif ipv4_piece == 0
                failure.()
              else
                ipv4_piece = ipv4_piece * 10 + number
              end
              failure.() if ipv4_piece > 255
              pointer += 1
            end
            address[piece_index] = address[piece_index] * 0x100 + ipv4_piece
            numbers_seen += 1
            piece_index += 1 if numbers_seen == 2 || numbers_seen == 4
          end
          failure.() unless numbers_seen == 4
          break
        elsif c.() == ":"
          pointer += 1
          failure.() unless c.()
        elsif c.()
          failure.()
        end

        address[piece_index] = value
        piece_index += 1
      end

      if compress
        swaps = piece_index - compress
        piece_index = 7
        while piece_index != 0 && swaps > 0
          address[piece_index], address[compress + swaps - 1] = address[compress + swaps - 1], address[piece_index]
          piece_index -= 1
          swaps -= 1
        end
      elsif piece_index != 8
        failure.()
      end

      address
    end

    # IPv6 serializer (without the surrounding brackets): the first
    # longest run of two or more zero pieces is written as "::".
    def serialize_ipv6(address)
      compress = longest_zero_run(address)
      output = +""
      ignore0 = false
      address.each_with_index do |piece, piece_index|
        next if ignore0 && piece == 0
        ignore0 = false
        if compress == piece_index
          output << (piece_index == 0 ? "::" : ":")
          ignore0 = true
          next
        end
        output << piece.to_s(16)
        output << ":" unless piece_index == 7
      end
      output
    end

    # Index of the first longest run of two or more zero pieces, or nil.
    def longest_zero_run(address)
      best = nil
      best_length = 1
      run_start = nil
      (address + [nil]).each_with_index do |piece, i|
        if piece == 0
          run_start ||= i
        elsif run_start
          if i - run_start > best_length
            best = run_start
            best_length = i - run_start
          end
          run_start = nil
        end
      end
      best
    end

    # IPv4 serializer
    def serialize_ipv4(address)
      [24, 16, 8, 0].map { |shift| (address >> shift) & 0xFF }.join(".")
    end

    # opaque-host parser
    def parse_opaque_host(input)
      raise InvalidURIError, "invalid host: #{input.dump}" if input.match?(FORBIDDEN_HOST_CODE_POINT)
      utf8_percent_encode(input, C0_CONTROL_PERCENT_ENCODE_SET)
    end

    # percent-decode, then UTF-8 decode without BOM (invalid sequences
    # become U+FFFD).
    def percent_decode(input)
      input.b.gsub(PERCENT_ENCODED_BYTE) { $&[1, 2].hex.chr }.force_encoding(Encoding::UTF_8).scrub
    end

    def utf8_percent_encode(input, encode_set)
      input.gsub(encode_set) { |c| c.unpack("C*").map { |b| format("%%%02X", b) }.join }
    end

    # Generic#merge. The URL Standard resolves a reference while parsing
    # it against a base. A relative +base+, which Generic#route_to can
    # return, is merged with an absolute URI only, as in Generic#merge.
    def merge(base, reference)
      return join(base, reference) if base.absolute?
      absolute_uri(reference) or raise BadURIError, "both URI are relative"
    end

    # Returns +uri+ converted to a URI if it is absolute, or nil if it is
    # a relative reference.
    def absolute_uri(uri)
      return (uri.absolute? ? uri : nil) if uri.is_a?(URI::Generic)

      str = String.try_convert(uri)
      raise ArgumentError, "bad argument (expected URI object or URI string)" unless str
      scheme, = parse_scheme(preprocess(to_utf8(str)))
      scheme ? parse(str) : nil
    end

    # A URI that this parser built, or the relative URI that
    # Generic#route_to returned for one, is returned as it is; a URI that
    # another parser built is parsed, as its string would be.
    def convert_to_uri(uri)
      if uri.is_a?(URI::Generic)
        uri.parser.is_a?(WHATWG_Parser) ? uri : parse(uri.to_s)
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected URI object or URI string)"
      end
    end
  end
end
