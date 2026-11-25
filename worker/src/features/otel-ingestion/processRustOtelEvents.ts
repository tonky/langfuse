import { processingHooksFor, type OtelWriteTarget } from "./processingHooks";
import type {
  EarlyOtelBatch,
  FinalizedOtelBatch,
  OtelLookupRequest,
  OtelMediaRequest,
  OtelMediaResolution,
  OtelOverflowRequest,
  OtelProcessingContext,
  RustOtelBatch,
} from "@langfuse/native";
import {
  completeObservationForEval,
  convertEventRecordToObservationEvalFilterFields,
  isMediaContentType,
  MediaAssociationOrigin,
  observationEvalFilterRecordColumns,
  MediaContentType,
} from "@langfuse/shared";
import {
  findModel,
  forEachMedia,
  getCurrentSpan,
  logger,
  otelMediaUploads,
  PromptService,
  recordDistribution,
  recordIncrement,
  redis,
  SkillCacheService,
  uploadMediaForTrace,
  type EventRecordInsertType,
} from "@langfuse/shared/src/server";
import { prisma } from "@langfuse/shared/src/db";
import { resolveSkillReferences } from "../../services/IngestionService/skillReferences";
import { env, v4WritesToLegacyTables } from "../../env";
import type { ClickhouseWriter } from "../../services/ClickhouseWriter";
import { TableName } from "../../services/ClickhouseWriter/types";
import { classifyJobFailure } from "../../queues/jobFailureReason";
import { fetchEvalRules, type EvalRules } from "../evaluation/fetchEvalRules";
import { encodeOtelLookups, type OtelLookupResult } from "./encodeOtelLookups";
import {
  createEvalSchedulerDeps,
  scheduleEvals,
} from "../evaluation/scheduleEvals";
import {
  isTraceDispatchSampled,
  resolveTraceDispatchSamplingRate,
} from "../traceDispatch/traceDispatchSampling";
import { isEventsDispatchEnabled } from "../eventsDispatch/config";
import type { OtelMediaPresence } from "../otel-media/processOtelMedia";
import {
  shouldRecordOtelMediaMetrics,
  uploadOtelMedia,
} from "../otel-media/uploadHooks";
import {
  recordExtractedMediaUpload,
  uploadExtractedMediaOnce,
} from "../otel-media/resolveExtractedMedia";

type EvalRuleResolution = {
  traceDispatchSamplingRate: number;
  sampledTraceIds: string[];
  evalConfigs: EvalRules;
};

type FinalizedEvent = FinalizedOtelBatch["events"][number];
type NativeEventWriter = Pick<
  ReturnType<typeof ClickhouseWriter.getNativeInstance>,
  "addToQueue"
>;
/**
 * Processes a native OTEL batch through service lookups, native completion,
 * evaluation scheduling, and the ClickHouse writer.
 */
export async function processRustOtelEvents(params: {
  batch: EarlyOtelBatch;
  context: OtelProcessingContext;
  getWriter: () => NativeEventWriter;
  writes: OtelWriteTarget;
}): Promise<OtelMediaPresence> {
  const { batch, context, writes } = params;
  const { projectId } = context;
  const samplingRate = isEventsDispatchEnabled()
    ? resolveTraceDispatchSamplingRate(projectId)
    : Promise.resolve(0);
  const prepared = await batch.process(context);
  const processing = prepared.batch;
  try {
    const [mediaResults, lookups, rules] = await waitForServiceWork([
      uploadRequestedMedia(
        batch,
        processing,
        prepared.mediaRequests,
        context,
        writes,
      ),
      resolveLookups(prepared.lookupRequests, context, writes),
      fetchSampledEvalRules(projectId, prepared.traceIds, samplingRate),
    ] as const);
    const finalized = await completeOrFinalizeBatch(
      processing,
      mediaResults,
      lookups,
      rules,
      projectId,
      writes,
    );
    const writer = params.getWriter();
    if (!writer) throw new Error("Native OTEL writer unavailable");
    await writeRecordsAndScheduleEvals(
      processing,
      finalized,
      rules,
      context,
      writer,
      writes,
    );
    return prepared.mediaRequests.length > 0 ? "present" : "absent";
  } finally {
    await processing.dispose();
  }
}

