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

  def test_invalid_utf8
    assert_failure("\xFF.com".dup.force_encoding(Encoding::UTF_8))
  end

  def test_input_is_not_modified
    domain = "\u00DC.com"
    IDNA.to_ascii(domain)
    assert_equal("\u00DC.com", domain)
  end
end
