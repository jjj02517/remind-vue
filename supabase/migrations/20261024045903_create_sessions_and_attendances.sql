-- Remind PT | 수업 관리 DB 1단계
-- 수업 일정과 참여 회원 구조만 생성합니다.
-- 출석 처리, 이용권 차감, 정산 금액 계산은 후속 RPC 마이그레이션에서 구현합니다.

BEGIN;

-- ============================================
-- 1. 수업 일정
-- ============================================
CREATE TABLE public.sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL DEFAULT auth.uid()
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  company_id uuid NOT NULL,
  session_type text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'scheduled',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT sessions_type_check
    CHECK (session_type IN ('pt', 'group')),
  CONSTRAINT sessions_status_check
    CHECK (status IN ('scheduled', 'completed', 'cancelled')),
  CONSTRAINT sessions_time_order_check
    CHECK (ends_at > starts_at),
  -- 로그인한 트레이너의 근무처에만 수업 등록 가능
  CONSTRAINT sessions_company_owner_fk
    FOREIGN KEY (trainer_id, company_id)
    REFERENCES public.companies (trainer_id, id)
    ON DELETE RESTRICT,
  -- 참여자 테이블에서 수업의 트레이너·근무처·종류를 함께 검증
  CONSTRAINT sessions_identity_with_type_unique
    UNIQUE (trainer_id, company_id, id, session_type)
);

-- ============================================
-- 2. 참여 회원 + 출석 상태
-- ============================================
-- package_id는 추후 수업 등록 RPC에서 선택/검증합니다.
-- 멤버십으로 그룹 수업을 이용하는 정책은 별도로 확정합니다.
-- 기존 이용권의 (id, 회사, 회원) 조합을 FK로 검증하기 위한 키입니다.
ALTER TABLE public.member_packages
  ADD CONSTRAINT member_packages_session_reference_unique
  UNIQUE (id, company_id, member_id);

CREATE TABLE public.session_attendances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL DEFAULT auth.uid(),
  company_id uuid NOT NULL,
  session_id uuid NOT NULL,
  session_type text NOT NULL,
  member_id uuid NOT NULL,
  package_id uuid,
  attendance_status text NOT NULL DEFAULT 'scheduled',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT session_attendances_type_check
    CHECK (session_type IN ('pt', 'group')),
  CONSTRAINT session_attendances_status_check
    CHECK (attendance_status IN (
      'scheduled', 'attended', 'no_show', 'same_day_cancelled', 'cancelled'
    )),
  -- 한 수업에 같은 회원을 중복 연결하지 않음
  CONSTRAINT session_attendances_session_member_unique
    UNIQUE (session_id, member_id),
  -- 수업과 참여 기록의 트레이너, 근무처, 수업 종류 일치
  CONSTRAINT session_attendances_session_fk
    FOREIGN KEY (trainer_id, company_id, session_id, session_type)
    REFERENCES public.sessions (trainer_id, company_id, id, session_type)
    ON DELETE RESTRICT,
  -- 해당 근무처에 실제로 소속된 회원만 연결
  CONSTRAINT session_attendances_company_member_fk
    FOREIGN KEY (company_id, member_id)
    REFERENCES public.company_members (company_id, member_id)
    ON DELETE RESTRICT,
  -- 이용권을 선택했다면 그 회원의 그 근무처 이용권인지 검증
  CONSTRAINT session_attendances_package_fk
    FOREIGN KEY (package_id, company_id, member_id)
    REFERENCES public.member_packages (id, company_id, member_id)
    ON DELETE RESTRICT
);

-- PT 수업은 참여 회원이 최대 1명, 그룹 수업은 여러 명 가능
CREATE UNIQUE INDEX session_attendances_pt_one_member_idx
  ON public.session_attendances (session_id)
  WHERE session_type = 'pt';

-- ============================================
-- 3. 달력과 참여 회원 조회 인덱스
-- ============================================
CREATE INDEX sessions_trainer_starts_at_idx
  ON public.sessions (trainer_id, starts_at);

CREATE INDEX sessions_trainer_company_starts_at_idx
  ON public.sessions (trainer_id, company_id, starts_at);

CREATE INDEX session_attendances_session_idx
  ON public.session_attendances (session_id);

CREATE INDEX session_attendances_member_idx
  ON public.session_attendances (member_id);

-- ============================================
-- 4. 읽기 전용 RLS (등록/출석 변경 RPC는 다음 단계)
-- ============================================
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_attendances ENABLE ROW LEVEL SECURITY;

CREATE POLICY sessions_trainer_select
  ON public.sessions
  FOR SELECT TO authenticated
  USING (trainer_id = (SELECT auth.uid()));

CREATE POLICY session_attendances_trainer_select
  ON public.session_attendances
  FOR SELECT TO authenticated
  USING (trainer_id = (SELECT auth.uid()));

-- 초기 버전에서는 앱에서 테이블 직접 쓰기를 허용하지 않습니다.
-- 향후 SECURITY DEFINER RPC에서 소유권/잔여 횟수를 함께 검사합니다.
REVOKE ALL ON public.sessions, public.session_attendances
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.sessions, public.session_attendances TO authenticated;

COMMENT ON TABLE public.sessions IS
  '트레이너의 근무처별 PT/그룹 수업 일정';
COMMENT ON TABLE public.session_attendances IS
  '수업별 참여 회원 및 출석 상태. 이용권 차감과 정산은 후속 RPC에서 처리';

COMMIT;
