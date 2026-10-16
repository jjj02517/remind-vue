// 연락처에서 숫자만 추출
export function normalizePhone(phone: string): string {
  return phone.replace(/\D/g, '')
}

// 연락처에 하이픈 추가 (010-0000-0000)
export function formatPhone(phone: string): string {
  const digits = normalizePhone(phone).slice(0, 11)

  if (digits.length <= 3) {
    return digits
  }

  if (digits.length <= 7) {
    return `${digits.slice(0, 3)}-${digits.slice(3)}`
  }

  return `${digits.slice(0, 3)}-${digits.slice(3, 7)}-${digits.slice(7)}`
}

// 한국 010 휴대폰 번호 유효성 검사
export function isValidPhone(phone: string): boolean {
  return /^010\d{8}$/.test(normalizePhone(phone))
}
