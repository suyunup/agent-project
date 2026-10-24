# ClipWeave 로컬 개발 환경

설정·검증일: 2026-09-11. 현재 Mac: macOS 15.5 / Apple Silicon.

## M1 앱 개발·검증

앱 초기화와 M1 구현을 추가했다. 현재 실행 명령과 자동/수동 검증 결과는 [M1_VALIDATION.md](M1_VALIDATION.md)를 참고한다. 아래 도구 설치 기록은 초기 환경 설정 당시의 기록이다.

```sh
sh scripts/with-dev-env.sh pnpm install --frozen-lockfile
sh scripts/with-dev-env.sh pnpm app:dev
sh scripts/with-dev-env.sh pnpm app:build
```

## 설치·설정 완료

| 도구 | 확인한 버전·상태 |
| --- | --- |
| Node | Homebrew `node@24`, 24.20.0 |
| pnpm | 기존 9.6.0, Node 24 환경에서 실행 확인 |
| Rust | 1.98.1, `rust-toolchain.toml`로 프로젝트 버전 고정 |
| Cargo | 1.98.1 |
| rustfmt·Clippy | 설치·실행 확인 |
| macOS 개발 도구 | 기존 Command Line Tools 16.2 선택, SDK 15.2 |
| Ollama | 0.33.3, 로컬 API 연결·생성 확인 |
| 테스트 모델 | `qwen3:0.6b`, 설치 완료 |

Homebrew로 Node 24, rustup, Ollama 및 필요한 의존성을 설치했다. 설치 과정에서 Homebrew 메타데이터와 일부 공유 의존성도 업데이트되었다. 기존 전역 Node 연결과 Xcode 선택 경로, 사용자 셸 설정은 변경하지 않았다.

## 개발 명령 실행

### 공개 저장소와 로컬 환경 변수

이 저장소는 공개 저장소다. `.env`는 개발용 로컬 설정과 키를 위한 파일이며 Git에서 제외한다. 다른 개발 환경에서는 `.env.example`을 `.env`로 복사해서 사용한다. 공개하는 `.env.example`의 키 값은 항상 비워둔다.

현재 `.env`에는 로컬 Ollama 주소·테스트 모델과 빈 API 키 항목만 있다. 앱 백엔드는 시작할 때 저장소 루트의 `.env`를 개발용 설정으로 읽으며, 같은 이름의 프로세스 환경변수가 있으면 그 값을 우선한다. 배포 앱의 사용자 API 키는 요구사항대로 추후 macOS Keychain에 보관한다.

비밀키에 `VITE_` 접두사를 붙이거나 프런트엔드 빌드 설정에 주입하지 않는다. `.env`를 소스 코드·로그·샘플·문서에 복사하지 않는다. `.gitignore`는 로컬 DB, 로그, 개인키·서명 인증서, 빌드 결과도 제외한다. 의존성 버전 재현을 위한 `pnpm-lock.yaml`과 `Cargo.lock`은 커밋 대상이다.

`.gitignore`는 이미 추적 중인 파일이나 과거 커밋에서 비밀정보를 제거하지 않는다. 실제 키를 커밋했다면 해당 키를 폐기·재발급하고 추적 파일과 기록을 별도로 정리해야 한다.

### 프로젝트 도구 사용

저장소 루트에서 명령 앞에 환경 스크립트를 붙인다. 이 스크립트는 해당 명령에만 Node 24·Rust 경로와 Command Line Tools를 적용한다.

```sh
sh scripts/with-dev-env.sh node --version
sh scripts/with-dev-env.sh pnpm --version
sh scripts/with-dev-env.sh cargo --version
sh scripts/with-dev-env.sh xcrun --show-sdk-version
```

일반 터미널의 `node --version`은 기존 23.7.0을 표시할 수 있다. ClipWeave 명령은 위 스크립트를 사용한다. `.node-version`에는 24.20.0을 기록했고 스크립트는 Homebrew의 Node 24 계열을 선택한다. 추후 Homebrew 업그레이드 시 실제 버전과 이 파일을 함께 갱신한다.

`DEVELOPER_DIR`가 이미 명시되어 있으면 스크립트가 해당 선택을 존중한다. 현재 선택된 오래된 Xcode 대신 SDK 15.2를 사용한 네이티브 링크 검증을 통과했으므로 Xcode 전체 업데이트는 이번에 하지 않았다.

## Ollama

이번 설정 중 `127.0.0.1:11434`에 서버를 실행했다. 로그인 자동 실행은 등록하지 않았다. 서버가 종료된 경우 별도 터미널에서 다음 명령으로 실행하고 터미널을 유지한다.

```sh
sh scripts/with-dev-env.sh ollama serve
```

서버가 이미 실행 중이면 다시 실행할 필요가 없다. 별도 터미널에서 연결과 설치 모델을 확인할 수 있다.

```sh
curl --fail http://127.0.0.1:11434/api/version
sh scripts/with-dev-env.sh ollama list
```

`qwen3:0.6b`는 환경 검증용 소형 모델이다. 최종 작업용 모델·품질 기준은 아직 정하지 않았다. 공식 모델 페이지는 약 523MB로 안내한다. [Ollama 모델 정보](https://ollama.com/library/qwen3:0.6b)

## 완료한 검증과 남은 범위

- 환경 스크립트 셸 문법, Node·pnpm·Rust·Cargo·rustfmt·Clippy 실행 확인.
- 임시 폴더에서 Rust 프로그램 컴파일·실행 성공.
- SDK 15.2로 AppKit·CoreGraphics·Security·WebKit 프레임워크를 링크한 최소 프로그램 빌드·실행 성공. 실제 API 동작 검증을 의미하지 않는다.
- Ollama 버전 API 응답 및 `qwen3:0.6b` 텍스트 생성 요청 성공: `done: true`, 응답 `OK`.

초기 환경 설정 당시에는 개발 도구만 준비했다. 이후 package.json·Cargo.toml과 lockfile을 추가하고 전체 Tauri 개발·release 빌드를 검증했다. Tauri CLI는 프로젝트 개발 의존성으로 사용하며 전역 설치하지 않는다.

⌘V 처리에 필요한 macOS 권한은 실제 앱의 식별자와 실행 경로가 생긴 뒤 설정한다. Gemini·OpenAI API 키는 앱의 비밀 저장 기능이 만들어질 때 등록하며 이번 설정에서 수집하거나 저장하지 않았다.
