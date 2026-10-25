
-- Remind PT | 수업 전체 취소 RPC
-- 예약된 수업을 취소하고 참여 회원 상태를 함께 변경
-- 이용권 차감이 발생한 수업은 전체 취소를 허용하지 않음
-- 출석 변경 이력을 보존하고 데이터는 삭제하지 않음

CREATE OR REPLACE FUNCTION public.cancel_session(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();
  v_session_status text;
BEGIN
  -- ============================================
  -- 1. 로그인 및 입력값 확인
  -- ============================================

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  IF p_session_id IS NULL THEN
    RAISE EXCEPTION '취소할 수업을 선택해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  -- ============================================
  -- 2. 트레이너 단위 잠금
  -- ============================================

  -- 수업 등록 및 출석 처리 RPC와 같은 잠금을 사용
  -- 동시 요청으로 인한 상태 충돌 방지
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_trainer_id::text, 0)
  );

  -- ============================================
  -- 3. 본인 수업 확인
  -- ============================================

  SELECT s.status
    INTO v_session_status
  FROM public.sessions AS s
  WHERE s.id = p_session_id
    AND s.trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '수업을 찾을 수 없습니다.'
      USING ERRCODE = '42501';
  END IF;

  -- ============================================
  -- 4. 참여 회원 출석 기록 잠금
  -- ============================================

  PERFORM 1
  FROM public.session_attendances AS a
  WHERE a.session_id = p_session_id
    AND a.trainer_id = v_trainer_id
  ORDER BY a.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '수업 참여 기록이 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- ============================================
  -- 5. 기존 출석 처리 여부 확인
  -- ============================================

  -- 이미 출석·노쇼·당일 취소가 처리된 수업은
  -- 이용권 차감 이력이 있으므로 전체 취소 차단
  IF EXISTS (
    SELECT 1
    FROM public.session_attendances AS a
    WHERE a.session_id = p_session_id
      AND a.trainer_id = v_trainer_id
      AND a.attendance_status IN (
        'attended',
        'no_show',
        'same_day_cancelled'
      )
  ) THEN
    RAISE EXCEPTION
      '출석 처리가 완료된 회원이 있습니다. 회원별 출석 상태를 먼저 확인해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  IF v_session_status = 'completed' THEN
    RAISE EXCEPTION
      '완료된 수업은 전체 취소할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- ============================================
  -- 6. 회원별 출석 상태 취소 및 이력 저장
  -- ============================================

  -- 예정 상태인 회원만 취소 처리
  -- 이미 일반 취소된 회원은 중복 변경하지 않음
  -- 예약 시 이용권 미차감이므로 package_delta = 0
  WITH changed_attendances AS (
    UPDATE public.session_attendances AS a
    SET
      attendance_status = 'cancelled',
      updated_at = now()
    WHERE a.session_id = p_session_id
      AND a.trainer_id = v_trainer_id
      AND a.attendance_status = 'scheduled'
    RETURNING a.id, a.trainer_id
  )
  INSERT INTO public.session_attendance_history (
    trainer_id,
    attendance_id,
    previous_status,
    new_status,
    package_delta,
    changed_by
  )
  SELECT
    ca.trainer_id,
    ca.id,
    'scheduled',
    'cancelled',
    0,
    v_trainer_id
  FROM changed_attendances AS ca;

  -- ============================================
  -- 7. 수업 상태 취소
  -- ============================================

  UPDATE public.sessions
  SET
    status = 'cancelled',
    updated_at = now()
  WHERE id = p_session_id
    AND trainer_id = v_trainer_id
    AND status IS DISTINCT FROM 'cancelled';

  -- 취소된 수업은 기존 예약 중복 검사에서 제외됨
  -- 회원 및 이용권 기록은 삭제하지 않음

END;
$$;

-- ============================================
-- 8. RPC 실행 권한
-- ============================================

REVOKE ALL
  ON FUNCTION public.cancel_session(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.cancel_session(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.cancel_session(uuid)
IS
  '예약된 PT·그룹 수업 전체 취소 및 출석 변경 이력 저장';
