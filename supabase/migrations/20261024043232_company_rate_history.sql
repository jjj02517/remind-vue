-- ============================================
-- 근무처별 PT/그룹 정산 단가 및 변경 이력
-- 파일명은 npx supabase migration new company_rate_history 로 생성된 이름으로 변경
-- ============================================

BEGIN;

-- 금액은 원(KRW) 단위의 정수로 저장한다.
-- 기록은 수정/삭제하지 않고 변경 시 새 행을 추가한다.
-- 같은 적용일에 여러 변경 이력이 있으면 id가 큰 최신 행을 적용한다.
CREATE TABLE public.company_rate_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  effective_from date NOT NULL,
  pt_rate_per_session integer,
  group_rate_per_attendee integer,
  currency_code text NOT NULL DEFAULT 'KRW',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  CONSTRAINT company_rate_history_pt_nonnegative
    CHECK (pt_rate_per_session IS NULL OR pt_rate_per_session >= 0),
  CONSTRAINT company_rate_history_group_nonnegative
    CHECK (group_rate_per_attendee IS NULL OR group_rate_per_attendee >= 0),
  CONSTRAINT company_rate_history_has_at_least_one_rate
    CHECK (pt_rate_per_session IS NOT NULL OR group_rate_per_attendee IS NOT NULL),
  CONSTRAINT company_rate_history_currency_krw
    CHECK (currency_code = 'KRW')
);

-- 날짜별 적용 단가를 조회하기 위한 인덱스
CREATE INDEX company_rate_history_lookup_idx
  ON public.company_rate_history (company_id, effective_from DESC, id DESC);

-- 로그인한 트레이너는 자신이 소유한 근무처의 단가 이력만 조회할 수 있다.
ALTER TABLE public.company_rate_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_rate_history_select_own
ON public.company_rate_history
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.companies AS company
    WHERE company.id = company_rate_history.company_id
      AND company.trainer_id = (SELECT auth.uid())
  )
);

-- 프론트엔드에서 직접 INSERT/UPDATE/DELETE하지 않도록 제한한다.
-- 신규 기록은 검증 함수로만 생성할 수 있다.
REVOKE ALL ON public.company_rate_history FROM anon, authenticated;
GRANT SELECT ON public.company_rate_history TO authenticated;

CREATE FUNCTION public.add_company_rate_version(
  p_company_id uuid,
  p_effective_from date,
  p_pt_rate_per_session integer,
  p_group_rate_per_attendee integer
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trainer_id uuid := auth.uid();
  v_history_id bigint;
BEGIN
  -- 로그인 및 근무처 소유권/상태 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.' USING ERRCODE = '42501';
  END IF;

  IF p_company_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.companies AS company
    WHERE company.id = p_company_id
      AND company.trainer_id = v_trainer_id
      AND company.is_active = true
  ) THEN
    RAISE EXCEPTION '설정 가능한 근무처를 찾을 수 없습니다.' USING ERRCODE = '42501';
  END IF;

  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION '단가 적용 시작일을 입력해 주세요.' USING ERRCODE = '22023';
  END IF;

  IF p_pt_rate_per_session IS NULL AND p_group_rate_per_attendee IS NULL THEN
    RAISE EXCEPTION 'PT 또는 그룹 단가를 하나 이상 입력해 주세요.' USING ERRCODE = '22023';
  END IF;

  IF (p_pt_rate_per_session IS NOT NULL AND p_pt_rate_per_session < 0)
    OR (p_group_rate_per_attendee IS NOT NULL AND p_group_rate_per_attendee < 0) THEN
    RAISE EXCEPTION '단가는 0원 이상이어야 합니다.' USING ERRCODE = '22023';
  END IF;

  -- 기존 버전을 덮어쓰지 않고 새 이력 추가 (같은 날 재설정 가능)
  INSERT INTO public.company_rate_history (
    company_id,
    effective_from,
    pt_rate_per_session,
    group_rate_per_attendee,
    created_by
  ) VALUES (
    p_company_id,
    p_effective_from,
    p_pt_rate_per_session,
    p_group_rate_per_attendee,
    v_trainer_id
  )
  RETURNING id INTO v_history_id;

  RETURN v_history_id;
END;
$$;

-- 함수 기본 PUBLIC 실행 권한 제거, 인증된 사용자에게만 허용
REVOKE ALL ON FUNCTION public.add_company_rate_version(uuid, date, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_company_rate_version(uuid, date, integer, integer)
  TO authenticated;

COMMENT ON TABLE public.company_rate_history IS
  '근무처별 정산 단가 적용일 및 변경 이력. 과거 확정 수업의 정산에는 별도의 단가/금액 스냅샷을 사용해야 한다.';

COMMIT;
