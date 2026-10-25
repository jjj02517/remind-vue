
-- Remind PT | 수업 날짜·시간·메모 수정
-- 예약 상태의 수업만 수정 가능
-- 기존 회원 및 이용권 연결은 유지
-- 다른 수업과 시간 중복 방지
-- 수정 이력 저장

BEGIN;

-- ============================================
-- 1. 수업 수정 이력 테이블
-- ============================================

CREATE TABLE public.session_edit_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  trainer_id uuid NOT NULL
    REFERENCES auth.users(id),

  session_id uuid NOT NULL
    REFERENCES public.sessions(id) ON DELETE RESTRICT,

  old_starts_at timestamptz NOT NULL,
  new_starts_at timestamptz NOT NULL,

  old_ends_at timestamptz NOT NULL,
  new_ends_at timestamptz NOT NULL,

  old_notes text,
  new_notes text,

  changed_by uuid NOT NULL
    REFERENCES auth.users(id),

  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX session_edit_history_session_idx
  ON public.session_edit_history (
    session_id,
    changed_at DESC
  );

-- 로그인한 트레이너만 자신의 수정 이력 조회 가능
ALTER TABLE public.session_edit_history
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY session_edit_history_trainer_select
  ON public.session_edit_history
  FOR SELECT TO authenticated
  USING (
    trainer_id = (SELECT auth.uid())
  );

-- 수정 이력은 앱에서 직접 변경할 수 없음
REVOKE ALL ON public.session_edit_history
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.session_edit_history
  TO authenticated;


-- ============================================
-- 2. 수업 수정 RPC
-- ============================================

