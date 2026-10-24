
-- ============================================
-- 기존 회원에게 근무처별 PT 이용권 추가
-- ============================================

-- 기존 2개 매개변수 RPC는 유지
-- 근무처 ID를 필수로 받는 3개 매개변수 버전 추가
CREATE OR REPLACE FUNCTION public.add_pt_package(
  p_member_id UUID,
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

  -- 새로 등록한 이용권 ID
  v_package_id UUID;
BEGIN
  -- ============================================
  -- 1. 로그인 및 입력값 검증
  -- ============================================

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- PT 횟수는 1 이상의 정수
  IF p_total_sessions IS NULL OR p_total_sessions < 1 THEN
    RAISE EXCEPTION 'PT 횟수는 1회 이상이어야 합니다.';
  END IF;

  -- 근무처 선택 필수
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION '근무처를 선택해 주세요.';
  END IF;

  -- ============================================
  -- 2. 회원 소유권 확인
  -- ============================================

  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE id = p_member_id
      AND trainer_id = v_trainer_id
  ) THEN
    RAISE EXCEPTION
      '회원을 찾을 수 없거나 접근 권한이 없습니다.';
  END IF;

  -- ============================================
  -- 3. 근무처 소유권 및 활성 상태 확인
  -- ============================================

  IF NOT EXISTS (
    SELECT 1
    FROM public.companies
    WHERE id = p_company_id
      AND trainer_id = v_trainer_id
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION
      '사용할 수 없는 근무처입니다.';
  END IF;

  -- ============================================
  -- 4. 회원과 근무처의 연결 관계 확인
  -- ============================================

  -- 해당 회원에게 이미 연결된 근무처만 이용권 등록 허용
  IF NOT EXISTS (
    SELECT 1
    FROM public.company_members
    WHERE trainer_id = v_trainer_id
      AND member_id = p_member_id
      AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION
      '회원과 연결되지 않은 근무처입니다. 먼저 근무처를 연결해 주세요.';
  END IF;

  -- ============================================
  -- 5. PT 이용권 등록
  -- ============================================

  INSERT INTO public.member_packages (
    trainer_id,
    member_id,
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
    v_trainer_id,
    p_member_id,
    p_company_id,
    'pt',
    'count',
    p_total_sessions,
    p_total_sessions,
    NULL,
    NULL,
    'active'
  )
  RETURNING id INTO v_package_id;

  -- 새로 등록한 이용권 UUID 반환
  RETURN v_package_id;
END;
$$;

-- ============================================
-- 실행 권한 설정
-- ============================================

REVOKE ALL ON FUNCTION
  public.add_pt_package(UUID, INTEGER, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.add_pt_package(UUID, INTEGER, UUID)
TO authenticated;
