
-- ============================================
-- 근무처를 지정한 신규 회원 및 그룹 수업권 등록
-- ============================================

-- 기존 3개 매개변수 RPC는 유지
-- 근무처 ID를 받는 4개 매개변수 버전 추가
CREATE OR REPLACE FUNCTION public.register_member_with_group(
  p_name TEXT,
  p_phone TEXT,
  p_total_sessions INTEGER,
  p_company_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 선택된 근무처 ID
  v_company_id UUID;

  -- 새로 생성된 회원 ID
  v_member_id UUID;
BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 회원명 유효성 검사
  IF p_name IS NULL OR BTRIM(p_name) = '' THEN
    RAISE EXCEPTION '회원명을 입력해 주세요.';
  END IF;

  -- 연락처 유효성 검사
  IF p_phone IS NULL
     OR BTRIM(p_phone) !~ '^010[0-9]{8}$' THEN
    RAISE EXCEPTION '올바른 휴대폰 번호를 입력해 주세요.';
  END IF;

  -- 그룹 수업 횟수 유효성 검사
  IF p_total_sessions IS NULL OR p_total_sessions < 1 THEN
    RAISE EXCEPTION '그룹 수업 횟수는 1회 이상이어야 합니다.';
  END IF;

  -- ============================================
  -- 1. 등록할 근무처 확인
  -- ============================================

  -- 근무처 미선택 시 기본 '개인 고객' 사용
  IF p_company_id IS NULL THEN
    SELECT id
    INTO v_company_id
    FROM public.companies
    WHERE trainer_id = v_trainer_id
      AND company_type = 'personal'
      AND is_active = TRUE;
  ELSE
    -- 본인이 소유한 활성 근무처만 선택 가능
    SELECT id
    INTO v_company_id
    FROM public.companies
    WHERE id = p_company_id
      AND trainer_id = v_trainer_id
      AND is_active = TRUE;
  END IF;

  -- 다른 트레이너의 근무처 및 보관된 근무처 차단
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION
      '사용할 수 없는 근무처입니다. 근무처를 확인해 주세요.';
  END IF;

  -- ============================================
  -- 2. 신규 회원 등록
  -- ============================================

  INSERT INTO public.members (
    trainer_id,
    name,
    phone
  )
  VALUES (
    v_trainer_id,
    BTRIM(p_name),
    BTRIM(p_phone)
  )
  RETURNING id INTO v_member_id;

  -- ============================================
  -- 3. 회원과 근무처 연결
  -- ============================================

  INSERT INTO public.company_members (
    trainer_id,
    company_id,
    member_id
  )
  VALUES (
    v_trainer_id,
    v_company_id,
    v_member_id
  );

  -- ============================================
  -- 4. 그룹 수업권 등록
  -- ============================================

  INSERT INTO public.member_packages (
    member_id,
    trainer_id,
    company_id,
    package_type,
    usage_type,
    total_sessions,
    remaining_sessions,
    starts_on,
    ends_on,
    status
  )
  VALUES (
    v_member_id,
    v_trainer_id,
    v_company_id,
    'group',
    'count',
    p_total_sessions,
    p_total_sessions,
    NULL,
    NULL,
    'active'
  );

  -- 등록한 회원 UUID 반환
  RETURN v_member_id;
END;
$$;

-- 신규 RPC 실행 권한 제한
REVOKE ALL ON FUNCTION
  public.register_member_with_group(TEXT, TEXT, INTEGER, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.register_member_with_group(TEXT, TEXT, INTEGER, UUID)
TO authenticated;
