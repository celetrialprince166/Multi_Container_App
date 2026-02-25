import { Module } from '@nestjs/common';
import { LoggerModule as PinoLoggerModule } from 'nestjs-pino';
import { trace } from '@opentelemetry/api';

@Module({
  imports: [
    PinoLoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL || 'info',
        messageKey: 'msg',
        transport:
          process.env.NODE_ENV !== 'production'
            ? {
                target: 'pino-pretty',
                options: {
                  colorize: true,
                },
              }
            : undefined,
        mixin() {
          const span = trace.getActiveSpan();
          if (!span) {
            return {};
          }
          const ctx = span.spanContext();
          if (!ctx || !ctx.traceId || !ctx.spanId) {
            return {};
          }
          return {
            trace_id: ctx.traceId,
            span_id: ctx.spanId,
          };
        },
      },
    }),
  ],
  exports: [PinoLoggerModule],
})
export class LoggerModule {}

