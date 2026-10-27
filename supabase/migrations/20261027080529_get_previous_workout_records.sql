-- Remind PT | 회원의 이전 운동 기록 조회
-- 현재 작성 중인 수업보다 이전 수업의 운동 기록을 조회합니다.
-- 수업 관리와 회원 상세에서 동일한 함수로 사용할 수 있습니다.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_previous_workout_records(
  p_attendance_id uuid,
  p_page_size integer DEFAULT 3,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  attendance_id uuid,
  session_id uuid,
  starts_at timestamptz,
  session_type text,
  company_name text,
  workout_notes text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT
    previous_attendance.id,
    previous_session.id,
    previous_session.starts_at,
    previous_session.session_type,
    company.name::text,
    previous_attendance.workout_notes
  FROM public.session_attendances AS current_attendance

  -- 현재 작성 중인 수업의 날짜를 확인
  JOIN public.sessions AS current_session
    ON current_session.id = current_attendance.session_id
    AND current_session.trainer_id = current_attendance.trainer_id

  -- 같은 회원의 다른 수업 참여 기록 조회
  JOIN public.session_attendances AS previous_attendance
    ON previous_attendance.member_id = current_attendance.member_id
    AND previous_attendance.trainer_id = current_attendance.trainer_id
    AND previous_attendance.id <> current_attendance.id

  JOIN public.sessions AS previous_session
    ON previous_session.id = previous_attendance.session_id
    AND previous_session.trainer_id = previous_attendance.trainer_id

  JOIN public.companies AS company
    ON company.id = previous_session.company_id
    AND company.trainer_id = previous_session.trainer_id

  WHERE current_attendance.id = p_attendance_id

    -- 로그인한 트레이너의 기록만 조회
    AND current_attendance.trainer_id = (SELECT auth.uid())

    -- 삭제된 수업 제외
    AND current_session.deleted_at IS NULL
    AND previous_session.deleted_at IS NULL

    -- 현재 작성 중인 수업보다 이전에 진행한 수업만 조회
    AND previous_session.starts_at < current_session.starts_at

    -- 실제 운동 기록이 작성된 수업만 조회
    AND NULLIF(btrim(previous_attendance.workout_notes), '') IS NOT NULL

  -- 이전 수업 중 가장 최근 기록부터 표시
  ORDER BY
    previous_session.starts_at DESC,
    previous_session.id DESC,
    previous_attendance.id DESC

  -- 기본 3건, 최대 50건
  LIMIT LEAST(
    GREATEST(COALESCE(p_page_size, 3), 1),
    50
  )

  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

-- 로그인한 사용자에게만 함수 실행 권한 부여
REVOKE ALL
ON FUNCTION public.get_previous_workout_records(
  uuid,
  integer,
  integer
)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_previous_workout_records(
  uuid,
  integer,
  integer
)
TO authenticated;

COMMENT ON FUNCTION public.get_previous_workout_records(
  uuid,
  integer,
  integer
) IS
  '현재 수업보다 이전에 작성된 동일 회원의 운동 기록 조회';

COMMIT;