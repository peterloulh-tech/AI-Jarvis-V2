"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const tools = require("../diagnostic-tools.js");

const styles = ["style-1", "style-2", "style-3"];

function result(sequence, isSpeak, rawResponse, ok = true) {
  return {
    event: "duplex_result",
    run_generation: 4,
    asset_sequence: sequence,
    user_seq: sequence,
    frame_id: sequence,
    ok,
    is_speak: isSpeak,
    decision: isSpeak ? "SPEAK" : "LISTEN",
    raw_response: rawResponse
  };
}

function testKnownFieldFragmentsRemainOneIncompleteAggregate() {
  const events = [
    result(1, false, ""),
    result(2, false, ""),
    result(3, false, ""),
    result(4, true, '{"batches": [{"style_id":"style-'),
    result(5, true, '1", "items": ["01 \u5f00'),
    result(6, true, '\u59cb\u3002"]}, {"style_id":"style-'),
    result(7, true, '2", "items": ["0')
  ];

  const report = tools.aggregateEvents(events, {
    styleIds: styles,
    minimumItems: 1,
    maximumItems: 5,
    budgetChars: 225
  });

  assert.strictEqual(report.fragments.length, 4);
  assert.ok(report.fragments.every((item) => item.validation_status === "awaiting_completion"));
  assert.ok(report.fragments.every((item) => item.aggregate_id === 1));
  assert.strictEqual(report.aggregates.length, 1);
  assert.strictEqual(report.aggregates[0].aggregate_id, 1);
  assert.strictEqual(report.aggregates[0].fragment_count, 4);
  assert.strictEqual(report.aggregates[0].completion_basis, "evidence_end_without_complete_json");
  assert.strictEqual(report.aggregates[0].json_parse_complete, false);
  assert.strictEqual(report.valid_three_batch_aggregates, 0);
  assert.strictEqual(
    report.aggregates[0].aggregated_text,
    '{"batches": [{"style_id":"style-1", "items": ["01 \u5f00\u59cb\u3002"]}, {"style_id":"style-2", "items": ["0'
  );
}

function testCompleteJsonClosesAggregateAndValidatesSchema() {
  const complete = '{"batches":[{"style_id":"style-1","items":["a"]},{"style_id":"style-2","items":["b"]},{"style_id":"style-3","items":["c"]}]}';
  const split = 48;
  const report = tools.aggregateEvents([
    result(4, true, complete.slice(0, split)),
    result(5, true, complete.slice(split))
  ], {
    styleIds: styles,
    minimumItems: 1,
    maximumItems: 5,
    budgetChars: 225
  });

  assert.strictEqual(report.aggregates.length, 1);
  assert.strictEqual(report.aggregates[0].completion_basis, "aggregate_json_parse_complete");
  assert.strictEqual(report.aggregates[0].json_parse_complete, true);
  assert.strictEqual(report.aggregates[0].schema_valid, true);
  assert.strictEqual(report.aggregates[0].batch_count, 3);
  assert.strictEqual(report.valid_three_batch_aggregates, 1);
  assert.strictEqual(report.fragments[0].validation_status, "awaiting_completion");
  assert.strictEqual(report.fragments[1].validation_status, "completed_valid_json");
}

function testFailedResultBreaksGenerationAndIsNotListen() {
  const report = tools.aggregateEvents([
    result(4, true, '{"batches":['),
    result(5, false, "", false)
  ], {
    styleIds: styles,
    minimumItems: 1,
    maximumItems: 5,
    budgetChars: 225
  });

  assert.strictEqual(report.failed_results, 1);
  assert.strictEqual(report.listen_results, 0);
  assert.strictEqual(report.aggregates[0].completion_basis, "failed_result_boundary");
}

function testTimelineValidationUsesLiteralOffsetsAndHashes() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "task23-timeline-"));
  const chunksDir = path.join(root, "chunks");
  fs.mkdirSync(chunksDir);
  fs.writeFileSync(path.join(root, "authorization.md"), "authorized\n");
  fs.writeFileSync(path.join(root, "gold.json"), "{}\n");
  const chunks = [];
  for (let index = 0; index < 3; index += 1) {
    const stem = String(index + 1).padStart(4, "0");
    fs.writeFileSync(path.join(chunksDir, stem + ".wav"), "wav-" + index);
    fs.writeFileSync(path.join(chunksDir, stem + ".jpg"), "jpg-" + index);
    chunks.push({
      sequence: index + 1,
      offset_ms: index * 1000,
      duration_ms: 1000,
      marker: "source-part-" + (index + 1) + "-of-3",
      source_sequence: 1,
      source_part: index + 1,
      audio: "chunks/" + stem + ".wav",
      audio_sha256: tools.sha256File(path.join(chunksDir, stem + ".wav")),
      image: "chunks/" + stem + ".jpg",
      image_sha256: tools.sha256File(path.join(chunksDir, stem + ".jpg"))
    });
  }
  const manifest = {
    input_id: "O-IN-07",
    duration_ms: 3000,
    style_ids: styles,
    authorization_record: "authorization.md",
    authorization_sha256: tools.sha256File(path.join(root, "authorization.md")),
    gold_record: "gold.json",
    gold_sha256: tools.sha256File(path.join(root, "gold.json")),
    chunks
  };

  const validation = tools.validateTimeline(manifest, root, 1000, true);
  assert.strictEqual(validation.chunk_count, 3);
  assert.strictEqual(validation.timeline_end_ms, 3000);
  assert.deepStrictEqual(validation.rounds.map((item) => item.offset_ms), [0, 1000, 2000]);

  manifest.chunks[1].offset_ms = 1100;
  assert.throws(() => tools.validateTimeline(manifest, root, 1000, true), /not continuous/);
}

const tests = [
  testKnownFieldFragmentsRemainOneIncompleteAggregate,
  testCompleteJsonClosesAggregateAndValidatesSchema,
  testFailedResultBreaksGenerationAndIsNotListen,
  testTimelineValidationUsesLiteralOffsetsAndHashes
];

for (const test of tests) {
  test();
  process.stdout.write("PASS " + test.name + "\n");
}
