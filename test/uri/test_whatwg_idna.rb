# frozen_string_literal: false
require 'test/unit'
require 'uri'

# Domain to ASCII: UTS #46 ToASCII with the settings of the URL Standard
# (CheckHyphens=false, CheckBidi=true, CheckJoiners=true,
# UseSTD3ASCIIRules=false, Transitional_Processing=false,
# VerifyDnsLength=false, IgnoreInvalidPunycode=false).
class URI::TestWHATWGIDNA < Test::Unit::TestCase
  IDNA = URI::WHATWG_Parser::IDNA

  def assert_to_ascii(expected, domain)
    assert_equal(expected, IDNA.to_ascii(domain), "to_ascii(#{domain.dump})")
  end

  def assert_failure(domain)
    assert_nil(IDNA.to_ascii(domain), "to_ascii(#{domain.dump})")
  end

  # --- ASCII ---------------------------------------------------------

  def test_ascii_is_lowercased
    assert_to_ascii("example.com", "EXAMPLE.com")
  end

  def test_ascii_without_std3_rules
    assert_to_ascii("a_b.com", "a_b.com")
    assert_to_ascii("a b", "a b")
  end

  def test_hyphens_are_not_checked
    assert_to_ascii("-a-.com", "-a-.com")
    assert_to_ascii("ab--c.com", "ab--c.com")
  end

  def test_dns_length_is_not_verified
    assert_to_ascii("", "")
    assert_to_ascii("a..b", "a..b")
    assert_to_ascii("a.", "a.")
    assert_to_ascii("a" * 64, "a" * 64)
  end

  # --- Map -----------------------------------------------------------

  def test_mapped
    assert_to_ascii("example.com", "\uFF25\uFF38\uFF21\uFF2D\uFF30\uFF2C\uFF25.com")
    assert_to_ascii("a.com", "\u24D0.com")
  end

  def test_mapped_to_several_code_points
    assert_to_ascii("tm.com", "\u2122.com")
  end

  def test_ignored
    assert_to_ascii("example.com", "ex\u00ADample.com")
  end

  def test_ideographic_full_stop_separates_labels
    assert_to_ascii("xn--wgv71a119e.jp", "\u65E5\u672C\u8A9E\u3002jp")
    assert_to_ascii("xn--wgv71a119e.jp", "\u65E5\u672C\u8A9E\uFF0Ejp")
    assert_to_ascii("xn--wgv71a119e.jp", "\u65E5\u672C\u8A9E\uFF61jp")
  end

  def test_deviation_is_kept
    assert_to_ascii("xn--fa-hia.de", "fa\u00DF.de")
    assert_to_ascii("xn--fa-hia.de", "FA\u1E9E.de")
  end

  # --- Mapping table derivation (UTS #46 section 6) -----------------
  # The IDNA Mapping Table is derived from the Unicode data of the
  # running Ruby.

  # Step 1: the label separators map to ".", Bidi_Control characters
  # to themselves (so step 6 disallows them), and U+1E9E to U+00DF.
  def test_derivation_base_mapping_exceptions
    assert_to_ascii("a.b", "a\u{FF0E}b")
    assert_to_ascii("a.b", "a\u{FF61}b")
    assert_to_ascii(".", "\u{3002}")
    assert_failure("a\u{200E}b")
    assert_failure("a\u{202A}b")
    assert_to_ascii("xn--zca", "\u{1E9E}")
  end

  # Step 1 otherwise: NFKC_Casefold, which removes default ignorable
  # code points.
  def test_derivation_nfkc_casefold
    assert_to_ascii("viii", "\u{2167}")
    assert_to_ascii("ffi", "\u{FB03}")
    assert_to_ascii("xn--bya", "\u{2126}")
    assert_to_ascii("ab", "a\u{AD}b")
    assert_to_ascii("ab", "a\u{200B}b")
    assert_to_ascii("ab", "a\u{180E}b")
    assert_to_ascii("ab", "a\u{FE0F}b")
    assert_to_ascii("ab", "a\u{E0100}b")
  end

  # The full case folding, including the code points that
  # String#downcase(:fold) of TruffleRuby folds only partly or to
  # lowercase.
  def test_case_fold
    assert_equal("", IDNA.case_fold(""))
    assert_equal("a1-", IDNA.case_fold("A1-"))
    assert_equal("ss", IDNA.case_fold("\u{DF}"))
    assert_equal("ss", IDNA.case_fold("\u{1E9E}"))
    assert_equal("i\u{307}", IDNA.case_fold("\u{130}"))
    assert_equal("\u{1F00}\u{3B9}", IDNA.case_fold("\u{1F88}"))
    assert_equal("\u{1F00}\u{3B9}", IDNA.case_fold("\u{1F80}"))
    assert_equal("\u{3B1}\u{3B9}", IDNA.case_fold("\u{1FBC}"))
    assert_equal("\u{3C9}\u{3B9}", IDNA.case_fold("\u{1FFC}"))
    # Cherokee folds to uppercase, from both ends of each range.
    assert_equal("\u{13A0}\u{13F5}", IDNA.case_fold("\u{13A0}\u{13F5}"))
    assert_equal("\u{13A0}\u{13AF}", IDNA.case_fold("\u{AB70}\u{AB7F}"))
    assert_equal("\u{13F0}\u{13F5}", IDNA.case_fold("\u{13F8}\u{13FD}"))
    assert_equal("a\u{13A0}ss", IDNA.case_fold("A\u{AB70}\u{1E9E}"))
  end

  def test_nfkc_casefold_of_cherokee
    assert_equal("\u{13F1}", IDNA.nfkc_casefold("\u{13F1}"))
    assert_equal("\u{13F1}", IDNA.nfkc_casefold("\u{13F9}"))
    assert_equal("\u{13A0}", IDNA.nfkc_casefold("\u{AB70}"))
    assert_to_ascii("xn--hce", "\u{13F1}")
    assert_to_ascii("xn--hce", "\u{13F9}")
    assert_to_ascii("xn--58d", "\u{AB70}")
    assert_to_ascii("xn--uxa970l", "\u{1F88}")
    assert_to_ascii("xn--mxaq", "\u{1FBC}")
  end

  # Step 2: the base valid set has the ASCII code points but ".", and no
  # other control, format, private use, unassigned or separator code
  # point, nor IDS operator.
  def test_derivation_base_valid_set
    assert_to_ascii("a\u{0}b", "a\u{0}b")
    assert_to_ascii("a b", "a\u{A0}b")
    assert_to_ascii("a b", "a\u{3000}b")
    assert_failure("a\u{2028}b")
    assert_failure("a\u{E000}")
    assert_failure("a\u{FDD0}")
    assert_failure("a\u{2FF0}b")
    assert_failure("a\u{2FFE}b")
    assert_to_ascii("xn--a-jv3s", "a\u{1F600}")
    assert_to_ascii("xn--o39a", "\u{AC00}")
  end

  # Step 3: the base exclusion set.
  def test_derivation_base_exclusion_set
    assert_failure("a\u{FFFC}")
    assert_failure("a\u{FFFD}")
    assert_failure("a\u{E0001}")
    assert_failure("a\u{E007F}")
  end

  # Step 4: the deviations are valid in Nontransitional Processing.
  def test_derivation_deviations
    assert_to_ascii("xn--a-ymb", "a\u{3C2}")
    assert_to_ascii("xn--fa-hia.de", "fa\u{DF}.de")
  end

  # Step 6: an unassigned code point is disallowed, as is one whose
  # mapping has a code point outside the base valid set, such as the
  # "." of U+2488 DIGIT ONE FULL STOP.
  def test_derivation_disallowed
    assert_failure("a\u{378}")
    assert_failure("a\u{2488}b")
  end

  # Step 7: a mapping must be wholly valid. U+FE12 maps to U+3002, which
  # is mapped itself.
  def test_derivation_mapping_to_a_mapped_code_point
    assert_failure("a\u{FE12}b")
  end

  # A code point added in a later Unicode version than the running
  # Ruby's is unassigned, so disallowed.
  def test_code_point_unknown_to_ruby_is_disallowed
    unknown = (0x30000..0x3FFFD).find { |c| c.chr(Encoding::UTF_8).match?(/\p{Cn}/) }
    assert_failure("a" + unknown.chr(Encoding::UTF_8))
  end

  # NFKC_Casefold of one code point, computed with String#unicode_normalize
  # instead of URI::WHATWG_Parser::NFC.
  def reference_nfkc_casefold(s)
    loop do
      t = IDNA.case_fold(s.unicode_normalize(:nfkc)).unicode_normalize(:nfkc).gsub(/\p{Default_Ignorable_Code_Point}/, "")
      return t if t == s
      s = t
    end
  end

  # Every code point with a decomposition or a combining class, and a
  # sample of the others.
  def test_nfkc_casefold
    require "unicode_normalize/tables"
    IDNA.load_data
    chars = UnicodeNormalize::KOMPATIBLE_TABLE.keys + UnicodeNormalize::DECOMPOSITION_TABLE.keys +
            UnicodeNormalize::CLASS_TABLE.keys
    chars += (0x80..0x10FFFF).step(97).reject { |c| (0xD800..0xDFFF).cover?(c) }.map { |c| c.chr(Encoding::UTF_8) }
    chars += ["A", "\u{DF}", "\u{1E9E}", "\u{130}", "\u{FB03}", "\u{AD}", "\u{AC00}", "\u{2126}", "\u{1F600}"]
    wrong = chars.uniq.reject { |c| IDNA.nfkc_casefold(c) == reference_nfkc_casefold(c) }
    assert_equal([], wrong.map(&:dump))
  end

  # The Bidi_Class and Joining_Type values come from generated data, so
  # a code point that Ruby knows but the data does not, on a Ruby whose
  # Unicode version is newer, is disallowed.
  def test_newer_than_matches_code_points_assigned_after_a_version
    newer = IDNA.newer_than("6.0.0")
    assert_match(newer, "\u{1F600}") # Unicode 6.1
    assert_no_match(newer, "\u{263A}") # Unicode 1.1
    assert_no_match(newer, "a")
    assert_no_match(newer, "\u{378}") # unassigned
    assert_no_match(newer, "\u{FDD0}") # noncharacter
    assert_predicate(newer, :frozen?)
  end

  def test_newer_than_a_version_that_ruby_does_not_know_is_nil
    assert_nil(IDNA.newer_than("999.0.0"))
  end

  def test_code_point_newer_than_the_data_is_disallowed
    assert_separately([], <<~'RUBY')
      require "uri"
      idna = URI::WHATWG_Parser::IDNA
      idna.load_data
      idna.send(:remove_const, :NEWER_THAN_DATA)
      idna.const_set(:NEWER_THAN_DATA, idna.newer_than("6.0.0"))
      assert_nil(idna.to_ascii("a\u{1F600}"))
      assert_nil(idna.to_ascii("xn--a-jv3s"))
      assert_equal("xn--a-60p", idna.to_ascii("a\u{263A}"))
    RUBY
  end

  # --- Normalize -----------------------------------------------------

  def test_normalized_to_nfc
    assert_to_ascii("xn--9ca.com", "e\u0301.com")
  end

  # --- Convert -------------------------------------------------------

  def test_non_ascii_labels_are_converted
    assert_to_ascii("xn--wgv71a119e.jp", "\u65E5\u672C\u8A9E.jp")
    assert_to_ascii("xn--tda.xn--tda", "\u00FC.\u00DC")
  end

  def test_result_is_ascii
    assert_predicate(IDNA.to_ascii("\u65E5\u672C\u8A9E.jp"), :ascii_only?)
  end

  def test_empty_labels_around_non_ascii
    assert_to_ascii("xn--tda..com", "\u00FC..com")
    assert_to_ascii("xn--tda.", "\u00FC.")
    assert_to_ascii(".xn--tda", ".\u00FC")
  end

  # --- Validity criteria ---------------------------------------------

  def test_disallowed
    assert_failure("\uFFFD.com")
    assert_failure("a\u2028b.com")
    assert_failure("\uE000.com")
    assert_failure("\u{E0001}.com")
  end

  def test_leading_combining_mark
    assert_failure("\u0301a.com")
    assert_to_ascii("xn--9ca.com", "e\u0301.com")
  end

  def test_label_starting_with_xn_dash_dash_and_non_ascii
    assert_failure("xn--\u00FC.com")
  end

  # --- Punycode labels -----------------------------------------------

  def test_valid_punycode_label_is_kept
    assert_to_ascii("xn--tda.xn--tda", "xn--tda.\u00FC")
    assert_to_ascii("xn--tda.xn--tda", "XN--TDA.\u00FC")
  end

  def test_invalid_punycode
    assert_failure("xn--a-!.\u00FC")
    assert_failure("xn--a-9.\u00FC")
  end

  def test_empty_punycode
    assert_failure("xn--.\u00FC")
    assert_failure("xn---.\u00FC")
  end

  def test_ascii_only_punycode
    assert_failure("xn--ascii-.\u00FC")
  end

  def test_punycode_decoding_to_disallowed
    assert_failure("xn--a.\u00FC") # U+0080
  end

  def test_punycode_decoding_to_mapped
    # U+24D0 is mapped; a decoded label is validated, not mapped.
    assert_failure("xn--vuh.\u00FC")
  end

  def test_punycode_decoding_to_non_nfc
    assert_failure("xn--e-xbb.\u00FC") # "e\u0301"
  end

  # --- CheckJoiners --------------------------------------------------

  def test_zwnj_after_virama
    assert_to_ascii("xn--11b2ezcs70k", "\u0915\u094D\u200C\u0937")
  end

  def test_zwnj_in_joining_context
    assert_to_ascii("xn--ngba799q", "\u0628\u200C\u0628")
  end

  def test_zwnj_in_joining_context_with_transparent
    assert_equal(
      IDNA.to_ascii("\u0628\u064B\u200C\u064B\u0628"),
      "xn--" + URI::WHATWG_Parser::Punycode.encode("\u0628\u064B\u200C\u064B\u0628")
    )
  end

  def test_zwnj_without_context
    assert_failure("a\u200Cb")
    assert_failure("\u200Cb")
    assert_failure("\u0628\u200C")
    assert_failure("\u200C\u0628")
  end

  def test_zwj_after_virama
    assert_to_ascii("xn--11b2ezcw70k", "\u0915\u094D\u200D\u0937")
  end

  def test_zwj_without_virama
    assert_failure("a\u200Db")
    assert_failure("\u200Db")
    assert_failure("\u0628\u200D\u0628")
  end

  # --- CheckBidi -----------------------------------------------------

  def test_rtl_label
    assert_to_ascii("xn--4dbc.com", "\u05D0\u05D1.com")
  end

  def test_rtl_label_ending_with_nsm
    assert_to_ascii("xn--7cb7d", "\u05D0\u05B0")
  end

  def test_rtl_label_with_an
    assert_to_ascii("xn--mgb0j", "\u0627\u0661")
  end

  def test_rtl_label_with_en_at_the_end
    assert_to_ascii("xn--1-zhc", "\u05D01")
  end

  def test_rtl_label_with_l
    assert_failure("\u05D0a")
  end

  def test_rtl_label_starting_with_an
    assert_failure("\u0661\u0627")
  end

  def test_rtl_label_mixing_an_and_en
    assert_failure("\u0627\u0661\u06F1")
  end

  def test_rtl_label_ending_with_on
    assert_failure("\u05D0!")
  end

  def test_ltr_label_with_r
    assert_failure("a\u05D0")
  end

  def test_ltr_label_in_a_bidi_domain_starting_with_en
    assert_failure("1a.\u05D0")
  end

  def test_ltr_label_in_a_bidi_domain_ending_with_on
    assert_failure("a!.\u05D0")
  end

  def test_ltr_label_outside_a_bidi_domain_is_not_checked
    assert_to_ascii("1a.xn--tda", "1a.\u00FC")
  end

  # --- Input ---------------------------------------------------------

  # A non-main Ractor can read only shareable constants.
  def test_constants_are_shareable
    omit "Ractor is not available" unless defined?(Ractor)
    IDNA.load_data
    [IDNA, URI::WHATWG_Parser::NFC].each do |mod|
      assert_equal([], mod.constants.reject { |c| Ractor.shareable?(mod.const_get(c)) }, mod.name)
    end
  end

  def test_invalid_utf8
    assert_failure("\xFF.com".dup.force_encoding(Encoding::UTF_8))
  end

  def test_input_is_not_modified
    domain = "\u00DC.com"
    IDNA.to_ascii(domain)
    assert_equal("\u00DC.com", domain)
  end
end
