# ClipWeave

복사한 텍스트를 가공한 뒤 원래 입력창에 붙여넣는 macOS 데스크톱 도구입니다. 반복적인 텍스트 정리 작업을 사용자가 구성한 변환 단계로 처리하는 것을 목표로 합니다.

현재는 **M1 — 가공 붙여넣기 기술 검증 + AI 요약 프리뷰** 단계입니다. 고정 치환과 로컬 Ollama 기반 AI 요약으로 호출부터 결과 전달까지 구현했고, 사용자 검수에서 Chrome 붙여넣기와 원래 입력 포커스 유지를 확인했습니다. 전체 워크플로우 편집기와 다른 앱·예외 상황의 검수는 진행 중입니다.

## 현재 사용할 수 있는 기능

- **한 번만 가공:** 메인 창에서 준비한 다음 ⌘V 한 번만 가공 메뉴로 처리합니다. 평소 ⌘V는 일반 붙여넣기로 동작합니다.
- **고정 텍스트 치환:** 모든 `foo`를 `bar`로 바꿉니다. 대소문자를 구분하며 한글·이모지·공백·줄바꿈을 보존합니다.
- **AI 요약:** 기본값인 로컬 Ollama 또는 환경변수로 선택한 Gemini/OpenAI를 호출해 복사한 텍스트를 바로 붙여넣을 수 있는 요약으로 바꿉니다.
- **포커스를 유지하는 패널:** 원래 앱의 입력 포커스를 유지한 채 원문과 결과를 확인합니다.
- **결과 전달:** 원문 붙여넣기, 변환 결과 붙여넣기, 결과 복사, 취소를 제공합니다.
- **키보드 조작:** 방향키로 선택하고 Enter로 실행하거나 Esc로 취소합니다.

워크플로우 편집·저장, 정규식, 템플릿, 앱 내부 AI 설정 화면, 파일 내보내기는 아직 구현하지 않았습니다. 일반 치환은 AI 모델이나 API 키 없이 실행할 수 있습니다.

## 시작하기

개발·검증 환경은 **macOS 15.5 / Apple Silicon**입니다. Node 24, pnpm 9.6.0, Rust 및 macOS Command Line Tools가 필요합니다. 설치와 환경 스크립트 설명은 [SETUP.md](SETUP.md)를 참고하세요.

저장소 루트에서 의존성을 설치하고 데스크톱 앱을 실행합니다.

```sh
sh scripts/with-dev-env.sh pnpm install --frozen-lockfile
sh scripts/with-dev-env.sh pnpm app:dev
```

### 첫 가공 붙여넣기

1. 앱의 **권한 확인**을 누르고 macOS의 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 ClipWeave를 허용합니다.
2. `foo 한글 😀 foo`를 복사합니다.
3. 메인 창에서 **다음 붙여넣기 한 번만 가공**을 누릅니다.
4. 대상 앱의 입력창을 선택하고 **⌘V**를 누릅니다.
5. 패널에서 **테스트 치환**을 선택합니다.
6. 결과 `bar 한글 😀 bar`를 확인하고 **붙여넣기**를 누릅니다.

한 번 호출하면 가공 대기는 자동 해제됩니다. Chrome에서는 처음 입력창 정보를 준비하는 데 몇 초 걸릴 수 있습니다. 입력 위치를 확인하지 못하면 자동 삽입을 중단하며, 결과를 복사해 직접 붙여넣을 수 있습니다.

### AI 요약 사용

로컬 개발 설정은 저장소 루트의 `.env`를 백엔드가 시작할 때 읽습니다. 기본 Provider는 Ollama이며 `qwen3:0.6b` 모델이 설치되어 있어야 합니다.

```sh
cp .env.example .env
sh scripts/with-dev-env.sh ollama serve
```

앱을 실행한 뒤 일반 변환과 같은 순서로 호출하고 패널에서 **AI 요약**을 선택합니다. Provider를 바꾸려면 `.env`의 `CLIPWEAVE_AI_PROVIDER`를 `ollama`, `gemini`, `openai` 중 하나로 설정하고 해당 모델·API 키 항목을 채운 뒤 앱을 다시 시작합니다. 키는 프런트엔드로 전달하거나 로그에 기록하지 않지만, 현재 환경변수 방식은 개발용입니다. 배포용 키 저장은 추후 macOS Keychain 설정 화면으로 대체할 예정입니다.

