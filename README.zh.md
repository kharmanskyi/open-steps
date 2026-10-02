[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [한국어](README.ko.md) · **中文**

# Open Steps

*[英文 README](README.md) 的简短译本，最后更新于 2026 年 9 月 30 日。测量数据、内部结构和贡献者说明只在英文版里。翻译借助了 AI，尚未经母语者审校。看到翻译有误，欢迎用 pull request 修正。*

**一组技能，让主导开发的人始终看得见开发过程：会话、决策、下一步、全局，全部用通俗易懂的语言。**

用通俗语言说话的智能体技能，适用于 Claude Code、Codex、Cursor 和 Gemini CLI。

作者：[Pavlo Kharmanskyi](https://github.com/kharmanskyi)。

## 为什么做这个

我不是工程师。二十年来我一直从产品这一侧做产品，现在我的公司有 50 多名开发者。除此之外，我开始只带着一个智能体、不靠工程师自己做产品。很快就撞上了一堵墙。智能体活干得不错，然后用提交哈希和术语向我汇报，我判断不出我们做完了没有。活本身没问题。只是从来没人教过智能体怎么跟一个不读代码的人说话。

这个技能包就是教它这件事。它不替智能体写代码，也不替它审代码。它只在几个关键时刻改变智能体对你说的话，并在过去一句"做完了"就算过关的地方要求证据。

## 各个技能做什么

| 技能 | 做什么 | 什么时候触发 |
|---|---|---|
| `os-done-or-not` | 一屏汇报加结论：做完没有、需要你做什么、有没有新的欠账、能不能收工。每个"是"都要给出依据 | 工作收尾时，或你问进展如何时 |
| `os-step-by-step` | 不懂技术的人也能照做的分步说明。智能体必须先自己把能做的都做完，只请你做真正非你不可的事 | 智能体需要你运行、粘贴、点击、批准或测试什么东西时 |
| `os-ask-simple` | 用通俗的话提问，说明以后的代价，并给出一个标明的建议 | 智能体有问题或有选项要问你时 |
| `os-what-could-go-wrong` | 假定这个决定已经失败，倒推原因。由一个没参与决策的新智能体来做，最后只给一个结论 | 即将敲定一件难以回头的事：合同、采购、迁移、上线 |
| `os-whats-next` | 先把已验证、已就绪的改动合并（merge），再推荐下一项任务并用通俗的话说明原因 | 你问还剩什么、接下来做什么时 |
| `os-check-work` | 不轻信另一个会话的汇报。把每一条说法与实际发生的事核对，然后说该怎么办 | 另一个会话说它做完了时 |
| `os-say-simple` | 把任何文字改写成通俗易懂的话，不丢事实，也不丢坏消息。给它一个数字，它就给你恰好那么多条要点 | 任何读起来像工程师写的文字：汇报、评论、报错、智能体自己的回答 |
| `os-big-picture` | 维护一个 `BIG-PICTURE.md` 文件：产品是什么、每个功能做到哪一步、哪些部分很久没人动、排队的有什么。如果你已经在用任务跟踪器，会提议把排队事项开成工单 | 你问项目现在到哪了，或刚写完一份会话汇报时 |

这些技能要求智能体用你跟它说话的语言回答。代码、文件名和命令保持英文。

## 安装

**安装前要知道：如果一个 pull request 的检查全部通过、评审已经批准，这个技能包会自己把它合并（merge）。** 合并前，智能体会再核实一次。在 Claude Code 上，合并不会弹出权限确认。据这些工具的文档，在 Codex、Cursor 和 Gemini CLI 上，合并命令要经过该工具自己的权限设置。有两种情况会阻止合并：某条说法没有通过核实，或者任务上注明只在收到指令时合并。如果你希望只在你下指令时才合并，把这一点写进常驻指令文件：`~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.gemini/GEMINI.md`，或 Cursor 上项目里的 `AGENTS.md`。

这个技能包可以装进 Claude Code、Codex、Cursor 和 Gemini CLI。在 Claude Code 上，一个插件用一条命令接好技能和两个钩子。在 Codex、Cursor 和 Gemini CLI 上，一条复制命令装好技能，钩子要在每个工具里手动设置。每个工具上实际运行过什么、哪些来自它的文档，见[英文 README 里的表格](README.md#what-was-run-on-each-tool)。

### 先做这一步，任何工具都一样

下载仓库：

```bash
git clone https://github.com/kharmanskyi/open-steps.git
```

下面所有命令都在你下载到的那个文件夹里运行，也就是现在包含 `open-steps/` 的那个文件夹，而不是在它内部。

四个工具都值得手动加一样东西：一段规则，放进该工具当作常驻指令读取的文件。技能是模型自己选择去用的东西。钩子会提醒它，在 Claude Code 上这一段则把提醒变成规则。每个工具放在哪里，见下面各自的小节。

汇报保存在你的仓库之外，在 `~/.claude/open-steps/reports/<project>/`，所以不会进入提交。

### Claude Code

作为插件安装：

```bash
claude plugin marketplace add ./open-steps && claude plugin install open-steps@open-steps
```

这就完成了：技能和两个钩子都已接好。看看装了什么：

```bash
claude plugin details open-steps
```

这段规则放进你自己的 `~/.claude/CLAUDE.md`，在长对话中也不会丢。执行一条命令，重复执行也安全：

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat open-steps/docs/routing-block.md >> ~/.claude/CLAUDE.md
```

之后想检查整个安装而不只是插件，在 Claude Code 里运行 `/open-steps:os-install-check`。它会说哪些接好了、哪些没有，看不到的地方就写"未检查"。

### Codex CLI、Cursor CLI 和 Gemini CLI

这三个工具从 `~/.agents/skills/` 读取技能。一条命令就为三个工具都装好技能：

```bash
mkdir -p ~/.agents/skills && cp -R open-steps/skills/os-* ~/.agents/skills/
```

这段规则放进该工具当作常驻指令读取的文件：

| 工具 | 规则放在哪里 |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Cursor | 项目根目录的 `AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |

每个文件对应的命令见 [docs/other-agents.md](docs/other-agents.md#the-routing-block)（英文），重复执行也安全。钩子的设置也在那里：每个工具各不相同，需要手动设置。

检查安装：运行 `bash open-steps/doctor.sh`。它会读取技能文件夹、规则段落和它找到的每个工具的钩子设置，看不到的地方就写"未检查"。它暂时还不检查每个钩子挂在哪个事件上。

## 更新与卸载

**Claude Code**：更新时，在 `open-steps/` 里运行 `git pull`，然后运行 `claude plugin update open-steps@open-steps`。两步都要：插件从你的文件夹更新，不是从 GitHub；而且只有版本号变了，文件才会进入已安装的副本。卸载时，运行 `claude plugin uninstall open-steps`，再把那一段从 `CLAUDE.md` 里删掉。

**Codex CLI、Cursor CLI 和 Gemini CLI**：更新时，在 `open-steps/` 里运行 `git pull`，然后重新运行复制命令。这是复制，所以在你重新运行之前，已安装的技能不会变。卸载时（这些步骤还没有实际运行过），从 `~/.agents/skills/` 删掉 `os-*` 文件夹，从该工具的指令文件里删掉那一段，再从它的设置文件（`~/.codex/config.toml`、`~/.cursor/hooks.json` 或 `~/.gemini/settings.json`）里删掉两条钩子设置。

## 许可

MIT。这是公开的技能包，欢迎贡献：规则见 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。

Open Steps is an independent open-source project, not affiliated with or endorsed by the makers of the tools it runs on. Claude and Claude Code are trademarks of Anthropic. All other trademarks, including Codex, Cursor and Gemini, are the property of their respective owners.
