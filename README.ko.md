[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · **한국어** · [中文](README.zh.md)

# Open Steps

*[영어 README](README.md)를 짧게 옮긴 것입니다. 마지막 업데이트: 2026년 9월 30일. 측정 수치, 내부 구조, 기여자 안내는 영어판에만 있습니다. AI의 도움을 받아 옮겼고, 아직 한국어 원어민이 검토하지 않았습니다. 틀린 곳이 보이면 pull request로 고쳐 주세요.*

**개발을 이끄는 사람이 개발 과정을 계속 볼 수 있게 해 주는 스킬 모음입니다. 세션, 결정, 다음 단계, 전체 그림, 모두 쉬운 말로.**

Claude Code, Codex, Cursor, Gemini CLI에서 쓰는, 쉬운 말로 된 에이전트 스킬입니다.

만든 사람: [Pavlo Kharmanskyi](https://github.com/kharmanskyi).

## 왜 만들었나

저는 엔지니어가 아닙니다. 20년 동안 제품 쪽에서 제품을 만들어 왔고, 지금 제 회사에는 개발자가 50명이 넘습니다. 그와 별개로 에이전트만 데리고, 엔지니어 없이 혼자 제품을 만들기 시작했습니다. 곧 벽에 부딪혔습니다. 에이전트는 일을 잘 해 놓고, 그 결과를 커밋 해시와 전문 용어로 설명합니다. 그래서 우리가 끝난 건지 아닌지 알 수가 없습니다. 일 자체는 문제가 없습니다. 코드를 읽지 않는 사람과 이야기하는 법을 아무도 에이전트에게 가르치지 않았을 뿐입니다.

이 팩이 그것을 가르칩니다. 에이전트 대신 코드를 쓰거나 코드를 검토하지는 않습니다. 몇 가지 중요한 순간에 에이전트가 사용자에게 하는 말을 바꾸고, 전에는 "끝났습니다" 한마디로 넘어가던 자리에 증거를 요구합니다.

## 스킬이 하는 일

| 스킬 | 하는 일 | 켜지는 때 |
|---|---|---|
| `os-done-or-not` | 한 화면짜리 보고서와 판정: 끝났는지, 사용자가 해야 할 일이 있는지, 새로 생긴 빚이 있는지, 닫아도 되는지. "예"에는 반드시 근거가 붙습니다 | 작업이 끝났을 때, 또는 어떻게 됐는지 물을 때 |
| `os-step-by-step` | 기술을 모르는 사람도 따라갈 수 있는 번호 붙은 단계. 에이전트는 먼저 스스로 다 해 보고, 정말 사용자만 할 수 있는 일만 요청합니다 | 에이전트가 실행, 붙여넣기, 클릭, 승인, 테스트를 요청해야 할 때 |
| `os-ask-simple` | 쉬운 말로 된 질문, 나중에 드는 비용, 그리고 표시된 추천 하나 | 에이전트가 질문하거나 선택지를 제시할 때 |
| `os-what-could-go-wrong` | 결정이 이미 실패했다고 가정하고 그 이유를 거꾸로 찾습니다. 결정에 관여하지 않은 새 에이전트가 맡고, 판정은 하나로 끝냅니다 | 되돌리기 어려운 일이 합의되기 직전: 계약, 구매, 마이그레이션, 출시 |
| `os-whats-next` | 검증되어 준비된 것을 먼저 병합(merge)하고, 다음 작업 하나를 추천하며 이유를 쉬운 말로 설명합니다 | 무엇이 남았는지, 다음에 무엇을 할지 물을 때 |
| `os-check-work` | 다른 세션의 보고서를 그대로 믿지 않습니다. 주장 하나하나를 실제로 일어난 일과 대조하고, 어떻게 할지 말합니다 | 다른 세션이 끝났다고 말할 때 |
| `os-say-simple` | 어떤 글이든 사실과 나쁜 소식을 빼지 않고 쉬운 말로 다시 씁니다. 숫자를 말하면 정확히 그 개수의 요점을 줍니다 | 보고서, 댓글, 오류 메시지, 에이전트 자신의 답변 등 글이 엔지니어 말투일 때 |
| `os-big-picture` | `BIG-PICTURE.md` 파일 하나를 관리합니다: 이 제품이 무엇인지, 기능마다 어디까지 왔는지, 오래 손대지 않은 부분은 무엇인지, 대기 중인 일은 무엇인지. 이미 쓰는 이슈 트래커가 있으면 대기 목록을 티켓으로 여는 것을 제안합니다 | 프로젝트가 지금 어디쯤인지 물을 때, 또는 세션 보고서가 막 작성됐을 때 |

스킬은 에이전트에게 사용자가 쓰는 언어로 답하라고 요청합니다. 코드, 파일 이름, 명령은 영어 그대로입니다.

## 설치

**설치 전에 알아 둘 점: pull request의 검사가 모두 통과하고 리뷰가 승인되면, 이 팩은 그것을 스스로 병합(merge)합니다.** 그 전에 에이전트가 한 번 더 확인합니다. Claude Code에서는 권한 확인 없이 병합됩니다. Codex, Cursor, Gemini CLI에서는 병합 명령이 각 도구의 권한 설정을 거칩니다. 각 도구의 문서에 그렇게 나와 있습니다. 병합을 멈추는 것은 두 가지입니다. 확인을 통과하지 못한 주장, 또는 명령할 때만 병합하라는 작업 메모입니다. 명령할 때만 병합하게 하려면 상시 지침 파일에 그렇게 적어 두세요: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, 또는 Cursor에서는 프로젝트의 `AGENTS.md`.

이 팩은 Claude Code, Codex, Cursor, Gemini CLI에 설치됩니다. Claude Code에서는 플러그인이 명령 한 번으로 스킬과 두 훅을 연결합니다. Codex, Cursor, Gemini CLI에서는 복사 명령 하나로 스킬이 설치되고, 훅은 도구마다 직접 설정합니다. 도구별로 실제로 실행한 것과 문서에서 가져온 것은 [영어 README의 표](README.md#what-was-run-on-each-tool)에 있습니다.

### 먼저, 모든 도구 공통

저장소를 내려받습니다:

```bash
git clone https://github.com/kharmanskyi/open-steps.git
```

아래 명령은 모두 내려받은 폴더, 즉 이제 `open-steps/`가 들어 있는 폴더에서 실행합니다. 그 안에서 실행하지 않습니다.

네 도구 모두에서 한 가지는 손으로 추가하는 것이 좋습니다: 도구가 상시 지침으로 읽는 파일에 넣는 규칙 블록입니다. 스킬은 모델이 쓰기로 선택하는 것입니다. 훅은 그것을 상기시키고, Claude Code에서는 이 블록이 그것을 규칙으로 만듭니다. 블록을 어디에 넣는지는 아래 도구별 항목에 있습니다.

보고서는 저장소 밖 `~/.claude/open-steps/reports/<project>/`에 저장되므로 커밋에 들어가지 않습니다.

### Claude Code

플러그인으로 설치합니다:

```bash
claude plugin marketplace add ./open-steps && claude plugin install open-steps@open-steps
```

끝입니다. 스킬과 두 훅이 연결됐습니다. 무엇이 설치됐는지 확인:

```bash
claude plugin details open-steps
```

규칙 블록은 `~/.claude/CLAUDE.md`에 넣습니다. 거기서는 긴 대화에서도 살아남습니다. 명령 하나, 여러 번 실행해도 안전합니다:

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat open-steps/docs/routing-block.md >> ~/.claude/CLAUDE.md
```

나중에 플러그인만이 아니라 설치 전체를 점검하려면 Claude Code에서 `/open-steps:os-install-check`를 실행합니다. 무엇이 연결됐고 무엇이 안 됐는지 말하고, 확인할 수 없던 곳은 "확인 안 함"이라고 씁니다.

### Codex CLI, Cursor CLI, Gemini CLI

이 세 도구는 `~/.agents/skills/`에서 스킬을 읽습니다. 명령 하나로 세 도구 모두에 스킬이 설치됩니다:

```bash
mkdir -p ~/.agents/skills && cp -R open-steps/skills/os-* ~/.agents/skills/
```

규칙 블록은 도구가 상시 지침으로 읽는 파일에 넣습니다:

| 도구 | 블록을 넣는 곳 |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Cursor | 프로젝트 루트의 `AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |

파일마다 쓰는 명령은 [docs/other-agents.md](docs/other-agents.md#the-routing-block)에 있습니다 (영어). 여러 번 실행해도 안전합니다. 훅 설정도 거기에 있습니다. 도구마다 다르고, 직접 설정합니다.

설치 점검: `bash open-steps/doctor.sh`. 스킬 폴더, 규칙 블록, 찾은 도구마다의 훅 설정을 읽고, 확인할 수 없던 곳은 "확인 안 함"이라고 씁니다. 각 훅이 어떤 이벤트에 걸려 있는지는 아직 확인하지 않습니다.

## 업데이트와 제거

**Claude Code.** 업데이트: `open-steps/` 안에서 `git pull`, 그다음 `claude plugin update open-steps@open-steps`. 둘 다 필요합니다. 플러그인은 GitHub가 아니라 내려받은 폴더에서 업데이트되고, 파일은 버전 번호가 바뀔 때만 설치된 복사본으로 옮겨집니다. 제거: `claude plugin uninstall open-steps`, 그다음 `CLAUDE.md`에서 블록을 지웁니다.

**Codex CLI, Cursor CLI, Gemini CLI.** 업데이트: `open-steps/` 안에서 `git pull`, 그다음 복사 명령을 다시 실행합니다. 복사본이므로 다시 실행하기 전까지 설치된 스킬은 그대로입니다. 제거(이 단계는 아직 실행해 보지 않았습니다): `~/.agents/skills/`에서 `os-*` 폴더를 지우고, 도구의 지침 파일에서 블록을 빼고, 설정 파일(`~/.codex/config.toml`, `~/.cursor/hooks.json`, `~/.gemini/settings.json`)에서 훅 항목 두 개를 지웁니다.

## 라이선스

MIT. 공개 팩이고 기여를 환영합니다. 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md)에 있습니다 (영어).

Open Steps is an independent open-source project, not affiliated with or endorsed by the makers of the tools it runs on. Claude and Claude Code are trademarks of Anthropic. All other trademarks, including Codex, Cursor and Gemini, are the property of their respective owners.
