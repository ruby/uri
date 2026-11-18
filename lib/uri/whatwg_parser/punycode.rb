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

      # Up to this many insertions, inserting into an array is faster
      # than placing them with a Fenwick tree, and takes little time even
      # when each one goes to the start.
      ARRAY_INSERTION_LIMIT = 1024

      module_function

      # Encodes +input+, a String of Unicode code points, as Punycode.
      #
      # RFC 3492 scans the whole input once for each distinct non-basic
      # code point, which takes time proportional to the length times the
      # number of distinct code points. Instead, the positions of each
      # code point are visited in order, and the code points smaller than
      # it between two positions are counted with a Fenwick tree, which
      # gives the same deltas.
      def encode(input)
        code_points = input.codepoints
        output = code_points.select { |c| c < INITIAL_N }.pack("U*")
        basic_count = handled = output.size
        output << DELIMITER if basic_count > 0

        smaller = FenwickTree.new(code_points.size)
        positions = Hash.new { |hash, c| hash[c] = [] }
        code_points.each_with_index do |c, i|
          c < INITIAL_N ? smaller.add(i) : positions[c] << i
        end

        n = INITIAL_N
        delta = 0
        bias = INITIAL_BIAS
        positions.keys.sort.each do |m|
          delta += (m - n) * (handled + 1)
          n = m
          previous = -1
          positions[m].each do |i|
            delta += smaller.count(previous + 1, i)
            previous = i
            encode_delta(output, delta, bias)
            bias = adapt(delta, handled + 1, handled == basic_count)
            delta = 0
            handled += 1
          end
          delta += smaller.count(previous + 1, code_points.size)
          positions[m].each { |i| smaller.add(i) }
          delta += 1
          n += 1
        end
        output
      end

      # Appends +delta+ as a variable-length integer.
      def encode_delta(output, delta, bias)
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
      end

      # Counts marked positions.
      class FenwickTree # :nodoc:
        # A tree of +size+ positions, all of them marked if +marked+.
        def initialize(size, marked: false)
          @tree = Array.new(size + 1) { |i| marked ? i & -i : 0 }
        end

        # Marks position +i+, or unmarks it if +value+ is -1.
        def add(i, value = 1)
          i += 1
          while i < @tree.size
            @tree[i] += value
            i += i & -i
          end
        end

        # The number of marked positions in first...last.
        def count(first, last)
          prefix(last) - prefix(first)
        end

        # The position of the marked position that has +k+ marked
        # positions before it.
        def find(k)
          position = 0
          step = 1
          step <<= 1 while step * 2 < @tree.size
          while step > 0
            if position + step < @tree.size && @tree[position + step] <= k
              position += step
              k -= @tree[position]
            end
            step >>= 1
          end
          position
        end

        private

        # The number of marked positions in 0...i.
        def prefix(i)
          sum = 0
          while i > 0
            sum += @tree[i]
            i -= i & -i
          end
          sum
        end
      end
      private_constant :FenwickTree

      # Decodes +input+, a Punycode String. Returns nil when +input+ is
      # not valid Punycode or decodes to something that is not a sequence
      # of Unicode scalar values.
      #
      # RFC 3492 inserts each decoded code point into the output, which
      # takes time proportional to the square of the length when each one
      # goes to the start. Instead, the insertions are recorded, and then
      # placed by #place, which inserts only a few into an array.
      def decode(input)
        return nil unless input.ascii_only?

        delimiter = input.rindex(DELIMITER)
        basic = delimiter ? input[0, delimiter].codepoints : []
        rest = delimiter ? input[delimiter + 1..-1] : input
        indices = []
        inserted = []

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
          length = basic.size + indices.size + 1
          bias = adapt(i - old_i, length, old_i == 0)
          n += i / length
          return nil if n > MAX_CODE_POINT || SURROGATES.cover?(n)
          i %= length
          indices << i
          inserted << n
          i += 1
        end
        place(basic, indices, inserted).pack("U*")
      end

      # The code points of +basic+ followed by those of +inserted+, each
      # inserted at the index of the same place in +indices+, in order.
      # Going back from the last insertion, each code point takes the free
      # position that has as many free positions before it as its index,
      # since the positions after it are those of later insertions.
      def place(basic, indices, inserted)
        if indices.size <= ARRAY_INSERTION_LIMIT
          indices.each_with_index { |index, j| basic.insert(index, inserted[j]) }
          return basic
        end

        output = Array.new(basic.size + indices.size)
        free = FenwickTree.new(output.size, marked: true)
        (indices.size - 1).downto(0) do |j|
          position = free.find(indices[j])
          output[position] = inserted[j]
          free.add(position, -1)
        end
        # The basic code points take the positions left, in order.
        basic_index = 0
        output.map! do |c|
          next c if c
          basic_index += 1
          basic[basic_index - 1]
        end
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
