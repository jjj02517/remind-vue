
-- ============================================
-- 근무처 필수 저장 및 구형 RPC 정리
-- ============================================

BEGIN;

-- ============================================
-- 1. 근무처가 없는 이용권이 남아 있는지 검사
-- ============================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.member_packages
    WHERE company_id IS NULL
  ) THEN
    RAISE EXCEPTION
      '근무처가 지정되지 않은 이용권이 있습니다. 데이터를 먼저 확인해 주세요.';
  END IF;
END;
$$;

-- ============================================
-- 2. 근무처 ID 필수 제약조건 적용
-- ============================================

ALTER TABLE public.member_packages
  ALTER COLUMN company_id SET NOT NULL;

-- ============================================
-- 3. 구형 신규 회원 등록 RPC 제거
-- ============================================

-- 회원만 등록
DROP FUNCTION IF EXISTS
  public.register_member_only(TEXT, TEXT);

-- 회원 + PT 이용권 등록
DROP FUNCTION IF EXISTS
  public.register_member_with_pt(TEXT, TEXT, INTEGER);

-- 회원 + 그룹 수업권 등록
DROP FUNCTION IF EXISTS
  public.register_member_with_group(TEXT, TEXT, INTEGER);

-- 회원 + 월 회원권 등록
DROP FUNCTION IF EXISTS
  public.register_member_with_membership(TEXT, TEXT, DATE, DATE);

-- ============================================
-- 4. 구형 기존 회원 이용권 추가 RPC 제거
-- ============================================

-- PT 이용권 추가
DROP FUNCTION IF EXISTS
  public.add_pt_package(UUID, INTEGER);

-- 그룹 수업권 추가
DROP FUNCTION IF EXISTS
  public.add_group_package(UUID, INTEGER);

-- 월 회원권 추가
DROP FUNCTION IF EXISTS
  public.add_membership_package(UUID, DATE, DATE);

COMMIT;
