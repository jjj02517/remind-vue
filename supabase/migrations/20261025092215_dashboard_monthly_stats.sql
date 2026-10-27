
-- Remind PT | 대시보드 월간 수업 및 출석 통계
-- 기존 데이터 변경 없음
-- 한국 시간 기준으로 해당 월의 수업을 집계

BEGIN;

CREATE OR REPLACE FUNCTION public.get_dashboard_monthly_stats(
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  total_sessions bigint,
  pt_sessions bigint,
  group_sessions bigint,
  completed_sessions bigint,
  scheduled_sessions bigint,
  cancelled_sessions bigint,
  attended_count bigint,
  no_show_count bigint,
  same_day_cancelled_count bigint,
  attendance_cancelled_count bigint,
  attendance_scheduled_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  -- ============================================
  -- 1. 로그인 및 조회 기간 검증
  -- ============================================

  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  IF p_year IS NULL
    OR p_year NOT BETWEEN 2000 AND 2100
    OR p_month IS NULL
    OR p_month NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION '올바른 연도와 월을 선택해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY

  -- ============================================
  -- 2. 한국 시간 기준 조회 기간
  -- ============================================

  WITH month_bounds AS (
    SELECT
      make_timestamptz(
        p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul'
      ) AS start_at,
      make_timestamptz(
        p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul'
      ) + interval '1 month' AS end_at
  ),

  -- ============================================
  -- 3. 해당 월의 수업 조회
  -- ============================================

  month_sessions AS MATERIALIZED (
    SELECT
      s.id,
      s.session_type,
      s.status
    FROM public.sessions AS s
    CROSS JOIN month_bounds AS b
    WHERE s.trainer_id = (SELECT auth.uid())
      AND s.deleted_at IS NULL
      AND s.starts_at >= b.start_at
      AND s.starts_at < b.end_at
  ),

  -- ============================================
  -- 4. 수업 단위 통계
  -- ============================================

  session_stats AS (
    SELECT
      count(*) AS total_sessions,
      count(*) FILTER (
        WHERE session_type = 'pt'
      ) AS pt_sessions,
      count(*) FILTER (
        WHERE session_type = 'group'
      ) AS group_sessions,
      count(*) FILTER (
        WHERE status = 'completed'
      ) AS completed_sessions,
      count(*) FILTER (
        WHERE status = 'scheduled'
      ) AS scheduled_sessions,
      count(*) FILTER (
        WHERE status = 'cancelled'
      ) AS cancelled_sessions
    FROM month_sessions
  ),

  -- ============================================
  -- 5. 회원별 출석 통계
  -- ============================================

  attendance_stats AS (
    SELECT
      count(*) FILTER (
        WHERE a.attendance_status = 'attended'
      ) AS attended_count,
      count(*) FILTER (
        WHERE a.attendance_status = 'no_show'
      ) AS no_show_count,
      count(*) FILTER (
        WHERE a.attendance_status = 'same_day_cancelled'
      ) AS same_day_cancelled_count,
      count(*) FILTER (
        WHERE a.attendance_status = 'cancelled'
      ) AS attendance_cancelled_count,
      count(*) FILTER (
        WHERE a.attendance_status = 'scheduled'
      ) AS attendance_scheduled_count
    FROM public.session_attendances AS a
    JOIN month_sessions AS s
      ON s.id = a.session_id
    WHERE a.trainer_id = (SELECT auth.uid())
  )

  -- ============================================
  -- 6. 최종 통계 반환
  -- ============================================

  SELECT
    ss.total_sessions,
    ss.pt_sessions,
    ss.group_sessions,
    ss.completed_sessions,
    ss.scheduled_sessions,
    ss.cancelled_sessions,
    ast.attended_count,
    ast.no_show_count,
    ast.same_day_cancelled_count,
    ast.attendance_cancelled_count,
    ast.attendance_scheduled_count
  FROM session_stats AS ss
  CROSS JOIN attendance_stats AS ast;

END;
$$;

-- ============================================
-- 7. 실행 권한
-- ============================================

REVOKE ALL
ON FUNCTION public.get_dashboard_monthly_stats(integer, integer)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_dashboard_monthly_stats(integer, integer)
TO authenticated;

COMMIT;