function fetchSampledEvalRules(
  projectId: string,
  traceIds: string[],
  traceDispatchSamplingRatePromise: Promise<number>,
): Promise<EvalRuleResolution> {
  return traceDispatchSamplingRatePromise.then(
    async (traceDispatchSamplingRate) => {
      // Select transcript rules using `process`'s trace IDs. Pass selected IDs to
      // `complete`/`finalize` to measure rows after oversized fields are replaced.
      const sampledTraceIds = traceIds.filter((traceId) =>
        isTraceDispatchSampled(traceId, traceDispatchSamplingRate),
      );
      const evalConfigs = await fetchEvalRules(projectId, {
        includeTraceTranscriptRules: sampledTraceIds.length > 0,
      }).catch((error) => {
        logger.warn(
          "Failed to fetch OTEL eval rules; continuing without eval rules",
          {
            projectId,
            stage: "eval_rules",
            reason: classifyJobFailure(error),
          },
        );
        return { observationRules: [], traceTranscriptRules: [] };
      });
      return { traceDispatchSamplingRate, sampledTraceIds, evalConfigs };
    },
  );
}

async function waitForServiceWork<T extends readonly Promise<unknown>[]>(
  serviceWork: T,
) {
  try {
    return await Promise.all(serviceWork);
  } catch (error) {
    // Pending uploads still read the native batch; drain them before disposal.
    await Promise.allSettled(serviceWork);
    throw error;
  }
}

async function completeOrFinalizeBatch(
  processing: RustOtelBatch,
  mediaResults: OtelMediaResolution[],
  lookups: OtelLookupResult[],
  { evalConfigs, sampledTraceIds }: EvalRuleResolution,
  projectId: string,
  writes: OtelWriteTarget,
): Promise<FinalizedOtelBatch> {
  const overflowLimitBytes =
    env.LANGFUSE_OBSERVATION_FIELD_OVERFLOW_ENABLED === "true"
      ? env.LANGFUSE_OBSERVATION_FIELD_SIZE_LIMIT_BYTES
      : undefined;
  // With rules, Rust returns these columns of every row for matching.
  const evaluationFilterColumns =
    evalConfigs.observationRules.length > 0 ||
    evalConfigs.traceTranscriptRules.length > 0
      ? observationEvalFilterRecordColumns
      : undefined;
  const traceActivityIds =
    sampledTraceIds.length > 0 ? sampledTraceIds : undefined;
  const completion = await processing.complete(
    mediaResults,
    encodeOtelLookups(lookups),
    overflowLimitBytes,
    evaluationFilterColumns,
    traceActivityIds,
  );
  if (completion.finalized) {
    return completion.finalized;
  }

  const overflowResults = await uploadOverflowFields(
    processing,
    completion.overflowRequests,
    projectId,
    writes,
  );
  return processing.finalize(
    overflowResults,
    evaluationFilterColumns,
    traceActivityIds,
  );
}

