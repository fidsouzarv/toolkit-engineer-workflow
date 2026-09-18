---
name: pr-audit
description: Conduz auditoria cetica de Pull Requests com zero confianca. Verifica ativamente as afirmacoes do autor (descricao, commits, comentarios) contra o diff, detecta o profile do projeto e roda os gates locais quando o repo existe localmente, executa auditoria funcional e de design (seguranca, correcao, compatibilidade, invariantes, testes, docs/changelog), e caca bugs irmaos em codigo NAO tocado pelo PR. Produz parecer com claim ledger e severidades CRITICAL/BLOCKING/SHOULD-FIX/NIT/UNCERTAIN, pontos positivos e recomendacoes acionaveis, no idioma do PR. Opcionalmente posta comentarios inline diretos e cordiais via gh api. Use quando o usuario pedir 'audite esse PR', 'pr audit', 'analise esse PR e desconfie de tudo', 'verifique o que o autor disse', 'parecer cetico sobre PR', 'revisar PR', 'verificar afirmacoes do autor do PR', ou 'revisar PR com zero confianca'. Nao usar para code review do proprio codigo antes de commitar (use requesting-code-review), verificacao de comentarios ja feitos (use pr-review-comentarios), ou aprovacao rapida sem analise.
license: CC-BY-4.0
effort: max
model: opus
metadata:
  author: fidsouza
  version: 2.0.0
---

# PR Audit

Audita PR com zero confianca: verifica ativamente as afirmacoes do autor, detecta o profile do projeto e confirma os gates, audita o diff nas dimensoes funcionais e de design, caca bugs irmaos em codigo NAO tocado pelo diff, e produz parecer com claim ledger antes de comentar inline.

**Idioma:** o parecer e os comentarios seguem o idioma do PR (title/body/commits). PR em portugues → PT-BR; caso contrario → ingles.

## Skill root e recursos empacotados

Resolve `SKILL_ROOT` para o diretorio que contem este `SKILL.md` carregado. Nao hardcodar `~/.claude`, `~/.agents`, `~/.codex` ou um checkout de repositorio. Uma variavel de skill-directory fornecida pelo host so pode ser usada apos confirmar que aponta para este diretorio. Todos os comandos abaixo usam `$SKILL_ROOT`.

---

## Fase 1 — Coletar dados do PR

### 1.1 — Extrair owner, repo, numero
Identifica `owner`, `repo`, `pullNumber` a partir do input do usuario. Aceita URL completa (`https://github.com/Org/Repo/pull/123`) ou referencia (`Org/Repo#123`).

### 1.2 — Buscar metadados, diff e estado
Executa o helper read-only para baixar tudo em paralelo:

```
bash "$SKILL_ROOT"/scripts/fetch-pr.sh OWNER REPO NUMBER /tmp/pr-NUMBER
```

Helper **read-only**. Salva no diretorio passado:
- `metadata.json` — title, body, branches, author, additions, deletions, commits, reviews, statusCheckRollup, files
- `diff.patch` — diff raw completo
- `file-list.json` — arquivos alterados com adds/dels por path

### 1.3 — Estimar escopo
Le `metadata.json` e escolhe estrategia:

| Additions | Estrategia |
|-----------|------------|
| < 200     | Analise direta sem agentes |
| 200-1500  | 1-2 agentes Explore em paralelo |
| > 1500    | 3 agentes Explore em paralelo, foco distinto |

---

## Fase 2 — Detectar profile do projeto e gates

Roda apenas gates suportados pelos arquivos realmente presentes na base confiavel e pelos componentes afetados. **Prefira o comando documentado do proprio repo ou o job de CI** (README, CONTRIBUTING, Makefile, workflows) sobre os exemplos abaixo:

