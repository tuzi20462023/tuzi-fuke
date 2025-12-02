-- =====================================================
-- 私聊消息系统 - L5 一对一通讯
-- 创建日期: 2025-12-02
-- =====================================================

-- 1. 创建私聊消息表
CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    device_type TEXT NOT NULL DEFAULT 'radio',  -- 发送者设备类型
    sender_lat DOUBLE PRECISION,                 -- 发送者位置（用于L4距离记录）
    sender_lon DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,                -- 计算得出的距离
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 创建索引
CREATE INDEX IF NOT EXISTS idx_direct_messages_sender ON direct_messages(sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_recipient ON direct_messages(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_conversation ON direct_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_unread ON direct_messages(recipient_id, is_read) WHERE is_read = FALSE;

-- 3. 启用 RLS
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;

-- 4. RLS 策略 - 用户只能看到自己发送或接收的消息
CREATE POLICY "Users can view own messages"
    ON direct_messages FOR SELECT
    USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Users can send messages"
    ON direct_messages FOR INSERT
    WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update read status"
    ON direct_messages FOR UPDATE
    USING (auth.uid() = recipient_id)
    WITH CHECK (auth.uid() = recipient_id);

-- 5. 启用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;

-- =====================================================
-- 附近玩家查询函数（L4 距离过滤）
-- =====================================================

-- 获取附近玩家
CREATE OR REPLACE FUNCTION get_nearby_players(
    p_user_id UUID,
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_range_km DOUBLE PRECISION DEFAULT 100
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    callsign TEXT,
    distance_km DOUBLE PRECISION,
    last_seen_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH user_locations AS (
        -- 获取用户最近的位置心跳
        SELECT DISTINCT ON (ph.user_id)
            ph.user_id,
            ph.latitude,
            ph.longitude,
            ph.recorded_at as last_seen
        FROM position_heartbeat ph
        WHERE ph.recorded_at > NOW() - INTERVAL '24 hours'
        ORDER BY ph.user_id, ph.recorded_at DESC
    )
    SELECT
        ul.user_id as id,
        COALESCE(p.username, 'survivor_' || LEFT(ul.user_id::text, 8)) as username,
        p.callsign,
        -- 使用 Haversine 公式计算距离
        (6371 * acos(
            cos(radians(p_lat)) * cos(radians(ul.latitude)) *
            cos(radians(ul.longitude) - radians(p_lon)) +
            sin(radians(p_lat)) * sin(radians(ul.latitude))
        )) as distance_km,
        ul.last_seen as last_seen_at
    FROM user_locations ul
    LEFT JOIN profiles p ON p.id = ul.user_id
    WHERE ul.user_id != p_user_id
      AND (6371 * acos(
            cos(radians(p_lat)) * cos(radians(ul.latitude)) *
            cos(radians(ul.longitude) - radians(p_lon)) +
            sin(radians(p_lat)) * sin(radians(ul.latitude))
          )) <= p_range_km
    ORDER BY distance_km ASC
    LIMIT 50;
END;
$$;

-- =====================================================
-- 发送私聊消息函数（带L4距离检查）
-- =====================================================

CREATE OR REPLACE FUNCTION send_direct_message(
    p_sender_id UUID,
    p_recipient_id UUID,
    p_content TEXT,
    p_device_type TEXT,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lon DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_device_range_km DOUBLE PRECISION;
    v_recipient_lat DOUBLE PRECISION;
    v_recipient_lon DOUBLE PRECISION;
    v_distance_km DOUBLE PRECISION;
    v_message_id UUID;
BEGIN
    -- 获取设备范围
    CASE p_device_type
        WHEN 'radio' THEN
            -- 收音机不能发送
            RETURN jsonb_build_object(
                'success', false,
                'error', 'device_cannot_send',
                'message', '收音机只能接收，无法发送消息'
            );
        WHEN 'walkie_talkie' THEN v_device_range_km := 3;
        WHEN 'camp_radio' THEN v_device_range_km := 30;
        WHEN 'cellphone' THEN v_device_range_km := 100;
        ELSE v_device_range_km := 3;  -- 默认3km
    END CASE;

    -- 如果提供了位置，检查距离
    IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
        -- 获取接收者最近位置
        SELECT latitude, longitude INTO v_recipient_lat, v_recipient_lon
        FROM position_heartbeat
        WHERE user_id = p_recipient_id
        ORDER BY recorded_at DESC
        LIMIT 1;

        IF v_recipient_lat IS NOT NULL AND v_recipient_lon IS NOT NULL THEN
            -- 计算距离 (Haversine)
            v_distance_km := 6371 * acos(
                cos(radians(p_lat)) * cos(radians(v_recipient_lat)) *
                cos(radians(v_recipient_lon) - radians(p_lon)) +
                sin(radians(p_lat)) * sin(radians(v_recipient_lat))
            );

            -- 检查是否超出范围
            IF v_distance_km > v_device_range_km THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'out_of_range',
                    'distance_km', v_distance_km,
                    'max_range_km', v_device_range_km,
                    'message', '目标超出通讯范围'
                );
            END IF;
        END IF;
    END IF;

    -- 插入消息
    INSERT INTO direct_messages (
        sender_id, recipient_id, content, device_type,
        sender_lat, sender_lon, distance_km
    )
    VALUES (
        p_sender_id, p_recipient_id, p_content, p_device_type,
        p_lat, p_lon, v_distance_km
    )
    RETURNING id INTO v_message_id;

    RETURN jsonb_build_object(
        'success', true,
        'message_id', v_message_id,
        'distance_km', v_distance_km,
        'max_range_km', v_device_range_km
    );
END;
$$;

-- =====================================================
-- 获取对话列表函数
-- =====================================================

CREATE OR REPLACE FUNCTION get_conversations(p_user_id UUID)
RETURNS TABLE (
    other_user_id UUID,
    username TEXT,
    callsign TEXT,
    last_message TEXT,
    last_message_time TIMESTAMPTZ,
    unread_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH conversation_users AS (
        -- 获取所有对话的对方用户ID
        SELECT DISTINCT
            CASE
                WHEN sender_id = p_user_id THEN recipient_id
                ELSE sender_id
            END as other_id
        FROM direct_messages
        WHERE sender_id = p_user_id OR recipient_id = p_user_id
    ),
    last_messages AS (
        -- 获取每个对话的最后一条消息
        SELECT DISTINCT ON (
            CASE
                WHEN sender_id = p_user_id THEN recipient_id
                ELSE sender_id
            END
        )
            CASE
                WHEN sender_id = p_user_id THEN recipient_id
                ELSE sender_id
            END as other_id,
            content,
            created_at
        FROM direct_messages
        WHERE sender_id = p_user_id OR recipient_id = p_user_id
        ORDER BY
            CASE
                WHEN sender_id = p_user_id THEN recipient_id
                ELSE sender_id
            END,
            created_at DESC
    ),
    unread_counts AS (
        -- 计算未读消息数
        SELECT
            sender_id as other_id,
            COUNT(*) as cnt
        FROM direct_messages
        WHERE recipient_id = p_user_id AND is_read = false
        GROUP BY sender_id
    )
    SELECT
        cu.other_id as other_user_id,
        COALESCE(p.username, 'survivor_' || LEFT(cu.other_id::text, 8)) as username,
        p.callsign,
        lm.content as last_message,
        lm.created_at as last_message_time,
        COALESCE(uc.cnt, 0) as unread_count
    FROM conversation_users cu
    LEFT JOIN profiles p ON p.id = cu.other_id
    LEFT JOIN last_messages lm ON lm.other_id = cu.other_id
    LEFT JOIN unread_counts uc ON uc.other_id = cu.other_id
    ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;

-- =====================================================
-- 说明
-- =====================================================
--
-- L4 距离过滤功能:
-- 1. send_direct_message 函数会检查发送者和接收者之间的距离
-- 2. 如果超出设备通讯范围，消息发送会被拒绝
-- 3. 设备范围: 对讲机3km, 营地电台30km, 手机100km
--
-- L5 私聊功能:
-- 1. direct_messages 表存储所有私聊消息
-- 2. RLS 确保用户只能看到自己相关的消息
-- 3. Realtime 支持实时消息推送
-- 4. get_conversations 函数返回对话列表
-- 5. get_nearby_players 函数返回附近可通讯的玩家
