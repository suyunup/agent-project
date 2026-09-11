# ClipWeave 개발 환경 조사

조사일: 2026-09-11. 대상 폴더: 이 저장소의 루트.

공식 문서와 당시 Mac의 도구 상태를 확인한 조사 기록이다. 아래 구성은 추천안이며 REQUIREMENTS.md의 미결정 사항을 자동으로 확정하지 않는다. 조사 이후 개발 도구 설치와 검증을 진행했다. **현재 설치 상태와 명령은 [SETUP.md](SETUP.md)를 참고한다.** 아래 2절은 설치 전 상태를 보존한다.

## 1. 추천 구성

**Tauri 2 + React + TypeScript + Vite, Rust 실행 엔진, SQLite, macOS Keychain, macOS 전용 입력·창 제어 모듈**을 추천한다.

Tauri는 Vite 프런트엔드 구성을 공식 안내하고 있다. 기존 기술 방향을 유지하면서 편집기와 오버레이의 화면을 React로 공유할 수 있는 구성이다. [Tauri Vite 연동](https://v2.tauri.app/start/frontend/vite/)

| 영역 | 추천 | ClipWeave에서의 역할 |
| --- | --- | --- |
| 개발 머신 | 현재 Apple Silicon Mac | 우선 arm64에서 실제 붙여넣기 흐름 검증 |
| Node | Node 24 LTS | 프런트엔드 개발·빌드 도구 실행 |
| 패키지 관리 | pnpm | 설치된 도구를 활용하고 프로젝트별 정확한 버전 고정 |
| 데스크톱 | Tauri 2 + Rust stable | 앱 수명, 창, IPC, 실행 상태, OS 연동 |
| 화면 | React + TypeScript + Vite | 워크플로우 편집기, 설정, 오버레이 내용 |
| 변환 엔진 | Rust 모듈 | UI와 분리한 순차 실행·치환·정규식·템플릿 |
| 일반 데이터 | SQLite + rusqlite 후보 | 워크플로우·일반 설정만 저장 |
| 비밀정보 | macOS Keychain | API 키 저장·조회·삭제 |
| AI 통신 | Rust HTTP 클라이언트 + Provider 어댑터 | Ollama·Gemini·OpenAI와 OpenAI 호환 연결 분리 |
| ⌘V 제어 | Core Graphics 이벤트 탭 검증 | 실제 키 입력을 조건부로 처리하고 원문 중복 삽입 방지 |
| 오버레이 | Tauri 창 우선, 필요 시 AppKit NSPanel 연동 | 마우스 근처 표시와 포커스 동작 검증 |
| 배포 | 초기에는 앱 번들·DMG 직접 배포 제안 | 서명·공증은 외부 배포 단계에서 구성 |

Node 24는 조사 시점 LTS이고 현재 설치된 Node 23은 지원 종료 상태다. Node를 프로젝트용 LTS로 맞추는 것을 권한다. Vite 공식 문서는 Node 20.19+ 또는 22.12+를 요구하며 템플릿별 추가 요구가 있을 수 있다고 안내한다. 프런트엔드 의존성은 초기 생성 때 호환성을 확인하고 lockfile로 고정한다. [Node 릴리스 상태](https://nodejs.org/en/about/previous-releases), [Vite 요구 환경](https://vite.dev/guide/)

## 2. 현재 머신에서 확인한 상태

| 항목 | 확인 결과 | 다음 조치 |
| --- | --- | --- |
| macOS | 15.5, 빌드 24F74 | 현재 머신에서 먼저 검증 |
| CPU 아키텍처 | arm64 | 초기 빌드 타깃 `aarch64-apple-darwin` 제안 |
| Node | 23.7.0 | 프로젝트용 Node 24 LTS 준비 권장 |
| npm | 10.9.2 | pnpm 사용 시 보조 도구 |
| pnpm | 9.6.0 | 초기 호환성 확인 후 버전 고정 |
| Rust·Cargo | PATH에서 발견되지 않음, 기본 `.cargo/bin`도 없음 | rustup 기반 stable 도구체인 준비 필요. 다른 위치 설치 여부까지 조사한 것은 아님. |
| Xcode | 14.3.1 | 현재 OS와 호환되는 최신 지원 Xcode/개발 도구로 정비 권장 |
| 선택된 개발 경로 | `/Applications/Xcode.app/Contents/Developer` | 정비 후 선택 경로 재확인 |
| 선택된 macOS SDK | 13.3 | 새 SDK로 빌드·연동 검증 권장 |
| Clang | 선택된 Xcode 안에서 경로 확인 | 실제 Tauri 컴파일은 아직 미검증 |
| Ollama | PATH 및 `/Applications/Ollama.app`에서 발견되지 않음 | 로컬 AI 검증 전에 설치 여부 확인·준비 |
| 프로젝트 | README.md, REQUIREMENTS.md | 아직 package.json·Cargo.toml·앱 코드 없음 |

도구 조회 중 Xcode가 파일 이벤트·캐시 관련 경고를 출력했지만 버전과 SDK 조회 결과는 반환했다. 이 경고만으로 빌드 불가라고 판단하지 않는다.

Tauri는 macOS 개발 도구와 Rust를 요구한다. Xcode의 정확한 업데이트 대상은 현재 OS에서 실행 가능한 버전을 Apple 호환 표로 골라야 한다. 최신 Xcode라는 이유만으로 현재 macOS에 설치 가능하다고 가정하지 않는다. [Tauri 사전 준비](https://v2.tauri.app/start/prerequisites/), [Apple Xcode 호환 표](https://developer.apple.com/xcode/system-requirements)

Ollama 공식 macOS 요구 환경은 macOS 14 이상이며 Apple M 시리즈의 CPU·GPU를 지원한다. 현재 OS·아키텍처는 이 조건에 부합한다. RAM·디스크 여유와 모델 크기는 이번 조사에서 확인하지 않았으므로 모델과 속도 목표는 아직 정하지 않는다. [Ollama macOS 요구사항](https://docs.ollama.com/macos)

## 3. 가장 먼저 검증할 부분: ⌘V

Tauri의 Global Shortcut 플러그인은 전역 단축키 등록 기능을 제공한다. 그러나 문서만으로 기존 ⌘V의 조건부 통과, 원문 삽입 억제, 최종 붙여넣기의 재호출 방지까지 보장된다고 판단할 수 없다. 대체 호출 단축키 후보와 기본 ⌘V 처리 경로를 구분하는 설계를 추천한다. [Tauri Global Shortcut](https://v2.tauri.app/plugin/global-shortcut/)

Apple의 Core Graphics 이벤트 탭은 수동 관찰과 능동 필터를 구분하고, CGEvent는 이벤트 게시 기능을 제공한다. 이를 근거로 **⌘V 처리에 네이티브 이벤트 탭과 결과 전달 경로를 사용하는 방안**을 우선 검증하자는 판단이다. 실제 앱 간 호환성은 문서 조사로 증명되지 않는다. [Apple 이벤트 탭](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)), [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)

검증할 흐름:

1. 활성화 상태에서 실제 ⌘V만 식별하고 대상 앱 정보를 확보한다.
2. 원문 입력을 억제하고 오버레이 표시 작업을 전달한다. 이벤트 콜백 안에서 AI·DB·긴 작업을 기다리지 않는다.
3. 현재 클립보드 텍스트로 간단한 코드 변환을 수행한다.
4. 오버레이를 닫고 원래 대상이 유효한지 확인한다.
5. 결과를 한 번만 붙여넣고, 앱이 만든 이벤트로 오버레이가 다시 열리지 않게 한다.
6. 비활성화·취소·권한 거부·실패 후 일반 붙여넣기가 회복되는지 확인한다.

접근성 권한과 입력 모니터링 관련 API를 검토하고 선택한 구현에서 실제로 필요한 권한만 안내한다. 모든 환경에 두 권한이 무조건 필요하다고 선행 확정하지 않는다. 입력 관찰 권한 확인 API도 별도로 존재한다. [Apple 입력 접근 확인](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess())

처음에는 TextEdit와 브라우저 입력창에서 확인하고, 이후 VS Code·Discord 등 목표 앱으로 넓힌다. 키 반복, 한글 입력기, 수정키 조합, 비텍스트 클립보드, 전체 화면, 여러 모니터, 대상 변경·종료를 검수한다. Terminal은 명령 실행 위험 때문에 초기 자동 붙여넣기 시험 대상에서 제외하는 것을 제안한다.

## 4. 화면과 네이티브 연동 경계

메인 편집기와 설정은 일반 Tauri 창으로 구성한다. 오버레이는 테두리 없는 작은 창부터 검증하고, 다른 앱과의 포커스·Spaces 동작 때문에 필요한 경우 NSPanel 기반 연동을 추가한다. Tauri는 창 사용자화를 제공하고 AppKit의 NSPanel은 보조 패널 창을 위한 API다. 이 둘의 실제 결합 방식은 아직 구현하지 않았다. [Tauri 창 사용자화](https://v2.tauri.app/learn/window-customization/), [Apple NSPanel](https://developer.apple.com/documentation/appkit/nspanel)

Rust에서 macOS API를 호출하는 방식과 작은 Swift/Objective-C 브리지를 두는 방식을 기술 실험에서 비교한다. 별도의 상주 helper 프로세스나 비공식 패널 플러그인을 처음부터 필수 의존성으로 삼지는 않는다. 메인 스레드 창 조작, 이벤트 수명, 포커스 복원까지 검증한 뒤 연결 방식을 결정한다.

권장 책임 분리는 다음과 같다.

```text
React 화면: 편집기 · 오버레이 · 설정
                 ↕ Tauri IPC
Rust: 실행 상태 · 변환 엔진 · Provider · 저장소
                 ↕ macOS 전용 모듈
키 입력 처리 · 창/포커스 · 클립보드 · Keychain
```

브라우저에서 Vite 화면이 뜨는 것은 UI 개발 확인이다. 실제 ⌘V·OS 권한·다른 앱 붙여넣기 확인은 Tauri 앱으로 해야 한다.

## 5. 저장·변환·AI의 환경 선택

**저장:** Rust에 저장소를 모아 SQLite를 사용하는 안을 추천한다. `rusqlite`는 Rust용 SQLite 래퍼다. Tauri 공식 SQL 플러그인도 SQLite를 지원하므로 대안이지만 두 저장 계층을 동시에 도입할 필요는 없다. 입력·결과·실행 이력은 메모리에만 두고 구성·일반 설정만 저장한다. [rusqlite](https://docs.rs/rusqlite/latest/rusqlite/), [Tauri SQL](https://v2.tauri.app/plugin/sql/)

**키:** macOS 전용 MVP이므로 Keychain을 우선 후보로 추천한다. 키를 조회하는 동작은 네이티브 쪽에 두고 화면에는 등록 여부만 반환한다. 키 최초 입력은 화면에서 받을 수 있지만 저장 후 조회 API로 원문을 돌려주지 않는 설계다. [Apple Keychain services](https://developer.apple.com/documentation/security/keychain-services)

**변환:** 엔진을 Rust에 두면 편집기와 오버레이가 동일한 실행 경로를 사용하도록 만들 수 있다. 정규식 후보인 Rust `regex`는 look-around와 backreference 같은 문법을 지원하지 않는다. JavaScript/PCRE와 같은 문법으로 안내하면 안 되므로 REQUIREMENTS.md의 D-07을 해결하고 선택해야 한다. 템플릿 라이브러리도 문법 합의 후 고른다. [Rust regex 문서](https://docs.rs/regex/latest/regex/)

**AI:** Rust의 비동기 HTTP 클라이언트 후보로 `reqwest`를 검토한다. 공통 요청·응답·취소·오류 계약 아래 Ollama, Gemini, OpenAI, OpenAI 호환 어댑터를 분리하는 설계를 추천한다. 특정 SDK 하나에 실행 엔진을 맞추지 않는다. API별 endpoint·모델·옵션은 AI 통합 시 공식 문서를 다시 확인하며, 이번 조사로 특정 API 버전까지 확정하지 않는다. [reqwest](https://docs.rs/reqwest/latest/reqwest/)

Docker, 별도 웹 서버, Python 환경, Node sidecar는 현재 요구사항을 위한 초기 필수 구성에 포함하지 않는 것을 추천한다. 로컬 AI를 사용할 때는 별도 Ollama 서비스와 모델이 필요하다.

## 6. 이 폴더에 만들 구조 제안

아래는 생성 예정 구조이며 현재 만들어진 앱 파일이 아니다.

```text
agent-project/
  REQUIREMENTS.md
  DEVELOPMENT_ENVIRONMENT.md
  package.json
  pnpm-lock.yaml
  vite.config.ts
  src/
    features/editor/
    features/overlay/
    features/settings/
    lib/ipc/
  src-tauri/
    Cargo.toml
    Cargo.lock
    tauri.conf.json
    capabilities/
    src/
      commands/
      engine/
      providers/
      storage/
      platform/macos/
  samples/
```

저장소 루트를 앱 루트로 사용한다. 기존 README·요구사항 파일을 보존하면서 초기화하고, React·Vite·Tauri·Rust 및 pnpm 버전을 실제 빌드 성공 후 고정한다. 로컬 DB와 사용자 API 키는 프로젝트 폴더나 Git에 넣지 않는다.

## 7. 구축 순서와 검증 기준

1. **도구 준비:** Node LTS, Rust stable, 현재 OS와 호환되는 Xcode/개발 도구를 준비하고 버전을 확인한다.
2. **기본 앱 생성:** 이 폴더에 Tauri 2 + React + TypeScript + Vite를 구성하고 dev 앱과 release 앱의 창 표시를 확인한다.
3. **핵심 기술 실험:** AI 없이 ⌘V → 오버레이 → 간단한 치환 → 대상 앱 붙여넣기를 완성한다. 중복 입력·재귀 호출·취소·권한 회수·설정 비활성화를 통과해야 한다.
4. **실행·저장:** Rust 변환 엔진, SQLite 구성 저장, 편집기·미리보기를 연결한다.
5. **AI:** Keychain과 Provider 어댑터를 붙이고 Ollama·Gemini·OpenAI를 각각 검증한다.
6. **통합·배포:** 샘플, 접근성, 다중 모니터·지원 앱 검수 후 앱 번들·DMG의 서명·공증을 준비한다.

UI 시험만으로 붙여넣기 성공을 판정하지 않는다. 실행 엔진은 Rust 단위 테스트, 프런트엔드는 컴포넌트 테스트, 실제 앱은 통합 테스트로 나눈다. 현재 Tauri 문서는 macOS에서 WebdriverIO의 임베디드 WebDriver 경로를 안내한다. 외부 앱 포커스·권한·키 이벤트 검증은 별도의 실제 Mac 검수가 여전히 필요하다. 테스트 서버와 진단 플러그인은 배포 빌드에서 제외한다. [Tauri WebDriver 안내](https://v2.tauri.app/develop/tests/webdriver/)

공개 배포는 Developer ID 서명과 공증을 사용하는 DMG 경로를 추천한다. 로컬 개발 준비와 외부 배포 인증 준비를 구분한다. App Store 배포 가능 여부는 이번 조사에서 판정하지 않았으며 필수 경로로 삼지 않는다. [Tauri macOS 서명·공증](https://v2.tauri.app/distribute/sign/macos/)

**다음 구현의 첫 통과 기준은 실제 Mac에서 ⌘V 흐름이 동작하는 작은 앱이다.** 이 결과에 따라 네이티브 브리지·오버레이 방식과 지원 환경을 확정한 뒤 편집기와 AI 기능을 확장하는 순서를 추천한다.
