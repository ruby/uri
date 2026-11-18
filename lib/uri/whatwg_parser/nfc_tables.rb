# frozen_string_literal: true
require_relative "idna_data"

module URI
  class WHATWG_Parser
    module NFC # :nodoc:
      # Canonical_Combining_Class by code point, for classes other than 0.
      COMBINING_CLASS = IDNA::COMBINING_CLASS.each_with_object({}) do |(char, ccc), classes|
        classes[char.ord] = ccc
      end.freeze

      raw = IDNA::CANONICAL_DECOMPOSITION.each_with_object({}) do |(char, target), mappings|
        mappings[char.ord] = target.codepoints
      end
      full = lambda do |code_point|
        mapping = raw[code_point]
        mapping ? mapping.flat_map { |c| full.call(c) } : [code_point]
      end

      # The full canonical decomposition by code point, except Hangul
      # syllables.
      DECOMPOSITION = raw.keys.each_with_object({}) do |code_point, decompositions|
        decompositions[code_point] = full.call(code_point).freeze
      end.freeze

      # The primary composite by pair of code points (see pair_key),
      # except Hangul syllables.
      COMPOSITION = IDNA::CANONICAL_DECOMPOSITION.each_with_object({}) do |(char, target), compositions|
        next unless target.size == 2 && !IDNA::COMPOSITION_EXCLUSION.match?(char)
        first, second = target.codepoints
        compositions[pair_key(first, second)] = char.ord
      end.freeze

      Ractor.make_shareable(DECOMPOSITION) if defined?(Ractor)
    end
  end
end
