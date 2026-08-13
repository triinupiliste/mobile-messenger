export interface Chat {
    id: string;
    created_at: Date;
}

export interface ChatParticipant {
    chat_id: string;
    user_id: string;
    is_archived: boolean;
    is_muted: boolean;
}

export interface ChatListItem {
    chat_id: string;
    contact_id: string;
    contact_username: string;
    contact_avatar?: string | null;
    is_archived: boolean;
    is_muted: boolean;
    last_message_content?: string | null; // Decrypted content preview
    last_message_type?: string | null;
    last_message_status?: string | null;
    last_message_sender_id?: string | null;
    last_message_time?: Date | null;
    unread_count: number;
}