export type InviteStatus = 'pending' | 'accepted' | 'declined' | 'removed';

export interface Invite {
    id: string;
    sender_id: string;
    receiver_id: string;
    status: InviteStatus;
    created_at: Date;
}

// The other user's public-facing details attached to an enriched invite row
// (avatar_url is already decrypted by the time it's returned).
export interface InviteUserSummary {
    id: string;
    username: string;
    email: string;
    avatar_url: string | null;
}

// Shape returned by InviteRepository.getPendingInvitesForUser/getIncomingInviteById.
export interface IncomingInviteItem {
    id: string;
    sender_id: string;
    status: InviteStatus;
    created_at: Date;
    sender: InviteUserSummary;
}

// Shape returned by InviteRepository.getOutgoingInvitesForUser.
export interface OutgoingInviteItem {
    id: string;
    receiver_id: string;
    status: InviteStatus;
    created_at: Date;
    recipient: InviteUserSummary;
}