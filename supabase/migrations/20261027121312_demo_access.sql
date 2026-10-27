DO $$
DECLARE
  v_trainer_id uuid;
BEGIN
  LOCK TABLE remind_private.demo_settings IN SHARE ROW EXCLUSIVE MODE;

  SELECT id INTO STRICT v_trainer_id
  FROM auth.users
  WHERE lower(email) = lower('tous889900@gmail.com');

  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE trainer_id = v_trainer_id
      AND name LIKE '데모 %'
  ) THEN
    RAISE EXCEPTION '데모 계정의 샘플 데이터를 확인해 주세요.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM remind_private.demo_settings
    WHERE singleton
      AND trainer_id <> v_trainer_id
  ) THEN
    RAISE EXCEPTION '다른 데모 계정이 연결되어 있습니다. 설정을 확인해 주세요.';
  END IF;

  INSERT INTO remind_private.demo_settings (
    singleton,
    trainer_id,
    is_enabled
  )
  VALUES (true, v_trainer_id, true)
  ON CONFLICT (singleton)
  DO UPDATE SET is_enabled = true;
END;
$$;

SELECT is_enabled
FROM remind_private.demo_settings
WHERE singleton;