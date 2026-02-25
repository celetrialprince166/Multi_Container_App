import { Controller, Get, InternalServerErrorException } from '@nestjs/common';

@Controller()
export class DebugController {
  @Get('debug/slow')
  async slowEndpoint() {
    await new Promise((resolve) => setTimeout(resolve, 500));
    return { status: 'slow response' };
  }

  @Get('debug/error')
  errorEndpoint() {
    throw new InternalServerErrorException('Intentional error for testing');
  }
}

