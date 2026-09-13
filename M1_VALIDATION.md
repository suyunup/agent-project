# M1 구현 및 검증 기록

작성일: 2026-09-11. 대상: macOS 15.5 / Apple Silicon.

**상태: 구현·빌드·자동 테스트 완료. 사용자 검수에서 비활성 패널의 커서 유지와 Chrome 붙여넣기 성공을 확인했다. TextEdit/Safari 및 예외 시나리오의 전체 검수가 남아 있어 M1 전체 통과나 전체 MVP 완료로 판정하지 않는다.**

## 이번 구현

- Tauri 2 + React + TypeScript + Vite 앱과 메인 창·오버레이. 오버레이 WebView는 비활성 NSPanel에 배치해 대상 앱의 활성 상태와 포커스를 유지한다.
- ‘다음 붙여넣기 한 번만 가공’ 버튼과 접근성 권한 안내. 유효한 외부 텍스트 호출 한 번을 처리하면 자동 해제한다.
- Core Graphics 이벤트 탭으로 외부 앱의 수정키 없는 기본 ⌘V 처리. 콜백에서는 호출 시 클립보드 텍스트와 대상 PID만 확보하고, AX 조회·창 표시·변환은 다음 메인 스레드 작업으로 분리한다.
- 고정 치환 `foo` → `bar` (대소문자 구분, 전체 치환), 원문·결과 표시, 원문 붙여넣기·결과 붙여넣기·복사·취소.
- 호출별 ID, 키 반복 억제, 자체 생성 이벤트 표식, 지연 붙여넣기 취소 토큰. 패널이 키보드 포커스를 가져오지 않으므로 방향키·Enter·Esc는 호출 처리 모듈에서 메뉴로 전달한다.
- 대상 앱·AX 창·포커스 요소와 제공되는 경우 선택 범위를 대조한다. 앱 전환 또는 확인 실패 시 삽입을 거부하고 결과 복사를 안내한다.
- 결과 확인 후 명시적으로 붙여넣으며 클립보드에는 결과를 남긴다. 취소는 클립보드를 변경하지 않는다.
- 입력·출력·대상 정보는 세션 메모리 전용이다. DB·실행 이력·본문 로그·AI 호출·클립보드 감시를 추가하지 않았다.

화면은 React, 호출·변환 상태는 Rust, AppKit/AX/CGEvent 처리는 `src-tauri/native/macos.m`의 Objective-C 브리지로 분리했다. 브리지의 모든 호출은 메인 스레드에서 실행된다. 메뉴·결과는 일반 텍스트로 렌더링하며 HTML/Markdown을 실행하지 않는다.

## 재현 명령

저장소 루트에서 실행한다.

```sh
sh scripts/with-dev-env.sh pnpm install --frozen-lockfile
sh scripts/with-dev-env.sh pnpm app:dev
```

배포용 로컬 앱 번들 생성:

```sh
sh scripts/with-dev-env.sh pnpm app:build
open src-tauri/target/release/bundle/macos/ClipWeave.app
```

개발 앱과 release 앱은 동시에 켜지 말고 하나를 종료한 후 다른 하나를 실행한다. 메인 창을 닫으면 앱과 이벤트 탭이 종료된다. 접근성 권한은 실제 실행 파일에 적용되므로 개발/release 전환이나 재빌드 뒤 다시 허용해야 할 수 있다. Developer ID 서명·공증·외부 배포는 이번 범위가 아니다.

```sh
sh scripts/with-dev-env.sh pnpm build
sh scripts/with-dev-env.sh cargo test --manifest-path src-tauri/Cargo.toml --locked
sh scripts/with-dev-env.sh cargo clippy --manifest-path src-tauri/Cargo.toml --locked -- -D warnings
sh scripts/with-dev-env.sh cargo fmt --manifest-path src-tauri/Cargo.toml --check
```

## 확인한 결과

