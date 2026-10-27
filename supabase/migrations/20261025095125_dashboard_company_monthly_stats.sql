
-- Remind PT | 대시보드 근무처별 월간 수업 통계
-- 기존 데이터 변경 없음
-- 한국 시간 기준 월간 수업 조회

BEGIN;

-- ============================================
-- 1. 근무처별 월간 수업 통계 RPC
-- ============================================

CREATE OR REPLACE FUNCTION public.get_dashboard_company_monthly_stats(
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  company_id uuid,
  company_name text,
  company_type text,
  is_active boolean,
  total_sessions bigint,
  pt_sessions bigint,
  group_sessions bigint,
  completed_sessions bigint,
  scheduled_sessions bigint,
  cancelled_sessions bigint
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_start_at timestamptz;
  v_end_at timestamptz;
BEGIN

  -- ============================================
  -- 2. 로그인 및 조회 기간 검증
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

  -- ============================================
  -- 3. 한국 시간 기준 월간 조회 범위
  -- ============================================

  v_start_at := make_timestamptz(
    p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul'
  );

  v_end_at := (
    (make_date(p_year, p_month, 1) + interval '1 month')::date
    ::timestamp AT TIME ZONE 'Asia/Seoul'
  );

  -- ============================================
  -- 4. 근무처별 수업 집계
  -- ============================================

  RETURN QUERY

  SELECT
    c.id AS company_id,
    c.name::text AS company_name,
    c.company_type::text AS company_type,
    c.is_active,

    COUNT(s.id) AS total_sessions,

    COUNT(s.id) FILTER (
      WHERE s.session_type = 'pt'
    ) AS pt_sessions,

    COUNT(s.id) FILTER (
      WHERE s.session_type = 'group'
    ) AS group_sessions,

    COUNT(s.id) FILTER (
      WHERE s.status = 'completed'
    ) AS completed_sessions,

    COUNT(s.id) FILTER (
      WHERE s.status = 'scheduled'
    ) AS scheduled_sessions,

    COUNT(s.id) FILTER (
      WHERE s.status = 'cancelled'
    ) AS cancelled_sessions

  FROM public.companies AS c

  LEFT JOIN public.sessions AS s
    ON s.company_id = c.id
    AND s.trainer_id = c.trainer_id

    -- 소프트 삭제된 수업 제외
    AND s.deleted_at IS NULL

    -- 선택한 월의 수업만 집계
    AND s.starts_at >= v_start_at
    AND s.starts_at < v_end_at

  -- 로그인한 트레이너의 근무처만 조회
  WHERE c.trainer_id = (SELECT auth.uid())

  -- 활성 근무처는 수업이 0건이어도 표시
  -- 보관된 근무처는 해당 월 수업이 있을 때만 표시
    AND (
      c.is_active = true
      OR s.id IS NOT NULL
    )

  GROUP BY
    c.id,
    c.name,
    c.company_type,
    c.is_active

  -- 수업이 많은 근무처부터 정렬
  ORDER BY
    COUNT(s.id) DESC,
    c.name ASC,
    c.id ASC;

END;
$$;

-- ============================================
-- 5. RPC 실행 권한
-- ============================================

REVOKE ALL
ON FUNCTION public.get_dashboard_company_monthly_stats(integer, integer)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_dashboard_company_monthly_stats(integer, integer)
TO authenticated;

COMMIT;
