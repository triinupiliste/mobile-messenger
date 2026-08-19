import { execFile } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';
import os from 'os';
import path from 'path';
import crypto from 'crypto';
import { COMPRESSION_TIMEOUT_MS } from '../config/constants';

const execFileAsync = promisify(execFile);

// Re-encodes video via the ffmpeg binary in the server container (see
// Dockerfile) — runs server-side since client-side compression (video_compress plugin) was unreliable across devices.
export async function compressVideo(inputBuffer: Buffer, originalExtension: string): Promise<Buffer> {
    // Only used to name the temp input file so ffmpeg has a hint about the
    // container format — validate it so it can't be used to inject a path.
    const safeExtension = /^\.[a-zA-Z0-9]{1,5}$/.test(originalExtension) ? originalExtension : '.dat';
    const id = crypto.randomBytes(8).toString('hex');
    const inputPath = path.join(os.tmpdir(), `vc-${id}-in${safeExtension}`);
    const outputPath = path.join(os.tmpdir(), `vc-${id}-out.mp4`);

    await fs.promises.writeFile(inputPath, inputBuffer);

    try {
        await execFileAsync('ffmpeg', [
            '-y',
            '-i', inputPath,
            // Cap resolution at 1280px on the long edge (smaller videos untouched);
            // -2 keeps the other edge divisible by 2, which H.264 requires.
            '-vf', "scale='min(1280,iw)':-2",
            '-c:v', 'libx264',
            '-preset', 'veryfast',
            '-crf', '28',
            '-c:a', 'aac',
            '-b:a', '128k',
            // Move the moov atom to the front so playback/seeking can start
            // before the whole file has downloaded.
            '-movflags', '+faststart',
            outputPath,
        ], { timeout: COMPRESSION_TIMEOUT_MS });

        return await fs.promises.readFile(outputPath);
    } finally {
        // Best-effort cleanup — don't let a missing file (e.g. ffmpeg never
        // produced output) fail the request after we already have our result.
        await Promise.allSettled([
            fs.promises.unlink(inputPath),
            fs.promises.unlink(outputPath),
        ]);
    }
}
