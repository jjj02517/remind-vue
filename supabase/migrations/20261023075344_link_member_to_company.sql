
-- ============================================
-- 기존 회원을 다른 근무처에 추가 연결
-- ============================================

CREATE OR REPLACE FUNCTION public.link_member_to_company(
  p_member_id UUID,
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

  -- 새로 생성한 근무처 연결 ID
  v_connection_id UUID;
BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- ============================================
  -- 1. 회원 소유권 확인
  -- ============================================

  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE id = p_member_id
      AND trainer_id = v_trainer_id
  ) THEN
    RAISE EXCEPTION '회원을 찾을 수 없거나 접근 권한이 없습니다.';
  END IF;

  -- ============================================
  -- 2. 근무처 소유권 및 활성 상태 확인
  -- ============================================

  IF NOT EXISTS (
    SELECT 1
    FROM public.companies
    WHERE id = p_company_id
      AND trainer_id = v_trainer_id
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION '사용할 수 없는 근무처입니다.';
  END IF;

  -- ============================================
  -- 3. 기존 연결 중복 검사
  -- ============================================

  IF EXISTS (
    SELECT 1
    FROM public.company_members
    WHERE member_id = p_member_id
      AND company_id = p_company_id
      AND trainer_id = v_trainer_id
  ) THEN
    RAISE EXCEPTION '이미 연결된 근무처입니다.';
  END IF;

  -- ============================================
  -- 4. 회원과 근무처 연결
  -- ============================================

  INSERT INTO public.company_members (
    trainer_id,
    company_id,
    member_id
  )
  VALUES (
    v_trainer_id,
    p_company_id,
    p_member_id
  )
  RETURNING id INTO v_connection_id;

  -- 새 연결 ID 반환
  RETURN v_connection_id;
END;
$$;

-- 로그인한 트레이너만 함수 실행 가능
REVOKE ALL ON FUNCTION
  public.link_member_to_company(UUID, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.link_member_to_company(UUID, UUID)
TO authenticated;
