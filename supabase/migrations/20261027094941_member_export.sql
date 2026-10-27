-- Remind PT | 회원별 전체 내역 엑셀 다운로드용 데이터
-- 회원 정보, 소속 근무처, 전체 이용권, 일시정지, 수업 기록을 반환합니다.
-- 회원 활동 상태는 앱의 기존 getMemberStatus 함수로 계산합니다.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_member_export(
  p_member_id uuid
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
  v_exported_at timestamptz := statement_timestamp();
  v_result jsonb;
BEGIN
  -- 로그인 및 회원 ID 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  IF p_member_id IS NULL THEN
    RAISE EXCEPTION '회원을 선택해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  WITH target_member AS MATERIALIZED (
    -- 로그인한 트레이너가 관리하는 회원만 조회
    -- 보관 회원도 기존 이력을 조회할 수 있도록 상태로 제외하지 않음
    SELECT
      m.id,
      m.name,
      m.phone,
      m.status,
      m.created_at
    FROM public.members AS m
    WHERE m.id = p_member_id
      AND m.trainer_id = v_trainer_id
  ),

  member_companies AS MATERIALIZED (
    -- 현재 연결된 근무처: 보관된 근무처도 포함
    SELECT
      c.id AS company_id,
      c.name::text AS company_name,
      c.company_type,
      c.is_active
    FROM public.company_members AS link
    JOIN target_member AS m
      ON m.id = link.member_id
    JOIN public.companies AS c
      ON c.id = link.company_id
      AND c.trainer_id = link.trainer_id
    WHERE link.trainer_id = v_trainer_id
  ),

  member_packages AS MATERIALIZED (
    -- 현재·예정·지난 이용권을 모두 조회
    SELECT
      p.id,
      p.member_id,
      p.company_id,
      c.name::text AS company_name,
      c.is_active AS company_is_active,
      p.package_type,
      p.usage_type,
      p.total_sessions,
      p.remaining_sessions,
      p.starts_on,
      p.ends_on,
      p.status,
      p.created_at
    FROM public.member_packages AS p
    JOIN target_member AS m
      ON m.id = p.member_id

    -- 과거에 근무처가 지정되지 않은 이용권도 누락하지 않음
    LEFT JOIN public.companies AS c
      ON c.id = p.company_id
      AND c.trainer_id = p.trainer_id

    WHERE p.trainer_id = v_trainer_id
  ),

  member_pauses AS MATERIALIZED (
    -- 정지 예정·정지 중·종료·조기 복귀·예약 취소 내역 모두 포함
    SELECT
      pause.id,
      pause.package_id,
      pause.starts_on,
      pause.ends_on,
      pause.resumed_on,
      pause.cancelled_at,
      pause.reason,
      pause.created_at
    FROM public.package_pauses AS pause
    JOIN member_packages AS p
      ON p.id = pause.package_id
    WHERE pause.trainer_id = v_trainer_id
  ),

  member_records AS MATERIALIZED (
    -- 해당 회원의 전체 기간 수업 이력
    -- 그룹 수업도 이 회원의 참여 기록 한 건만 반환
    SELECT
      a.id AS attendance_id,
      s.id AS session_id,
      m.id AS member_id,
      m.name::text AS member_name,
      a.package_id,
      c.id AS company_id,
      c.name::text AS company_name,
      s.session_type,
      s.status AS session_status,
      a.attendance_status,
      s.starts_at,
      s.ends_at,
      s.notes AS session_notes,
      a.workout_notes,

      CASE
        WHEN a.attendance_status IN (
          'attended', 'no_show', 'same_day_cancelled'
        ) THEN 1
        ELSE 0
      END AS deducted_sessions

    FROM public.session_attendances AS a
    JOIN target_member AS m
      ON m.id = a.member_id
    JOIN public.sessions AS s
      ON s.id = a.session_id
      AND s.trainer_id = a.trainer_id
    JOIN public.companies AS c
      ON c.id = s.company_id
      AND c.trainer_id = s.trainer_id

    WHERE a.trainer_id = v_trainer_id
      AND s.deleted_at IS NULL
  )

  SELECT jsonb_build_object(
    'exported_at', v_exported_at,
    'as_of_date', (v_exported_at AT TIME ZONE 'Asia/Seoul')::date,
    'timezone', 'Asia/Seoul',
    'member', to_jsonb(m),

    'companies', (
      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(company)
          ORDER BY
            (company.company_type = 'personal') DESC,
            company.company_name ASC,
            company.company_id ASC
        ),
        '[]'::jsonb
      )
      FROM member_companies AS company
    ),

    'packages', (
      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(p)
          ORDER BY p.created_at DESC, p.id DESC
        ),
        '[]'::jsonb
      )
      FROM member_packages AS p
    ),

    'pauses', (
      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(pause)
          ORDER BY
            pause.starts_on DESC,
            pause.created_at DESC,
            pause.id DESC
        ),
        '[]'::jsonb
      )
      FROM member_pauses AS pause
    ),

    'records', (
      SELECT COALESCE(
        jsonb_agg(
          to_jsonb(record)
          ORDER BY
            record.starts_at ASC,
            record.session_id ASC,
            record.attendance_id ASC
        ),
        '[]'::jsonb
      )
      FROM member_records AS record
    ),

    -- 각 배열의 누락 여부를 앱에서 확인하기 위한 전체 건수
    'company_count', (SELECT count(*) FROM member_companies),
    'package_count', (SELECT count(*) FROM member_packages),
    'pause_count', (SELECT count(*) FROM member_pauses),
    'record_count', (SELECT count(*) FROM member_records)
  )
  INTO v_result
  FROM target_member AS m;

  IF v_result IS NULL THEN
    RAISE EXCEPTION '회원을 찾을 수 없거나 조회 권한이 없습니다.'
      USING ERRCODE = '42501';
  END IF;

  RETURN v_result;
END;
$$;

-- 로그인한 사용자만 실행 가능하며 기존 RLS를 유지
REVOKE ALL
ON FUNCTION public.get_member_export(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_member_export(uuid)
TO authenticated;

COMMENT ON FUNCTION public.get_member_export(uuid) IS
  '회원별 전체 정보, 이용권, 일시정지 및 수업 이력 엑셀 다운로드용 조회';

COMMIT;