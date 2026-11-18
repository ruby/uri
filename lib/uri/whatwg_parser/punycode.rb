# frozen_string_literal: true
module URI
  class WHATWG_Parser
    # Punycode (RFC 3492), the encoding of a domain label's code points
    # in ASCII that follows "xn--" in an A-label.
    module Punycode # :nodoc:
      BASE = 36
      TMIN = 1
      TMAX = 26
      SKEW = 38
      DAMP = 700
      INITIAL_BIAS = 72
      INITIAL_N = 0x80
      DELIMITER = "-"

      # The largest value an intermediate integer may take while
      # decoding. Ruby's integers do not overflow, but a value this large
      # can only produce a code point beyond Unicode, so decoding stops
      # there instead of computing with ever larger integers.
      MAXINT = 0x7FFF_FFFF
      MAX_CODE_POINT = 0x10FFFF
      SURROGATES = (0xD800..0xDFFF).freeze

      module_function

      # Encodes +input+, a String of Unicode code points, as Punycode.
      def encode(input)
        code_points = input.codepoints
        output = code_points.select { |c| c < INITIAL_N }.pack("U*")
        basic_count = handled = output.size
        output << DELIMITER if basic_count > 0

        n = INITIAL_N
        delta = 0
        bias = INITIAL_BIAS
        while handled < code_points.size
          m = code_points.select { |c| c >= n }.min
          delta += (m - n) * (handled + 1)
          n = m
          code_points.each do |c|
            delta += 1 if c < n
            next unless c == n

            q = delta
            k = BASE
            loop do
              t = threshold(k, bias)
              break if q < t
              output << digit(t + (q - t) % (BASE - t))
              q = (q - t) / (BASE - t)
              k += BASE
            end
            output << digit(q)
            bias = adapt(delta, handled + 1, handled == basic_count)
            delta = 0
            handled += 1
          end
          delta += 1
          n += 1
        end
        output
      end

      # Decodes +input+, a Punycode String. Returns nil when +input+ is
      # not valid Punycode or decodes to something that is not a sequence
      # of Unicode scalar values.
      def decode(input)
        return nil unless input.ascii_only?

        delimiter = input.rindex(DELIMITER)
        output = delimiter ? input[0, delimiter].codepoints : []
        rest = delimiter ? input[delimiter + 1..-1] : input

        n = INITIAL_N
        i = 0
        bias = INITIAL_BIAS
        position = 0
        while position < rest.size
          old_i = i
          w = 1
          k = BASE
          loop do
            return nil if position >= rest.size
            d = digit_value(rest[position])
            position += 1
            return nil unless d
            i += d * w
            return nil if i > MAXINT
            t = threshold(k, bias)
            break if d < t
            w *= BASE - t
            return nil if w > MAXINT
            k += BASE
          end
          length = output.size + 1
          bias = adapt(i - old_i, length, old_i == 0)
          n += i / length
          return nil if n > MAX_CODE_POINT || SURROGATES.cover?(n)
          i %= length
          output.insert(i, n)
          i += 1
        end
        output.pack("U*")
      end

      def threshold(k, bias)
        if k <= bias
          TMIN
        elsif k >= bias + TMAX
          TMAX
        else
          k - bias
        end
      end

      def adapt(delta, num_points, first_time)
        delta = first_time ? delta / DAMP : delta / 2
        delta += delta / num_points
        k = 0
        while delta > ((BASE - TMIN) * TMAX) / 2
          delta /= BASE - TMIN
          k += BASE
        end
        k + (BASE - TMIN + 1) * delta / (delta + SKEW)
      end

      # The basic code point for the digit +d+ (0..35): "a".."z", "0".."9".
      def digit(d)
        (d < 26 ? d + 0x61 : d + 0x16).chr
      end

      # The value of the basic code point +char+ as a digit, or nil.
      def digit_value(char)
        case char
        when "a".."z" then char.ord - 0x61
        when "A".."Z" then char.ord - 0x41
        when "0".."9" then char.ord - 0x16
        end
      end
    end
  end
end
