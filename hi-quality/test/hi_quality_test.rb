# frozen_string_literal: true
#
# hi-quality, part of ableton-scripts - Copyright (C) 2026 Ari Russo
# SPDX-License-Identifier: GPL-3.0-or-later
# Licensed under the GNU GPL v3 or later, with an attribution term under
# section 7(b). See LICENSE and NOTICE in the ableton-scripts directory.

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/hi_quality"

class HiQualityTest < Minitest::Test
  # Mirrors the real structure: tab-indented, " />" self-closing, devices
  # nested inside a rack chain, Live 11 int / Live 12 bool Saturator formats.
  XML = <<~XML.b.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <Ableton MajorVersion="5" Creator="Ableton Live 11.3.42">
    \t<Devices>
    \t\t<GlueCompressor Id="1">
    \t\t\t<On><Manual Value="true" /></On>
    \t\t\t<Oversample Value="false" />
    \t\t</GlueCompressor>
    \t\t<Eq8 Id="2">
    \t\t\t<Precision Value="0" />
    \t\t\t<Mode Value="0" />
    \t\t</Eq8>
    \t\t<AudioEffectGroupDevice Id="3">
    \t\t\t<Eq8 Id="4">
    \t\t\t\t<Precision Value="1" />
    \t\t\t</Eq8>
    \t\t\t<Saturator Id="5">
    \t\t\t\t<Oversampling Value="0" />
    \t\t\t</Saturator>
    \t\t</AudioEffectGroupDevice>
    \t\t<Saturator Id="6">
    \t\t\t<Oversampling Value="false" />
    \t\t</Saturator>
    \t\t<UserName Value="Eq8 notes Precision 0 caf\xC3\xA9" />
    \t</Devices>
    </Ableton>
  XML

  def test_turns_on_every_device_and_keeps_value_format
    out, stats = HiQuality.enable(XML)

    assert_includes out, %(<Oversample Value="true" />)
    assert_equal 0, out.scan(/<Precision Value="0"/).size
    assert_equal 2, out.scan(/<Precision Value="1"/).size
    assert_includes out, %(<Oversampling Value="1" />)    # Live 11 format kept
    assert_includes out, %(<Oversampling Value="true" />) # Live 12 format kept
    refute_includes out, %(<Oversampling Value="false")

    assert_equal [1, 0], [stats["glue"].changed, stats["glue"].already_on]
    assert_equal [1, 1], [stats["eq8"].changed, stats["eq8"].already_on]
    assert_equal [2, 0], [stats["sat"].changed, stats["sat"].already_on]
  end

  def test_only_flag_lines_change
    out, stats = HiQuality.enable(XML)
    changed = stats.values.sum(&:changed)
    HiQuality.verify!(XML, out, changed) # raises on anything unexpected
    assert_equal 4, XML.lines.zip(out.lines).count { |a, b| a != b }
  end

  def test_does_not_mutate_input
    copy = XML.dup
    HiQuality.enable(XML)
    assert_equal copy, XML
  end

  def test_device_subset
    out, stats = HiQuality.enable(XML, devices: ["eq8"])
    assert_equal ["eq8"], stats.keys
    assert_includes out, %(<Oversample Value="false" />)
    assert_includes out, %(<Oversampling Value="0" />)
  end

  def test_idempotent
    once, = HiQuality.enable(XML)
    twice, stats = HiQuality.enable(once)
    assert_equal once, twice
    assert_equal 0, stats.values.sum(&:changed)
  end

  def test_unrecognized_value_left_alone
    xml = %(<Eq8 Id="1">\n<Precision Value="7" />\n</Eq8>\n).b
    out, stats = HiQuality.enable(xml)
    assert_equal xml, out
    assert_equal 1, stats["eq8"].unrecognized
  end

  def test_verify_rejects_unexpected_edits
    tampered = XML.sub(%(<Mode Value="0" />), %(<Mode Value="1" />))
    assert_raises(HiQuality::Error) { HiQuality.verify!(XML, tampered, 1) }
  end

  def test_file_round_trip_and_cli_safety
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "Song Project", "Backup"))
      src = File.join(dir, "Song Project", "Song.als")
      HiQuality.write_als(src, XML)
      HiQuality.write_als(File.join(dir, "Song Project", "Backup", "Song [old].als"), XML)
      original = File.binread(src)

      files = HiQuality.collect([dir], "-hq")
      assert_equal [src], files # Backup skipped

      r = HiQuality.process(src, devices: HiQuality::DEVICES.keys, suffix: "-hq", dry_run: false, force: false)
      assert_equal File.join(dir, "Song Project", "Song-hq.als"), r[:out]
      assert_equal 4, r[:changed]
      assert_equal original, File.binread(src) # original untouched
      assert_includes HiQuality.read_als(r[:out]), %(<Oversample Value="true" />)

      assert_raises(HiQuality::Error) do
        HiQuality.process(src, devices: HiQuality::DEVICES.keys, suffix: "-hq", dry_run: false, force: false)
      end
      assert_equal [src], HiQuality.collect([dir], "-hq") # own output skipped
    end
  end
end
