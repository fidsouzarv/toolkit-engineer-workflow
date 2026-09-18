# Severity Criteria

Criterios objetivos para classificar findings em CRITICAL, BLOCKING, SHOULD-FIX, NIT ou UNCERTAIN.

A escolha de severidade deve ser conservadora: na duvida entre dois niveis, escolher o MAIOR e justificar. Incerteza nunca vira aprovacao — vira UNCERTAIN com a evidencia faltante nomeada.

---

## CRITICAL

Comportamento malicioso crivel ou falha grave prontamente exploravel. Parar e conter — trust gate do parecer fica `blocked`.

Exemplos:
- Codigo com intencao suspeita (exfiltracao, backdoor, dependencia maliciosa)
- SQL injection, XSS ou RCE prontamente exploraveis
- Exposicao direta de secrets/credenciais ou PII em massa
- Perda de dados irreversivel em caminho comum

---

## BLOCKING

Incorreto, inseguro, incompativel, enganoso ou insuficientemente testado para merge.

Exemplos:
- NPE em caminho comum (nao edge case raro)
- Perda silenciosa de mensagens/eventos
- Race condition em fluxo concorrente
- Cache sem invalidacao causando dados stale
- Index ausente em coluna de query frequente em tabela que cresce
- Breaking change de contrato de API sem versionamento
- Dependencia externa nao linkada que pode quebrar em deploy
- Claim do autor demonstravelmente FALSA sobre o fix ou causa-raiz
- Bug irmao confirmado em outro modulo, mesmo padrao
- Refactor que muda comportamento sem teste de regressao
- Remocao de simbolo que ainda e referenciado em outro arquivo
- Gate local (test/lint/typecheck) falhando no head do PR (e nao na base)

---

## SHOULD-FIX

Issue limitada de qualidade, cobertura ou docs; impacto real mas nao imediato, ou com mitigacao parcial. Corrigir antes do merge quando pratico.

Exemplos:
- Vazamento de detalhes internos em mensagem de erro
- FK sem ON DELETE explicito
- Inconsistencia de schema (tamanhos de coluna, audit columns)
- `@Async` com fallback sincrono nao documentado
- Falta de validacao de tenant em consumer interno
- Reformatacao macica camuflando o fix (poluicao de diff, blame quebrado)
- Inconsistencia semantica entre fluxos similares (ex: filtros que recebem tipos diferentes)
- Falta de teste para um padrao de bug ja conhecido (>= 2 ocorrencias)
- Claim de escopo FALSA mas sem impacto runtime
- Changelog na secao/categoria errada; breaking change nao flagged

---

## NIT

Cosmetico apenas: boas praticas, completude, debito tecnico aceitavel.

Exemplos:
- `@PreUpdate` faltando (se ja setado manualmente)
- Tabela sem estrategia de purge para dados temporarios
- Colisao de idempotency key em edge case raro
- Const literal recriada a cada render (sem impacto)
- Falta de comentario WHY em codigo nao-obvio
- Nomenclatura inconsistente

---

## UNCERTAIN

Evidencia insuficiente para veredicto. Nomear explicitamente a evidencia faltante e NAO converter em aprovacao.

Exemplos:
- Claim `NAO_VERIFICAVEL` (link de PR/card faltando, "ja existia antes", "era dead code" sem prova)
- Dependencia de estado externo (feature flag, config de ambiente) nao inspecionavel
- Comportamento que so seria confirmavel rodando gate que foi `deliberately not run`

No post inline, UNCERTAIN vira pergunta especifica ao autor, nunca afirmacao.

---

## Regras de override

- Se um finding BLOCKING aparece em codigo NAO testado, eleva a prioridade no parecer (highlighted)
- Se um finding SHOULD-FIX aparece em fluxo critico (auth, pagamento, dados sensiveis), eleva para BLOCKING
- Se um finding NIT aparece varias vezes no mesmo PR, mencionar em bulk mas nao postar inline individualmente
