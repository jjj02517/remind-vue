
-- Remind PT | 잘못 등록한 수업 삭제
-- 실제 DELETE 대신 소프트 삭제 방식 사용
-- 일반 수업 취소 기록과 삭제 기록을 구분
-- 회원, 이용권, 출석 변경 이력은 보존

-- ============================================
-- 1. 수업 삭제 정보 컬럼 추가
-- ============================================

ALTER TABLE public.sessions
  ADD COLUMN deleted_at timestamptz,
  ADD COLUMN deleted_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL;

-- 삭제된 수업은 반드시 취소 상태여야 함
ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_deleted_status_check
  CHECK (
    deleted_at IS NULL
    OR status = 'cancelled'
  );

COMMENT ON COLUMN public.sessions.deleted_at IS
  '잘못 등록한 수업을 삭제 처리한 시각. NULL이면 일반 수업';

COMMENT ON COLUMN public.sessions.deleted_by IS
  '수업 삭제를 실행한 트레이너';


-- ============================================
-- 2. 삭제된 수업의 출석 기록 수정 방지
-- ============================================

-- 기존 출석 처리 RPC를 통해 삭제된 수업이
-- 다시 예약 상태로 복구되지 않도록 보호
CREATE FUNCTION public.prevent_deleted_session_attendance_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.sessions AS s
    WHERE s.id = NEW.session_id
      AND s.deleted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION
      '삭제된 수업의 출석 기록은 변경할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER prevent_deleted_session_attendance_update_trigger
BEFORE UPDATE ON public.session_attendances
FOR EACH ROW
EXECUTE FUNCTION
  public.prevent_deleted_session_attendance_update();


-- ============================================
-- 3. 수업 삭제 RPC
-- ============================================

CREATE FUNCTION public.delete_session(
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
  v_deleted_at timestamptz;

BEGIN
  -- ============================================
  -- 로그인 및 입력값 확인
  -- ============================================

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  IF p_session_id IS NULL THEN
    RAISE EXCEPTION '삭제할 수업을 선택해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  -- ============================================
  -- 트레이너 단위 잠금
  -- ============================================

  -- 수업 등록, 출석 처리, 수업 취소 RPC와
  -- 동일한 잠금을 사용하여 동시 요청 충돌 방지
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_trainer_id::text,
      0
    )
  );

  -- ============================================
  -- 본인 수업인지 확인
  -- ============================================

  SELECT
    s.status,
    s.deleted_at
  INTO
    v_session_status,
    v_deleted_at
  FROM public.sessions AS s
  WHERE s.id = p_session_id
    AND s.trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '삭제할 수업을 찾을 수 없습니다.'
      USING ERRCODE = '42501';
  END IF;

  -- 이미 삭제된 수업은 중복 처리하지 않음
  IF v_deleted_at IS NOT NULL THEN
    RETURN;
  END IF;

  -- ============================================
  -- 삭제 가능한 수업 상태 확인
  -- ============================================

  -- 이미 완료되거나 취소 처리된 수업은
  -- 정상적인 운영 이력이므로 삭제하지 않음
  IF v_session_status <> 'scheduled' THEN
    RAISE EXCEPTION
      '예약 상태인 수업만 삭제할 수 있습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 출석 완료, 노쇼, 당일 취소가 처리되었다면
  -- 이용권 차감 이력이 있으므로 삭제 차단
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
      '이미 출석 처리가 진행된 수업은 삭제할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- ============================================
  -- 참여 회원 예약 취소
  -- ============================================

  -- 기존에 검증된 수업 취소 RPC를 재사용
  -- 이 RPC가 참여 회원의 예약 상태를 취소하고
  -- 출석 변경 이력도 함께 저장함
  --
  -- 같은 DB 트랜잭션 안에서 실행되므로
  -- 아래 삭제 처리에 실패하면 취소도 롤백됨
  PERFORM public.cancel_session(p_session_id);

  -- ============================================
  -- 수업 소프트 삭제
  -- ============================================

  UPDATE public.sessions
  SET
    deleted_at = now(),
    deleted_by = v_trainer_id,
    updated_at = now()
  WHERE id = p_session_id
    AND trainer_id = v_trainer_id
    AND deleted_at IS NULL;

  -- ============================================
  -- 결과
  -- ============================================

  -- 수업과 출석 기록은 DB에 보존
  -- 삭제된 수업은 향후 달력 조회에서 제외
  -- 취소 상태이므로 시간 중복 검사에서도 제외

END;
$$;


-- ============================================
-- 4. RPC 실행 권한
-- ============================================

REVOKE ALL
  ON FUNCTION public.delete_session(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.delete_session(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.delete_session(uuid) IS
  '잘못 등록한 예약 수업을 소프트 삭제하고 참여 회원 및 변경 이력을 보존';
