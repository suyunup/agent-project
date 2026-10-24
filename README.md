# ClipWeave

**복사한 텍스트를 붙여넣기 전에 원하는 형태로 다듬는 macOS 앱입니다.**

평소에는 기존 `⌘V`를 그대로 사용하고, 필요할 때만 한 번 가공합니다. 로컬 치환과 AI 요약 결과를 확인한 뒤 원래 입력창에 바로 붙여넣을 수 있습니다.

## 주요 기능

- 한 번만 동작하는 가공 붙여넣기
- 원래 앱의 입력 포커스를 유지하는 결과 패널
- 로컬 텍스트 치환과 AI 요약
- Ollama, Gemini, OpenAI 지원
- 결과 붙여넣기·복사 및 요청 취소
- 입력과 결과를 저장하지 않는 세션 기반 처리

## 시작하기

macOS와 Node 24, pnpm, Rust, Command Line Tools가 필요합니다.

```sh
cp .env.example .env
sh scripts/with-dev-env.sh pnpm install --frozen-lockfile
```

AI 요약에 기본 설정인 Ollama를 사용하려면 첫 번째 터미널에서 서버를 실행합니다.

```sh
sh scripts/with-dev-env.sh ollama serve
```

다른 터미널에서 ClipWeave를 실행합니다.

```sh
sh scripts/with-dev-env.sh pnpm app:dev
```

## 사용 방법

1. 앱에서 **권한 확인**을 누르고 macOS 손쉬운 사용 권한을 허용합니다.
2. 텍스트를 복사합니다.
3. **다음 붙여넣기 한 번만 가공**을 누릅니다.
4. 원하는 입력창에서 `⌘V`를 누릅니다.
5. AI 요약 또는 로컬 치환을 선택하고 결과를 붙여넣습니다.

## AI 설정

기본 Provider는 로컬 Ollama이며 설정은 `.env`에서 변경할 수 있습니다.

```env
CLIPWEAVE_AI_PROVIDER=ollama
CLIPWEAVE_OLLAMA_BASE_URL=http://127.0.0.1:11434
CLIPWEAVE_OLLAMA_MODEL=qwen3:0.6b
```

`CLIPWEAVE_AI_PROVIDER`는 `ollama`, `gemini`, `openai`를 지원합니다. 실제 API 키는 `.env`에만 입력하고 커밋하지 마세요. `.env`는 Git에서 제외되어 있습니다.

## 개인정보 보호

- 클립보드를 백그라운드에서 수집하거나 기록하지 않습니다.
- 입력과 결과는 현재 세션의 메모리에만 유지합니다.
- AI 요약을 선택했을 때만 설정된 Provider로 텍스트를 전송합니다.
- 로컬 Ollama를 사용하면 외부 AI API 키가 필요하지 않습니다.

## 개발

```sh
sh scripts/with-dev-env.sh pnpm build
sh scripts/with-dev-env.sh cargo test --manifest-path src-tauri/Cargo.toml --locked
sh scripts/with-dev-env.sh cargo clippy --manifest-path src-tauri/Cargo.toml --locked -- -D warnings
sh scripts/with-dev-env.sh pnpm app:build
```

기술 구성은 Tauri 2, React, TypeScript, Rust와 macOS AppKit·Accessibility API입니다.

현재 macOS용 프리뷰 버전이며 공개 배포용 서명과 공증은 준비 중입니다.

자세한 제품 요구사항과 검증 기록은 [REQUIREMENTS.md](REQUIREMENTS.md), [M1_VALIDATION.md](M1_VALIDATION.md)에서 확인할 수 있습니다.
