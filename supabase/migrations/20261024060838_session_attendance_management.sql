
-- Remind PT | 수업 출석 처리 및 이용권 횟수 차감
-- 기존 sessions, session_attendances, member_packages 테이블 사용
-- 예약 시 미차감
-- 출석·노쇼·당일 취소 시 1회 차감
-- 일반 취소 시 미차감
-- 상태 수정 시 중복 차감 방지 및 기존 차감 복구
-- 급여 정산은 추후 별도로 구현

BEGIN;

-- ============================================
-- 1. 회원별 출석 상태 변경 이력
-- ============================================

CREATE TABLE public.session_attendance_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  trainer_id uuid NOT NULL REFERENCES auth.users(id),
  attendance_id uuid NOT NULL
    REFERENCES public.session_attendances(id) ON DELETE RESTRICT,
  previous_status text NOT NULL,
  new_status text NOT NULL,
  package_delta smallint NOT NULL,
  changed_by uuid NOT NULL REFERENCES auth.users(id),
  changed_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT session_attendance_history_status_previous_check
    CHECK (
      previous_status IN (
        'scheduled',
        'attended',
        'no_show',
        'same_day_cancelled',
        'cancelled'
      )
    ),

  CONSTRAINT session_attendance_history_status_new_check
    CHECK (
      new_status IN (
        'scheduled',
        'attended',
        'no_show',
        'same_day_cancelled',
        'cancelled'
      )
    ),

  CONSTRAINT session_attendance_history_delta_check
    CHECK (package_delta BETWEEN -1 AND 1)
);

-- 출석 변경 이력 조회 성능 개선
CREATE INDEX session_attendance_history_attendance_idx
  ON public.session_attendance_history (
    attendance_id,
    changed_at DESC
  );

-- 출석 변경 이력 RLS 활성화
ALTER TABLE public.session_attendance_history
  ENABLE ROW LEVEL SECURITY;

-- 로그인한 트레이너의 출석 변경 이력만 조회
CREATE POLICY session_attendance_history_trainer_select
  ON public.session_attendance_history
  FOR SELECT TO authenticated
  USING (trainer_id = (SELECT auth.uid()));

-- 출석 변경 이력은 직접 수정하지 못하도록 제한
REVOKE ALL ON public.session_attendance_history
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.session_attendance_history
  TO authenticated;


-- ============================================
-- 2. 출석 상태 변경 및 이용권 횟수 처리 RPC
-- ============================================

