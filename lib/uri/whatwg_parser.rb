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

      if scheme == "file"
        # Approximates file state, file slash state and file host state
        # until they are implemented: exactly two leading "/" or "\\"
        # start a host, which may be empty.
        if rest.match?(FILE_SLASHES)
          split_authority(scheme, rest[2..-1], true, host_required: false)
        else
          [scheme, nil, nil, nil, nil, rest, nil, nil, nil]
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
          [scheme, nil, nil, nil, nil, rest, nil, nil, nil]
        end
      else
        # opaque path state
        [scheme, nil, nil, nil, nil, nil, rest, nil, nil]
      end
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

      [scheme, userinfo, host, port, nil, remainder, nil, nil, nil]
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
