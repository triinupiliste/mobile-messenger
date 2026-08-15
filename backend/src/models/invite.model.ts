export type InviteStatus = 'pending' | 'accepted' | 'declined' | 'removed';

export interface Invite {
    id: string;
    sender_id: string;
    receiver_id: string;
    status: InviteStatus;
    created_at: Date;
}

export interface PendingInviteItem {
    id: string;
    sender_id: string;
    sender_username: string;
    sender_avatar?: string | null;
    created_at: Date;
}