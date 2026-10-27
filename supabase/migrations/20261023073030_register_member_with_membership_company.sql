
-- ============================================
-- 근무처를 지정한 신규 회원 및 월 회원권 등록
-- ============================================

-- 기존 4개 매개변수 RPC는 유지
-- 근무처 ID를 받는 5개 매개변수 버전 추가
CREATE OR REPLACE FUNCTION public.register_member_with_membership(
  p_name TEXT,
  p_phone TEXT,
  p_starts_on DATE,
  p_ends_on DATE,
  p_company_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
SET "TimeZone" TO 'Asia/Seoul'
AS $$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 선택된 근무처 ID
  v_company_id UUID;

  -- 새로 생성된 회원 ID
  v_member_id UUID;

  -- 이용권 상태
  v_package_status TEXT;
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

  -- 이용권 시작일과 종료일 필수
  IF p_starts_on IS NULL OR p_ends_on IS NULL THEN
    RAISE EXCEPTION '이용권 시작일과 종료일을 입력해 주세요.';
  END IF;

  -- 이용권 종료일은 시작일보다 빠를 수 없음
  IF p_ends_on < p_starts_on THEN
    RAISE EXCEPTION '이용권 종료일은 시작일보다 빠를 수 없습니다.';
  END IF;

  -- 월 회원권은 최소 30일 이상
  -- 시작일과 종료일을 모두 포함하여 계산
  IF p_ends_on < p_starts_on + 29 THEN
    RAISE EXCEPTION '월 회원권 이용 기간은 최소 30일이어야 합니다.';
  END IF;

  -- 이미 종료된 이용권은 만료 상태로 등록
  -- 함수 시간대 설정에 따라 한국 날짜 기준
  IF p_ends_on < CURRENT_DATE THEN
    v_package_status := 'expired';
  ELSE
    v_package_status := 'active';
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
  -- 4. 월 회원권 등록
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
    'membership',
    'period',
    NULL,
    NULL,
    p_starts_on,
    p_ends_on,
    v_package_status
  );

  -- 등록한 회원 UUID 반환
  RETURN v_member_id;
END;
$$;

-- 신규 RPC 실행 권한 제한
REVOKE ALL ON FUNCTION
  public.register_member_with_membership(
    TEXT, TEXT, DATE, DATE, UUID
  )
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.register_member_with_membership(
    TEXT, TEXT, DATE, DATE, UUID
  )
TO authenticated;
