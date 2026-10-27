
-- ============================================
-- 이용권에 근무처 정보 추가
-- ============================================

-- 이용권이 속한 근무처 ID
-- 기존 등록 RPC 호환성을 위해 우선 NULL 허용
ALTER TABLE public.member_packages
ADD COLUMN IF NOT EXISTS company_id UUID;

-- ============================================
-- 기존 테스트 데이터의 30일 미만 회원권 처리
-- ============================================

-- 과거에 등록된 30일 미만 월 회원권도
-- company_id를 변경할 수 있도록 제약조건 임시 해제
ALTER TABLE public.member_packages
DROP CONSTRAINT membership_min_30_days;

-- ============================================
-- 기존 이용권을 '개인 고객' 근무처로 연결
-- ============================================

UPDATE public.member_packages AS mp
SET company_id = c.id
FROM public.companies AS c
WHERE c.trainer_id = mp.trainer_id
  AND c.company_type = 'personal'
  AND mp.company_id IS NULL;

-- ============================================
-- 월 회원권 최소 30일 제약조건 복원
-- ============================================

-- 기존 30일 미만 테스트 데이터는 그대로 유지
-- 신규 등록 및 이후 수정에는 최소 30일 규칙 적용
ALTER TABLE public.member_packages
ADD CONSTRAINT membership_min_30_days
CHECK (
  package_type <> 'membership'
  OR (
    usage_type = 'period'
    AND starts_on IS NOT NULL
    AND ends_on IS NOT NULL
    AND ends_on >= starts_on + 29
  )
)
NOT VALID;

-- ============================================
-- 기존 이용권의 근무처 연결 확인
-- ============================================

-- 연결되지 않은 이용권이 있다면 마이그레이션 중단
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.member_packages
    WHERE company_id IS NULL
  ) THEN
    RAISE EXCEPTION
      '근무처가 연결되지 않은 기존 이용권이 있습니다.';
  END IF;
END;
$$;

-- ============================================
-- 이용권과 근무처의 소유권 검증
-- ============================================

-- 이용권은 해당 트레이너의 근무처에만 연결 가능
ALTER TABLE public.member_packages
ADD CONSTRAINT member_packages_company_owner_fk
FOREIGN KEY (trainer_id, company_id)
REFERENCES public.companies (trainer_id, id);

-- 해당 근무처에 연결된 회원의 이용권만 등록 가능
ALTER TABLE public.member_packages
ADD CONSTRAINT member_packages_company_member_fk
FOREIGN KEY (company_id, member_id)
REFERENCES public.company_members (company_id, member_id);

-- 근무처별 이용권 조회 성능 개선
CREATE INDEX IF NOT EXISTS member_packages_company_id_idx
ON public.member_packages (company_id);