async function uploadOverflowFields(
  processing: RustOtelBatch,
  requests: OtelOverflowRequest[],
  projectId: string,
  writes: OtelWriteTarget,
): Promise<OtelMediaResolution[]> {
  const overflowResults = new Array<OtelMediaResolution>(requests.length);
  await forEachMedia(requests, async (request) => {
    let reference: string | undefined;
    let outcome = "failed";
    let uploadBoundaryStarted = false;
    try {
      const mediaBucket = env.LANGFUSE_S3_MEDIA_UPLOAD_BUCKET;
      if (!mediaBucket)
        throw new Error("Media upload bucket is not configured");
      const field = request.field;
      if (field !== "input" && field !== "output" && field !== "metadata")
        throw new Error("unsupported overflow field");
      const sha256Hash = request.sha256Hash;
      if (!sha256Hash) throw new Error("missing overflow media digest");
      uploadBoundaryStarted = true;
      const result = await uploadOtelMedia(writes, {
        projectId,
        traceId: request.traceId,
        observationId: request.observationId,
        field,
        contentType: MediaContentType.TXT,
        origin: MediaAssociationOrigin.INGESTION_FIELD_OVERFLOW,
        sha256Hash,
        loadBody: () => processing.overflowBody(request.index),
        admit: (work) => otelMediaUploads.run(request.byteLength, work),
        upload: (contentBytes, capturedHash) =>
          uploadMediaForTrace({
            projectId,
            traceId: request.traceId,
            observationId: request.observationId,
            field,
            contentType: MediaContentType.TXT,
            contentBytes,
            sha256Hash: capturedHash ?? sha256Hash,
            mediaBucket,
            mediaPrefix: env.LANGFUSE_S3_MEDIA_UPLOAD_PREFIX,
            origin: MediaAssociationOrigin.INGESTION_FIELD_OVERFLOW,
          }),
      });
      reference = `@@@langfuseMedia:type=text/plain|id=${result.mediaId}|source=field_size_limit@@@`;
      outcome = result.outcome;
    } catch (error) {
      if (!uploadBoundaryStarted)
        processingHooksFor(writes)?.onFailure?.("media_upload");
      logger.warn(
        "Oversized observation field upload failed; persisting original field",
        {
          projectId,
          stage: "overflow_media_upload",
          reason: classifyJobFailure(error),
        },
      );
    }
    if (shouldRecordOtelMediaMetrics(writes)) {
      recordIncrement("langfuse.ingestion.observation_field_overflow", 1, {
        field: request.field,
        outcome,
      });
      recordDistribution(
        "langfuse.ingestion.observation_field_overflow.bytes_removed",
        reference
          ? Math.max(request.byteLength - Buffer.byteLength(reference), 0)
          : 0,
        { field: request.field, outcome },
      );
    }
    overflowResults[request.index] = { index: request.index, reference };
  });
  return overflowResults;
}

function recordIngestionCounts(records: FinalizedEvent[]): void {
  // Dual writes count ingestion in legacy processing; events-only jobs count
  // the finalized rows here.
  if (v4WritesToLegacyTables(env)) return;

  const traceCount = new Set(records.map((record) => record.traceId)).size;
  recordIncrement("langfuse.ingestion.event", records.length, {
    source: "otel",
  });
  recordDistribution("langfuse.ingestion.otel.trace_count", traceCount);
  recordDistribution(
    "langfuse.ingestion.otel.observation_count",
    records.length,
  );
  getCurrentSpan()?.setAttributes({
    "langfuse.ingestion.otel.trace_count": traceCount,
    "langfuse.ingestion.otel.observation_count": records.length,
  });
}

type EvaluationFilterRow = Parameters<
  typeof convertEventRecordToObservationEvalFilterFields
>[0];

/**
 * Parse the columns that evaluation rule filters read, one row per event. They
 * carry no input or output; Rust keeps the full rows until a rule selects one.
 */
function parseEvaluationFilterRows(
  texts: string[] | undefined,
): EvaluationFilterRow[] {
  return (
    texts?.flatMap((text): EvaluationFilterRow[] => JSON.parse(text)) ?? []
  );
}

/** Validate an event's filter fields; load the rest of its row once a rule selects it. */
function observationForScheduling(
  processing: RustOtelBatch,
  filterRow: EvaluationFilterRow,
  index: number,
) {
  const filterFields =
    convertEventRecordToObservationEvalFilterFields(filterRow);
  return {
    observation: filterFields,
    // The taken row holds the columns the filter row lacks.
    loadSnapshot: () =>
      completeObservationForEval(
        filterFields,
        processing.takeEvaluationRow(index) as EventRecordInsertType,
      ),
  };
}

