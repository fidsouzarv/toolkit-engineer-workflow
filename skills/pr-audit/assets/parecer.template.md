# Parecer — PR #{NUMERO} {REPO}: {TITLE}

**Autor:** {AUTOR} · **Branch:** `{HEAD}` → `{BASE}` · **Diff:** +{ADDS}/-{DELS} em {N_FILES} arquivo(s) · **{N_COMMITS} commits**

**Trust gate:** {clear | blocked by <finding>}
**Head audited:** {HEAD_SHA}
**Local gates:** {comandos e resultados | deliberately not run (motivo)}
**Hosted gates:** {resultados do statusCheckRollup e caveats de workflow}

## Veredicto curto

{1-2 linhas sobre o estado geral do PR. Cita riscos e/ou pontos a verificar.}

---

## Findings

{Em ordem de severidade. Para cada finding:
- **[SEVERITY]** `path:line` — {impacto, caminho de exploit/falha e correcao necessaria. Prefixo [CLAIM] se vier da Fase 3, [IRMAO] se vier da Fase 5.}

Severidades: CRITICAL, BLOCKING, SHOULD-FIX, NIT, UNCERTAIN.
Se nao houver findings, dizer explicitamente e declarar o escopo residual de teste/seguranca nao coberto.}

---

## Claim ledger

| Claim do autor | Evidencia independente | Veredicto |
|---|---|---|
| {claim} | {o que foi checado, path:line} | {VERIFICADO_VERDADEIRO / VERIFICADO_FALSO / NAO_VERIFICAVEL} |

---

## Pros

{Lista 3-6 itens com evidencia. SEMPRE preencher. Exemplos:
- Correcao do bug X esta objetivamente certa
- Refactor para Y simplifica o codigo
- PR description detalhada com causa-raiz
- CI verde, lint passa, SonarCloud sem novos issues
}

## Cons

{Riscos, tradeoffs e incerteza residual.}

---

## Recomendacoes

{Lista 3-6 acoes acionaveis, verbo no infinitivo:
1. {Acao concreta, com path/contexto}
2. ...
}

---

**Recommended action:** {merge as-is | adjust before merge | ask author | decline}
**Recommended fix:** {menor correcao limpa e testes}

## Resumo

{Frase final 1-2 linhas. Quantos findings por severidade, e se ha bloqueador claro para o merge.}
