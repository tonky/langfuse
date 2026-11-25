import type { ObservationEvalSchedulerDeps } from "../evaluation/observationEval/types";
import type { recordTraceActivity } from "../traceDispatch/traceRuleRecording";

export type OtelSchedulingHooks = {
  observationWrites?: (
    real: ObservationEvalSchedulerDeps,
  ) => ObservationEvalSchedulerDeps;
  recordTraceActivity?: typeof recordTraceActivity;
};
