export interface User {
    id: string;
    email: string;
    username: string;
    password_hash: string;
    is_verified: boolean;
    verification_token?: string | null;
    reset_token?: string | null;
    reset_token_expires?: Date | null;
    created_at: Date;
}

export interface Profile {
    user_id: string;
    avatar_url?: string | null;
    about_me?: string | null; // Stored as encrypted text
}

export interface UserWithProfile extends User {
    avatar_url?: string | null;
    about_me?: string | null;
}