async function writeRecordsAndScheduleEvals(
  processing: RustOtelBatch,
  { events: records, evaluationFilterRows }: FinalizedOtelBatch,
  {
    traceDispatchSamplingRate,
    sampledTraceIds,
    evalConfigs,
  }: EvalRuleResolution,
  { projectId }: OtelProcessingContext,
  writer: NativeEventWriter,
  writes: OtelWriteTarget,
): Promise<void> {
  const needsScheduler =
    evalConfigs.observationRules.length > 0 || sampledTraceIds.length > 0;
  const schedulerDeps = needsScheduler
    ? createEvalSchedulerDeps(projectId, evalConfigs, writes)
    : null;
  const filterRows = schedulerDeps
    ? parseEvaluationFilterRows(evaluationFilterRows)
    : [];
  const hooks = processingHooksFor(writes);
  if (hooks?.recordIngestionMetrics !== false) recordIngestionCounts(records);
  await Promise.all(
    records.map(async (record, index) => {
      const traceActivity = isTraceDispatchSampled(
        record.traceId,
        traceDispatchSamplingRate,
      )
        ? {
            traceId: record.traceId,
            spanStartTimeISO: record.startTimeIso,
          }
        : undefined;
      const matchedRuleIds = schedulerDeps
        ? await scheduleEvals({
            parseObservation: () =>
              observationForScheduling(processing, filterRows[index], index),
            environment: record.environment,
            traceActivity,
            rules: evalConfigs,
            schedulerDeps,
            buildFailureContext: () => ({
              projectId,
              observationId: record.event.ids.id,
            }),
          })
        : undefined;

      try {
        writer.addToQueue(TableName.EventsFull, record.event);
        hooks?.onRowEnqueued?.({
          traceId: record.traceId,
          spanId: record.event.ids.id,
          startTime: record.startTimeIso,
        });
        if (
          traceActivity &&
          matchedRuleIds !== undefined &&
          schedulerDeps &&
          record.serializedEventBytes !== undefined
        ) {
          schedulerDeps.collectTraceActivity({
            ...traceActivity,
            ruleIds: matchedRuleIds,
            serializedEventBytes: record.serializedEventBytes,
          });
        }
      } catch (error) {
        hooks?.onFailure?.("row_write");
        logger.error(
          "Failed to write OTEL event record; continuing ingestion",
          {
            projectId,
            stage: "row_write",
            reason: classifyJobFailure(error),
          },
        );
      }
    }),
  );
  await schedulerDeps?.flushTraceActivity();
}

