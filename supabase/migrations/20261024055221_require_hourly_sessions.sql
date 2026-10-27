-- Remind PT: 신규 수업은 한국 시간 정시 시작 + 60분 고정
-- 기존 회원/이용권/수업 데이터는 삭제하거나 변경하지 않습니다.
-- 과거에 등록된 비정시 수업이 있어도 안전하게 적용되도록 NOT VALID를 사용합니다.
-- 기존 행을 나중에 모두 정리한 후에만 VALIDATE CONSTRAINT를 고려합니다.

BEGIN;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_hourly_slot_check
  CHECK (
    ends_at = starts_at + interval '1 hour'
    AND EXTRACT(MINUTE FROM starts_at AT TIME ZONE 'Asia/Seoul') = 0
    AND EXTRACT(SECOND FROM starts_at AT TIME ZONE 'Asia/Seoul') = 0
  ) NOT VALID;

COMMENT ON CONSTRAINT sessions_hourly_slot_check ON public.sessions IS
  '한국 시간 기준 정시에 시작하고 정확히 1시간 진행 (신규/변경 수업에 적용)';

COMMIT;
