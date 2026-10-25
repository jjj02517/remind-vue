
-- Remind PT | 회원별 수업 이력 서버 페이지네이션
-- 기존 회원·수업·운동 기록은 변경하지 않음
-- 실제 수업 날짜 기준 최신순으로 조회
-- 근무처별 필터는 실제 수업 이력이 있는 근무처만 제공

BEGIN;

-- ============================================
-- 1. 수업 이력 조회용 인덱스
-- ============================================

CREATE INDEX IF NOT EXISTS
  session_attendances_trainer_member_session_idx
ON public.session_attendances (
  trainer_id,
  member_id,
  session_id
);

CREATE INDEX IF NOT EXISTS
  sessions_history_order_idx
ON public.sessions (
  trainer_id,
  starts_at DESC,
  id DESC
)
WHERE deleted_at IS NULL;


-- ============================================
-- 2. 회원별 수업 이력 페이지 조회
-- ============================================

CREATE FUNCTION public.get_member_session_history_page(
  p_member_id uuid,
  p_company_id uuid DEFAULT NULL,
  p_page_size integer DEFAULT 5,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  attendance_id uuid,
  session_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  session_type text,
  attendance_status text,
  company_id uuid,
  company_name text,
  session_notes text,
  workout_notes text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT
    a.id,
    s.id,
    s.starts_at,
    s.ends_at,
    s.session_type,
    a.attendance_status,
    c.id,
    c.name::text,
    s.notes,
    a.workout_notes
  FROM public.session_attendances AS a

  JOIN public.sessions AS s
    ON s.id = a.session_id
    AND s.trainer_id = a.trainer_id

  JOIN public.companies AS c
    ON c.id = s.company_id
    AND c.trainer_id = s.trainer_id

  JOIN public.members AS m
    ON m.id = a.member_id
    AND m.trainer_id = a.trainer_id

  WHERE a.member_id = p_member_id

    -- 로그인한 트레이너의 데이터만 조회
    AND a.trainer_id = (SELECT auth.uid())
    AND s.trainer_id = (SELECT auth.uid())

    -- 소프트 삭제된 수업 제외
    AND s.deleted_at IS NULL

    -- 특정 근무처 선택 시 해당 근무처만 조회
    AND (
      p_company_id IS NULL
      OR s.company_id = p_company_id
    )

  -- 등록일이 아닌 실제 수업일 기준 최신순
  -- 같은 시간인 경우 UUID로 순서를 고정
  ORDER BY
    s.starts_at DESC,
    s.id DESC,
    a.id DESC

  -- 한 번에 최대 50건까지만 조회
  LIMIT LEAST(
    GREATEST(COALESCE(p_page_size, 5), 1),
    50
  )

  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;


-- ============================================
-- 3. 수업 이력이 있는 근무처 목록 및 건수
-- ============================================

CREATE FUNCTION public.get_member_session_history_companies(
  p_member_id uuid
)
RETURNS TABLE (
  company_id uuid,
  company_name text,
  session_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT
    c.id,
    c.name::text,
    COUNT(*)::bigint
  FROM public.session_attendances AS a

  JOIN public.sessions AS s
    ON s.id = a.session_id
    AND s.trainer_id = a.trainer_id

  JOIN public.companies AS c
    ON c.id = s.company_id
    AND c.trainer_id = s.trainer_id

  JOIN public.members AS m
    ON m.id = a.member_id
    AND m.trainer_id = a.trainer_id

  WHERE a.member_id = p_member_id
    AND a.trainer_id = (SELECT auth.uid())
    AND s.trainer_id = (SELECT auth.uid())
    AND s.deleted_at IS NULL

  GROUP BY c.id, c.name
  ORDER BY c.name ASC, c.id ASC;
$$;


-- ============================================
-- 4. RPC 실행 권한
-- ============================================

REVOKE ALL
ON FUNCTION public.get_member_session_history_page(
  uuid, uuid, integer, integer
)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_member_session_history_page(
  uuid, uuid, integer, integer
)
TO authenticated;

REVOKE ALL
ON FUNCTION public.get_member_session_history_companies(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_member_session_history_companies(uuid)
TO authenticated;

COMMIT;
