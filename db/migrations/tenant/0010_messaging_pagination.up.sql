-- Cursor pagination and latest-message previews remain index-backed as inboxes grow.
CREATE INDEX conversations_history_page
    ON conversations (tenant_id, last_message_at DESC, id DESC);
CREATE INDEX messages_history_page
    ON messages (tenant_id, conversation_id, created_at DESC, id DESC);
