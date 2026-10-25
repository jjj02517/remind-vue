-- Remind PT | PT·그룹 수업 등록 RPC
-- 기존 sessions, session_attendances 테이블 생성 마이그레이션 이후 적용
-- 예약 단계에서는 이용권을 차감하지 않습니다.

BEGIN;

CREATE OR REPLACE FUNCTION public.create_session_with_participants(
  p_company_id uuid,
  p_session_type text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_participants jsonb,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();
  v_session_id uuid;
  v_item jsonb;
  v_member_id uuid;
  v_package_id uuid;
  v_seen_members uuid[] := ARRAY[]::uuid[];
  v_remaining integer;
  v_reserved bigint;
  v_count integer;
  v_session_date date;
BEGIN
  -- 1. 로그인, 시간 및 수업 종류 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.' USING ERRCODE = '42501';
  END IF;

  IF p_session_type IS NULL OR p_session_type NOT IN ('pt', 'group') THEN
    RAISE EXCEPTION 'PT 또는 그룹 수업을 선택해 주세요.' USING ERRCODE = '22023';
  END IF;

  IF p_starts_at IS NULL OR p_ends_at IS NULL
    OR p_ends_at <= p_starts_at
    OR p_ends_at > p_starts_at + interval '12 hours' THEN
    RAISE EXCEPTION '수업 시작·종료 시간을 확인해 주세요. (최대 12시간)' USING ERRCODE = '22023';
  END IF;

  IF p_notes IS NOT NULL AND char_length(p_notes) > 1000 THEN
    RAISE EXCEPTION '메모는 1000자 이하로 입력해 주세요.' USING ERRCODE = '22023';
  END IF;

  IF p_participants IS NULL OR jsonb_typeof(p_participants) <> 'array' THEN
    RAISE EXCEPTION '참여 회원 목록이 올바르지 않습니다.' USING ERRCODE = '22023';
  END IF;

  v_count := jsonb_array_length(p_participants);
  IF v_count < 1 OR v_count > 30 OR (p_session_type = 'pt' AND v_count <> 1) THEN
    RAISE EXCEPTION 'PT는 회원 1명, 그룹은 1~30명을 선택해 주세요.' USING ERRCODE = '22023';
  END IF;

  -- 2. 본인의 활성 근무처인지 확인 (보관된 근무처로 신규 예약 불가)
  PERFORM 1
  FROM public.companies AS c
  WHERE c.id = p_company_id
    AND c.trainer_id = v_trainer_id
    AND c.is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION '사용할 수 없는 근무처입니다.' USING ERRCODE = '42501';
  END IF;

  -- 같은 트레이너의 동시 등록을 직렬화해 시간 중복을 방지
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_trainer_id::text, 0));

  IF EXISTS (
    SELECT 1
    FROM public.sessions AS s
    WHERE s.trainer_id = v_trainer_id
      AND s.status <> 'cancelled'
      AND s.starts_at < p_ends_at
      AND s.ends_at > p_starts_at
  ) THEN
    RAISE EXCEPTION '같은 시간에 이미 등록된 수업이 있습니다.' USING ERRCODE = '23505';
  END IF;

  v_session_date := (p_starts_at AT TIME ZONE 'Asia/Seoul')::date;

  -- 3. 회원별 근무처·이용권·잔여 횟수 검증
  FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_participants) AS x(value)
  LOOP
    IF jsonb_typeof(v_item) <> 'object'
      OR v_item->>'member_id' IS NULL
      OR v_item->>'package_id' IS NULL THEN
      RAISE EXCEPTION '회원과 이용권을 모두 선택해 주세요.' USING ERRCODE = '22023';
    END IF;

    v_member_id := (v_item->>'member_id')::uuid;
    v_package_id := (v_item->>'package_id')::uuid;

    IF v_member_id = ANY (v_seen_members) THEN
      RAISE EXCEPTION '한 수업에 같은 회원을 중복 등록할 수 없습니다.' USING ERRCODE = '23505';
    END IF;
    v_seen_members := array_append(v_seen_members, v_member_id);

    PERFORM 1
    FROM public.company_members AS cm
    JOIN public.members AS m ON m.id = cm.member_id
    WHERE cm.company_id = p_company_id
      AND cm.member_id = v_member_id
      AND cm.trainer_id = v_trainer_id
      AND m.trainer_id = v_trainer_id
      AND m.status <> 'archived';
    IF NOT FOUND THEN
      RAISE EXCEPTION '해당 근무처에 연결되지 않은 회원이 포함되어 있습니다.' USING ERRCODE = '42501';
    END IF;

    -- 각 이용권 행을 잠가 동시 예약에 의한 잔여 횟수 초과를 방지
    SELECT p.remaining_sessions INTO v_remaining
    FROM public.member_packages AS p
    WHERE p.id = v_package_id
      AND p.trainer_id = v_trainer_id
      AND p.company_id = p_company_id
      AND p.member_id = v_member_id
      AND p.package_type = p_session_type
      AND p.usage_type = 'count'
      AND p.status = 'active'
      AND p.remaining_sessions > 0
      AND (p.starts_on IS NULL OR p.starts_on <= v_session_date)
      AND (p.ends_on IS NULL OR p.ends_on >= v_session_date)
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION '사용 가능한 횟수제 이용권이 없습니다. 근무처·기간·잔여 횟수를 확인해 주세요.'
        USING ERRCODE = '22023';
    END IF;

    -- 예약 중인 수업은 차감 전이므로 남은 횟수에서 예약 건수를 제외하여 확인
    SELECT count(*) INTO v_reserved
    FROM public.session_attendances AS a
    JOIN public.sessions AS s ON s.id = a.session_id
    WHERE a.package_id = v_package_id
      AND a.attendance_status = 'scheduled'
      AND s.status = 'scheduled';

    IF v_reserved >= v_remaining THEN
      RAISE EXCEPTION '선택한 이용권의 남은 횟수가 이미 다른 수업에 예약되어 있습니다.'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- 4. 수업과 참여 회원을 하나의 트랜잭션에서 저장
  INSERT INTO public.sessions (
    trainer_id, company_id, session_type, starts_at, ends_at, notes
  ) VALUES (
    v_trainer_id, p_company_id, p_session_type, p_starts_at, p_ends_at, nullif(btrim(p_notes), '')
  ) RETURNING id INTO v_session_id;

  FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_participants) AS x(value)
  LOOP
    INSERT INTO public.session_attendances (
      trainer_id, company_id, session_id, session_type, member_id, package_id
    ) VALUES (
      v_trainer_id,
      p_company_id,
      v_session_id,
      p_session_type,
      (v_item->>'member_id')::uuid,
      (v_item->>'package_id')::uuid
    );
  END LOOP;

  RETURN v_session_id;
END;
$$;

-- 함수 호출은 인증 사용자에게만 허용; 테이블 직접 INSERT/UPDATE는 계속 차단
REVOKE ALL ON FUNCTION public.create_session_with_participants(
  uuid, text, timestamptz, timestamptz, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_session_with_participants(
  uuid, text, timestamptz, timestamptz, jsonb, text
) TO authenticated;

COMMIT;
