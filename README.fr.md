[English](README.md) · [Español](README.es.md) · **Français** · [Русский](README.ru.md) · [Українська](README.uk.md) · [한국어](README.ko.md) · [中文](README.zh.md)

# Open Steps

*Traduction courte du [README anglais](README.md). Dernière mise à jour : 30 septembre 2026. Les mesures, le fonctionnement interne et les notes pour les contributeurs sont seulement dans la version anglaise. Traduction faite avec l'aide d'une IA, pas encore relue par un francophone natif. Si vous voyez une erreur, corrigez-la par une pull request.*

**Des compétences qui gardent le développement ouvert à la personne qui le dirige : les sessions, les décisions, les prochaines étapes, la vue d'ensemble, tout en langage clair.**

Des compétences d'agent en langage clair pour Claude Code, Codex, Cursor et Gemini CLI.

Par [Pavlo Kharmanskyi](https://github.com/kharmanskyi).

## Pourquoi ce paquet existe

Je ne suis pas ingénieur. Je construis des produits depuis vingt ans, toujours du côté produit, et mon entreprise compte aujourd'hui plus de 50 développeurs. En parallèle, j'ai commencé à construire un produit seul, avec un agent et sans ingénieurs. Très vite, j'ai heurté un mur. L'agent travaille bien, puis il me raconte ce qu'il a fait avec des identifiants de commits et du jargon, et je ne peux pas savoir si nous avons terminé. Le travail lui-même est bien fait. Simplement, personne n'a appris à l'agent à parler à quelqu'un qui ne lit pas le code.

Ce paquet le lui apprend. Il n'écrit pas de code à la place de l'agent et ne relit pas le code à votre place. Il change ce que l'agent vous dit à quelques moments importants, et il lui demande des preuves là où un « c'est fait » suffisait avant.

## Ce que font les compétences

| Compétence | Ce qu'elle fait | Quand elle se déclenche |
|---|---|---|
| `os-done-or-not` | Un rapport d'un écran avec un verdict : fait ou pas, ce qu'il faut de vous, s'il y a de nouvelles dettes, si on peut clore. Chaque « oui » vient avec sa preuve | Le travail se termine, ou vous demandez comment ça s'est passé |
| `os-step-by-step` | Des étapes numérotées qu'une personne sans formation technique peut suivre. L'agent doit d'abord tout essayer lui-même et ne demander que ce dont il a vraiment besoin de votre part | L'agent a besoin que vous exécutiez, colliez, cliquiez, approuviez ou testiez quelque chose |
| `os-ask-simple` | La question en mots simples, ce qu'elle coûtera plus tard et une recommandation clairement désignée | L'agent a une question ou des options pour vous |
| `os-what-could-go-wrong` | Part du principe que la décision a déjà échoué et cherche pourquoi. C'est un nouvel agent, qui n'a pas pris part à la décision, qui s'en charge. Se termine sur un seul verdict | Quelque chose de difficile à défaire est sur le point d'être décidé : un contrat, un achat, une migration, un lancement |
| `os-whats-next` | Fusionne (merge) ce qui est vérifié et prêt, puis recommande la tâche suivante et dit pourquoi en mots simples | Vous demandez ce qui reste ou quoi faire maintenant |
| `os-check-work` | Ne fait pas confiance au rapport d'une autre session. Vérifie chaque affirmation contre ce qui s'est vraiment passé et dit quoi en faire | Une autre session dit qu'elle a terminé |
| `os-say-simple` | Réécrit n'importe quel texte en mots simples sans perdre de faits ni de mauvaises nouvelles. Donnez-lui un nombre et vous recevez exactement autant de points | Un texte se lit comme un rapport d'ingénieur : un compte rendu, un commentaire, une erreur, la propre réponse de l'agent |
| `os-big-picture` | Tient un fichier, `BIG-PICTURE.md` : ce qu'est le produit, chaque fonction et jusqu'où elle est allée, les parties que personne ne touche plus, ce qui est en attente. Si vous utilisez déjà un gestionnaire de tâches, il propose d'y ouvrir la file en tickets | Vous demandez où en est le projet, ou un rapport de session vient d'être écrit |

Les compétences demandent à l'agent de répondre dans la langue dans laquelle vous lui parlez. Le code, les noms de fichiers et les commandes restent en anglais.

## Installation

**À savoir avant d'installer : le paquet fusionne (merge) de lui-même une pull request dont les vérifications sont au vert et la revue approuvée.** Avant cela, l'agent la vérifie une fois de plus. Sur Claude Code, la fusion se fait sans demande d'autorisation. Sur Codex, Cursor et Gemini CLI, la commande de fusion passe par les réglages d'autorisation de l'outil, d'après leur documentation. Deux choses arrêtent une fusion : une affirmation qui échoue à la vérification, ou une note sur la tâche qui dit que la fusion se fait seulement sur ordre. Si vous voulez des fusions seulement sur ordre, écrivez-le dans votre fichier d'instructions permanentes : `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` ou le `AGENTS.md` du projet sur Cursor.

Le paquet s'installe dans Claude Code, Codex, Cursor et Gemini CLI. Sur Claude Code, un plugin branche les compétences et les deux hooks en une commande. Sur Codex, Cursor et Gemini CLI, une commande de copie installe les compétences, et les hooks se règlent à la main dans chaque outil. Ce qui a été lancé sur chaque outil, et ce qui vient de sa documentation, se trouve dans le [tableau du README anglais](README.md#what-was-run-on-each-tool).

### D'abord, pour tout outil

Téléchargez le dépôt :

```bash
git clone https://github.com/kharmanskyi/open-steps.git
```

Toutes les commandes suivantes se lancent depuis le dossier où vous l'avez téléchargé, celui qui contient maintenant `open-steps/`, pas depuis l'intérieur de ce dernier.

Dans les quatre outils, une pièce vaut la peine d'être ajoutée à la main : le bloc de règles, dans le fichier que l'outil lit comme instructions permanentes. Les compétences sont quelque chose que le modèle choisit d'utiliser. Les hooks le lui rappellent ; sur Claude Code, le bloc transforme le rappel en règle. La section de chaque outil, plus bas, dit où va le bloc.

Les rapports sont enregistrés hors de vos dépôts, dans `~/.claude/open-steps/reports/<project>/`, donc ils n'entrent pas dans vos commits.

### Claude Code

Installez le paquet comme plugin :

```bash
claude plugin marketplace add ./open-steps && claude plugin install open-steps@open-steps
```

C'est tout : les compétences et les deux hooks sont branchés. Pour voir ce qui a été installé :

```bash
claude plugin details open-steps
```

Le bloc de règles va dans votre `~/.claude/CLAUDE.md`, où il survit aux longues conversations. Une commande, que vous pouvez relancer sans risque :

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat open-steps/docs/routing-block.md >> ~/.claude/CLAUDE.md
```

Plus tard, pour vérifier toute l'installation et pas seulement le plugin, tapez `/open-steps:os-install-check` dans Claude Code. Elle dit ce qui est branché et ce qui ne l'est pas, et écrit « non vérifié » là où elle n'a pas pu regarder.

### Codex CLI, Cursor CLI et Gemini CLI

Ces trois outils lisent les compétences dans `~/.agents/skills/`. Une commande les installe pour les trois :

```bash
mkdir -p ~/.agents/skills && cp -R open-steps/skills/os-* ~/.agents/skills/
```

Le bloc de règles va dans le fichier que chaque outil lit comme instructions permanentes :

| Outil | Où va le bloc |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Cursor | `AGENTS.md` à la racine du projet |
| Gemini CLI | `~/.gemini/GEMINI.md` |

La commande pour chaque fichier, que vous pouvez relancer sans risque, est dans [docs/other-agents.md](docs/other-agents.md#the-routing-block) (en anglais). Le réglage des hooks s'y trouve aussi : chaque outil a le sien, et il se fait à la main.

Pour vérifier l'installation : `bash open-steps/doctor.sh`. Il lit les dossiers de compétences, le bloc de règles et les réglages des hooks de chaque outil qu'il trouve, et écrit « non vérifié » là où il n'a pas pu regarder. Il ne vérifie pas encore sous quel événement se trouve chaque hook.

## Mettre à jour et retirer

**Claude Code.** Pour mettre à jour : `git pull` dans `open-steps/`, puis `claude plugin update open-steps@open-steps`. Les deux étapes comptent : le plugin se met à jour depuis votre dossier, pas depuis GitHub, et les fichiers n'arrivent dans la copie installée que quand le numéro de version change. Pour retirer : `claude plugin uninstall open-steps`, puis supprimez le bloc de votre `CLAUDE.md`.

**Codex CLI, Cursor CLI et Gemini CLI.** Pour mettre à jour : `git pull` dans `open-steps/`, puis relancez la commande de copie. C'est une copie, donc les compétences installées ne changent pas tant que vous ne la relancez pas. Pour retirer (ces étapes n'ont pas encore été lancées) : supprimez les dossiers `os-*` de `~/.agents/skills/`, retirez le bloc du fichier d'instructions de l'outil et les deux entrées de hooks de son fichier de réglages (`~/.codex/config.toml`, `~/.cursor/hooks.json` ou `~/.gemini/settings.json`).

## Licence

MIT. Le paquet est public et les contributions sont bienvenues : les règles sont dans [CONTRIBUTING.md](CONTRIBUTING.md) (en anglais).

Open Steps is an independent open-source project, not affiliated with or endorsed by the makers of the tools it runs on. Claude and Claude Code are trademarks of Anthropic. All other trademarks, including Codex, Cursor and Gemini, are the property of their respective owners.
