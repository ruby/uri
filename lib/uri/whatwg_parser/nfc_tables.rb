# frozen_string_literal: true
require "unicode_normalize/tables"

module URI
  class WHATWG_Parser
    # The tables of NFC and NFKC, built from those of
    # String#unicode_normalize, which are shareable between Ractors.
    module NFC # :nodoc:
      # Canonical_Combining_Class by code point, for classes other than 0.
      COMBINING_CLASS = UnicodeNormalize::CLASS_TABLE.each_with_object({}) do |(char, ccc), classes|
        classes[char.ord] = ccc
      end.freeze

      # The full canonical decomposition by code point, except Hangul
      # syllables.
      DECOMPOSITION = UnicodeNormalize::DECOMPOSITION_TABLE.each_with_object({}) do |(char, target), decompositions|
        decompositions[char.ord] = target.codepoints.freeze
      end.freeze

      # The full compatibility decomposition by code point, for the code
      # points whose compatibility decomposition differs from their
      # canonical one. The targets in UnicodeNormalize::KOMPATIBLE_TABLE
      # may still have canonical decompositions, such as U+0F81 in that of
      # U+0F77.
      COMPATIBILITY_DECOMPOSITION = UnicodeNormalize::KOMPATIBLE_TABLE.each_with_object({}) do |(char, target), decompositions|
        decompositions[char.ord] = decompose(target.codepoints).freeze
      end.freeze

      # The primary composite by pair of code points (see pair_key),
      # except Hangul syllables.
      COMPOSITION = UnicodeNormalize::COMPOSITION_TABLE.each_with_object({}) do |(pair, char), compositions|
        first, second = pair.codepoints
        compositions[pair_key(first, second)] = char.ord
      end.freeze

      Ractor.make_shareable(DECOMPOSITION) if defined?(Ractor)
      Ractor.make_shareable(COMPATIBILITY_DECOMPOSITION) if defined?(Ractor)
    end
  end
end
