import {
  type ClickhouseClientType,
  withCustomerDataLoggingSuppressed,
} from "@langfuse/shared/src/server";
import { ClickhouseWriter } from "../../../services/ClickhouseWriter";
import { nativeWriteStrategyFactory } from "../../../services/ClickhouseWriter/writeStrategies";
import { otelProcessingHooks } from "../processingHooks";

const SHADOW_TABLE = "events_native_test";
let writer: ReturnType<typeof ClickhouseWriter.createNativeWriter> | undefined;

/** The flush timer outlives a sample. It must not retain the batch or its service overrides. */
export function getShadowWriter(client?: ClickhouseClientType) {
  if (writer) return writer;
  writer = otelProcessingHooks.exit(() =>
    withCustomerDataLoggingSuppressed(() =>
      ClickhouseWriter.createNativeWriter(client, {
        format: "native-test",
        metricEntityType: SHADOW_TABLE,
        create() {
          const native = nativeWriteStrategyFactory.create();
          return {
            ...native,
            write: (client, params) =>
              native.write(client, {
                ...params,
                table: SHADOW_TABLE,
                clickhouse_settings: {
                  ...params.clickhouse_settings,
                  log_queries: 0,
                },
              }),
          };
        },
      }),
    ),
  );
  return writer;
}

export async function closeShadowWriter() {
  await withCustomerDataLoggingSuppressed(() => writer?.shutdown());
  writer = undefined;
}
