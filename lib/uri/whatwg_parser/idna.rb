# frozen_string_literal: true
module URI
  class WHATWG_Parser
    # Domain to ASCII (https://url.spec.whatwg.org/#concept-domain-to-ascii)
    # for a domain that is not ASCII: Unicode ToASCII (UTS #46,
    # https://www.unicode.org/reports/tr46/) with CheckHyphens=false,
    # CheckBidi=true, CheckJoiners=true, UseSTD3ASCIIRules=false,
    # Transitional_Processing=false, VerifyDnsLength=false and
    # IgnoreInvalidPunycode=false.
    #
    # The IDNA Mapping Table is not stored: the status and the mapping of
    # each code point are derived as UTS #46 section 6 does, from the
    # Unicode data of the running Ruby (its character properties, case
    # folding and the tables of NFC and NFKC), so a code point added in a
    # later Unicode version is disallowed. Only the Bidi_Class and
    # Joining_Type values that the Bidi Rule and CONTEXTJ need, which Ruby
    # has not, are generated (idna_data.rb).
    #
    # The data is loaded on first use, or with whatwg_parser.rb where a
    # Ractor cannot require it safely.
    module IDNA # :nodoc:
      ACE_PREFIX = "xn--"
      LABEL_SEPARATOR = "."
      ZWNJ = 0x200C.chr(Encoding::UTF_8).freeze
      ZWJ = 0x200D.chr(Encoding::UTF_8).freeze

      # Every code point the IDNA Mapping Table leaves unchanged is
      # matched out; ASCII code points other than A-Z are among them.
      MAPPING_CANDIDATE = /[A-Z]|[^\x00-\x7F]/
      UPPERCASE_ASCII = /\A[A-Z]\z/

      # The Bidi Rule (RFC 5893 section 2), over a label whose code points
      # are replaced by their Bidi_Class: L, R (R or AL), A (AN), E (EN),
      # N (ES, CS, ET, ON or BN), M (NSM), or X (anything else).
      BIDI_RTL = /[RA]/
      BIDI_FIRST = /\A[LR]/
      BIDI_RTL_ALLOWED = /\A[RAENM]*\z/
      BIDI_RTL_END = /[RAE]M*\z/
      BIDI_LTR_ALLOWED = /\A[LENM]*\z/
      BIDI_LTR_END = /[LE]M*\z/

      # The sets of the Mapping Table Derivation (UTS #46 section 6).
      LABEL_SEPARATORS = ["\u{FF0E}", "\u{3002}", "\u{FF61}"].freeze
      CAPITAL_SHARP_S = "\u{1E9E}"
      SHARP_S = "\u{DF}"
      BIDI_CONTROL = /\p{Bidi_Control}/
      DEFAULT_IGNORABLE = /\p{Default_Ignorable_Code_Point}/
      OTHER_OR_SEPARATOR = /[\p{C}\p{Z}]/
      IDS_OPERATOR =
        begin
          # Regexp.new, unlike a literal, is not frozen.
          Regexp.new("[\\p{IDS_Unary_Operator}\\p{IDS_Binary_Operator}\\p{IDS_Trinary_Operator}]").freeze
        rescue RegexpError
          # IDS_Unary_Operator is new in Unicode 15.1, with U+2FFE and U+2FFF.
          /[\u{2FFE}\u{2FFF}\p{IDS_Binary_Operator}\p{IDS_Trinary_Operator}]/
        end
      EXCLUDED = /[\u{FFFC}\u{FFFD}\u{E0001}-\u{E007F}]/
      UNASSIGNED = /\p{Cn}/
      DEVIATIONS = [ZWNJ, ZWJ, SHARP_S, "\u{3C2}"].freeze

      # General_Category=Mark.
      MARK = /\p{M}/
      # Canonical_Combining_Class=Virama.
      VIRAMA_CLASS = 9
      # The ASCII code points whose Bidi_Class (B, S or WS) is none that
      # the Bidi Rule names. Every other valid code point not listed in
      # idna_data.rb has Bidi_Class L.
      BIDI_OTHER = /[\t\n\v\f\r\x1C-\x20]/

      module_function

      # Returns the ASCII form of +domain+, or nil on failure.
      def to_ascii(domain)
        labels = process(domain)
        return nil unless labels
        labels.map { |label| label.ascii_only? ? label : ACE_PREFIX + Punycode.encode(label) }.join(LABEL_SEPARATOR)
      end

      # UTS #46 Processing. Returns the labels in Unicode, or nil if an
      # error is recorded.
      def process(domain)
        return nil unless domain.valid_encoding?
        load_data

        # Deriving the status of a code point takes several
        # normalizations, so each one is derived once per domain.
        statuses = {}
        mapped = domain.gsub(MAPPING_CANDIDATE) do |c|
          st = status(c, statuses)
          st.is_a?(String) ? st : c
        end
        labels = NFC.normalize(mapped).split(LABEL_SEPARATOR, -1)
        labels.map! do |label|
          label = decode_label(label) if label.start_with?(ACE_PREFIX)
          return nil unless label && valid_label?(label, statuses)
          label
        end
        return nil if bidi_domain?(labels) && !labels.all? { |label| satisfies_bidi_rule?(label) }
        labels
      end

      def load_data
        require_relative "idna_data" unless const_defined?(:BIDI_NSM, false)
        NFC.load_tables
      end

      # Steps 6 and 7 of the Mapping Table Derivation for +c+: true if its
      # status is valid or deviation, its mapping (an empty string if it
      # is ignored) if it is mapped, or false if it is disallowed.
      # +statuses+ caches the result by code point.
      def status(c, statuses = {})
        statuses.fetch(c) { statuses[c] = derive_status(c, statuses) }
      end

      def derive_status(c, statuses)
        return c.downcase if UPPERCASE_ASCII.match?(c)
        return c != LABEL_SEPARATOR if c.ord < 0x80
        return true if DEVIATIONS.include?(c)
        return false if c.match?(EXCLUDED) || unknown?(c)
        mapping = base_mapping(c)
        return base_valid?(c) if mapping == c
        return false unless LABEL_SEPARATORS.include?(c) || mapping.each_char.all? { |m| base_valid?(m) }
        # Step 7: a mapping that is not wholly valid is disallowed, such
        # as the U+3002 of U+FE12, which is mapped itself. A mapping is
        # stable under NFKC_Casefold, so this needs no repeating.
        return false unless mapping.each_char.all? { |m| m == LABEL_SEPARATOR || status(m, statuses) == true }
        mapping
      end

      # Whether +c+ is unassigned in the Unicode version of the running
      # Ruby, or assigned after that of the generated data, whose
      # Bidi_Class and Joining_Type values it does not have.
      def unknown?(c)
        c.match?(UNASSIGNED) || (!NEWER_THAN_DATA.nil? && c.match?(NEWER_THAN_DATA))
      end

      # A pattern of the code points assigned after Unicode +version+, or
      # nil when the running Ruby does not know +version+, so knows no
      # later one either.
      def newer_than(version)
        Regexp.new("(?!\\p{Age=#{version[/\A\d+\.\d+/]}})\\P{Cn}").freeze
      rescue RegexpError
        nil
      end

      # Step 1: the base mapping of +c+.
      def base_mapping(c)
        return LABEL_SEPARATOR if LABEL_SEPARATORS.include?(c)
        return c if c.match?(BIDI_CONTROL)
        return SHARP_S if c == CAPITAL_SHARP_S
        nfkc_casefold(c)
      end

      # Step 2: whether +c+ is in the base valid set.
      def base_valid?(c)
        return c != LABEL_SEPARATOR if c.ord < 0x80
        return true if c == SHARP_S
        return false if c.match?(OTHER_OR_SEPARATOR) || c.match?(IDS_OPERATOR)
        nfkc_casefold(c) == c
      end

      # NFKC_Casefold: the closure of NFKC(toCasefold(NFKC(X))) with the
      # default ignorable code points removed.
      def nfkc_casefold(s)
        # Most code points have no decomposition, which NFKC keeps as they
        # are, and fold to themselves.
        return s if s.size == 1 && stable_code_point?(s)
        loop do
          t = NFC.normalize_kc(NFC.normalize_kc(s).downcase(:fold)).gsub(DEFAULT_IGNORABLE, "")
          return t if t == s
          s = t
        end
      end

      # Whether NFKC and case folding leave the code point +c+ unchanged,
      # and it is not default ignorable, so NFKC_Casefold does.
      def stable_code_point?(c)
        code_point = c.ord
        !NFC::DECOMPOSITION.key?(code_point) && !NFC::COMPATIBILITY_DECOMPOSITION.key?(code_point) &&
          c.downcase(:fold) == c && !c.match?(DEFAULT_IGNORABLE)
      end

      # Processing step 4 for a label that starts with "xn--". Returns the
      # decoded label, or nil.
      def decode_label(label)
        return nil unless label.ascii_only?
        decoded = Punycode.decode(label[ACE_PREFIX.size..-1])
        return nil if decoded.nil? || decoded.empty? || decoded.ascii_only?
        return nil unless NFC.normalized?(decoded)
        decoded
      end

      # Validity Criteria (UTS #46 section 4.1) for Nontransitional
      # Processing, except the Bidi Rule, which needs the whole domain.
      # Criterion 1 (NFC) holds for a label that was not decoded.
      #
      # +statuses+ caches #status by code point.
      def valid_label?(label, statuses = {})
        return true if label.empty?
        !label.start_with?(ACE_PREFIX) &&
          !label.include?(LABEL_SEPARATOR) &&
          !MARK.match?(label[0]) &&
          label.each_char.all? { |c| status(c, statuses) == true } &&
          valid_joiners?(label)
      end

      # CONTEXTJ rules (RFC 5892 Appendix A.1 and A.2).
      def valid_joiners?(label)
        return true unless label.include?(ZWNJ) || label.include?(ZWJ)
        chars = label.chars
        chars.each_with_index.all? do |char, i|
          case char
          when ZWJ
            i > 0 && virama?(chars[i - 1])
          when ZWNJ
            (i > 0 && virama?(chars[i - 1])) || joining_context?(chars, i)
          else
            true
          end
        end
      end

      def virama?(c)
        NFC::COMBINING_CLASS[c.ord] == VIRAMA_CLASS
      end

      # Whether the ZWNJ at +i+ is preceded by Joining_Type L or D and
      # followed by Joining_Type R or D, with only Joining_Type T between.
      def joining_context?(chars, i)
        before = i - 1
        before -= 1 while before >= 0 && JOINING_TYPE_T.match?(chars[before])
        return false unless before >= 0 && JOINING_TYPE_L_OR_D.match?(chars[before])

        after = i + 1
        after += 1 while after < chars.size && JOINING_TYPE_T.match?(chars[after])
        after < chars.size && JOINING_TYPE_R_OR_D.match?(chars[after])
      end

      # A Bidi domain name contains a code point with Bidi_Class R, AL or AN.
      def bidi_domain?(labels)
        labels.any? { |label| BIDI_RTL.match?(bidi_classes(label)) }
      end

      def satisfies_bidi_rule?(label)
        return true if label.empty?
        classes = bidi_classes(label)
        return false unless BIDI_FIRST.match?(classes)
        if BIDI_RTL.match?(classes)
          BIDI_RTL_ALLOWED.match?(classes) && BIDI_RTL_END.match?(classes) &&
            !(classes.include?("A") && classes.include?("E"))
        else
          BIDI_LTR_ALLOWED.match?(classes) && BIDI_LTR_END.match?(classes)
        end
      end

      def bidi_classes(label)
        label.each_char.map do |char|
          if BIDI_R_OR_AL.match?(char) then "R"
          elsif BIDI_AN.match?(char) then "A"
          elsif BIDI_EN.match?(char) then "E"
          elsif BIDI_ES_CS_ET_ON_BN.match?(char) then "N"
          elsif BIDI_NSM.match?(char) then "M"
          elsif BIDI_OTHER.match?(char) then "X"
          else "L"
          end
        end.join
      end
    end
  end
end
