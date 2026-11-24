# frozen_string_literal: true
module URI
  class WHATWG_Parser
    # Unicode Normalization Forms C and KC (UAX #15,
    # https://www.unicode.org/reports/tr15/) with the tables of
    # String#unicode_normalize, so with the Unicode version of the running
    # Ruby. String#unicode_normalize itself cannot run in a non-main
    # Ractor.
    #
    # The tables (nfc_tables.rb) are loaded on first use, or with
    # whatwg_parser.rb where a Ractor cannot require them safely.
    module NFC # :nodoc:
      # Hangul syllable composition (Unicode Standard, section 3.12).
      S_BASE = 0xAC00
      L_BASE = 0x1100
      V_BASE = 0x1161
      T_BASE = 0x11A7
      L_COUNT = 19
      V_COUNT = 21
      T_COUNT = 28
      N_COUNT = V_COUNT * T_COUNT
      S_COUNT = L_COUNT * N_COUNT

      CODE_SPACE = 0x110000

      module_function

      # Returns +input+, a UTF-8 String, in NFC.
      def normalize(input)
        recompose(input) { |code_points| decompose(code_points) }
      end

      # Returns +input+, a UTF-8 String, in NFKC.
      def normalize_kc(input)
        recompose(input) { |code_points| decompose(code_points, COMPATIBILITY_DECOMPOSITION) }
      end

      # Composes +input+ decomposed by the block.
      def recompose(input)
        return input.dup if input.ascii_only?
        load_tables
        code_points = yield input.codepoints
        reorder!(code_points)
        compose(code_points).pack("U*")
      end

      def normalized?(input)
        normalize(input) == input
      end

      def load_tables
        require_relative "nfc_tables" unless const_defined?(:COMPOSITION, false)
      end

      def pair_key(first, second)
        first * CODE_SPACE + second
      end

      # The full canonical decomposition of +code_points+, or the full
      # compatibility decomposition with COMPATIBILITY_DECOMPOSITION as
      # +compatibility+.
      def decompose(code_points, compatibility = nil)
        code_points.each_with_object([]) do |c, result|
          s_index = c - S_BASE
          if s_index >= 0 && s_index < S_COUNT
            result << L_BASE + s_index / N_COUNT << V_BASE + (s_index % N_COUNT) / T_COUNT
            t = s_index % T_COUNT
            result << T_BASE + t if t > 0
          elsif (decomposition = (compatibility && compatibility[c]) || DECOMPOSITION[c])
            result.concat(decomposition)
          else
            result << c
          end
        end
      end

      # The Canonical Ordering Algorithm: sorts each run of code points
      # whose combining class is not 0 by class, keeping the order of
      # equal classes.
      def reorder!(code_points)
        i = 0
        while i < code_points.size
          if COMBINING_CLASS.key?(code_points[i])
            run_end = i
            run_end += 1 while run_end < code_points.size && COMBINING_CLASS.key?(code_points[run_end])
            if run_end - i > 1
              run = code_points[i...run_end].each_with_index.sort_by { |c, index| [COMBINING_CLASS[c], index] }
              code_points[i...run_end] = run.map(&:first)
            end
            i = run_end
          else
            i += 1
          end
        end
        code_points
      end

      # The Canonical Composition Algorithm.
      def compose(code_points)
        result = []
        starter = nil
        # The combining class of the last code point kept since the
        # starter, or nil when the starter is the last one.
        last_class = nil
        code_points.each do |c|
          ccc = COMBINING_CLASS.fetch(c, 0)
          if starter && (last_class.nil? || last_class < ccc)
            composite = compose_pair(result[starter], c)
            if composite
              result[starter] = composite
              next
            end
          end
          if ccc == 0
            starter = result.size
            last_class = nil
          else
            last_class = ccc
          end
          result << c
        end
        result
      end

      def compose_pair(first, second)
        l_index = first - L_BASE
        v_index = second - V_BASE
        if l_index >= 0 && l_index < L_COUNT && v_index >= 0 && v_index < V_COUNT
          return S_BASE + (l_index * V_COUNT + v_index) * T_COUNT
        end

        s_index = first - S_BASE
        t_index = second - T_BASE
        if s_index >= 0 && s_index < S_COUNT && s_index % T_COUNT == 0 && t_index > 0 && t_index < T_COUNT
          return first + t_index
        end

        COMPOSITION[pair_key(first, second)]
      end
    end
  end
end
