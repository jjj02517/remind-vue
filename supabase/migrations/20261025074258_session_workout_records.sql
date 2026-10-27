
-- Remind PT | 회원별 실제 운동 기록
-- 수업 공통 계획은 기존 sessions.notes 사용
-- 회원별 실제 운동 내용은 session_attendances에 저장
-- 출석 상태와 운동 기록을 함께 저장할 수 있도록 RPC 제공

BEGIN;

-- ============================================
-- 1. 회원별 운동 기록 컬럼
-- ============================================

ALTER TABLE public.session_attendances
  ADD COLUMN workout_notes text;

-- 운동 기록은 최대 2000자
ALTER TABLE public.session_attendances
  ADD CONSTRAINT session_attendances_workout_notes_length_check
  CHECK (
    workout_notes IS NULL
    OR char_length(workout_notes) <= 2000
  );

COMMENT ON COLUMN public.session_attendances.workout_notes IS
  '회원별 실제 운동 기록. 수업 전 계획은 sessions.notes에 저장';


-- ============================================
-- 2. 운동 기록 저장 RPC
-- ============================================

CREATE FUNCTION public.save_session_workout_record(
  p_attendance_id uuid,
  p_workout_notes text,
  p_new_status text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();

  v_old_notes text;
  v_new_notes text;

BEGIN

  -- ============================================
  -- 로그인 및 입력값 검증
  -- ============================================

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  IF p_attendance_id IS NULL THEN
    RAISE EXCEPTION '수업 참여 기록을 선택해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  IF p_workout_notes IS NOT NULL
     AND char_length(p_workout_notes) > 2000 THEN
    RAISE EXCEPTION '운동 기록은 2000자 이하로 입력해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  -- 입력값 양끝 공백 제거
  -- 빈 문자열은 NULL로 저장
  v_new_notes := NULLIF(btrim(p_workout_notes), '');

  -- ============================================
  -- 동시 저장 충돌 방지
  -- ============================================

  -- 기존 출석 처리 RPC와 같은 트레이너 단위 잠금
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_trainer_id::text,
      0
    )
  );

  -- ============================================
  -- 본인 회원 및 수업인지 확인
  -- ============================================

  SELECT a.workout_notes
    INTO v_old_notes
  FROM public.session_attendances AS a
  JOIN public.sessions AS s
    ON s.id = a.session_id
  WHERE a.id = p_attendance_id
    AND a.trainer_id = v_trainer_id
    AND s.trainer_id = v_trainer_id
    AND s.deleted_at IS NULL
  FOR UPDATE OF a, s;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      '운동 기록을 저장할 수 있는 수업을 찾지 못했습니다.'
      USING ERRCODE = '42501';
  END IF;

  -- ============================================
  -- 3. 출석 상태 변경 (선택 사항)
  -- ============================================

  -- p_new_status가 NULL이면 운동 기록만 저장
  -- 상태가 전달되면 출석 상태도 함께 저장
  --
  -- 기존 RPC에서 이용권 차감·복구,
  -- 예약 횟수 검증 및 출석 이력을 처리
  IF p_new_status IS NOT NULL THEN

    PERFORM public.set_session_attendance_status(
      p_attendance_id,
      p_new_status
    );

  END IF;

  -- ============================================
  -- 4. 회원별 실제 운동 기록 저장
  -- ============================================

  -- 기록 내용이 같으면 불필요한 UPDATE 생략
  IF v_old_notes IS DISTINCT FROM v_new_notes THEN

    UPDATE public.session_attendances
    SET
      workout_notes = v_new_notes,
      updated_at = now()
    WHERE id = p_attendance_id
      AND trainer_id = v_trainer_id;

  END IF;

  -- 출석 변경과 운동 기록 저장은 하나의 트랜잭션
  -- 어느 한 작업이라도 실패하면 모두 롤백됨

END;
$$;


-- ============================================
-- 5. RPC 실행 권한
-- ============================================

REVOKE ALL
  ON FUNCTION public.save_session_workout_record(
    uuid,
    text,
    text
  )
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.save_session_workout_record(
    uuid,
    text,
    text
  )
  TO authenticated;

COMMENT ON FUNCTION public.save_session_workout_record(
  uuid,
  text,
  text
) IS
  '회원별 운동 기록 저장 및 선택적 출석 상태 변경';

COMMIT;