async function uploadRequestedMedia(
  batch: EarlyOtelBatch,
  processing: RustOtelBatch,
  mediaRequests: OtelMediaRequest[],
  { projectId }: OtelProcessingContext,
  writes: OtelWriteTarget,
): Promise<OtelMediaResolution[]> {
  const mediaResults = new Array<OtelMediaResolution>(mediaRequests.length);
  const mediaStartedAt = Date.now();
  let mediaBytesProcessed = 0;
  // Rust retains encoded media. `uploadExtractedMediaOnce` reuses successful uploads
  // across legacy and direct writes, linking each asset to both destinations.
  await forEachMedia(mediaRequests, async (request) => {
    let reference: string | undefined;
    let uploadBoundaryStarted = false;
    try {
      const contentType = request.contentType;
      if (!isMediaContentType(contentType))
        throw new Error("unsupported extracted media type");
      const mediaBucket = env.LANGFUSE_S3_MEDIA_UPLOAD_BUCKET;
      if (!mediaBucket)
        throw new Error("Media upload bucket is not configured");
      const field = request.field;
      if (field !== "input" && field !== "output" && field !== "metadata")
        throw new Error("unsupported media field");
      const sha256Hash = request.sha256Hash;
      if (!sha256Hash) throw new Error("missing extracted media digest");
      uploadBoundaryStarted = true;
      const result = await uploadExtractedMediaOnce(writes, {
        batch,
        projectId,
        mediaBucket,
        mediaPrefix: env.LANGFUSE_S3_MEDIA_UPLOAD_PREFIX,
        sha256Hash,
        contentType,
        byteLengthUpperBound: request.originalByteLength,
        traceId: request.traceId,
        observationId: request.observationId,
        field,
        loadBody: () => processing.mediaBody(request.mediaIndex),
      });
      mediaBytesProcessed += result.byteLength;
      reference = request.reference.replace(
        /\|id=[^|@]+/,
        `|id=${result.mediaId}`,
      );
      recordExtractedMediaUpload(
        writes,
        result.outcome,
        request.kind,
        "direct",
        result.byteLength,
        Math.max(0, request.originalByteLength - Buffer.byteLength(reference)),
      );
    } catch (error) {
      if (!uploadBoundaryStarted)
        processingHooksFor(writes)?.onFailure?.("media_upload");
      recordExtractedMediaUpload(writes, "failed", request.kind, "direct");
      logger.warn(
        "Native OTEL media upload failed; keeping the original inline value",
        {
          projectId,
          stage: "media_upload",
          reason: classifyJobFailure(error),
        },
      );
    }
    mediaResults[request.index] = { index: request.index, reference };
  });
  if (shouldRecordOtelMediaMetrics(writes)) {
    recordDistribution(
      "langfuse.ingestion.otel.media.batch_byte_length",
      mediaBytesProcessed,
      { write_path: "direct", media_path: "early" },
    );
    recordDistribution(
      "langfuse.ingestion.otel.media.processing_duration_ms",
      Date.now() - mediaStartedAt,
      { write_path: "direct", media_path: "early" },
    );
  }
  return mediaResults;
}

async function resolveLookups(
  lookupRequests: OtelLookupRequest[],
  { projectId }: OtelProcessingContext,
  writes: OtelWriteTarget,
): Promise<OtelLookupResult[]> {
  const prompts = new PromptService(prisma, redis);
  const skills = new SkillCacheService(prisma, redis);
  const lookups: OtelLookupResult[] = [];
  // Resolve up to 64 lookup requests at a time; event payloads stay in Rust.
  for (let offset = 0; offset < lookupRequests.length; offset += 64) {
    lookups.push(
      ...(await Promise.all(
        lookupRequests.slice(offset, offset + 64).map(async (request) => {
          try {
            const [matched, prompt, skillReferences] = await Promise.all([
              request.modelName
                ? findModel({ projectId, model: request.modelName })
                : { model: null, pricingTiers: [] },
              request.promptName && request.promptVersion
                ? prompts.getPrompt({
                    projectId,
                    promptName: request.promptName,
                    version: request.promptVersion,
                    label: undefined,
                  })
                : null,
              resolveSkillReferences({
                projectId,
                type: request.eventType,
                service: skills,
                available: request.skillsAvailable,
                loaded: request.skillsResourceLoaded,
              }),
            ]);
            const model = matched.model;
            return {
              promptId: prompt?.id,
              model: model
                ? {
                    id: model.id,
                  }
                : null,
              pricingTiers: matched.pricingTiers.map((tier) => ({
                ...tier,
                prices: tier.prices.map((price) => ({
                  usageType: price.usageType,
                  price: price.price.toString(),
                })),
              })),
              skillsAvailable: skillReferences.skills_available,
              skillsResourceLoaded: skillReferences.skills_resource_loaded,
            };
          } catch (error) {
            processingHooksFor(writes)?.onFailure?.("lookup");
            const reason = classifyJobFailure(error);
            logger.error("Failed to resolve OTEL lookup", {
              projectId,
              reason,
            });
            return { error: reason };
          }
        }),
      )),
    );
  }
  return lookups;
}
