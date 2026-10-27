-- ============================================
-- 근무처 등록과 최초 정산 단가를 원자적으로 저장
-- 이미 적용된 company_rate_history 마이그레이션 뒤에 실행
-- ============================================
BEGIN;

CREATE FUNCTION public.create_company_with_rates(
  p_name text,
  p_effective_from date,
  p_pt_rate_per_session integer,
  p_group_rate_per_attendee integer
)
RETURNS public.companies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();
  v_name text := btrim(p_name);
  v_company public.companies%ROWTYPE;
BEGIN
  -- 로그인 확인: 호출자가 아닌 다른 트레이너 소유로 생성할 수 없음
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.' USING ERRCODE = '42501';
  END IF;

  -- 근무처 이름 검증
  IF v_name IS NULL OR v_name = '' OR char_length(v_name) > 100 THEN
    RAISE EXCEPTION '근무처 이름을 1~100자로 입력해 주세요.' USING ERRCODE = '22023';
  END IF;

  -- 금액 검증
  IF (p_pt_rate_per_session IS NOT NULL AND p_pt_rate_per_session < 0)
    OR (p_group_rate_per_attendee IS NOT NULL AND p_group_rate_per_attendee < 0) THEN
    RAISE EXCEPTION '단가는 0원 이상이어야 합니다.' USING ERRCODE = '22023';
  END IF;

  -- 최초 단가를 입력했다면 적용일 필요
  IF (p_pt_rate_per_session IS NOT NULL OR p_group_rate_per_attendee IS NOT NULL)
    AND p_effective_from IS NULL THEN
    RAISE EXCEPTION '단가 적용 시작일을 입력해 주세요.' USING ERRCODE = '22023';
  END IF;

  -- 신규 일반 근무처 등록
  INSERT INTO public.companies (trainer_id, name, company_type)
  VALUES (v_trainer_id, v_name, 'workplace')
  RETURNING * INTO v_company;

  -- 두 단가 중 하나라도 입력했으면 최초 이력 추가
  IF p_pt_rate_per_session IS NOT NULL OR p_group_rate_per_attendee IS NOT NULL THEN
    INSERT INTO public.company_rate_history (
      company_id,
      effective_from,
      pt_rate_per_session,
      group_rate_per_attendee,
      created_by
    ) VALUES (
      v_company.id,
      p_effective_from,
      p_pt_rate_per_session,
      p_group_rate_per_attendee,
      v_trainer_id
    );
  END IF;

  -- INSERT 실패 시 회사/단가 이력이 함께 롤백됨
  RETURN v_company;
END;
$$;

REVOKE ALL ON FUNCTION public.create_company_with_rates(text, date, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_company_with_rates(text, date, integer, integer)
  TO authenticated;

COMMIT;