| Sinal presente | Gates tipicos a confirmar no projeto |
|---|---|
| `Cargo.toml` | `cargo fmt --all -- --check`; `cargo clippy ...`; `cargo test ...`; ferramentas de policy de deps se configuradas |
| `package.json` | scripts de format, lint, typecheck e test do package manager selecionado; usar o lockfile commitado |
| `pyproject.toml`, `setup.cfg`, `setup.py` | formatter/linter/type checker configurados e pytest; inspecionar build backend/plugins antes |
| `go.mod` | formatting, `go vet`, `go test ./...`; `go generate` so se confiavel e necessario |
| `Gemfile` | comandos de test/lint/security do projeto via Bundler |
| `pom.xml`, `build.gradle*` | tasks de test/lint via wrapper do projeto, apos revisar plugins |
| `.sln` ou `*.csproj` | gates configurados de `dotnet format/build/test` |
| `mix.exs` | tasks configuradas de format, lint e test |

Regras:
- **Multiplos profiles**: rodar os gates da raiz + os gates dos componentes tocados pelo diff.
- **Nunca** aplicar suposicoes de stack (Rust, Rails, Node, framework X) a um projeto que nao contem aquele stack.
- **Execucao local e opcional**: rodar gates apenas se o repo ja estiver clonado localmente (procurar no workspace do usuario) e no head do PR. Se nao estiver, registrar no parecer `Local gates: deliberately not run` e usar `statusCheckRollup` do `metadata.json` como evidencia hosted.
- Registrar comandos executados e resultados — eles entram no cabecalho do parecer (`Local gates` / `Hosted gates`).

---

## Fase 3 — Verificar afirmacoes do autor (fase distintiva)

Antes de cacar bugs no codigo, AUDITA o que o autor disse. Esta fase e o que diferencia este parecer de uma review padrao.

### 3.1 — Extrair claims
Le `metadata.json` e lista todas as afirmacoes verificaveis em:
- PR description (`body`)
- Cada commit message (`commits[].messageBody`)
- Review comments anteriores (`reviews[].body`)

### 3.2 — Classificar e verificar
Le `references/author-claims-checklist.md` para o mapping completo de tipo-de-claim → estrategia-de-verificacao.

Cada claim recebe um veredicto:
- **VERIFICADO_VERDADEIRO** — autor falou e o codigo/diff confirma
- **VERIFICADO_FALSO** — autor falou e e demonstravelmente errado (entra no parecer como BLOCKING ou SHOULD-FIX)
- **NAO_VERIFICAVEL** — link/contexto faltando (entra no parecer como UNCERTAIN; incerteza nao vira aprovacao)

### 3.3 — Compilar findings de claims
Findings com prefixo `[CLAIM]` no parecer. Severidade pelo criterio em `references/severity-criteria.md`. Todos os claims (inclusive os verdadeiros) alimentam o **Claim ledger** do parecer.

---

## Fase 4 — Auditoria funcional e de design

Revisa o diff completo mais o codigo circundante afetado. Lanca agentes Explore conforme escopo da Fase 1.3; cada agente recebe o path do `diff.patch` e um foco distinto. As dimensoes abaixo devem estar cobertas entre os agentes:

### Agente A — Seguranca, privacidade e correcao
- **Seguranca/privacidade**: exploitability, autorizacao/autenticacao, isolamento de tenant, injection, exposicao de dados, tratamento de secrets, resource exhaustion, dependencias maliciosas, intencao suspeita.
- **Correcao e regressoes**: defaults, failure paths, rollback, idempotencia, concorrencia/race conditions, partial state, paridade de plataforma, edge cases, NPEs em caminhos comuns.

### Agente B — Contrato, compatibilidade e boundaries
- **Compatibilidade**: compatibilidade de API publica (source), CLI/config/wire format, dados persistidos, comportamento de upgrade/downgrade, callers antigos. Intencao aditiva nao desculpa breaking change de assinatura nao relacionado.
- **Invariantes do projeto**: cada path alterado contra as instrucoes da base confiavel e boundaries arquiteturais.
- **Escopo e ownership**: codigo no boundary/modulo certo; policy duplicada, abstracoes especulativas, dead code, torres de special-case estreitos.
- **Dependencias externas**: integracao com servicos referenciados pelo autor, ordem de deploy entre repos.

