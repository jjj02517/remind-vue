SET local check_function_bodies = off;

CREATE TABLE "public"."companies" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "trainer_id"   uuid                     NOT NULL,
  "name"         text                     NOT NULL,
  "company_type" text                     NOT NULL DEFAULT 'workplace'::text,
  "is_active"    boolean                  NOT NULL DEFAULT true,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "companies_company_type_check" CHECK ((company_type = ANY (ARRAY['personal'::text, 'workplace'::text]))),
  CONSTRAINT "companies_name_not_empty" CHECK ((length(btrim(name)) > 0)),
  CONSTRAINT "companies_personal_name" CHECK (((company_type <> 'personal'::text) OR (name = '개인 고객'::text))),
  CONSTRAINT "companies_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."companies"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."member_packages" (
  "id"                 uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "member_id"          uuid                     NOT NULL,
  "package_type"       text                     NOT NULL DEFAULT 'pt'::text,
  "usage_type"         text                     NOT NULL DEFAULT 'count'::text,
  "total_sessions"     integer,
  "remaining_sessions" integer,
  "starts_on"          date,
  "ends_on"            date,
  "status"             text                     NOT NULL DEFAULT 'active'::text,
  "created_at"         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "member_packages_package_type_check" CHECK ((package_type = ANY (ARRAY['pt'::text, 'group'::text, 'membership'::text]))),
  CONSTRAINT "member_packages_pkey" PRIMARY KEY (id),
  CONSTRAINT "member_packages_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'expired'::text, 'cancelled'::text]))),
  CONSTRAINT "member_packages_usage_type_check" CHECK ((usage_type = ANY (ARRAY['count'::text, 'period'::text]))),
  CONSTRAINT "valid_package_usage"
    CHECK
    ((((usage_type = 'count'::text) AND (total_sessions > 0) AND (remaining_sessions >= 0) AND (remaining_sessions <= total_sessions)) OR ((usage_type = 'period'::text) AND
    (total_sessions IS NULL) AND (remaining_sessions IS NULL) AND (starts_on IS NOT NULL) AND (ends_on IS NOT NULL) AND (ends_on >= starts_on)))),
  "trainer_id"         uuid                     NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."member_packages"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."members" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"       text                     NOT NULL,
  "phone"      text                     NOT NULL,
  "status"     text                     NOT NULL DEFAULT 'active'::text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "members_name_check" CHECK ((length(TRIM(BOTH FROM name)) > 0)),
  CONSTRAINT "members_phone_check" CHECK ((phone ~ '^010[0-9]{8}$'::text)),
  CONSTRAINT "members_pkey" PRIMARY KEY (id),
  CONSTRAINT "members_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text]))),
  "trainer_id" uuid                     NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."package_pauses" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "package_id"   uuid                     NOT NULL,
  "starts_on"    date                     NOT NULL,
  "ends_on"      date                     NOT NULL,
  "resumed_on"   date,
  "reason"       text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "cancelled_at" timestamp with time zone,
  CONSTRAINT "package_pauses_pkey" PRIMARY KEY (id),
  CONSTRAINT "valid_pause_period" CHECK ((ends_on >= starts_on)),
  CONSTRAINT "valid_resume_date" CHECK (((resumed_on IS NULL) OR ((resumed_on >= starts_on) AND (resumed_on <= ends_on)))),
  "trainer_id"   uuid                     NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."package_pauses"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."package_pauses" FROM "anon";