CREATE FUNCTION public.update_session_details(
  p_session_id uuid,
  p_starts_at timestamptz,
  p_notes text
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

  v_old_starts_at timestamptz;
  v_old_ends_at timestamptz;
  v_old_notes text;

  v_new_ends_at timestamptz;
  v_new_notes text;
  v_new_date date;
  v_old_date date;

BEGIN

  -- ============================================
  -- 로그인 및 입력값 확인
  -- ============================================

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.'
      USING ERRCODE = '42501';
  END IF;

  IF p_session_id IS NULL OR p_starts_at IS NULL THEN
    RAISE EXCEPTION '수업 날짜와 시간을 확인해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  -- 수업은 한국 시간 기준 정시에 시작
  IF
    EXTRACT(
      MINUTE FROM p_starts_at AT TIME ZONE 'Asia/Seoul'
    ) <> 0
    OR
    EXTRACT(
      SECOND FROM p_starts_at AT TIME ZONE 'Asia/Seoul'
    ) <> 0
  THEN
    RAISE EXCEPTION '수업은 정시에만 시작할 수 있습니다.'
      USING ERRCODE = '22023';
  END IF;

  v_new_notes := NULLIF(BTRIM(p_notes), '');

  IF CHAR_LENGTH(v_new_notes) > 1000 THEN
    RAISE EXCEPTION '메모는 1000자 이하로 입력해 주세요.'
      USING ERRCODE = '22023';
  END IF;

  -- 종료 시간은 시작 시간에서 정확히 1시간 후
  v_new_ends_at := p_starts_at + INTERVAL '1 hour';

  v_new_date :=
    (p_starts_at AT TIME ZONE 'Asia/Seoul')::date;

  -- ============================================
  -- 트레이너 단위 잠금
  -- ============================================

  -- 기존 수업 등록·취소·출석 RPC와 같은 잠금 사용
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_trainer_id::text,
      0
    )
  );

  -- ============================================
  -- 3. 본인 수업 확인
  -- ============================================

  SELECT
    s.status,
    s.deleted_at,
    s.starts_at,
    s.ends_at,
    s.notes
  INTO
    v_session_status,
    v_deleted_at,
    v_old_starts_at,
    v_old_ends_at,
    v_old_notes
  FROM public.sessions AS s
  WHERE s.id = p_session_id
    AND s.trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '수업을 찾을 수 없습니다.'
      USING ERRCODE = '42501';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION '삭제된 수업은 수정할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  IF v_session_status <> 'scheduled' THEN
    RAISE EXCEPTION '예정 상태인 수업만 수정할 수 있습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 이미 출석 처리가 시작된 수업은 수정 차단
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
      '출석 처리가 진행된 수업은 일정을 수정할 수 없습니다.'
      USING ERRCODE = '22023';
  END IF;

  -- 변경사항이 없는 경우 중복 저장하지 않음
  IF
    v_old_starts_at = p_starts_at
    AND v_old_notes IS NOT DISTINCT FROM v_new_notes
  THEN
    RETURN;
  END IF;

  -- ============================================
  -- 4. 시간 중복 검사
  -- ============================================

  -- 같은 트레이너의 모든 근무처 수업을 검사
  -- 현재 수정 중인 수업은 중복 검사에서 제외
  IF EXISTS (
    SELECT 1
    FROM public.sessions AS s
    WHERE s.trainer_id = v_trainer_id
      AND s.id <> p_session_id
      AND s.status <> 'cancelled'
      AND s.deleted_at IS NULL
      AND s.starts_at < v_new_ends_at
      AND s.ends_at > p_starts_at
  ) THEN
    RAISE EXCEPTION
      '변경하려는 시간에 이미 다른 수업이 있습니다.'
      USING ERRCODE = '23505';
  END IF;

  -- ============================================
  -- 5. 변경 날짜의 이용권 유효성 확인
  -- ============================================

  v_old_date :=
    (v_old_starts_at AT TIME ZONE 'Asia/Seoul')::date;

  -- 날짜가 달라졌을 때만 이용권 기간 검증
  IF v_new_date <> v_old_date THEN

    -- 예정 상태인 회원의 이용권이 새 날짜에도
    -- 유효한지 확인 (이미 일반 취소한 회원 제외)
    IF EXISTS (
      SELECT 1
      FROM public.session_attendances AS a

      LEFT JOIN public.member_packages AS p
        ON p.id = a.package_id
        AND p.trainer_id = v_trainer_id
        AND p.member_id = a.member_id
        AND p.company_id = a.company_id
        AND p.package_type = a.session_type

      WHERE a.session_id = p_session_id
        AND a.trainer_id = v_trainer_id
        AND a.attendance_status = 'scheduled'
        AND (
          p.id IS NULL
          OR p.usage_type <> 'count'
          OR p.status <> 'active'
          OR (
            p.starts_on IS NOT NULL
            AND p.starts_on > v_new_date
          )
          OR (
            p.ends_on IS NOT NULL
            AND p.ends_on < v_new_date
          )
        )
    ) THEN
      RAISE EXCEPTION
        '변경하려는 날짜에 사용할 수 없는 회원 이용권이 있습니다.'
        USING ERRCODE = '22023';
    END IF;

  END IF;

  -- ============================================
  -- 6. 수업 일정 및 메모 수정
  -- ============================================

  UPDATE public.sessions
  SET
    starts_at = p_starts_at,
    ends_at = v_new_ends_at,
    notes = v_new_notes,
    updated_at = now()
  WHERE id = p_session_id
    AND trainer_id = v_trainer_id;

  -- ============================================
  -- 7. 수정 이력 저장
  -- ============================================

  INSERT INTO public.session_edit_history (
    trainer_id,
    session_id,
    old_starts_at,
    new_starts_at,
    old_ends_at,
    new_ends_at,
    old_notes,
    new_notes,
    changed_by
  )
  VALUES (
    v_trainer_id,
    p_session_id,
    v_old_starts_at,
    p_starts_at,
    v_old_ends_at,
    v_new_ends_at,
    v_old_notes,
    v_new_notes,
    v_trainer_id
  );

END;
$$;


-- ============================================
-- 8. RPC 실행 권한
-- ============================================

REVOKE ALL
  ON FUNCTION public.update_session_details(
    uuid,
    timestamptz,
    text
  )
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.update_session_details(
    uuid,
    timestamptz,
    text
  )
  TO authenticated;

COMMENT ON FUNCTION public.update_session_details(
  uuid,
  timestamptz,
  text
) IS
  '예정 수업 날짜·시간·메모 수정 및 변경 이력 저장';

COMMIT;
