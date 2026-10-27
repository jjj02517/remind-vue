-- Remind PT | 월별 엑셀 다운로드용 데이터 조회
-- 전체 월간 통계, 근무처별 통계, 회원별 수업 기록을 함께 반환합니다.
-- 기존 데이터와 대시보드 조회 함수는 변경하지 않습니다.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_monthly_session_export(
  p_year integer,
  p_month integer
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
SET timezone = 'Asia/Seoul'
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_result jsonb;
BEGIN
  -- 로그인 및 조회 기간 검증
  IF v_trainer_id IS NULL THEN
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

  -- 한국 시간 기준 월초부터 다음 달 월초 직전까지 조회
  v_start_at := make_timestamptz(
    p_year, p_month, 1, 0, 0, 0, 'Asia/Seoul'
  );

  v_end_at := (
    (make_date(p_year, p_month, 1) + interval '1 month')
    AT TIME ZONE 'Asia/Seoul'
  );

  -- 회원별 참여 기록: 그룹 수업에 3명이 참여하면 3행
  WITH monthly_records AS MATERIALIZED (
    SELECT
      a.id AS attendance_id,
      s.id AS session_id,
      m.id AS member_id,
      m.name::text AS member_name,
      c.id AS company_id,
      c.name::text AS company_name,
      s.session_type,
      s.status AS session_status,
      a.attendance_status,
      s.starts_at,
      s.ends_at,
      s.notes AS session_notes,
      a.workout_notes,

      -- 현재 출석 상태 기준 차감 횟수
      -- 일반 취소 또는 예정으로 복구된 기록은 0회
      CASE
        WHEN a.attendance_status IN (
          'attended', 'no_show', 'same_day_cancelled'
        ) THEN 1
        ELSE 0
      END AS deducted_sessions

    FROM public.session_attendances AS a

    JOIN public.sessions AS s
      ON s.id = a.session_id
      AND s.trainer_id = a.trainer_id

    JOIN public.members AS m
      ON m.id = a.member_id
      AND m.trainer_id = a.trainer_id

    JOIN public.companies AS c
      ON c.id = s.company_id
      AND c.trainer_id = s.trainer_id

    WHERE a.trainer_id = v_trainer_id
      AND s.deleted_at IS NULL
      AND s.starts_at >= v_start_at
      AND s.starts_at < v_end_at

    -- 보관된 회원과 근무처의 과거 수업도 포함
    -- 회원 상태나 근무처 활성 여부로 제외하지 않음
  )

  SELECT jsonb_build_object(
    'year', p_year,
    'month', p_month,
    'timezone', 'Asia/Seoul',

    -- 수업 단위 통계: 그룹 수업도 수업 자체는 1건
    -- 기존 대시보드 집계 함수를 재사용
    'summary', (
      SELECT to_jsonb(stats)
      FROM public.get_dashboard_monthly_stats(p_year, p_month) AS stats
    ),

    -- 활성 근무처는 수업이 0건이어도 포함
    -- 보관된 근무처는 해당 월 수업이 있을 때 포함
    'companies', (
      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(stats)
          ORDER BY
            stats.total_sessions DESC,
            stats.company_name ASC,
            stats.company_id ASC
        ),
        '[]'::jsonb
      )
      FROM public.get_dashboard_company_monthly_stats(p_year, p_month) AS stats
    ),

    -- 전체 내역을 배열로 반환하여 화면 페이지네이션과 분리
    'records', (
      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(record)
          ORDER BY
            record.starts_at ASC,
            record.session_id ASC,
            record.member_name ASC,
            record.attendance_id ASC
        ),
        '[]'::jsonb
      )
      FROM monthly_records AS record
    ),

    'record_count', (SELECT count(*) FROM monthly_records)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

-- 로그인한 사용자에게만 실행 권한 부여
-- 테이블 조회에는 기존 RLS가 그대로 적용됨
REVOKE ALL
ON FUNCTION public.get_monthly_session_export(integer, integer)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_monthly_session_export(integer, integer)
TO authenticated;

COMMENT ON FUNCTION public.get_monthly_session_export(integer, integer) IS
  '월별 엑셀 다운로드용 전체 통계, 근무처별 통계 및 회원별 수업 기록 조회';

COMMIT;