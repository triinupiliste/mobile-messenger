// Minimal structured logger — timestamps and tags every line with a level so
// production log output (e.g. Railway's log viewer) can be scanned/filtered consistently
type LogMeta = unknown;

function write(level: 'INFO' | 'WARN' | 'ERROR', message: string, meta?: LogMeta): void {
    const line = `${new Date().toISOString()} [${level}] ${message}`;
    if (meta !== undefined) {
        (level === 'ERROR' ? console.error : level === 'WARN' ? console.warn : console.log)(line, meta);
    } else {
        (level === 'ERROR' ? console.error : level === 'WARN' ? console.warn : console.log)(line);
    }
}

export const logger = {
    info: (message: string, meta?: LogMeta) => write('INFO', message, meta),
    warn: (message: string, meta?: LogMeta) => write('WARN', message, meta),
    error: (message: string, meta?: LogMeta) => write('ERROR', message, meta),
};