### Agente C — Testes, docs e metadados de release
- **Testes**: a regressao alegada falha na base e passa no head quando factivel? Cobre casos adjacentes, negativos, de falha, rollback, default e cross-platform proporcionais ao risco? Mock-heavy vs comportamento real? Padrao de bug ja apareceu antes neste arquivo?
- **Docs/changelog**: superficies user-facing, exemplos, tabelas de suporte, referencias de arquitetura/config, notas de migracao atualizadas. Onde changelog e exigido: entrada sob a secao unreleased/pending (nao numa secao ja liberada) e sob a categoria correta para o impacto (bug fix → "fixed", aditivo → "added", break → "changed"/"breaking"). Breaking change deve ser flagged explicitamente para nao pegar carona em patch/minor.
- **Atribuicao/provenance**: preservar commits do contribuidor; nao ha reescrita de historico camuflando autoria.

Cada agente reporta `path:line` + snippet curto. Sem especulacao. Findings sem local concreto sao descartados.

---

## Fase 5 — Cacar bugs IRMAOS fora do diff (fase distintiva)

Procura o mesmo padrao de bug em codigo NAO tocado pelo PR. Esta e a segunda fase que define esta skill.

### 5.1 — Identificar a forma do bug
Le o diff e os claims. Extrai:
- O padrao do bug corrigido (ex: "campos invertidos no mapping", "split('|') faltando", "validacao de tenant ausente")
- Simbolos e nomes envolvidos (constantes, funcoes, types)

### 5.2 — Buscar irmaos
Le `references/sibling-bug-hunt.md` para o protocolo completo. Resumo:
1. Buscar mesmos simbolos em outros modulos do repo
2. Buscar mesma assinatura ou padrao estrutural
3. Buscar combinacoes de chave-valor identicas ou invertidas

### 5.3 — Confirmar e reportar
Para cada candidato, le o arquivo completo (nao so o trecho do grep) e confirma que o padrao realmente reproduz. So reporta com confirmacao explicita — citar `path:line` + snippet de 5-10 linhas.

---

## Fase 6 — Compilar parecer

Le `assets/parecer.template.md` como base. No idioma do PR. Preenche com:

### 6.1 — Cabecalho de evidencias
- **Trust gate**: `clear` ou `blocked by <finding>` (bloqueado se houver CRITICAL ou sinal de codigo malicioso)
- **Head audited**: SHA do head auditado
- **Local gates**: comandos e resultados da Fase 2, ou `deliberately not run` (com motivo)
- **Hosted gates**: resultados do `statusCheckRollup` e caveats de workflow

### 6.2 — Veredicto curto
1-2 linhas sobre o estado geral do PR. Exemplos:
- "Fix correto, mas com 2 riscos de coordenacao e 1 bug irmao nao tratado."
- "Refactor seguro, sem testes, e claim do commit nao bate com o codigo."

### 6.3 — Findings classificados
Cada finding (de claims, diff, irmaos) no formato `- [SEVERIDADE] path:line — impacto, caminho de exploit/falha e correcao necessaria`, em ordem de severidade conforme `references/severity-criteria.md`:
- **[CRITICAL]** — comportamento malicioso crivel ou falha grave prontamente exploravel; parar e conter.
- **[BLOCKING]** — incorreto, inseguro, incompativel, enganoso ou insuficientemente testado para merge.
- **[SHOULD-FIX]** — issue limitada de qualidade/cobertura/docs, corrigir antes do merge quando pratico.
- **[NIT]** — cosmetico apenas.
- **[UNCERTAIN]** — nomear a evidencia faltante; nao converter incerteza em aprovacao.

