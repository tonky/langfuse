import type { OtelMediaHooks } from "../otel-media/uploadHooks";
import type { OtelSchedulingHooks } from "./scheduling";

type OtelRowKey = {
  traceId: string;
  spanId: string;
  startTime: string;
};

/** Temporary OTEL shadow replay target; all non-primary writes are explicit and fail-closed. */
export type OtelWriteTarget =
  | "primary"
  | {
      media: Required<OtelMediaHooks>;
      scheduling: Required<OtelSchedulingHooks>;
      onFailure?: (stage: string) => void;
      onRowEnqueued?: (row: OtelRowKey) => void;
      recordIngestionMetrics?: boolean;
    };

export function processingHooksFor(target: OtelWriteTarget) {
  return target === "primary" ? undefined : target;
}
