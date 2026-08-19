// Shared between REST auth middleware and the Socket.IO handshake so both
// enforce single-device login the same way.
import { UserRepository } from '../repositories/user.repository';

export async function hasValidSessionVersion(decoded: any): Promise<boolean> {
    const tokenVersion = typeof decoded.sv === 'number' ? decoded.sv : 0;
    const currentVersion = await UserRepository.getSessionVersion(decoded.userId);
    return currentVersion !== null && currentVersion === tokenVersion;
}