### 로컬 앱 빌드

```sh
sh scripts/with-dev-env.sh pnpm app:build
open src-tauri/target/release/bundle/macos/ClipWeave.app
```

개발 앱과 빌드한 앱은 하나씩 실행하세요. 메인 창을 닫으면 앱이 종료됩니다. 재빌드하거나 실행 버전을 바꾼 뒤에는 접근성 권한을 다시 허용해야 할 수 있습니다. 현재 앱 번들은 로컬 검증용이며 공개 배포를 위한 서명·공증은 준비하지 않았습니다.

## 데이터 처리

- 클립보드를 백그라운드에서 감시하거나 이력으로 수집하지 않습니다. 사용자가 준비한 붙여넣기 호출 때 텍스트를 읽습니다.
- 입력·결과·대상 정보는 세션 메모리에서만 관리하며, 실행 본문을 파일이나 로그에 저장하지 않습니다.
- 결과를 복사하거나 붙여넣으면 시스템 클립보드에는 결과가 남습니다. 취소는 클립보드를 변경하지 않습니다.
- AI 요약을 명시적으로 선택한 경우에만 해당 세션의 원문과 고정 지시문을 설정한 Provider로 전송합니다. Ollama 주소도 설정에 따라 원격일 수 있습니다.

빈 클립보드, 비텍스트 데이터, 1 MiB 초과 또는 NUL 문자가 포함된 텍스트는 가로채지 않고 OS의 기본 붙여넣기로 처리합니다.

## 개발과 검증

| 영역 | 구성 |
| --- | --- |
| 데스크톱 앱 | Tauri 2 |
| 화면 | React · TypeScript · Vite |
| 변환·호출 상태·AI Provider | Rust · reqwest |
| macOS 연동 | Objective-C · AppKit · Accessibility · Core Graphics |

```sh
# TypeScript 검사와 프런트엔드 빌드
sh scripts/with-dev-env.sh pnpm build

# Rust 테스트와 정적 검사
sh scripts/with-dev-env.sh cargo test --manifest-path src-tauri/Cargo.toml --locked
sh scripts/with-dev-env.sh cargo clippy --manifest-path src-tauri/Cargo.toml --locked -- -D warnings
sh scripts/with-dev-env.sh cargo fmt --manifest-path src-tauri/Cargo.toml --check
```

현재 자동 테스트 7개와 Clippy가 통과했습니다. 로컬 Ollama `qwen3:0.6b`의 실제 요약 응답도 확인했습니다. 실제 앱 간 붙여넣기는 자동 테스트와 별도로 검수합니다. Chrome에서 사용자 확인을 받았으며 TextEdit·Safari, 권한 회수, 연속 호출, 다중 모니터 등의 검수가 남아 있습니다. 재현 절차와 상세 결과는 [M1_VALIDATION.md](M1_VALIDATION.md)에 기록합니다.

## 다음 개발 단계

M1의 남은 검수를 마친 뒤 다음 순서로 확장할 예정입니다.

1. **M2 — 로컬 실행 기반:** 비AI 변환 엔진, 워크플로우 편집·저장, 단계별 미리보기.
2. **M3 — AI 통합:** 구현된 Ollama·Gemini·OpenAI 요약 어댑터를 설정 화면·Keychain·워크플로우 단계와 연결하고 통합 검수.
3. **M4 — 가공 붙여넣기 완성:** 저장 워크플로우 연결, 호출 설정, 결과 내보내기.
4. **M5 — 공개 배포 준비:** 샘플 워크플로우, 통합 검수, 배포 문서와 라이선스 확정.

## 관련 문서

- [REQUIREMENTS.md](REQUIREMENTS.md) — 제품 요구사항, M1에서 합의한 호출 방식, 전체 마일스톤
- [SETUP.md](SETUP.md) — 로컬 도구 설치 기록과 실행 환경
- [M1_VALIDATION.md](M1_VALIDATION.md) — 구현·검증 결과, 알려진 제약, 수동 검수표
- [DEVELOPMENT_ENVIRONMENT.md](DEVELOPMENT_ENVIRONMENT.md) — 기술 구성 조사와 선택 근거
- [manual/paste-target.html](manual/paste-target.html) — 브라우저 붙여넣기 검수용 입력창
