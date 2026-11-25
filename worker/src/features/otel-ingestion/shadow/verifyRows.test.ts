import { expect, it, vi } from "vitest";
import * as server from "@langfuse/shared/src/server";
import { enqueueShadowRows, flushShadowRows } from "./verifyRows";

it("rechecks only enqueued rows still missing from ClickHouse", async () => {
  const rows = ["ready", "late", "missing"].map((spanId) => ({
    traceId: "trace",
    spanId,
    startTime: "2026-11-24 10:00:00.000000",
  }));
  const stored = (side: "primary" | "shadow", position: number) => ({
    side,
    position,
    copies: 1,
    fields: {},
    sortedMaps: [],
  });
  const read = vi
    .spyOn(server, "queryClickhouse")
    .mockResolvedValueOnce([
      stored("primary", 1),
      stored("shadow", 1),
      stored("primary", 2),
    ])
    .mockResolvedValueOnce([stored("primary", 1), stored("shadow", 1)]);
  const report = vi.spyOn(server.logger, "info");
  const message =
    "OTEL shadow persisted rows differ or could not be attributed";
  vi.useFakeTimers();
  try {
    enqueueShadowRows({
      projectId: "project",
      fileKey: "file",
      inputBytes: 128,
      primary: rows,
      shadow: rows,
    });
    await vi.advanceTimersByTimeAsync(30_000);
    expect(read).toHaveBeenCalledTimes(1);
    expect(report).not.toHaveBeenCalledWith(message, expect.anything());

    await vi.advanceTimersByTimeAsync(30_000);
    expect(read.mock.calls[1][0].params?.locators).toEqual(
      rows
        .slice(1)
        .map(
          (row) =>
            new server.TupleParam([
              "project",
              row.traceId,
              row.spanId,
              row.startTime,
              "file",
            ]),
        ),
    );
    expect(report).toHaveBeenCalledWith(
      message,
      expect.objectContaining({ counts: { matched: 1, missing_both: 1 } }),
    );
    await flushShadowRows();
    expect(read).toHaveBeenCalledTimes(2);
  } finally {
    await flushShadowRows();
    vi.useRealTimers();
    report.mockRestore();
    read.mockRestore();
  }
});