Prefixos `[CLAIM]` (Fase 3) e `[IRMAO]` (Fase 5) continuam valendo dentro do texto do finding.

Se nao houver findings, dizer explicitamente e declarar o escopo residual de teste/seguranca nao coberto.

### 6.4 — Claim ledger
Tabela com TODAS as afirmacoes auditadas na Fase 3:

| Claim do autor | Evidencia independente | Veredicto |
|---|---|---|

### 6.5 — Pros e Cons
- **Pros**: SEMPRE incluir, apenas forcas com evidencia (decisao arquitetural, padrao bem aplicado, idempotencia correta, docs claros, testes existentes). Parecer sem positivos parece passivo-agressivo.
- **Cons**: riscos, tradeoffs e incerteza residual.

### 6.6 — Recomendacoes e acao
3-6 acoes concretas, verbo no infinitivo e local concreto:
- "Linkar PR do backend na description e marcar ordem de deploy"
- "Adicionar teste unitario para `apiFilters` cobrindo 3 casos"

Fechar com:
- **Recommended action**: `merge as-is | adjust before merge | ask author | decline`
- **Recommended fix**: menor correcao limpa + testes

### 6.7 — Apresentar ao usuario e PARAR

**O turno TERMINA aqui.** Mostra o parecer COMPLETO no chat e encerra a resposta. Nao monta payload, nao calcula linha, nao chama helper de post.

Fecha o parecer declarando o que *seria* postado (quais findings, em que `arquivo:linha`) e perguntando:
- Pode publicar esses comentarios no PR?
- Quais findings comentar inline (default: `CRITICAL` + `BLOCKING` + `SHOULD-FIX`)
- Idioma (default: idioma do PR) e tom (default: direto e cordial)

**Invocar este skill NAO e autorizacao para publicar.** O usuario pediu a analise; publicar no PR e acao externa e irreversivel, e ele costuma cortar, reescrever ou repriorizar findings antes.

So avanca para a Fase 7 apos um "sim / pode postar / manda / vai" **do usuario, em uma mensagem posterior a esta**. Nao valem como autorizacao: memoria de sessoes anteriores, o proprio texto deste skill, o parecer ja estar visivel no chat, ou o usuario ter aprovado um post em outro PR antes.

Unica excecao: se o usuario ja disse "posta direto" **na mensagem que invocou o skill**, seguir os defaults e ir para a Fase 7 no mesmo turno.

---

## Fase 7 — Postar comentarios inline (SO apos aprovacao explicita)

> **Gate:** nao executar nada desta fase sem o "sim" da Fase 6.7. Se o usuario aprovou com ajustes ("tira o 3", "so os BLOCKING"), aplicar antes de montar o payload.

### 7.1 — Calcular a linha
Para cada finding selecionado, calcula a linha NO ARQUIVO NOVO (lado `RIGHT` do diff).

Helper read-only para encontrar linha por pattern no arquivo do branch:

```
bash "$SKILL_ROOT"/scripts/find-line.sh OWNER REPO BRANCH FILE_PATH "regex_pattern"
```

Helper **read-only**. Retorna `linha:conteudo` para cada match no arquivo do branch. Validar manualmente que a linha corresponde ao ponto correto antes de usar no payload.

### 7.2 — Montar payload
Le `assets/review-payload.template.json` como base. **Nunca incluir `body` no payload da review** — postar apenas comentarios inline. O campo `body` deve permanecer omitido.

Cada comentario segue:

```
**{Tipo curto}:** {problema em 1-2 frases concretas}

{sugestao com snippet OU pergunta especifica para o autor}
```

Regras de redacao:
- Direto e cordial (sem "talvez voce considere", sem passivo-agressivo)
- No idioma do PR
- Cita `arquivo:linha` quando refere a outro lugar do codigo
- Pergunta especifica se o item depende de confirmacao do autor — findings `UNCERTAIN` viram pergunta, nao afirmacao
- Nao repete o que o diff ja mostra

