export type MessageStatus = 'sent' | 'delivered' | 'read';
export type MediaType = 'text' | 'image' | 'video' | 'audio';

export interface Message {
    id: string;
    chat_id: string;
    sender_id: string;
    content?: string | null; // Stored as encrypted text payload
    media_url?: string | null;
    media_type: MediaType;
    status: MessageStatus;
    is_edited: boolean;
    is_deleted: boolean;
    created_at: Date;
}