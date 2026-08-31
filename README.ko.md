# CalendarCountdown · 캘린더 카운트다운

> Apple 캘린더를 단일 진실 공급원으로 사용하고 사용자, 위젯, AI 에이전트에 명확하고 이식 가능한 카운트다운 기능을 제공하는 네이티브 macOS 중요 날짜 추적기입니다.

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## 스크린샷

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="CalendarCountdown 메인 창 데모">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="CalendarCountdown 데스크톱 위젯 데모">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="CalendarCountdown 메뉴 막대 데모">
</p>

> 이미지의 캘린더, 인물과 날짜는 모두 가상의 데모 데이터이며 실제 사용자 정보는 포함하지 않습니다.

## 프로젝트 소개

CalendarCountdown은 또 하나의 캘린더 데이터베이스가 아닙니다. 계정, 캘린더, 이벤트와 색상은 계속 Apple 캘린더에서 관리됩니다. 이 프로젝트는 EventKit을 통해 사용자가 허용한 캘린더를 읽고 쓰며, 중요한 날짜를 항상 확인하고 계산하고 내보내고 자동화에서 사용할 수 있도록 합니다.

## 핵심 기능

- 허용된 Apple 캘린더를 읽으면서 기존 계정, 분류와 색상을 유지합니다.
- 생일, 기념일, 공휴일과 반복되지 않는 중요 날짜를 추적합니다.
- 양력과 중국 음력의 연간 규칙, 윤달과 짧은 음력 월의 보정 정책을 지원합니다.
- 시스템의 로컬 캘린더로 ‘오늘’, ‘내일’과 남은 일수를 계산합니다.
- 네이티브 macOS 앱, 메뉴 막대 보기와 WidgetKit 데스크톱 위젯을 제공합니다.
- 일반 이벤트, 양력 생일과 음력 생일을 명시적으로 선택한 Apple 캘린더에 추가합니다.
- 앱에서 현재 추적 중인 모든 중요 날짜를 한 번에 내보냅니다.
- Apple Silicon과 Intel Mac을 모두 지원하는 Universal Binary입니다(macOS 14 이상).

## AI 에이전트에 적합한 설계

`calcount`는 에이전트의 셸 도구로 직접 노출할 수 있는 로컬 CLI입니다. 모든 구조화 명령은 대화형 문구 없이 JSON을 출력하며, 명확한 종료 코드로 사용법 오류, 캘린더 권한 부족과 실행 오류를 구분합니다.

에이전트 친화적 특성:

- **예측 가능한 읽기:** 캘린더 목록, 이벤트 검색, 다음 카운트다운과 추적 인덱스를 조회합니다.
- **안정적인 JSON 봉투:** 성공은 `{ "ok": true, "data": ... }`, 실패는 `{ "ok": false, "error": { "code": ..., "message": ... } }` 형식입니다.
- **검토 가능한 쓰기:** 쓰기 작업은 Apple 캘린더를 명시해야 하며, 일괄 가져오기는 `--dry-run`으로 미리 확인할 수 있습니다.
- **멱등 가져오기:** `externalId`로 에이전트 재시도 시 중복 생성을 방지합니다.
- **이식 가능한 문맥:** `tracked-events.json`에 시작 연도, 역법, 월일, 반복 규칙, 다음 발생일과 Apple 캘린더 참조를 보존합니다.
- **로컬 우선:** 서버나 클라우드 캘린더 복제본이 필요 없으며 현재 Mac에서 허용된 EventKit 데이터만 사용합니다.

자주 쓰는 읽기 및 내보내기 명령:

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

에이전트는 `jq`로 결과를 바로 처리할 수 있습니다:

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

데이터를 쓰기 전에 일괄 가져오기를 미리 확인합니다:

```bash
./calcount import /path/to/import.json --dry-run
```

현재 `calcount`가 제공하는 것은 로컬 CLI 계약입니다. MCP 서버나 원격 API를 구현했다고 주장하지 않지만, 셸 도구 호출을 지원하는 모든 에이전트 프레임워크에서 래핑할 수 있습니다.

## 추적 목록 JSON

이벤트 내용의 단일 진실 공급원은 항상 Apple 캘린더입니다. `tracked-events.json`은 두 번째 캘린더 데이터베이스가 아니라 현재 표시되는 추적 항목의 버전 관리 및 내보내기 가능한 인덱스입니다.

각 레코드는 다음을 포함합니다:

- 안정적인 UUID, 제목과 유형(생일, 기념일, 중요 날짜 또는 기타).
- 시작 연도, 월, 일과 양력/음력 표시.
- 반복 주기, 반복 역법과 음력 경계 정책.
- 다음 발생일, 시간, 시간대와 종일 여부.
- Apple 캘린더 원본, 캘린더, 색상과 재연결용 식별자.
- 추적 모드, 추적 시작 시각과 고정 상태.

전체 익명 예시는 [tracked-events.example.json](Documentation/tracked-events.example.json)을 참고하세요.

## 설치

현재 버전: **1.0.0**

1. [GitHub Releases에서 CalendarCountdown-1.0.0-macos-universal.dmg를 다운로드](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.0/CalendarCountdown-1.0.0-macos-universal.dmg)합니다.
2. CalendarCountdown을 Applications로 드래그합니다.
3. 앱을 실행하고 Apple 캘린더 전체 접근 권한을 허용합니다.

1.0.0 빌드는 현재 ad-hoc 서명 상태이며 Apple Developer ID 서명이나 공증은 받지 않았습니다. 처음 실행할 때 Finder에서 Control-클릭한 후 ‘열기’를 선택해야 할 수 있습니다.

## 소스에서 빌드

macOS 14 이상, Xcode와 [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 필요합니다.

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## 데이터 및 개인정보 보호 경계

- 캘린더 이벤트는 Apple 캘린더에 저장되며 프로젝트 자체의 클라우드 캘린더 서비스는 없습니다.
- 추적 선택과 `tracked-events.json`은 표시와 사용자가 요청한 내보내기를 위해 Mac에 저장됩니다.
- 쓰기는 사용자가 명시적으로 선택한 Apple 캘린더에만 적용됩니다.
- 실제 사용자의 기념일 파일은 `.gitignore`로 제외되며 공개 저장소나 릴리스에 포함하지 않습니다.

## 현재 범위

- 현재 macOS를 지원합니다. iPhone 앱, iPhone 위젯과 CloudKit 규칙 동기화는 향후 범위입니다.
- CalDAV 서버가 아니며 Apple 캘린더의 계정 및 분류 체계를 복제하지 않습니다.
- 자세한 제품 및 데이터 계약은 [Documentation/PRODUCT.md](Documentation/PRODUCT.md)를 참고하세요.

## 저장소 구조

- `Source/`: Swift 소스, XcodeGen 설정, 테스트와 빌드 스크립트.
- `Documentation/`: 제품 계약, 설치 안내와 익명 JSON 예시.
- `Releases/1.0.0/`: 릴리스 노트와 SHA-256 체크섬. DMG는 GitHub Releases에서 배포합니다.

## 라이선스

이 프로젝트는 [MIT License](LICENSE)로 배포됩니다.
