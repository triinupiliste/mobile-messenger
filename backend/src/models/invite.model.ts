export type InviteStatus = 'pending' | 'accepted' | 'declined' | 'removed';

export interface Invite {
    id: string;
    sender_id: string;
    receiver_id: string;
    status: InviteStatus;
    created_at: Date;
}