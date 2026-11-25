import { AsyncLocalStorage } from "node:async_hooks";
import type { OtelMediaHooks } from "../otel-media/uploadHooks";
import type { OtelSchedulingHooks } from "./scheduling";

type RowKey = { traceId: string; spanId: string; startTime: string };

export type OtelProcessingHooks = {
  media?: OtelMediaHooks;
  scheduling?: OtelSchedulingHooks;
  onFailure?: (stage: string) => void;
  recordIngestionMetrics?: boolean;
  onRowEnqueued?: (row: RowKey) => void;
};

/**
 * Primary ingestion uses this scope to observe writes inside shared services.
 * Replay receives its write target explicitly so losing this scope cannot redirect a write.
 */
export const otelProcessingHooks = new AsyncLocalStorage<
  OtelProcessingHooks | undefined
>();

/** Only the primary route can choose production writes when no observation hooks are installed. */
export type OtelWriteTarget =
  | "primary"
  | (OtelProcessingHooks & {
      media: Required<OtelMediaHooks>;
      scheduling: Required<OtelSchedulingHooks>;
    });

export function processingHooksFor(target: OtelWriteTarget) {
  return target === "primary" ? otelProcessingHooks.getStore() : target;
}
