import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { NotesModule } from './notes/notes.module';
import { MetricsModule } from './metrics.module';

// Validate required environment variables
const requiredEnvVars = ['DB_HOST', 'DB_USERNAME', 'DB_PASSWORD', 'DB_NAME'];
const missingEnvVars = requiredEnvVars.filter(varName => !process.env[varName]);
if (missingEnvVars.length > 0) {
  throw new Error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
}

// Log database configuration for debugging (without password)
const dbConfig = {
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  username: process.env.DB_USERNAME,
  database: process.env.DB_NAME,
};
console.log('Database configuration:', {
  ...dbConfig,
  password: '***REDACTED***'
});

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: dbConfig.host,
      port: dbConfig.port,
      username: dbConfig.username,
      password: process.env.DB_PASSWORD,
      database: dbConfig.database,
      autoLoadEntities: true,
      synchronize: true,
      ssl: process.env.DB_SSL === 'true' ? {
        rejectUnauthorized: false
      } : false,
      // Add retry logic for container startup
      retryAttempts: 10,
      retryDelay: 3000,
      // Log queries for debugging
      logging: process.env.NODE_ENV !== 'production' ? true : ['error', 'warn'],
    }),
    NotesModule,
    // Registers GET /metrics + HTTP request counter/histogram interceptor
    MetricsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule { }
