import { Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import {
    PrometheusModule,
    makeCounterProvider,
    makeHistogramProvider,
} from '@willsoto/nestjs-prometheus';
import { HttpMetricsInterceptor } from './http-metrics.interceptor';

/**
 * MetricsModule
 *
 * Wires up everything needed for the /metrics endpoint:
 *
 * 1. PrometheusModule.register()
 *    - Creates the GET /metrics route automatically
 *    - Enables default Node.js metrics collection (CPU, memory, event loop lag,
 *      garbage collection, active handles) via prom-client's collectDefaultMetrics()
 *
 * 2. makeCounterProvider / makeHistogramProvider
 *    - Registers named metrics in prom-client's global registry
 *    - These are then injectable via @InjectMetric() in the interceptor
 *
 * 3. HttpMetricsInterceptor (APP_INTERCEPTOR)
 *    - Applied globally to every route — no need to decorate each controller
 *    - Records http_requests_total and http_request_duration_seconds per request
 */
@Module({
    imports: [
        PrometheusModule.register({
            // The path Prometheus will scrape
            path: '/metrics',

            // Collect default Node.js runtime metrics automatically:
            // nodejs_heap_size_used_bytes, nodejs_eventloop_lag_seconds,
            // nodejs_active_handles_total, process_cpu_seconds_total, etc.
            defaultMetrics: {
                enabled: true,
                // Prefix all default metrics with "notes_" for easy filtering
                config: { prefix: 'notes_' },
            },
        }),
    ],

    providers: [
        // ── Custom metric: request counter ──────────────────────────────────────
        // Tracks total HTTP requests broken down by method, route, and status code.
        // Example Prometheus query for error rate:
        //   sum(rate(http_requests_total{status_code=~"5.."}[5m]))
        //   / sum(rate(http_requests_total[5m]))
        makeCounterProvider({
            name: 'http_requests_total',
            help: 'Total number of HTTP requests processed by the Notes API',
            labelNames: ['method', 'route', 'status_code'],
        }),

        // ── Custom metric: request duration histogram ────────────────────────────
        // Records how long each request takes in seconds.
        // Buckets chosen to give useful percentile data for a typical REST API.
        // Example Prometheus query for P95 latency:
        //   histogram_quantile(0.95,
        //     sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
        makeHistogramProvider({
            name: 'http_request_duration_seconds',
            help: 'HTTP request duration in seconds for the Notes API',
            labelNames: ['method', 'route', 'status_code'],
            buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
        }),

        // ── Global interceptor ───────────────────────────────────────────────────
        // APP_INTERCEPTOR applies HttpMetricsInterceptor to every route globally.
        // This is equivalent to calling app.useGlobalInterceptors() in main.ts,
        // but keeps the wiring inside the module for better encapsulation.
        {
            provide: APP_INTERCEPTOR,
            useClass: HttpMetricsInterceptor,
        },

        // The interceptor itself must be listed as a provider so NestJS can
        // resolve its @InjectMetric() constructor dependencies.
        HttpMetricsInterceptor,
    ],
})
export class MetricsModule { }
