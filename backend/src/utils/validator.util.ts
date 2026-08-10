export function isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

export function validatePasswordStrength(password: string): { isValid: boolean; errors: string[] } {
    const errors: string[] = [];
    if (password.length < 8) errors.push('Password must be at least 8 characters long.');
    if (!/[a-z]/.test(password)) errors.push('Password must contain at least 1 lowercase letter.');
    if (!/[A-Z]/.test(password)) errors.push('Password must contain at least 1 uppercase letter.');
    if (!/\d/.test(password)) errors.push('Password must contain at least 1 digit.');
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) errors.push('Password must contain at least 1 special character.');

    return {
        isValid: errors.length === 0,
        errors
    };
}