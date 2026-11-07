# frozen_string_literal: true
#
# hi-quality, part of ableton-scripts - Copyright (C) 2026 Ari Russo
# SPDX-License-Identifier: GPL-3.0-or-later
# Licensed under the GNU GPL v3 or later, with an attribution term under
# section 7(b). See LICENSE and NOTICE in the ableton-scripts directory.

require "zlib"

# Turns on the high-quality / oversampling flag for Glue Compressor,
# EQ Eight and Saturator in Ableton Live Set (.als) files.
#
# An .als file is gzipped XML. Each target device stores its flag as a
# direct child element:
#
#   <GlueCompressor> ... <Oversample   Value="false"/>  -> "true"
#   <Eq8>            ... <Precision    Value="0"/>      -> "1"
#   <Saturator>      ... <Oversampling Value="0"/>      -> "1"     (Live 8-11)
#                        <Oversampling Value="false"/>  -> "true"  (Live 12)
#
# Edits are done as minimal text substitutions so the rest of the file is
# byte-for-byte unchanged.
module HiQuality
  DEVICES = {
    "glue" => { tag: "GlueCompressor", field: "Oversample" },
    "eq8"  => { tag: "Eq8",            field: "Precision" },
    "sat"  => { tag: "Saturator",      field: "Oversampling" },
  }.freeze

  # Off value => on value, preserving whichever format the file uses.
  ON_VALUE = { "false" => "true", "0" => "1" }.freeze
  ALREADY_ON = %w[true 1].freeze

  class Error < StandardError; end

  Stats = Struct.new(:changed, :already_on, :unrecognized) do
    def self.empty = new(0, 0, 0)
    def total = changed + already_on + unrecognized
  end

  module_function

  def read_als(path)
    Zlib::GzipReader.open(path) { |gz| gz.read }.force_encoding(Encoding::BINARY)
  rescue Zlib::GzipFile::Error => e
    raise Error, "#{path}: not a gzipped .als file (#{e.message})"
  end

  def write_als(path, xml)
    tmp = "#{path}.tmp-#{Process.pid}"
    Zlib::GzipWriter.open(tmp) { |gz| gz.write(xml) }
    File.rename(tmp, path)
  ensure
    File.delete(tmp) if tmp && File.exist?(tmp)
  end

  # Returns [new_xml, { "eq8" => Stats, ... }]. Does not mutate the input.
  def enable(xml, devices: DEVICES.keys)
    xml = xml.dup
    stats = {}

    devices.each do |key|
      spec = DEVICES.fetch(key) { raise Error, "unknown device #{key.inspect}" }
      tag = Regexp.escape(spec[:tag])
      field = Regexp.escape(spec[:field])
      block_re = %r{<#{tag}\s[^>]*>.*?</#{tag}>}m
      flag_re = /<#{field} Value="([^"]*)"/
      s = stats[key] = Stats.empty

      xml.gsub!(block_re) do |block|
        value = block[flag_re, 1]
        if ON_VALUE.key?(value)
          s.changed += 1
          block.sub(flag_re) { %(<#{spec[:field]} Value="#{ON_VALUE[value]}") }
        else
          ALREADY_ON.include?(value) ? s.already_on += 1 : s.unrecognized += 1
          block
        end
      end
    end

    [xml, stats]
  end

  # Safety check: the only differing lines must be the flag lines we changed.
  def verify!(before, after, expected_changes)
    a = before.lines
    b = after.lines
    raise Error, "line count changed (#{a.size} -> #{b.size})" unless a.size == b.size

    diffs = a.zip(b).reject { |x, y| x == y }
    fields = DEVICES.values.map { |d| Regexp.escape(d[:field]) }.join("|")
    bad = diffs.reject { |_, y| y.match?(/\A\s*<(?:#{fields}) Value="(?:true|1)" \/>\s*\z/) }
    raise Error, "unexpected change: #{bad.first.last.strip}" unless bad.empty?
    raise Error, "expected #{expected_changes} changed lines, got #{diffs.size}" unless diffs.size == expected_changes
  end

  def output_path(path, suffix)
    ext = File.extname(path)
    File.join(File.dirname(path), "#{File.basename(path, ext)}#{suffix}#{ext}")
  end

  # Expands file and directory arguments into .als paths, skipping Ableton's
  # Backup folders and files this tool already produced.
  def collect(paths, suffix)
    paths.flat_map do |p|
      if File.directory?(p)
        Dir.glob(File.join(p, "**", "*.als")).sort
           .reject { |f| f.split(File::SEPARATOR).include?("Backup") }
      elsif File.file?(p)
        [p]
      else
        raise Error, "#{p}: no such file or directory"
      end
    end.reject { |f| File.basename(f, ".als").end_with?(suffix) }.uniq
  end

  def process(path, devices:, suffix:, dry_run:, force:)
    out = output_path(path, suffix)
    if !dry_run && File.exist?(out) && !force
      raise Error, "#{out} already exists (use --force to overwrite)"
    end

    before = read_als(path)
    after, stats = enable(before, devices: devices)
    changed = stats.values.sum(&:changed)
    verify!(before, after, changed)

    write_als(out, after) unless dry_run || changed.zero?
    { path: path, out: out, stats: stats, changed: changed }
  end
end
