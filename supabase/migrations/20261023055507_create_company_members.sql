
-- ============================================
-- 회원과 근무처 연결 테이블
-- ============================================

-- 회원·근무처의 트레이너 소유권을 FK로 검증하기 위한 고유 인덱스
CREATE UNIQUE INDEX IF NOT EXISTS members_trainer_id_id_unique
ON public.members (trainer_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS companies_trainer_id_id_unique
ON public.companies (trainer_id, id);

-- 한 회원을 여러 근무처에 연결할 수 있도록 구성
CREATE TABLE public.company_members (
  -- 연결 기록 고유 ID
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 연결을 관리하는 트레이너
  trainer_id UUID NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,

  -- 근무처 ID
  company_id UUID NOT NULL,

  -- 회원 ID
  member_id UUID NOT NULL,

  -- 연결 생성일
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- 같은 회원이 동일 근무처에 중복 연결되지 않도록 제한
  CONSTRAINT company_members_company_member_unique
    UNIQUE (company_id, member_id),

  -- 해당 트레이너 소유 근무처만 연결 가능
  CONSTRAINT company_members_company_owner_fk
    FOREIGN KEY (trainer_id, company_id)
    REFERENCES public.companies (trainer_id, id)
    ON DELETE CASCADE,

  -- 해당 트레이너 소유 회원만 연결 가능
  CONSTRAINT company_members_member_owner_fk
    FOREIGN KEY (trainer_id, member_id)
    REFERENCES public.members (trainer_id, id)
    ON DELETE CASCADE
);

-- 근무처별 회원 조회 최적화
CREATE INDEX company_members_company_id_idx
ON public.company_members (company_id);

-- 회원별 근무처 조회 최적화
CREATE INDEX company_members_member_id_idx
ON public.company_members (member_id);

-- ============================================
-- Row Level Security
-- ============================================

ALTER TABLE public.company_members
ENABLE ROW LEVEL SECURITY;

-- 로그인한 트레이너는 자신의 회원-근무처 연결만 조회
CREATE POLICY "company_members_select_own"
ON public.company_members
FOR SELECT
TO authenticated
USING (trainer_id = (SELECT auth.uid()));

-- 로그인한 트레이너는 자신의 회원과 근무처만 연결 가능
CREATE POLICY "company_members_insert_own"
ON public.company_members
FOR INSERT
TO authenticated
WITH CHECK (trainer_id = (SELECT auth.uid()));
