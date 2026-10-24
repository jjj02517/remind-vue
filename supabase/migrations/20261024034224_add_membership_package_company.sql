-- ============================================
-- 기존 회원에게 근무처별 월 회원권 추가
-- ============================================
-- 기존 add_membership_package(UUID, DATE, DATE)는 유지하며
-- 근무처를 필수로 받는 새 오버로드를 추가한다.
CREATE OR REPLACE FUNCTION public.add_membership_package(
  p_member_id UUID,
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

  -- 신규 월 회원권 ID
  v_package_id UUID;

  -- 신규 월 회원권 상태
  v_status TEXT;
BEGIN
  -- ============================================
  -- 1. 로그인 및 입력값 검증
  -- ============================================
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  IF p_member_id IS NULL THEN
    RAISE EXCEPTION '회원 ID가 필요합니다.';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION '근무처를 선택해 주세요.';
  END IF;

  IF p_starts_on IS NULL OR p_ends_on IS NULL THEN
    RAISE EXCEPTION '이용 시작일과 종료일을 입력해 주세요.';
  END IF;

  IF p_ends_on < p_starts_on THEN
    RAISE EXCEPTION '종료일은 시작일보다 빠를 수 없습니다.';
  END IF;

  -- 시작일·종료일을 포함한 최소 30일
  IF p_ends_on < p_starts_on + 29 THEN
    RAISE EXCEPTION '월 회원권 이용 기간은 최소 30일이어야 합니다.';
  END IF;

  -- ============================================
  -- 2. 회원·근무처 소유권 및 연결 관계 확인
  -- ============================================
  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE id = p_member_id
      AND trainer_id = v_trainer_id
  ) THEN
    RAISE EXCEPTION '회원을 찾을 수 없거나 접근 권한이 없습니다.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.companies
    WHERE id = p_company_id
      AND trainer_id = v_trainer_id
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION '사용할 수 없는 근무처입니다.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.company_members
    WHERE trainer_id = v_trainer_id
      AND member_id = p_member_id
      AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION '회원과 연결되지 않은 근무처입니다. 먼저 근무처를 연결해 주세요.';
  END IF;

  -- ============================================
  -- 3. 같은 근무처에서 이용 기간 중복 검사
  -- ============================================
  -- 동일 회원·근무처의 동시 등록을 순차 처리
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_trainer_id::TEXT || ':' || p_member_id::TEXT || ':' || p_company_id::TEXT,
      0
    )
  );

  -- 다른 근무처에서 겹치는 이용권은 허용
  -- 취소된 이용권은 중복 검사에서 제외
  IF EXISTS (
    SELECT 1
    FROM public.member_packages
    WHERE trainer_id = v_trainer_id
      AND member_id = p_member_id
      AND company_id = p_company_id
      AND package_type = 'membership'
      AND usage_type = 'period'
      AND status <> 'cancelled'
      AND starts_on <= p_ends_on
      AND ends_on >= p_starts_on
  ) THEN
    RAISE EXCEPTION '해당 근무처에 이용 기간이 겹치는 월 회원권이 있습니다.';
  END IF;

  -- ============================================
  -- 4. 월 회원권 등록
  -- ============================================
  v_status := CASE
    WHEN p_ends_on < CURRENT_DATE THEN 'expired'
    ELSE 'active'
  END;

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
    'membership',
    'period',
    NULL,
    NULL,
    p_starts_on,
    p_ends_on,
    v_status
  )
  RETURNING id INTO v_package_id;

  RETURN v_package_id;
END;
$$;

-- 새 버전은 인증된 사용자에게만 실행 권한 부여
REVOKE ALL ON FUNCTION
  public.add_membership_package(UUID, DATE, DATE, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.add_membership_package(UUID, DATE, DATE, UUID)
TO authenticated;
