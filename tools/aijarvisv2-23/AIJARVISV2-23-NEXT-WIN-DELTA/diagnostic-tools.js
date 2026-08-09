"use strict";

(function () {
  function utf8Codepoints(value) {
    var count = 0;
    var index = 0;
    while (index < value.length) {
      var first = value.charCodeAt(index);
      if (first >= 0xd800 && first <= 0xdbff && index + 1 < value.length) {
        var second = value.charCodeAt(index + 1);
        if (second >= 0xdc00 && second <= 0xdfff) index += 1;
      }
      count += 1;
      index += 1;
    }
    return count;
  }

  function isArray(value) {
    return Object.prototype.toString.call(value) === "[object Array]";
  }

  function parseCompleteJson(raw) {
    try {
      return { complete: true, value: JSON.parse(raw) };
    } catch (error) {
      return { complete: false, value: null };
    }
  }

  function validateThreeBatches(parsed, options, raw) {
    var result = {
      schema_valid: false,
      schema_error: "invalid_root",
      batch_count: 0,
      response_chars: utf8Codepoints(raw),
      batches: null
    };
    if (!parsed || typeof parsed !== "object" || isArray(parsed) || !isArray(parsed.batches)) {
      return result;
    }
    result.batch_count = parsed.batches.length;
    result.batches = parsed.batches;
    if (parsed.batches.length !== 3) {
      result.schema_error = "batch_count";
      return result;
    }
    for (var index = 0; index < 3; index += 1) {
      var batch = parsed.batches[index];
      if (!batch || typeof batch !== "object" || isArray(batch) ||
          batch.style_id !== options.styleIds[index] || !isArray(batch.items) ||
          batch.items.length < options.minimumItems || batch.items.length > options.maximumItems) {
        result.schema_error = "batch_schema";
        return result;
      }
      for (var itemIndex = 0; itemIndex < batch.items.length; itemIndex += 1) {
        if (typeof batch.items[itemIndex] !== "string" || batch.items[itemIndex].length === 0) {
          result.schema_error = "batch_schema";
          return result;
        }
      }
    }
    if (options.budgetChars > 0 && result.response_chars > options.budgetChars) {
      result.schema_error = "budget_exceeded";
      return result;
    }
    result.schema_valid = true;
    result.schema_error = null;
    return result;
  }

  function aggregateEvents(events, options) {
    var fragments = [];
    var aggregates = [];
    var current = null;
    var failedResults = 0;
    var listenResults = 0;
    var speakResults = 0;
    var nextAggregateId = 1;

    function flushCurrent(completionBasis, parsed) {
      if (!current) return;
      var validation = parsed && parsed.complete
        ? validateThreeBatches(parsed.value, options, current.text)
        : {
            schema_valid: false,
            schema_error: "incomplete_json",
            batch_count: 0,
            response_chars: utf8Codepoints(current.text),
            batches: null
          };
      aggregates.push({
        aggregate_id: current.aggregateId,
        generation_id: current.generation,
        first_asset_sequence: current.firstSequence,
        last_asset_sequence: current.lastSequence,
        fragment_count: current.fragmentCount,
        aggregated_text: current.text,
        completion_basis: completionBasis,
        json_parse_complete: !!(parsed && parsed.complete),
        schema_valid: validation.schema_valid,
        schema_error: validation.schema_error,
        batch_count: validation.batch_count,
        response_chars: validation.response_chars,
        batches: validation.batches
      });
      current = null;
    }

    for (var eventIndex = 0; eventIndex < events.length; eventIndex += 1) {
      var event = events[eventIndex];
      if (!event || event.event !== "duplex_result") continue;
      var generation = Number(event.run_generation);
      if (current && current.generation !== generation) {
        flushCurrent("generation_change_without_complete_json", null);
      }
      if (event.ok !== true) {
        failedResults += 1;
        flushCurrent("failed_result_boundary", null);
        continue;
      }
      if (event.is_speak !== true) {
        listenResults += 1;
        flushCurrent("listen_boundary_without_complete_json", null);
        continue;
      }

      speakResults += 1;
      if (!current) {
        current = {
          aggregateId: nextAggregateId,
          generation: generation,
          firstSequence: Number(event.asset_sequence),
          lastSequence: Number(event.asset_sequence),
          fragmentCount: 0,
          text: ""
        };
        nextAggregateId += 1;
      }
      current.lastSequence = Number(event.asset_sequence);
      current.fragmentCount += 1;
      current.text += typeof event.raw_response === "string" ? event.raw_response : "";
      var parsed = parseCompleteJson(current.text);
      var fragment = {
        aggregate_id: current.aggregateId,
        generation_id: generation,
        fragment_index: current.fragmentCount,
        asset_sequence: Number(event.asset_sequence),
        user_seq: event.user_seq,
        frame_id: event.frame_id,
        monotonic_timestamp_us: event.monotonic_timestamp_us,
        utc_timestamp: event.utc_timestamp,
        raw_fragment: typeof event.raw_response === "string" ? event.raw_response : "",
        aggregate_chars_after_fragment: utf8Codepoints(current.text),
        validation_status: "awaiting_completion"
      };
      if (parsed.complete) {
        var validation = validateThreeBatches(parsed.value, options, current.text);
        fragment.validation_status = validation.schema_valid
          ? "completed_valid_json"
          : "completed_invalid_schema";
      }
      fragments.push(fragment);
      if (parsed.complete) flushCurrent("aggregate_json_parse_complete", parsed);
    }
    flushCurrent("evidence_end_without_complete_json", null);

    var validCount = 0;
    for (var aggregateIndex = 0; aggregateIndex < aggregates.length; aggregateIndex += 1) {
      if (aggregates[aggregateIndex].schema_valid) validCount += 1;
    }
    return {
      schema_version: 1,
      completion_rule: "contiguous ok:true SPEAK fragments in one run_generation; close at complete JSON or explicit result boundary",
      completion_field_available: false,
      speak_results: speakResults,
      listen_results: listenResults,
      failed_results: failedResults,
      fragment_count: fragments.length,
      aggregate_count: aggregates.length,
      valid_three_batch_aggregates: validCount,
      fragments: fragments,
      aggregates: aggregates
    };
  }

  function sha256File(filePath) {
    if (typeof require !== "function") {
      throw new Error("sha256File is available to the zero-GPU Node self-check only");
    }
    var crypto = require("crypto");
    var fs = require("fs");
    return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
  }

  function validateTimeline(manifest, root, expectedDurationMs, verifyHashes) {
    if (!manifest || manifest.input_id !== "O-IN-07" || !isArray(manifest.style_ids) ||
        manifest.style_ids.length !== 3 || !isArray(manifest.chunks) || manifest.chunks.length === 0) {
      throw new Error("invalid O-IN-07 manifest identity, styles, or chunks");
    }
    var nodePath = typeof require === "function" ? require("path") : null;
    var nodeFs = typeof require === "function" ? require("fs") : null;
    var rounds = [];
    for (var index = 0; index < manifest.chunks.length; index += 1) {
      var chunk = manifest.chunks[index];
      var expectedSequence = index + 1;
      var expectedOffset = index * expectedDurationMs;
      if (Number(chunk.sequence) !== expectedSequence || Number(chunk.offset_ms) !== expectedOffset ||
          Number(chunk.duration_ms) !== expectedDurationMs) {
        throw new Error("O-IN-07 timeline is not continuous at sequence " + expectedSequence);
      }
      if (typeof chunk.marker !== "string" || chunk.marker.length === 0) {
        throw new Error("empty marker at sequence " + expectedSequence);
      }
      if (nodePath && nodeFs) {
        var paths = [
          { relative: chunk.audio, hash: chunk.audio_sha256 },
          { relative: chunk.image, hash: chunk.image_sha256 }
        ];
        for (var assetIndex = 0; assetIndex < paths.length; assetIndex += 1) {
          var absolute = nodePath.join(root, paths[assetIndex].relative);
          if (!nodeFs.statSync(absolute).isFile()) throw new Error("missing input asset: " + absolute);
          if (verifyHashes && sha256File(absolute) !== String(paths[assetIndex].hash).toLowerCase()) {
            throw new Error("input asset SHA-256 mismatch: " + absolute);
          }
        }
      }
      rounds.push({
        sequence: expectedSequence,
        offset_ms: expectedOffset,
        duration_ms: expectedDurationMs,
        marker: chunk.marker,
        source_sequence: chunk.source_sequence || chunk.sequence,
        source_part: chunk.source_part || 1,
        audio: chunk.audio,
        image: chunk.image
      });
    }
    var timelineEnd = manifest.chunks.length * expectedDurationMs;
    if (Number(manifest.duration_ms) !== timelineEnd) {
      throw new Error("manifest duration does not equal timeline end");
    }
    if (nodePath && nodeFs) {
      var metadata = [
        { relative: manifest.authorization_record, hash: manifest.authorization_sha256 },
        { relative: manifest.gold_record, hash: manifest.gold_sha256 }
      ];
      for (var metadataIndex = 0; metadataIndex < metadata.length; metadataIndex += 1) {
        var metadataPath = nodePath.join(root, metadata[metadataIndex].relative);
        if (!nodeFs.statSync(metadataPath).isFile()) throw new Error("missing metadata: " + metadataPath);
        if (verifyHashes && sha256File(metadataPath) !== String(metadata[metadataIndex].hash).toLowerCase()) {
          throw new Error("metadata SHA-256 mismatch: " + metadataPath);
        }
      }
    }
    return { chunk_count: manifest.chunks.length, timeline_end_ms: timelineEnd, rounds: rounds };
  }

  function readUtf8(filePath) {
    return require("fs").readFileSync(filePath, "utf8");
  }

  function writeUtf8(filePath, value) {
    require("fs").writeFileSync(filePath, value, "utf8");
  }

  function readJsonl(filePath) {
    var lines = readUtf8(filePath).replace(/^\ufeff/, "").split(/\r?\n/);
    var records = [];
    for (var index = 0; index < lines.length; index += 1) {
      if (lines[index].replace(/^\s+|\s+$/g, "").length > 0) records.push(JSON.parse(lines[index]));
    }
    return records;
  }

  function runAggregateCli(args) {
    if (args.length !== 8 || args[0] !== "aggregate") {
      throw new Error("usage: diagnostic-tools.js aggregate INPUT_JSONL FRAGMENTS_JSONL SUMMARY_JSON STYLE_IDS MIN_ITEMS MAX_ITEMS BUDGET_CHARS");
    }
    var report = aggregateEvents(readJsonl(args[1]), {
      styleIds: args[4].split(","),
      minimumItems: Number(args[5]),
      maximumItems: Number(args[6]),
      budgetChars: Number(args[7])
    });
    var fragmentLines = [];
    for (var index = 0; index < report.fragments.length; index += 1) {
      fragmentLines.push(JSON.stringify(report.fragments[index]));
    }
    writeUtf8(args[2], fragmentLines.join("\n") + (fragmentLines.length ? "\n" : ""));
    writeUtf8(args[3], JSON.stringify(report, null, 2) + "\n");
  }

  var exported = {
    aggregateEvents: aggregateEvents,
    validateTimeline: validateTimeline,
    validateThreeBatches: validateThreeBatches,
    sha256File: sha256File,
    utf8Codepoints: utf8Codepoints
  };
  if (typeof module !== "undefined" && module.exports) module.exports = exported;

  if (typeof require === "function" && require.main === module) {
    try {
      runAggregateCli(process.argv.slice(2));
    } catch (error) {
      process.stderr.write("Task23 diagnostic post-process failed: " + error.message + "\n");
      process.exitCode = 2;
    }
  }
}());
