import { Request, Response, NextFunction } from 'express';

export function errorHandler(
    err: any,
    req: Request,
    res: Response,
    next: NextFunction
): void {
    console.error('🔥 Global Error Caught:', err);

    const statusCode = err.statusCode || 500;
    const message = err.message || 'Internal Server Error';

    res.status(statusCode).json({
        error: message,
        // Include stack trace only if running in development mode for easier debugging
        ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
    });
}