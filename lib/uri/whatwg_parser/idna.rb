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
    # The Unicode data (idna_data.rb) is loaded on first use.
    module IDNA # :nodoc:
      ACE_PREFIX = "xn--"
      LABEL_SEPARATOR = "."
      ZWNJ = 0x200C.chr(Encoding::UTF_8)
      ZWJ = 0x200D.chr(Encoding::UTF_8)

      # Every code point the IDNA Mapping Table leaves unchanged is
      # matched out; ASCII code points other than A-Z are among them.
      MAPPING_CANDIDATE = /[A-Z]|[^\x00-\x7F]/

      # The Bidi Rule (RFC 5893 section 2), over a label whose code points
      # are replaced by their Bidi_Class: L, R (R or AL), A (AN), E (EN),
      # N (ES, CS, ET, ON or BN), M (NSM), or X (anything else).
      BIDI_RTL = /[RA]/
      BIDI_FIRST = /\A[LR]/
      BIDI_RTL_ALLOWED = /\A[RAENM]*\z/
      BIDI_RTL_END = /[RAE]M*\z/
      BIDI_LTR_ALLOWED = /\A[LENM]*\z/
      BIDI_LTR_END = /[LE]M*\z/

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

        mapped = domain.gsub(MAPPING_CANDIDATE) { |c| MAPPING.fetch(c, c) }
        labels = mapped.unicode_normalize(:nfc).split(LABEL_SEPARATOR, -1)
        labels.map! do |label|
          label = decode_label(label) if label.start_with?(ACE_PREFIX)
          return nil unless label && valid_label?(label)
          label
        end
        return nil if bidi_domain?(labels) && !labels.all? { |label| satisfies_bidi_rule?(label) }
        labels
      end

      def load_data
        require_relative "idna_data" unless const_defined?(:MAPPING, false)
      end

      # Processing step 4 for a label that starts with "xn--". Returns the
      # decoded label, or nil.
      def decode_label(label)
        return nil unless label.ascii_only?
        decoded = Punycode.decode(label[ACE_PREFIX.size..-1])
        return nil if decoded.nil? || decoded.empty? || decoded.ascii_only?
        return nil unless decoded.unicode_normalized?(:nfc)
        decoded
      end

      # Validity Criteria (UTS #46 section 4.1) for Nontransitional
      # Processing, except the Bidi Rule, which needs the whole domain.
      # Criterion 1 (NFC) holds for a label that was not decoded.
      def valid_label?(label)
        return true if label.empty?
        !label.start_with?(ACE_PREFIX) &&
          !label.include?(LABEL_SEPARATOR) &&
          !MARK.match?(label[0]) &&
          !INVALID.match?(label) &&
          valid_joiners?(label)
      end

      # CONTEXTJ rules (RFC 5892 Appendix A.1 and A.2).
      def valid_joiners?(label)
        return true unless label.include?(ZWNJ) || label.include?(ZWJ)
        chars = label.chars
        chars.each_with_index.all? do |char, i|
          case char
          when ZWJ
            i > 0 && VIRAMA.match?(chars[i - 1])
          when ZWNJ
            (i > 0 && VIRAMA.match?(chars[i - 1])) || joining_context?(chars, i)
          else
            true
          end
        end
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
          if BIDI_L.match?(char) then "L"
          elsif BIDI_R_OR_AL.match?(char) then "R"
          elsif BIDI_AN.match?(char) then "A"
          elsif BIDI_EN.match?(char) then "E"
          elsif BIDI_ES_CS_ET_ON_BN.match?(char) then "N"
          elsif BIDI_NSM.match?(char) then "M"
          else "X"
          end
        end.join
      end
    end
  end
end