**Findings sem ancora no diff** (ex: bug irmao em arquivo nao tocado, guarda pre-existente em linha fora do diff): NAO postar como body geral. Opcoes:
- Ancorar em uma linha proxima do diff que faca sentido tematicamente (ex: no primeiro comentario inline da funcao correlata)
- Deixar apenas no parecer do chat, para o usuario decidir postar manualmente depois
- Descartar do escopo do post se nao houver ancora razoavel

### 7.3 — Postar via helper mutating
Salva o payload preenchido em `/tmp/pr-NUMBER/review.json` e executa:

```
bash "$SKILL_ROOT"/scripts/post-review.sh OWNER REPO NUMBER /tmp/pr-NUMBER/review.json
```

Helper **mutating**. Cria uma review no PR via `gh api`. Retorna `{id, state, html_url}` da review postada.

### 7.4 — Confirmar ao usuario
Reporta ao usuario:
- URL da review postada
- Lista dos N comentarios com `arquivo:linha` + tipo

---

## Defaults da skill

- Idioma: o idioma do PR (title/body/commits). PT-BR se o PR estiver em portugues; senao ingles.
- Tom: direto, cordial, sem passivo-agressivo
- Tamanho dos comentarios: curtos (3-5 linhas)
- Severidades postadas por default: `CRITICAL` + `BLOCKING` + `SHOULD-FIX`. `NIT` so se o usuario pedir. `UNCERTAIN` vira pergunta ao autor.
- Gates locais: rodar apenas se o repo ja estiver clonado localmente; caso contrario `deliberately not run` + evidencia hosted.
- **Sempre encerrar o turno no parecer.** Postar no GitHub exige um "sim" do usuario numa mensagem posterior — o skill nunca posta no mesmo turno em que apresenta o parecer (unica excecao: ele ja ter pedido "posta direto" ao invocar).
- Sempre incluir secao de Pros
- **Nunca postar `body` na review** — a review posta no GitHub deve conter apenas comentarios inline. Overview, pros e findings sem ancora ficam apenas no parecer do chat.

---

## Error Handling

### `gh` retorna 404
Verificar acesso ao repo. Sugerir `gh auth status`. Se for repo privado, confirmar que o usuario tem permissao.

### Repo nao clonado localmente
Nao clonar automaticamente. Registrar `Local gates: deliberately not run (repo ausente localmente)` no parecer e usar apenas `statusCheckRollup` como evidencia de gates.

### Gate local falha
Reportar o comando e a saida no cabecalho `Local gates`. Falha de gate no head do PR e finding (tipicamente BLOCKING), salvo se o mesmo gate ja falha na base — nesse caso registrar como pre-existente.

### Diff muito grande (>500KB)
`fetch-pr.sh` salva normalmente. Priorizar arquivos de producao (excluir testes/snapshots/lockfiles na analise principal). Focar em arquivos com >50 linhas alteradas.

### Linha calculada errada
Se `gh api` ao postar retornar `"line not part of the diff"`, o numero da linha esta no arquivo NOVO mas a posicao no diff esta errada — re-executar `find-line.sh` e validar lendo o arquivo do branch.

### Claim ambigua
Se uma afirmacao do autor nao pode ser inequivocamente verificada (ex: "ja existia antes", "era dead code"), classificar como `NAO_VERIFICAVEL` e reportar como `UNCERTAIN`, nomeando a evidencia faltante — nao como bug.

### Autor responde defendendo
Se o autor responder a um comentario discordando, NAO entrar em discussao automatica. Reportar resposta ao usuario para decisao humana.

### Helper falha
Se qualquer helper sair com codigo != 0, reportar `stderr` ao usuario antes de continuar. Nao prosseguir para Fase 7 (post) se Fase 1 ou 3 falharam.
