
-- ============================================
-- 기존 회원을 기본 '개인 고객' 근무처에 연결
-- ============================================

INSERT INTO public.company_members (
  trainer_id,
  company_id,
  member_id
)
SELECT
  m.trainer_id,
  c.id,
  m.id
FROM public.members AS m
INNER JOIN public.companies AS c
  ON c.trainer_id = m.trainer_id
  AND c.company_type = 'personal'

-- 이미 연결된 회원은 중복 생성하지 않음
ON CONFLICT (company_id, member_id) DO NOTHING;
