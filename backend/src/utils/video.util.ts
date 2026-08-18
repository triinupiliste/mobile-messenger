import { execFile } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';
import os from 'os';
import path from 'path';
import crypto from 'crypto';

const execFileAsync = promisify(execFile);

// Bounds how much CPU/wall-clock time a single upload's compression can tie
// up on the server, in case ffmpeg gets stuck on a malformed/unusual file.
const COMPRESSION_TIMEOUT_MS = 5 * 60 * 1000;

// Re-encodes a video down to a size/bitrate that reliably fits under the
// upload limit, using the ffmpeg binary installed in the server's container
// (see Dockerfile). This runs server-side rather than on the user's phone so
// compression behaves consistently across uploads instead of depending on
// the wide variety of phone hardware/OS versions and native-plugin quirks
// that made client-side compression (the video_compress Flutter plugin)
// unreliable.
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
            // Cap resolution at 1280px on the long edge (already-smaller
            // videos are left untouched); -2 keeps the other edge divisible
            // by 2, which H.264 requires.
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