CREATE FUNCTION public.set_session_attendance_status(
  p_attendance_id uuid,
  p_new_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();

  v_session_id uuid;
  v_company_id uuid;
  v_session_type text;
  v_package_id uuid;

  v_old_status text;
  v_old_session_status text;
  v_new_session_status text;

  v_starts_at timestamptz;
  v_ends_at timestamptz;

  v_was_deducted boolean;
  v_will_deduct boolean;

  -- -1: 차감, +1: 복구, 0: 변경 없음
  v_delta integer := 0;

  v_total integer;
  v_remaining integer;
  v_new_remaining integer;
  v_package_status text;
  v_reserved bigint;

BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  -- 올바른 출석 상태인지 확인
  IF p_attendance_id IS NULL
     OR p_new_status IS NULL
     OR p_new_status NOT IN (
       'scheduled',
       'attended',
       'no_show',
       'same_day_cancelled',
       'cancelled'
     )
  THEN
    RAISE EXCEPTION '올바른 출석 상태를 선택해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  -- 트레이너 단위 잠금으로 동시 작업 충돌 방지
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_trainer_id::text, 0)
  );

  -- 수업과 참여 회원 정보 조회 및 잠금
  SELECT
    a.session_id,
    a.company_id,
    s.session_type,
    a.package_id,
    a.attendance_status,
    s.status,
    s.starts_at,
    s.ends_at
  INTO
    v_session_id,
    v_company_id,
    v_session_type,
    v_package_id,
    v_old_status,
    v_old_session_status,
    v_starts_at,
    v_ends_at
  FROM public.session_attendances AS a
  JOIN public.sessions AS s
    ON s.id = a.session_id
  WHERE a.id = p_attendance_id
    AND a.trainer_id = v_trainer_id
    AND s.trainer_id = v_trainer_id
  FOR UPDATE OF s, a;

  IF NOT FOUND THEN
    RAISE EXCEPTION '수업 참여 기록을 찾을 수 없습니다.'
      USING ERRCODE = '42501';
  END IF;

  -- 같은 상태를 다시 저장하면 아무 작업도 하지 않음
  IF v_old_status = p_new_status THEN
    RETURN;
  END IF;

  -- 취소된 수업 복구 시 시간 중복 여부 재검사
  IF v_old_session_status = 'cancelled'
     AND p_new_status <> 'cancelled'
  THEN
    IF EXISTS (
      SELECT 1
      FROM public.sessions AS s
      WHERE s.trainer_id = v_trainer_id
        AND s.id <> v_session_id
        AND s.status <> 'cancelled'
        AND s.starts_at < v_ends_at
        AND s.ends_at > v_starts_at
    ) THEN
      RAISE EXCEPTION
        '이미 같은 시간에 다른 수업이 있어 취소된 수업을 복구할 수 없습니다.'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- 기존 상태와 신규 상태의 차감 여부 계산
  v_was_deducted := v_old_status IN (
    'attended',
    'no_show',
    'same_day_cancelled'
  );

  v_will_deduct := p_new_status IN (
    'attended',
    'no_show',
    'same_day_cancelled'
  );

  -- 새롭게 차감해야 하는 경우
  IF v_will_deduct AND NOT v_was_deducted THEN
    v_delta := -1;

  -- 이미 차감했지만 복구해야 하는 경우
  ELSIF v_was_deducted AND NOT v_will_deduct THEN
    v_delta := 1;
  END IF;

  -- 연결된 이용권 확인
  IF v_package_id IS NULL THEN
    RAISE EXCEPTION
      '이용권이 연결되지 않은 수업은 출석 상태를 변경할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 이용권 조회 및 잠금
  SELECT
    p.total_sessions,
    p.remaining_sessions,
    p.status
  INTO
    v_total,
    v_remaining,
    v_package_status
  FROM public.member_packages AS p
  WHERE p.id = v_package_id
    AND p.trainer_id = v_trainer_id
    AND p.company_id = v_company_id
    AND p.package_type = v_session_type
    AND p.usage_type = 'count'
  FOR UPDATE;

  IF NOT FOUND
     OR v_total IS NULL
     OR v_remaining IS NULL
  THEN
    RAISE EXCEPTION
      '사용 가능한 횟수제 이용권을 찾을 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 같은 이용권에 연결된 다른 예약 횟수 조회
  SELECT COUNT(*)
  INTO v_reserved
  FROM public.session_attendances AS a
  JOIN public.sessions AS s
    ON s.id = a.session_id
  WHERE a.package_id = v_package_id
    AND a.id <> p_attendance_id
    AND a.attendance_status = 'scheduled'
    AND s.status = 'scheduled';

  -- 차감 또는 복구 후 잔여 횟수
  v_new_remaining := v_remaining + v_delta;

  -- 잔여 횟수가 허용 범위를 벗어나는 경우 차단
  IF v_new_remaining < 0
     OR v_new_remaining > v_total
  THEN
    RAISE EXCEPTION
      '이용권 잔여 횟수가 허용 범위를 벗어납니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 다른 예약에 필요한 횟수 보장
  -- CASE의 THEN이 IF 조건의 끝으로 읽히지 않도록 괄호로 감싼다
  IF v_new_remaining < (
    v_reserved +
    CASE
      WHEN p_new_status = 'scheduled' THEN 1
      ELSE 0
    END
  ) THEN
    RAISE EXCEPTION
      '다른 예약에 필요한 이용권 횟수가 부족합니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 활성 이용권에서만 신규 차감 허용
  IF v_delta = -1
     AND v_package_status <> 'active'
  THEN
    RAISE EXCEPTION
      '현재 이용권 상태에서는 횟수를 차감할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 취소 또는 만료된 이용권으로 예약 복구 방지
  IF p_new_status = 'scheduled'
     AND v_package_status NOT IN ('active', 'completed')
  THEN
    RAISE EXCEPTION
      '취소 또는 만료된 이용권으로 예약 상태를 복구할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 이용권 잔여 횟수 변경
  IF v_delta <> 0 THEN
    UPDATE public.member_packages
    SET
      remaining_sessions = v_new_remaining,
      status = CASE
        WHEN v_package_status IN ('active', 'completed') THEN
          CASE
            WHEN v_new_remaining = 0 THEN 'completed'
            ELSE 'active'
          END
        ELSE v_package_status
      END
    WHERE id = v_package_id;
  END IF;

  -- 회원별 출석 상태 변경
  UPDATE public.session_attendances
  SET
    attendance_status = p_new_status,
    updated_at = now()
  WHERE id = p_attendance_id;

  -- 그룹 수업은 참여 회원 상태에 따라 수업 상태 결정
  SELECT CASE
    WHEN bool_and(attendance_status = 'cancelled')
      THEN 'cancelled'
    WHEN bool_or(attendance_status = 'scheduled')
      THEN 'scheduled'
    ELSE 'completed'
  END
  INTO v_new_session_status
  FROM public.session_attendances
  WHERE session_id = v_session_id;

  -- 수업 상태 갱신
  UPDATE public.sessions
  SET
    status = v_new_session_status,
    updated_at = now()
  WHERE id = v_session_id
    AND status IS DISTINCT FROM v_new_session_status;

  -- 출석 변경 이력 저장
  INSERT INTO public.session_attendance_history (
    trainer_id,
    attendance_id,
    previous_status,
    new_status,
    package_delta,
    changed_by
  )
  VALUES (
    v_trainer_id,
    p_attendance_id,
    v_old_status,
    p_new_status,
    v_delta,
    v_trainer_id
  );

END;
$$;

-- ============================================
-- 3. RPC 실행 권한
-- ============================================

REVOKE ALL
  ON FUNCTION public.set_session_attendance_status(uuid, text)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.set_session_attendance_status(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION
  public.set_session_attendance_status(uuid, text)
IS
  '회원별 출석 상태 변경, 차감/복구, 수업 상태 갱신, 변경 이력을 원자적으로 처리';

COMMIT;
