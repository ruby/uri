# frozen_string_literal: true
module URI
  class WHATWG_Parser
    # The setters of the URL Standard (https://url.spec.whatwg.org/#api)
    # on a URL record. Each returns false when the URL Standard leaves the
    # URL unchanged because the value is rejected, and true otherwise,
    # including when only a part of the value is applied.

    private

    # The protocol setter: the scheme state with a state override.
    def set_url_scheme(url, value)
      match = SCHEME.match(remove_tab_and_newline(value) + ":")
      return false unless match

      scheme = match[0].chop.downcase
      return false if special?(url.scheme) != special?(scheme)
      return false if scheme == "file" && (includes_credentials?(url) || url.port)
      return false if url.scheme == "file" && url.host == ""

      url.scheme = scheme
      url.port = nil if url.port == SPECIAL_SCHEMES[scheme]
      true
    end

    # The username setter. The value is not stripped of tabs and newlines.
    def set_url_username(url, value)
      return false if cannot_have_credentials_or_port?(url)
      url.username = utf8_percent_encode(value, USERINFO_PERCENT_ENCODE_SET)
      true
    end

    # The password setter.
    def set_url_password(url, value)
      return false if cannot_have_credentials_or_port?(url)
      url.password = utf8_percent_encode(value, USERINFO_PERCENT_ENCODE_SET)
      true
    end

    # The hostname setter: the hostname state with a state override, or
    # the file host state for a file URL.
    def set_url_hostname(url, value)
      return false if url.path.is_a?(String)

      input = remove_tab_and_newline(value)
      return set_url_file_host(url, input) if url.scheme == "file"

      special = special?(url.scheme)
      buffer = host_buffer(input, special)
      # A ":" outside brackets would start the port, which the hostname
      # setter does not set.
      return false if input.size > buffer.size && input[buffer.size] == ":"
      return false if special && buffer.empty?
      return false if buffer.empty? && (includes_credentials?(url) || url.port)

      host = try_parse_host(buffer, special)
      return false unless host
      url.host = host
      true
    end

    # The file host state with a state override.
    def set_url_file_host(url, input)
      buffer = input[/\A[^\/\\?#]*/]
      if buffer.empty?
        url.host = ""
        return true
      end

      host = try_parse_host(buffer, true)
      return false unless host
      url.host = host == "localhost" ? "" : host
      true
    end

    # The host buffer of the host state: +input+ up to a ":" outside
    # brackets, "/", "?", "#", or "\" for a special URL.
    def host_buffer(input, special)
      inside_brackets = false
      input.each_char.with_index do |c, i|
        return input[0, i] if c == ":" && !inside_brackets
        return input[0, i] if c == "/" || c == "?" || c == "#" || (special && c == "\\")
        if c == "["
          inside_brackets = true
        elsif c == "]"
          inside_brackets = false
        end
      end
      input
    end

    def try_parse_host(buffer, special)
      parse_host(buffer, special)
    rescue InvalidURIError
      nil
    end

    # The port setter: the port state with a state override, which takes
    # the leading digits.
    def set_url_port(url, value)
      return false if cannot_have_credentials_or_port?(url)

      input = remove_tab_and_newline(value)
      if input.empty?
        url.port = nil
        return true
      end

      digits = input[/\A[0-9]*/]
      return false if digits.empty?
      port = digits.to_i
      return false if port > MAX_PORT
      url.port = port == SPECIAL_SCHEMES[url.scheme] ? nil : port
      true
    end

    # The pathname setter: the path start state with a state override,
    # in which "?" and "#" are part of the path.
    def set_url_path(url, value)
      return false if url.path.is_a?(String)

      input = remove_tab_and_newline(value)
      special = special?(url.scheme)
      url.path =
        if input.empty? && !special
          url.host.nil? ? [""] : []
        else
          parse_path(input, special, [], file: url.scheme == "file")
        end
      true
    end

    # The search setter, given the query without a leading "?", or nil
    # to remove it.
    def set_url_query(url, value)
      if value.nil?
        url.query = nil
      else
        encode_set = special?(url.scheme) ? SPECIAL_QUERY_PERCENT_ENCODE_SET : QUERY_PERCENT_ENCODE_SET
        url.query = utf8_percent_encode(remove_tab_and_newline(value), encode_set)
      end
      true
    end

    # The hash setter, given the fragment without a leading "#", or nil
    # to remove it.
    def set_url_fragment(url, value)
      if value.nil?
        url.fragment = nil
      else
        url.fragment = utf8_percent_encode(remove_tab_and_newline(value), FRAGMENT_PERCENT_ENCODE_SET)
      end
      true
    end

    def remove_tab_and_newline(value)
      value.to_s.delete(ASCII_TAB_OR_NEWLINE)
    end

    def special?(scheme)
      SPECIAL_SCHEMES.key?(scheme)
    end

    def includes_credentials?(url)
      !url.username.empty? || !url.password.empty?
    end

    def cannot_have_credentials_or_port?(url)
      url.host.nil? || url.host == "" || url.scheme == "file"
    end

    # Makes the setters of a URI built by WHATWG_Parser follow the URL
    # Standard. Prepended to URI::Generic; a URI that WHATWG_Parser did
    # not build, or one that is still being initialized, keeps the
    # setters of URI::Generic.
    #
    # A value that the URL Standard ignores raises InvalidComponentError.
    module GenericSetters # :nodoc:
      def scheme=(v)
        return super unless whatwg_url?
        update_whatwg_url(:scheme, v) { |parser, url| parser.__send__(:set_url_scheme, url, v) }
      end

      def user=(v)
        return super unless whatwg_url?
        update_whatwg_url(:user, v) { |parser, url| parser.__send__(:set_url_username, url, v.to_s) }
      end

      def password=(v)
        return super unless whatwg_url?
        update_whatwg_url(:password, v) { |parser, url| parser.__send__(:set_url_password, url, v.to_s) }
      end

      def host=(v)
        return super unless whatwg_url?
        update_whatwg_url(:host, v) { |parser, url| parser.__send__(:set_url_hostname, url, v) }
      end

      def port=(v)
        return super unless whatwg_url?
        update_whatwg_url(:port, v) { |parser, url| parser.__send__(:set_url_port, url, v) }
      end

      def path=(v)
        return super unless whatwg_url?
        update_whatwg_url(:path, v) { |parser, url| parser.__send__(:set_url_path, url, v) }
      end

      def query=(v)
        return super unless whatwg_url?
        update_whatwg_url(:query, v) { |parser, url| parser.__send__(:set_url_query, url, v) }
      end

      def fragment=(v)
        return super unless whatwg_url?
        update_whatwg_url(:fragment, v) { |parser, url| parser.__send__(:set_url_fragment, url, v) }
      end

      # The default port of the scheme, which can change with #scheme=
      # while the class stays.
      def default_port
        return super unless whatwg_url?
        SPECIAL_SCHEMES[@scheme]
      end

      protected

      # Marks a URI that WHATWG_Parser has finished building.
      def whatwg_url!
        @whatwg_url = true
        set_port(default_port) if @port.nil? && default_port
      end

      private

      COMPONENT_VARIABLES = %i[@scheme @user @password @host @port @path @query @opaque @fragment].freeze
      private_constant :COMPONENT_VARIABLES

      # Generic#merge! replaces the components through the setters, which
      # for a URL would apply the setters of the URL Standard to values
      # that are already serialized, and would also set the registry,
      # which always fails. The components are copied as they are.
      def replace!(oth)
        return super unless whatwg_url?
        raise ArgumentError, "expected #{self.class} object" if self.class != oth.class

        COMPONENT_VARIABLES.each do |name|
          instance_variable_set(name, oth.instance_variable_get(name))
        end
      end

      def whatwg_url?
        defined?(@whatwg_url) && @whatwg_url
      end

      # Applies a setter to the URL record of this URI, and replaces the
      # components with the result.
      def update_whatwg_url(component, value)
        parser = self.parser
        url = parser.__send__(:basic_parse, to_s)
        unless yield(parser, url)
          raise InvalidComponentError, "bad component(expected #{component} component): #{value.inspect}"
        end

        scheme, userinfo, host, port, _registry, path, opaque, query, fragment = parser.__send__(:to_components, url)
        @scheme = scheme.freeze
        @user, @password = userinfo ? userinfo.split(":", 2) : [nil, nil]
        @host = host
        @path = path
        @opaque = opaque
        @query = query
        @fragment = fragment
        @port = port ? port.to_i : default_port
        value
      end
    end

    Generic.prepend(GenericSetters)
  end
end
