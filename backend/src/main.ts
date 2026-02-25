import 'reflect-metadata';
import './telemetry/tracing';
import { NestFactory } from '@nestjs/core';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import * as dotenv from 'dotenv';

dotenv.config();

async function bootstrap() {
  try {
    const app = await NestFactory.create(AppModule, {
      bufferLogs: true,
    });

    app.useLogger(app.get(Logger));

    app.enableCors({
      origin: '*',
      methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
      credentials: true,
    });

    const port = process.env.PORT || 3001;
    await app.listen(port, '0.0.0.0');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Failed to start application:', error);
    process.exit(1);
  }
}

bootstrap().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('Unhandled bootstrap error:', error);
  process.exit(1);
});
