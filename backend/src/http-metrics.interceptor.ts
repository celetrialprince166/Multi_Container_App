import {
    CallHandler,
    ExecutionContext,
    Injectable,
    NestInterceptor,
} from '@nestjs/common';
import { InjectMetric } from '@willsoto/nestjs-prometheus';
import { Counter, Histogram } from 'prom-client';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

/**
 * HttpMetricsInterceptor
 *
 * Intercepts every incoming HTTP request and records two Prometheus metrics:
 *
 * 1. http_requests_total (Counter)
 *    - Incremented once per completed request
 *    - Labels: method (GET/POST/…), route (/api/notes), status_code (200/404/500)
 *    - Used for: Requests per Second (RPS) and Error Rate dashboards
 *
 * 2. http_request_duration_seconds (Histogram)
 *    - Records how long each request took in seconds
 *    - Labels: method, route, status_code
 *    - Used for: P50/P95/P99 latency dashboards
 *
 * Both metrics are automatically exposed at GET /metrics by PrometheusModule.
 */
@Injectable()
export class HttpMetricsInterceptor implements NestInterceptor {
    constructor(
        // Injected by @willsoto/nestjs-prometheus — must match the name
        // registered in MetricsModule
        @InjectMetric('http_requests_total')
        private readonly requestCounter: Counter<string>,

        @InjectMetric('http_request_duration_seconds')
        private readonly requestDuration: Histogram<string>,
    ) { }

    intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
        const req = context.switchToHttp().getRequest();
        const { method, route } = req;

        // Normalise the route path — use the Express route pattern if available
        // (e.g. "/api/notes/:id") rather than the raw URL ("/api/notes/42")
        // This prevents high-cardinality label explosion in Prometheus.
        const routePath: string = route?.path ?? req.url ?? 'unknown';

        // Record the wall-clock time at request start
        const startTime = Date.now();

        return next.handle().pipe(
            tap({
                next: () => {
                    const statusCode = context
                        .switchToHttp()
                        .getResponse()
                        .statusCode?.toString() ?? '200';

                    const durationSeconds = (Date.now() - startTime) / 1000;

                    this.requestCounter.inc({
                        method,
                        route: routePath,
                        status_code: statusCode,
                    });

                    this.requestDuration.observe(
                        { method, route: routePath, status_code: statusCode },
                        durationSeconds,
                    );
                },
                error: (err) => {
                    // Record errors (4xx/5xx) — the status code comes from the
                    // NestJS exception filter which sets it on the response
                    const statusCode =
                        err?.status?.toString() ??
                        err?.response?.statusCode?.toString() ??
                        '500';

                    const durationSeconds = (Date.now() - startTime) / 1000;

                    this.requestCounter.inc({
                        method,
                        route: routePath,
                        status_code: statusCode,
                    });

                    this.requestDuration.observe(
                        { method, route: routePath, status_code: statusCode },
                        durationSeconds,
                    );
                },
            }),
        );
    }
}
