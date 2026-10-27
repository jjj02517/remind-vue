
-- ============================================
-- 일반 근무처 수정 및 보관 권한 추가
-- ============================================

-- 일반 근무처만 수정 가능
-- 개인 고객은 수정 및 보관할 수 없음
CREATE POLICY "companies_update_own_workplaces"
ON public.companies
FOR UPDATE
TO authenticated
USING (
  trainer_id = (SELECT auth.uid())
  AND company_type = 'workplace'
)
WITH CHECK (
  trainer_id = (SELECT auth.uid())
  AND company_type = 'workplace'
);

-- ============================================
-- 근무처 등록 정책 보완
-- ============================================

-- 일반 사용자가 기본 개인 고객을 직접 생성하지 못하도록 제한
DROP POLICY IF EXISTS "companies_insert_own"
ON public.companies;

CREATE POLICY "companies_insert_own"
ON public.companies
FOR INSERT
TO authenticated
WITH CHECK (
  trainer_id = (SELECT auth.uid())
  AND company_type = 'workplace'
);

-- ============================================
-- 근무처 수정 시간 자동 갱신
-- ============================================

CREATE OR REPLACE FUNCTION public.update_company_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- 근무처 정보가 변경될 때 수정 시간 갱신
  NEW.updated_at := now();

  RETURN NEW;
END;
$$;

-- 중복 트리거 생성 방지
DROP TRIGGER IF EXISTS companies_updated_at
ON public.companies;

CREATE TRIGGER companies_updated_at
BEFORE UPDATE ON public.companies
FOR EACH ROW
EXECUTE FUNCTION public.update_company_timestamp();
