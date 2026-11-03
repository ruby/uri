# frozen_string_literal: true
module URI
  # A parser for the WHATWG URL Standard (https://url.spec.whatwg.org/).
  #
  # It is not the default parser. Use it explicitly with
  # URI::WHATWG_PARSER.parse, or switch to it with
  # <tt>URI.parser = URI::WHATWG_PARSER</tt>.
  class WHATWG_Parser # :nodoc:
    # Returns [scheme, userinfo, host, port, registry, path, opaque, query,
    # fragment], the same contract as URI::RFC3986_Parser#split.
    def split(uri) # :nodoc:
      begin
        uri = uri.to_str
      rescue NoMethodError
        raise InvalidURIError, "bad URI (is not URI?): #{uri.inspect}"
      end
      uri = preprocess(to_utf8(uri))

      scheme, rest = parse_scheme(uri)
      # Every state before the fragment state ends at the first "#", and
      # every state before the query state at the first "?" before it.
      rest, query, fragment = split_query_and_fragment(rest)

      # query state and fragment state
      special = SPECIAL_SCHEMES.key?(scheme)
      query &&= utf8_percent_encode(query, special ? SPECIAL_QUERY_PERCENT_ENCODE_SET : QUERY_PERCENT_ENCODE_SET)
      fragment &&= utf8_percent_encode(fragment, FRAGMENT_PERCENT_ENCODE_SET)

      components = split_before_query(scheme, rest)
      if (opaque = components[6])
        components[6] = opaque_with_query(opaque, query, fragment)
      else
        components[7] = query
      end
      components[8] = fragment
      components
    end

    def parse(uri) # :nodoc:
      URI.for(*split(uri), self)
    end

    def join(*uris) # :nodoc:
      uris[0] = convert_to_uri(uris[0])
      uris.inject :merge
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

    def split_query_and_fragment(rest)
      rest, hash, fragment = rest.partition("#")
      fragment = nil if hash.empty?
      rest, question, query = rest.partition("?")
      query = nil if question.empty?
      [rest, query, fragment]
    end

    # opaque path state: code points in the C0 control percent-encode set
    # are percent-encoded, and a space right before "?" or "#" is written
    # as "%20". The query is kept inside opaque, as URI::RFC3986_Parser
    # does, since URI::Generic does not serialize the query of an opaque
    # URI.
    def opaque_with_query(opaque, query, fragment)
      opaque = utf8_percent_encode(opaque, C0_CONTROL_PERCENT_ENCODE_SET)
      opaque = opaque.sub(TRAILING_SPACE, "%20") if query || fragment
      query ? "#{opaque}?#{query}" : opaque
    end

    # Splits everything after the scheme and before the query into the
    # components, leaving query and fragment nil.
    def split_before_query(scheme, rest)
      if scheme == "file"
        # Approximates file state, file slash state and file host state
        # until they are implemented: exactly two leading "/" or "\\"
        # start a host, which may be empty.
        if rest.match?(FILE_SLASHES)
          split_authority(scheme, rest[2..-1], true, host_required: false)
        else
          [scheme, nil, nil, nil, nil, path_without_host(rest, true), nil, nil, nil]
        end
      elsif SPECIAL_SCHEMES.key?(scheme)
        # special authority slashes state and special authority ignore
        # slashes state: skip any run of "/" or "\\".
        split_authority(scheme, rest.sub(SPECIAL_AUTHORITY_SLASHES, ""), true)
      elsif rest.start_with?("/")
        # path or authority state
        if rest.start_with?("//")
          split_authority(scheme, rest[2..-1], false)
        else
          [scheme, nil, nil, nil, nil, path_without_host(rest, false), nil, nil, nil]
        end
      else
        # opaque path state
        [scheme, nil, nil, nil, nil, nil, rest, nil, nil]
      end
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

    # scheme start state and scheme state: an ASCII alpha followed by
    # ASCII alphanumerics, "+", "-" or ".", up to the first ":".
    SCHEME = /\A[A-Za-z][A-Za-z0-9+\-.]*:/ # :nodoc:

    SPECIAL_AUTHORITY_SLASHES = %r{\A[/\\]*} # :nodoc:
    FILE_SLASHES = %r{\A[/\\]{2}} # :nodoc:
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

    # Returns the ASCII-lowercased scheme and the rest of +input+ after
    # the ":". Without a scheme, the no scheme state fails, since there
    # is no base URL.
    def parse_scheme(input)
      scheme = input[SCHEME] or
        raise InvalidURIError, "missing scheme: #{input.dump}"
      [scheme.chop.downcase, input[scheme.size..-1]]
    end

    # authority state and host state. +rest+ starts right after the
    # slashes preceding the authority.
    def split_authority(scheme, rest, special, host_required: special)
      authority_end = rest.index(special ? SPECIAL_AUTHORITY_END : AUTHORITY_END) || rest.size
      authority = rest[0, authority_end]
      remainder = rest[authority_end..-1]

      userinfo, host_and_port = split_userinfo(authority)
      host, port = split_host_and_port(host_and_port)
      raise InvalidURIError, "missing host: #{rest.dump}" if host.empty? && (host_required || port)
      host = parse_host(host, special) unless host.empty?
      port = parse_port(port, scheme) if port

      path = serialize_path(parse_path(remainder, special))
      [scheme, userinfo, host, port, nil, path, nil, nil, nil]
    end

    # The path of a URL without a host. The URL serializer writes "/."
    # before such a path when it would otherwise start with "//", so it
    # is not mistaken for an authority when reparsed.
    def path_without_host(input, special)
      segments = parse_path(input, special)
      path = serialize_path(segments)
      segments.size > 1 && segments[0].empty? ? "/.#{path}" : path
    end

    # path start state and path state. Returns the list of path segments.
    def parse_path(input, special)
      separator = special ? SPECIAL_PATH_SEPARATOR : "/"
      # path start state: a special URL always has a path, even an empty
      # one; another URL has one only if anything follows the authority.
      return [] if input.empty? && !special
      input = input[1..-1] if input.start_with?("/") || (special && input.start_with?("\\"))

      buffers = input.split(separator, -1)
      buffers = [""] if buffers.empty?
      buffers.each_with_index.with_object([]) do |(buffer, i), path|
        buffer = utf8_percent_encode(buffer, PATH_PERCENT_ENCODE_SET)
        # Whether this segment is ended by the end of the path rather
        # than by a separator.
        last = i == buffers.size - 1
        if double_dot_segment?(buffer)
          path.pop
          path << "" if last
        elsif single_dot_segment?(buffer)
          path << "" if last
        else
          path << buffer
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
    # username from the password. Returns the userinfo as the URL
    # serializer writes it (nil when both parts are empty), and the rest.
    def split_userinfo(authority)
      at = authority.rindex("@") or return [nil, authority]
      host_and_port = authority[at + 1..-1]
      raise InvalidURIError, "missing host after userinfo: #{authority.dump}" if host_and_port.empty?

      username, _, password = authority[0, at].gsub("@", "%40").partition(":")
      username = utf8_percent_encode(username, USERINFO_PERCENT_ENCODE_SET)
      password = utf8_percent_encode(password, USERINFO_PERCENT_ENCODE_SET)
      userinfo =
        if password.empty?
          username.empty? ? nil : username
        else
          "#{username}:#{password}"
        end
      [userinfo, host_and_port]
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
    # the authority. Returns the port as a decimal string, or nil when it
    # is empty or the scheme's default port.
    #
    # A port with more significant digits than 65535 has is rejected
    # without converting it.
    def parse_port(input, scheme)
      return nil if input.empty?
      raise InvalidURIError, "invalid port: #{input.dump}" unless input.match?(ASCII_DIGITS)

      digits = input.sub(LEADING_ZEROS, "")
      port = digits.size > PORT_MAX_DIGITS ? MAX_PORT + 1 : digits.to_i
      raise InvalidURIError, "port out of range: #{input.dump}" if port > MAX_PORT
      port == SPECIAL_SCHEMES[scheme] ? nil : port.to_s
    end

    # host parser
    def parse_host(input, special)
      if input.start_with?("[")
        raise InvalidURIError, "unterminated IPv6 address: #{input.dump}" unless input.end_with?("]")
        return "[#{serialize_ipv6(parse_ipv6(input[1..-2]))}]"
      end
      return parse_opaque_host(input) unless special

      domain = percent_decode(input)
      unless domain.ascii_only?
        # Interim: domain to ASCII (UTS #46) is not implemented yet, so a
        # non-ASCII domain is returned unchanged.
        raise InvalidURIError, "invalid host: #{input.dump}" if input.match?(FORBIDDEN_HOST_CODE_POINT)
        return input
      end

      # domain to ASCII, for an ASCII domain with beStrict false.
      ascii_domain = domain.downcase
      raise InvalidURIError, "invalid host: #{input.dump}" if ascii_domain.match?(FORBIDDEN_DOMAIN_CODE_POINT)
      return serialize_ipv4(parse_ipv4(ascii_domain)) if ends_in_a_number?(ascii_domain)
      ascii_domain
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

    def convert_to_uri(uri)
      if uri.is_a?(URI::Generic)
        uri
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected URI object or URI string)"
      end
    end
  end
end
