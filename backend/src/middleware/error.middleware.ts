import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger.util';

export function errorHandler(
    err: any,
    req: Request,
    res: Response,
    next: NextFunction
): void {
    logger.error('Global error caught:', err);

    const statusCode = err.statusCode || 500;

    // Security: Never leak raw internal error messages for 500 server crashes in production
    const message = (statusCode === 500 && process.env.NODE_ENV === 'production')
        ? 'Internal Server Error'
        : (err.message || 'Internal Server Error');

    res.status(statusCode).json({
        error: message,
        // Include stack trace only if running in development mode
        ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
    });
}