CREATE OR REPLACE FUNCTION public.add_group_package (
  p_member_id      uuid,
  p_total_sessions integer
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 새로 생성된 이용권 ID
  v_package_id UUID;
BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 회원 ID 필수
  IF p_member_id IS NULL THEN
    RAISE EXCEPTION '회원 ID가 필요합니다.';
  END IF;

  -- 그룹 수업 횟수 유효성 검사
  IF p_total_sessions IS NULL OR p_total_sessions < 1 THEN
    RAISE EXCEPTION '그룹 수업 횟수는 1회 이상이어야 합니다.';
  END IF;

  -- 본인이 관리하는 회원인지 확인
  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE id = p_member_id
      AND trainer_id = v_trainer_id
  ) THEN
    RAISE EXCEPTION '회원을 찾을 수 없거나 이용 권한이 없습니다.';
  END IF;

  -- 그룹 횟수제 이용권 추가
  INSERT INTO public.member_packages (
    member_id,
    trainer_id,
    package_type,
    usage_type,
    total_sessions,
    remaining_sessions,
    starts_on,
    ends_on,
    status
  )
  VALUES (
    p_member_id,
    v_trainer_id,
    'group',
    'count',
    p_total_sessions,
    p_total_sessions,
    NULL,
    NULL,
    'active'
  )
  RETURNING id INTO v_package_id;

  -- 생성된 이용권 UUID 반환
  RETURN v_package_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."add_group_package"(uuid, integer) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.add_membership_package (
  p_member_id uuid,
  p_starts_on date,
  p_ends_on   date
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  v_member_id UUID;
  v_package_id UUID;
  v_existing_starts_on DATE;
  v_existing_ends_on DATE;
BEGIN
  -- 로그인 확인
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 이용 기간 검사
  IF p_starts_on IS NULL OR p_ends_on IS NULL THEN
    RAISE EXCEPTION '이용 시작일과 종료일을 입력해 주세요.';
  END IF;

  IF p_ends_on < p_starts_on THEN
    RAISE EXCEPTION '종료일은 시작일보다 빠를 수 없습니다.';
  END IF;

  -- 본인 회원인지 확인하고 해당 회원 행 잠금
  -- 동시에 월 회원권 등록 요청이 들어오는 경우를 방지
  SELECT m.id
  INTO v_member_id
  FROM public.members AS m
  WHERE m.id = p_member_id
    AND m.trainer_id = auth.uid()
    AND m.status <> 'archived'
  FOR UPDATE;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION '이용권을 추가할 수 없는 회원입니다.';
  END IF;

  -- 기존 월 회원권과 이용 기간이 겹치는지 검사
  SELECT mp.starts_on, mp.ends_on
  INTO v_existing_starts_on, v_existing_ends_on
  FROM public.member_packages AS mp
  WHERE mp.member_id = p_member_id
    AND mp.trainer_id = auth.uid()
    AND mp.package_type = 'membership'
    AND mp.usage_type = 'period'

    -- 취소된 회원권은 중복 검사에서 제외
    AND mp.status <> 'cancelled'

    -- 기간이 서로 겹치는 조건 (시작일과 종료일 포함)
    AND mp.starts_on <= p_ends_on
    AND mp.ends_on >= p_starts_on
  LIMIT 1;

  -- 중복 기간이 존재하면 등록 차단
  IF FOUND THEN
    RAISE EXCEPTION
      '기존 월 회원권(% ~ %)과 이용 기간이 겹칩니다.',
      v_existing_starts_on,
      v_existing_ends_on;
  END IF;

  -- 중복되지 않는 월 회원권 추가
  INSERT INTO public.member_packages (
    member_id,
    trainer_id,
    package_type,
    usage_type,
    total_sessions,
    remaining_sessions,
    starts_on,
    ends_on,
    status
  )
  VALUES (
    p_member_id,
    auth.uid(),
    'membership',
    'period',
    NULL,
    NULL,
    p_starts_on,
    p_ends_on,
    CASE
      WHEN p_ends_on < CURRENT_DATE THEN 'expired'
      ELSE 'active'
    END
  )
  RETURNING id INTO v_package_id;

  RETURN v_package_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."add_membership_package"(uuid, date, date) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.add_pt_package (
  p_member_id      uuid,
  p_total_sessions integer
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  v_package_id UUID;
BEGIN
  -- 로그인한 트레이너인지 확인
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- PT 횟수 유효성 검사
  IF p_total_sessions IS NULL OR p_total_sessions < 1 THEN
    RAISE EXCEPTION 'PT 횟수는 1 이상이어야 합니다.';
  END IF;

  -- 본인이 관리하는 회원인지 확인
  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE id = p_member_id
      AND trainer_id = (SELECT auth.uid())
  ) THEN
    RAISE EXCEPTION '등록할 회원을 찾을 수 없거나 접근 권한이 없습니다.';
  END IF;

  -- 신규 PT 이용권 등록
  INSERT INTO public.member_packages (
    member_id,
    trainer_id,
    package_type,
    usage_type,
    total_sessions,
    remaining_sessions,
    status
  )
  VALUES (
    p_member_id,
    (SELECT auth.uid()),
    'pt',
    'count',
    p_total_sessions,
    p_total_sessions,
    'active'
  )
  RETURNING id INTO v_package_id;

  -- 새로 생성한 이용권 UUID 반환
  RETURN v_package_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."add_pt_package"(uuid, integer) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.cancel_member_package_pause (
  p_pause_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "TimeZone" TO 'Asia/Seoul'
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 오늘 날짜 (DB 세션 타임존 기준)
  v_today DATE := CURRENT_DATE;

  -- 일시정지 대상 이용권 ID
  v_package_id UUID;

  -- 본인 이용권
  v_package public.member_packages%ROWTYPE;

  -- 취소할 일시정지 이력
  v_pause public.package_pauses%ROWTYPE;

  -- 원복할 일시정지 일수
  v_pause_days INTEGER;
BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 취소 대상 일시정지 이력 찾기
  SELECT package_id
  INTO v_package_id
  FROM public.package_pauses
  WHERE id = p_pause_id
    AND trainer_id = v_trainer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '일시정지 예약을 찾을 수 없습니다.';
  END IF;

  -- 본인 이용권인지 확인하고 행 잠금
  -- 동일한 이용권에 대한 동시 변경을 방지
  SELECT *
  INTO v_package
  FROM public.member_packages
  WHERE id = v_package_id
    AND trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '이용권에 접근할 권한이 없습니다.';
  END IF;

  -- 잠금 이후 최신 예약 정보 다시 조회
  SELECT *
  INTO v_pause
  FROM public.package_pauses
  WHERE id = p_pause_id
    AND package_id = v_package.id
    AND trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '일시정지 예약을 찾을 수 없습니다.';
  END IF;

  -- 이미 취소된 예약은 다시 취소할 수 없음
  IF v_pause.cancelled_at IS NOT NULL THEN
    RAISE EXCEPTION '이미 취소된 일시정지 예약입니다.';
  END IF;

  -- 조기 복귀 처리된 이력은 예약 취소 불가
  IF v_pause.resumed_on IS NOT NULL THEN
    RAISE EXCEPTION '이미 복귀 처리된 일시정지입니다.';
  END IF;

  -- 시작 전 예약만 취소 가능
  IF v_pause.starts_on <= v_today THEN
    RAISE EXCEPTION '이미 시작한 일시정지는 예약 취소할 수 없습니다.';
  END IF;

  -- 예약 당시 연장한 일수 계산
  v_pause_days := v_pause.ends_on - v_pause.starts_on + 1;

  -- 만료일이 있는 이용권은 연장한 일수만큼 원복
  IF v_package.ends_on IS NOT NULL THEN
    UPDATE public.member_packages
    SET ends_on = ends_on - v_pause_days
    WHERE id = v_package.id
      AND trainer_id = v_trainer_id;
  END IF;

  -- 일시정지 기록을 삭제하지 않고 취소 시각 저장
  UPDATE public.package_pauses
  SET cancelled_at = now()
  WHERE id = v_pause.id
    AND trainer_id = v_trainer_id;

  -- 취소한 일시정지 ID 반환
  RETURN v_pause.id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."cancel_member_package_pause"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.check_member_name_duplicate (
  p_name              text,
  p_exclude_member_id uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
BEGIN
  -- 로그인하지 않은 경우
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 빈 이름은 중복 검사하지 않음
  IF p_name IS NULL OR length(btrim(p_name)) = 0 THEN
    RETURN FALSE;
  END IF;

  -- 같은 트레이너의 회원명 중복 여부 확인
  RETURN EXISTS (
    SELECT 1
    FROM public.members
    WHERE trainer_id = (SELECT auth.uid())

      -- 회원 수정 시 자기 자신은 제외
      AND (
        p_exclude_member_id IS NULL
        OR id <> p_exclude_member_id
      )

      -- 공백과 영문 대소문자를 무시하고 비교
      AND lower(
        regexp_replace(name, '[[:space:]]+', '', 'g')
      ) = lower(
        regexp_replace(p_name, '[[:space:]]+', '', 'g')
      )
  );
END;
$function$;

REVOKE ALL ON FUNCTION "public"."check_member_name_duplicate"(text, uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.create_default_company_for_trainer()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
BEGIN
  -- 새 트레이너 계정에 '개인 고객' 근무처 생성
  INSERT INTO public.companies (
    trainer_id,
    name,
    company_type
  )
  VALUES (
    NEW.id,
    '개인 고객',
    'personal'
  )
  -- 이미 기본 근무처가 있으면 중복 생성하지 않음
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."create_default_company_for_trainer"() FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.pause_member_package (
  p_package_id uuid,
  p_starts_on  date,
  p_ends_on    date,
  p_reason     text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "TimeZone" TO 'Asia/Seoul'
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 오늘 날짜 (DB 세션 타임존 기준)
  v_today DATE := CURRENT_DATE;

  -- 일시정지할 이용권
  v_package public.member_packages%ROWTYPE;

  -- 일시정지 일수
  v_pause_days INTEGER;

  -- 생성된 일시정지 이력 ID
  v_pause_id UUID;
BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 시작일과 종료일 입력 확인
  IF p_starts_on IS NULL OR p_ends_on IS NULL THEN
    RAISE EXCEPTION '일시정지 시작일과 종료일을 입력해 주세요.';
  END IF;

  -- 오늘 또는 미래 날짜만 등록 가능
  IF p_starts_on < v_today THEN
    RAISE EXCEPTION '지난 날짜로 일시정지를 등록할 수 없습니다.';
  END IF;

  -- 날짜 순서 확인
  IF p_ends_on < p_starts_on THEN
    RAISE EXCEPTION '종료일은 시작일보다 빠를 수 없습니다.';
  END IF;

  -- 본인 트레이너의 이용권만 조회하고 잠금
  SELECT *
  INTO v_package
  FROM public.member_packages
  WHERE id = p_package_id
    AND trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '이용권을 찾을 수 없거나 접근 권한이 없습니다.';
  END IF;

  -- 이용 중인 이용권만 일시정지 가능
  IF v_package.status <> 'active' THEN
    RAISE EXCEPTION '이용 중인 이용권만 일시정지할 수 있습니다.';
  END IF;

  -- 기간제 이용권은 개시일 이후부터 정지 가능
  IF v_package.usage_type = 'period'
     AND v_package.starts_on > p_starts_on THEN
    RAISE EXCEPTION '이용권 개시일 이후부터 일시정지할 수 있습니다.';
  END IF;

  -- 만료일 이후에 시작하는 일시정지는 등록 불가
  IF v_package.ends_on IS NOT NULL
     AND v_package.ends_on < p_starts_on THEN
    RAISE EXCEPTION '이용권 만료일 이후에는 일시정지할 수 없습니다.';
  END IF;

  -- 잔여 횟수가 없는 횟수제 이용권은 정지 불가
  IF v_package.usage_type = 'count'
     AND COALESCE(v_package.remaining_sessions, 0) <= 0 THEN
    RAISE EXCEPTION '잔여 횟수가 없는 이용권입니다.';
  END IF;

  -- 취소되지 않은 일시정지 이력만 중복 검사
  IF EXISTS (
    SELECT 1
    FROM public.package_pauses AS pp
    WHERE pp.package_id = p_package_id
      AND pp.cancelled_at IS NULL
      AND pp.starts_on <= p_ends_on
      AND COALESCE(pp.resumed_on - 1, pp.ends_on) >= p_starts_on
  ) THEN
    RAISE EXCEPTION '이미 겹치는 일시정지 기간이 있습니다.';
  END IF;

  -- 시작일과 종료일을 모두 포함해 일시정지 일수 계산
  v_pause_days := p_ends_on - p_starts_on + 1;

  -- 일시정지 이력 등록
  INSERT INTO public.package_pauses (
    package_id,
    trainer_id,
    starts_on,
    ends_on,
    reason
  )
  VALUES (
    p_package_id,
    v_trainer_id,
    p_starts_on,
    p_ends_on,
    NULLIF(BTRIM(p_reason), '')
  )
  RETURNING id INTO v_pause_id;

  -- 만료일이 있는 이용권만 일시정지 일수만큼 연장
  IF v_package.ends_on IS NOT NULL THEN
    UPDATE public.member_packages
    SET ends_on = ends_on + v_pause_days
    WHERE id = p_package_id
      AND trainer_id = v_trainer_id;
  END IF;

  RETURN v_pause_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."pause_member_package"(uuid, date, date, text) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.register_member_only (
  p_name  text,
  p_phone text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 새로 생성된 회원 ID
  v_member_id UUID;
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

  -- 회원 기본 정보 등록
  -- 기존 members 테이블의 RLS 정책 적용
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

  -- 생성된 회원 UUID 반환
  RETURN v_member_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."register_member_only"(text, text) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.register_member_with_group (
  p_name           text,
  p_phone          text,
  p_total_sessions integer
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 새로 생성된 회원 ID
  v_member_id UUID;
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

  -- 그룹 수업 횟수 유효성 검사
  IF p_total_sessions IS NULL OR p_total_sessions < 1 THEN
    RAISE EXCEPTION '그룹 수업 횟수는 1회 이상이어야 합니다.';
  END IF;

  -- 1. 신규 회원 등록
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

  -- 2. 신규 회원의 그룹 횟수제 이용권 등록
  INSERT INTO public.member_packages (
    member_id,
    trainer_id,
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
    'group',
    'count',
    p_total_sessions,
    p_total_sessions,
    NULL,
    NULL,
    'active'
  );

  -- 생성된 회원 UUID 반환
  RETURN v_member_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."register_member_with_group"(text, text, integer) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.register_member_with_membership (
  p_name      text,
  p_phone     text,
  p_starts_on date,
  p_ends_on   date
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

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

  -- 이용권 기간 유효성 검사
  IF p_ends_on < p_starts_on THEN
    RAISE EXCEPTION '이용권 종료일은 시작일보다 빠를 수 없습니다.';
  END IF;

  -- 이미 종료된 이용권은 만료 상태로 등록
  IF p_ends_on < CURRENT_DATE THEN
    v_package_status := 'expired';
  ELSE
    v_package_status := 'active';
  END IF;

  -- 1. 신규 회원 등록
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

  -- 2. 신규 회원의 기간제 회원권 등록
  INSERT INTO public.member_packages (
    member_id,
    trainer_id,
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
    'membership',
    'period',
    NULL,
    NULL,
    p_starts_on,
    p_ends_on,
    v_package_status
  );

  -- 생성된 회원 UUID 반환
  RETURN v_member_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."register_member_with_membership"(text, text, date, date) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.register_member_with_pt (
  p_name           text,
  p_phone          text,
  p_total_sessions integer
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
DECLARE
  v_member_id UUID;
BEGIN
  -- 로그인한 트레이너인지 확인
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 회원명 유효성 검사
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION '회원명을 입력해 주세요.';
  END IF;

  -- 연락처 유효성 검사
  IF p_phone IS NULL OR p_phone !~ '^010[0-9]{8}$' THEN
    RAISE EXCEPTION '올바른 연락처를 입력해 주세요.';
  END IF;

  -- PT 횟수 유효성 검사
  IF p_total_sessions IS NULL OR p_total_sessions < 1 THEN
    RAISE EXCEPTION 'PT 횟수는 1 이상이어야 합니다.';
  END IF;

  -- 회원 기본 정보 등록
  INSERT INTO public.members (name, phone)
  VALUES (trim(p_name), p_phone)
  RETURNING id INTO v_member_id;

  -- PT 이용권 등록
  INSERT INTO public.member_packages (
    member_id,
    package_type,
    usage_type,
    total_sessions,
    remaining_sessions
  )
  VALUES (
    v_member_id,
    'pt',
    'count',
    p_total_sessions,
    p_total_sessions
  );

  -- 등록한 회원 UUID 반환
  RETURN v_member_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."register_member_with_pt"(text, text, integer) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.resume_member_package_pause (
  p_pause_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "TimeZone" TO 'Asia/Seoul'
  AS $function$
DECLARE
  -- 로그인한 트레이너 ID
  v_trainer_id UUID := auth.uid();

  -- 오늘 날짜 (DB 세션 타임존 기준)
  v_today DATE := CURRENT_DATE;

  -- 일시정지 대상 이용권 ID
  v_package_id UUID;

  -- 복귀할 이용권
  v_package public.member_packages%ROWTYPE;

  -- 일시정지 이력
  v_pause public.package_pauses%ROWTYPE;

  -- 사용하지 않은 일시정지 일수
  v_unused_days INTEGER;
BEGIN
  -- 로그인 여부 확인
  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- 복귀할 일시정지 기록의 이용권 ID 조회
  SELECT package_id
  INTO v_package_id
  FROM public.package_pauses
  WHERE id = p_pause_id
    AND trainer_id = v_trainer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '일시정지 기록을 찾을 수 없습니다.';
  END IF;

  -- 본인 이용권인지 확인하고 행 잠금
  SELECT *
  INTO v_package
  FROM public.member_packages
  WHERE id = v_package_id
    AND trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '이용권에 접근할 권한이 없습니다.';
  END IF;

  -- 잠금 이후 일시정지 이력 다시 조회
  SELECT *
  INTO v_pause
  FROM public.package_pauses
  WHERE id = p_pause_id
    AND package_id = v_package.id
    AND trainer_id = v_trainer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '일시정지 기록을 찾을 수 없습니다.';
  END IF;

  -- 취소된 예약은 복귀 처리할 수 없음
  IF v_pause.cancelled_at IS NOT NULL THEN
    RAISE EXCEPTION '취소된 일시정지 예약입니다.';
  END IF;

  -- 이미 복귀 처리한 경우 중복 실행 차단
  IF v_pause.resumed_on IS NOT NULL THEN
    RAISE EXCEPTION '이미 조기 복귀 처리된 일시정지입니다.';
  END IF;

  -- 일시정지가 시작되지 않았다면 복귀 불가
  IF v_today < v_pause.starts_on THEN
    RAISE EXCEPTION '시작 전 예약은 조기 복귀할 수 없습니다. 예약 취소를 이용해 주세요.';
  END IF;

  -- 예정된 정지 기간이 이미 종료된 경우
  IF v_today > v_pause.ends_on THEN
    RAISE EXCEPTION '이미 종료된 일시정지입니다.';
  END IF;

  -- 복귀일부터 예정 종료일까지의 미사용 정지 일수
  v_unused_days := v_pause.ends_on - v_today + 1;

  -- 만료일이 있는 이용권은 미사용 일수만큼 차감
  IF v_package.ends_on IS NOT NULL THEN
    UPDATE public.member_packages
    SET ends_on = ends_on - v_unused_days
    WHERE id = v_package.id
      AND trainer_id = v_trainer_id;
  END IF;

  -- 복귀일 기록
  UPDATE public.package_pauses
  SET resumed_on = v_today
  WHERE id = v_pause.id
    AND trainer_id = v_trainer_id;

  -- 처리된 일시정지 ID 반환
  RETURN v_pause.id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."resume_member_package_pause"(uuid) FROM PUBLIC, "anon";

ALTER TABLE "public"."companies"
  ADD CONSTRAINT "companies_trainer_id_fkey" FOREIGN KEY (trainer_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."member_packages"
  ADD CONSTRAINT "membership_min_30_days" CHECK (((package_type <> 'membership'::text) OR ((usage_type = 'period'::text) AND (starts_on IS NOT NULL) AND (ends_on IS
    NOT NULL) AND (ends_on >= (starts_on + 29))))) NOT VALID;

ALTER TABLE "public"."member_packages"
  ADD CONSTRAINT "member_packages_member_id_fkey" FOREIGN KEY (member_id) REFERENCES public.members(id);

ALTER TABLE "public"."package_pauses"
  ADD CONSTRAINT "package_pauses_package_id_fkey" FOREIGN KEY (package_id) REFERENCES public.member_packages(id);

CREATE UNIQUE INDEX companies_one_personal_per_trainer ON public.companies USING btree (trainer_id)
  WHERE (company_type = 'personal'::text);

CREATE INDEX companies_trainer_id_idx ON public.companies USING btree (trainer_id);

CREATE INDEX member_packages_member_id_idx ON public.member_packages USING btree (member_id);

CREATE INDEX package_pauses_package_id_idx ON public.package_pauses USING btree (package_id);

CREATE TRIGGER on_auth_user_created_default_company
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_default_company_for_trainer();

CREATE POLICY "companies_insert_own" ON "public"."companies"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((trainer_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "companies_select_own" ON "public"."companies"
  FOR SELECT
  TO "authenticated"
  USING ((trainer_id = ( SELECT auth.uid() AS uid)));

COMMENT ON COLUMN "public"."package_pauses"."cancelled_at" IS '일시정지 예약 취소 시각. NULL이면 취소되지 않은 예약';

GRANT EXECUTE ON FUNCTION "public"."add_group_package"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."add_group_package"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."add_group_package"(uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."add_group_package"(uuid, integer) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."add_membership_package"(uuid, date, date) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."add_membership_package"(uuid, date, date) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."add_membership_package"(uuid, date, date) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."add_membership_package"(uuid, date, date) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."add_pt_package"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."add_pt_package"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."add_pt_package"(uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."add_pt_package"(uuid, integer) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."cancel_member_package_pause"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."cancel_member_package_pause"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."cancel_member_package_pause"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."cancel_member_package_pause"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."check_member_name_duplicate"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."check_member_name_duplicate"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."check_member_name_duplicate"(text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."check_member_name_duplicate"(text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "public"."create_default_company_for_trainer"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."create_default_company_for_trainer"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."create_default_company_for_trainer"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."pause_member_package"(uuid, date, date, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."pause_member_package"(uuid, date, date, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."pause_member_package"(uuid, date, date, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."pause_member_package"(uuid, date, date, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."register_member_only"(text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."register_member_only"(text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_only"(text, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_only"(text, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_group"(text, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."register_member_with_group"(text, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_group"(text, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_group"(text, text, integer) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_membership"(text, text, date, date) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."register_member_with_membership"(text, text, date, date) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_membership"(text, text, date, date) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_membership"(text, text, date, date) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_pt"(text, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."register_member_with_pt"(text, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_pt"(text, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_member_with_pt"(text, text, integer) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."resume_member_package_pause"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."resume_member_package_pause"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."resume_member_package_pause"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."resume_member_package_pause"(uuid) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."companies" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."companies" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."companies" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."companies" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."member_packages" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."member_packages" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."member_packages" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."member_packages" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."members" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."members" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."members" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."members" TO "service_role";

REVOKE ALL ON TABLE "public"."package_pauses" FROM "authenticated";

GRANT SELECT ON TABLE "public"."package_pauses" TO "authenticated";

REVOKE ALL ON TABLE "public"."package_pauses" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."package_pauses" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."package_pauses" TO "service_role";

ALTER TABLE "public"."member_packages"
  ADD CONSTRAINT "member_packages_trainer_id_fkey" FOREIGN KEY (trainer_id) REFERENCES auth.users(id);

ALTER TABLE "public"."members"
  ADD CONSTRAINT "members_trainer_id_fkey" FOREIGN KEY (trainer_id) REFERENCES auth.users(id);

CREATE UNIQUE INDEX members_trainer_phone_unique_idx ON public.members USING btree (trainer_id, phone);

CREATE POLICY "Trainers can insert own packages" ON "public"."member_packages"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((trainer_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.id = member_packages.member_id) AND (members.trainer_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "Trainers can update own packages" ON "public"."member_packages"
  FOR UPDATE
  TO "authenticated"
  USING ((trainer_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK (((trainer_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.id = member_packages.member_id) AND (members.trainer_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "Trainers can view own packages" ON "public"."member_packages"
  FOR SELECT
  TO "authenticated"
  USING (((trainer_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.members
  WHERE ((members.id = member_packages.member_id) AND (members.trainer_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "Trainers can insert own members" ON "public"."members"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((trainer_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Trainers can update own members" ON "public"."members"
  FOR UPDATE
  TO "authenticated"
  USING ((trainer_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((trainer_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Trainers can view own members" ON "public"."members"
  FOR SELECT
  TO "authenticated"
  USING ((trainer_id = ( SELECT auth.uid() AS uid)));

ALTER TABLE "public"."package_pauses"
  ADD CONSTRAINT "package_pauses_trainer_id_fkey" FOREIGN KEY (trainer_id) REFERENCES auth.users(id);

CREATE POLICY "Trainers can view own package pauses" ON "public"."package_pauses"
  FOR SELECT
  TO "authenticated"
  USING (((trainer_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.member_packages pkg
  WHERE ((pkg.id = package_pauses.package_id) AND (pkg.trainer_id = ( SELECT auth.uid() AS uid)))))));