| 항목 | 결과 |
| --- | --- |
| TypeScript 검사 및 Vite production 빌드 | 통과 |
| Rust 테스트 | 4개 통과: Unicode·공백 보존, 오래된 호출 차단, 중복 호출/전달 차단, 무일치·빈 결과 처리 |
| Clippy (`-D warnings`) | 통과 |
| Objective-C 브리지 컴파일 및 네이티브 링크 | 통과 |
| release `.app` 번들 생성 | 통과 |
| 개발 서버 및 개발 앱 프로세스 실행 | 통과, 창 내용의 수동 확인은 별도 |
| Chrome 실제 ⌘V·AX 포커스·삽입 | 사용자 확인: NSPanel로 커서 유지, Chrome 대응 후 붙여넣기 성공 |
| TextEdit/Safari 실제 삽입 | 수동 검수 대기 |
| 권한 거부·회수·재허용, 종료 후 기본 ⌘V | 수동 검수 대기 |
| 다중 모니터·전체 화면·한글 입력기 | 수동 검수 대기 |

자동 테스트는 변환·Rust 세션만 검증한다. CGEvent 게시 성공은 대상 앱의 실제 텍스트 삽입 확인과 다르다. UI 또는 빌드 성공으로 붙여넣기 성공을 판정하지 않는다.

## 수동 검수표

TextEdit 새 일반 텍스트 문서와 Safari의 일반 textarea에서 각각 실행한다. Safari 검수용 페이지는 `manual/paste-target.html`을 사용한다. 다른 앱이나 기존 문서 대신 검수용 입력창을 이용한다.

| 절차 | 기대 결과 | 결과 |
| --- | --- | --- |
| 앱 새 실행 | 호출 꺼짐, 자동 클립보드 읽기 없음 | 대기 |
| 접근성 미허용 상태에서 ⌘V | 일반 붙여넣기 유지, 가공 준비 불가 | 대기 |
| 권한 허용 후 한 번 가공 버튼 | 다음 ⌘V 대기 표시, 오류 없음 | 대기 |
| 한 번 가공 준비 후 `foo 한글 😀 foo` 복사 → ⌘V | 원문 선삽입 없이 패널 표시, 원래 앱·커서 유지 | Chrome에서 패널 표시·커서 유지 사용자 확인. 선삽입 여부는 별도 검수 |
| 한 번 처리/취소 후 다음 ⌘V | 다시 준비하지 않으면 일반 붙여넣기 | 대기 |
| 테스트 치환 → 붙여넣기 | `bar 한글 😀 bar`가 정확히 한 번 들어감, 재호출 없음 | Chrome에서 붙여넣기 성공 사용자 확인. 반복 입력·재호출 별도 검수 |
| 메뉴에서 원문 붙여넣기 | 원문이 한 번만 들어감 | 대기 |
| 결과 복사 | 결과가 클립보드에 복사됨, 외부 앱 삽입 없음 | 대기 |
| 메뉴/결과에서 Esc | 삽입·클립보드 변경 없이 닫힘 | 대기 |
| 방향키·Enter | 표시 순서대로 선택·실행 가능 | 대기 |
| 빠른 연속 ⌘V, V 키 길게 누르기 | 중복 세션·삽입·키 반복 없음 | 대기 |
| 한글·이모지·CRLF/LF·탭·앞뒤 공백·FOO 입력 | foo 치환 외 텍스트 보존 | 대기 |
| 빈/이미지 클립보드, 1 MiB 초과, NUL 포함 | 가로채지 않고 OS 기본 동작 유지 | 대기 |
| 대기 중 앱 자체 입력, ⌘⇧V 등 다른 조합 | 가로채지 않고 대기 유지 | 대기 |
| 결과 확인 도중 다른 앱으로 전환하거나 대상 종료 | 붙여넣기 거부, 결과 복사 가능 | 대기 |
| 대상 창/포커스/선택 변경 후 전달 시도 | 확인 실패 시 삽입 거부 | 대기 |
| 권한 회수 및 호출 끄기 | 새 호출을 가로채지 않음 | 대기 |
| 앱 종료 후 ⌘V | 일반 붙여넣기 유지 | 대기 |
| 화면 모서리 및 추가 모니터에서 호출 | 오버레이가 해당 화면 작업 영역 안에 표시됨 | 대기 |

실패 기록에는 앱/OS 버전, 개발 또는 release 실행 구분, 위 표의 절차와 실제 현상을 적는다. 사용자 원문이나 클립보드 내용을 진단 로그에 수집하지 않는다.

## 사용자 검수에서 수정한 문제

