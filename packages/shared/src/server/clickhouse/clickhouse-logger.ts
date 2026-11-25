import { ClickHouseLogLevel, Logger } from "@clickhouse/client";
import { logger as winstonLogger } from "../logger";

// SDK metadata may include request headers, parameters and server error text.
function requestDetails(args?: Record<string, unknown>, err?: Error) {
  const code = err && "code" in err ? err.code : undefined;
  return {
    request_id:
      typeof args?.request_id === "number" ? args.request_id : undefined,
    response_status:
      typeof args?.response_status === "number"
        ? args.response_status
        : undefined,
    duration_ms:
      typeof args?.duration_ms === "number" ? args.duration_ms : undefined,
    errorCode:
      typeof code === "number" ||
      (typeof code === "string" && /^\d{1,4}$/.test(code))
        ? Number(code)
        : undefined,
  };
}

/**
 * ClickHouseLogger bridges the ClickHouse client Logger interface to our Winston logger
 * This ensures ClickHouse client logs are formatted consistently with our application logs
 * and include OpenTelemetry trace context for correlation with spans in DataDog
 */
export class ClickHouseLogger implements Logger {
  trace({ module, message, args }: LogParams): void {
    winstonLogger.debug(`[${module}] ${message}`, requestDetails(args));
  }

  debug({ module, message, args }: LogParams): void {
    winstonLogger.debug(`[${module}] ${message}`, requestDetails(args));
  }

  info({ module, message, args }: LogParams): void {
    winstonLogger.info(`[${module}] ${message}`, requestDetails(args));
  }

  warn({ module, message, args, err }: WarnLogParams): void {
    winstonLogger.warn(`[${module}] ${message}`, requestDetails(args, err));
  }

  error({ module, message, args, err }: ErrorLogParams): void {
    winstonLogger.error(`[${module}] ${message}`, requestDetails(args, err));
  }
}

// Types from @clickhouse/client documentation
interface LogParams {
  module: string;
  message: string;
  args?: Record<string, unknown>;
}

type ErrorLogParams = LogParams & { err: Error };
type WarnLogParams = LogParams & { err?: Error };

/**
 * Map Winston log level to ClickHouse log level
 */
export const mapLogLevel = (level: string): ClickHouseLogLevel => {
  switch (level.toLowerCase()) {
    case "error":
      return ClickHouseLogLevel.ERROR;
    case "warn":
      return ClickHouseLogLevel.WARN;
    case "info":
      return ClickHouseLogLevel.INFO;
    case "debug":
      return ClickHouseLogLevel.DEBUG;
    case "trace":
      return ClickHouseLogLevel.TRACE;
    default:
      return ClickHouseLogLevel.OFF;
  }
};