1. 매 ⌘V 호출의 불편: 사용자가 선택한 ‘다음 붙여넣기 한 번만 가공’으로 변경했다.
2. 원래 앱의 포커스 상실: 비활성 NSPanel로 변경했고 사용자가 커서 유지를 확인했다.
3. 패널 이동 후 Tao 종료: 원래 contentView를 보존하고 WebView 자식만 옮기도록 수정했다.
4. 패널만 닫히고 입력되지 않음: HID 키 전달과 자체 이벤트 확인 경로로 변경했다.
5. Chrome 입력 요소 조회 실패: 시스템 AX 포커스 조회, Chromium 접근성 활성화 대기, 다중 프로세스 입력 요소 처리를 보완했다. 이후 사용자가 ‘붙여넣기 성공’으로 확인했다.

## 알려진 제약과 후속 판단

- 1 MiB 초과·NUL 포함 텍스트는 이번 검증에서 가로채지 않는다. 텍스트 없는 클립보드와 보안 입력 모드도 OS 동작으로 통과시킨다.
- 이벤트 탭이 시스템에 의해 비활성화되면 자동 재활성화하지 않는다. 메인 창에서 다시 켠다. AX 권한과 이벤트 탭 생성을 각각 확인하며 입력 모니터링 권한을 무조건 요구하지 않는다.
- 이벤트 콜백의 호출 시점 클립보드 읽기도 다른 프로세스 때문에 지연될 수 있다. 타임아웃 발생과 기본 붙여넣기 회복은 실제 환경 검수 대상이다.
- 입력 요소가 즉시 조회되지 않으면 시스템 전체 AX 포커스를 조회하고 활성 애플리케이션이 대상 앱인지 검사한다. 브라우저의 입력 요소는 renderer 프로세스에 속할 수 있으므로 요소 자체의 PID가 브라우저와 같아야 한다고 요구하지 않는다. 여전히 없으면 `AXManualAccessibility`와 Chromium의 `AXEnhancedUserInterface`를 요청하고 최대 약 4초간 재조회한다. Chromium의 활성화 지연을 고려한 시간이며, 각 AX IPC 응답 대기는 별도로 제한한다. 설정을 지원하지 않는 앱은 AX 오류를 반환하며 이를 강제 우회하지 않는다. 앱 식별자·창/요소 조회 상태·붙여넣기 실패 사유를 콘솔에 출력하지 않는다. 실패 사유는 사용자 화면에서만 안내한다.
- AX 포커스 정보를 제공하지 않는 앱은 자동 삽입을 거부한다. 선택 범위가 제공되지 않는 경우 동일 요소 안의 커서 이동까지 검증할 수 없어 해당 앱을 지원 확인 대상으로 확정하지 않는다.
- PID 직접 키 전달에서는 사용자가 패널만 닫히고 입력이 없음을 확인했다. 전달 경로를 HID 이벤트 스트림으로 변경하고 자체 이벤트가 세션 탭을 지날 때 활성 PID를 다시 검사한다. 게시 후 500ms 안에 키 전달을 확인하지 못하면 실패로 표시한다. 키 전달 확인도 대상 앱의 실제 삽입 확인을 대체하지 않는다. 전달 직후 앱 내부 포커스의 비동기 변경까지 완전히 막는다고 보장하지 않는다.
- 초기 Tauri 활성 창 방식의 포커스 상실은 비활성 NSPanel로 바꾸어 사용자 확인을 받았다. 초기 패널 구현에서 원래 contentView를 제거해 Tao가 종료되는 오류도 실행 로그로 확인했다. 원래 contentView는 유지하고 WebView 자식만 패널로 옮기도록 수정했다. Spaces/전체 화면과 실제 삽입은 수정 후 재검수 대상이다.
- 이번 화면은 고정 치환 기술 검증용이며 저장 워크플로우 선택, 대체 단축키 설정, 편집기, AI는 없다.
- M1 수동 검수가 통과하면 M2(비AI 실행 엔진·편집·저장·미리보기)로 진행한다. 기본 ⌘V 흐름이 성립하지 않으면 요구사항 범위를 재합의한다.

구현 참고: [Tauri Vite 구성](https://v2.tauri.app/start/frontend/vite/), [Tauri 메인 스레드 실행 API](https://docs.rs/tauri/latest/tauri/struct.AppHandle.html), [Apple 이벤트 탭](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)). [Electron 접근성 활성화](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md), [Chromium 접근성 구현](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_application_mac.mm). 실제 빌드 API는 설치된 macOS SDK 헤더와 Cargo lockfile 기준으로 확인했다.
