# Author Claims Checklist

Mapping de tipo-de-claim → estrategia-de-verificacao. Usado na Fase 2.

Para cada item na PR description, em cada commit message e em comentarios de review do autor, classificar conforme abaixo e aplicar a verificacao indicada.

---

## 1. Claim de causa-raiz ("o bug acontecia porque...")

**Como verificar:**
- Reproduzir o raciocinio lendo o codigo ANTERIOR (lado esquerdo do diff)
- Confirmar que o comportamento descrito realmente decorre do codigo antigo
- Sinal de alarme: explicacao plausivel mas que nao bate exatamente com o que o codigo fazia

**Veredicto FALSO se:** o codigo antigo nao se comportava como descrito.

---

## 2. Claim de fix ("agora corrige X")

**Como verificar:**
- Ler o codigo NOVO (lado direito do diff)
- Mentalmente executar a entrada problema descrita
- Confirmar que o caminho realmente leva ao resultado correto

**Veredicto FALSO se:** o codigo novo ainda tem o mesmo bug em algum caminho, mesmo que disfarcado.

---

## 3. Claim de escopo ("so altera X, nao mexe em Y")

**Como verificar:**
- Listar todos os arquivos alterados em `file-list.json`
- Listar todos os simbolos exportados/publicos modificados
- Comparar com o escopo declarado

**Veredicto FALSO se:** o diff toca arquivos ou simbolos publicos nao mencionados.

---

## 4. Claim de dependencia externa ("backend ja foi atualizado", "PR X no outro repo")

**Como verificar:**
- Procurar link explicito (URL, numero do PR, tag)
- Se nao houver link: `NAO_VERIFICAVEL` automatico, reportar como risco de coordenacao
- Se houver link: tentar verificar estado (se tem acesso ao repo via `gh`)

**Veredicto NAO_VERIFICAVEL e BLOCKING se:** falta link e o deploy do PR depende do estado externo.

---

## 5. Claim de remocao de dead code ("removi X que nao era usado")

**Como verificar:**
- Buscar referencias ao simbolo removido em TODO o repo (grep por nome exato)
- Se houver match: BLOCKING, possivel break de import/runtime

**Veredicto FALSO se:** o simbolo ainda e referenciado em qualquer arquivo nao removido pelo diff.

---

## 6. Claim de comportamento equivalente ("refactor sem mudanca de comportamento")

**Como verificar:**
- Comparar input/output equivalentes do codigo antigo vs novo
- Atencao especial a: ordem de operacoes, early returns, default values, error handling
- Sinal de alarme: o autor adicionou um `if` novo que muda fluxo

**Veredicto FALSO se:** ha qualquer mudanca semantica observavel.

---

## 7. Claim de "ja existia antes" / "esse bug nao e meu"

**Como verificar:**
- `git blame` no trecho afetado para confirmar autoria/idade
- Procurar PRs anteriores que tocaram o mesmo trecho

**Veredicto NAO_VERIFICAVEL se:** sem acesso a history completa. Reportar como risco mas nao bloquear.

---

## 8. Claim de teste / cobertura ("testes cobrem isso")

**Como verificar:**
- Procurar arquivos `*.test.*`, `*.spec.*`, ou testes E2E que cubram o codigo alterado
- Ler os testes e validar que o cenario do bug realmente esta coberto
- Sinal de alarme: teste existe mas mock-heavy ou nao reproduz o cenario

**Veredicto FALSO se:** nao ha teste, ou o teste passa mesmo com o bug presente.

---

## 9. Claim sem fato verificavel ("isso e seguro", "isso e idiomatico")

**Como tratar:**
- Nao classificar como TRUE/FALSE — sao opinioes
- So entram no parecer se o codigo demonstra o contrario

---

## Resumo

| Tipo de claim | Veredicto possivel | Onde entra no parecer |
|---------------|--------------------|-----------------------|
| Causa-raiz    | TRUE / FALSE       | BLOCKING se FALSE     |
| Fix           | TRUE / FALSE       | BLOCKING se FALSE     |
| Escopo        | TRUE / FALSE       | SHOULD-FIX se FALSE   |
| Dependencia   | NAO_VERIFICAVEL    | BLOCKING se sem link  |
| Dead code     | TRUE / FALSE       | BLOCKING se FALSE     |
| Refactor      | TRUE / FALSE       | BLOCKING se FALSE     |
| "Ja existia"  | NAO_VERIFICAVEL    | UNCERTAIN, contexto   |
| Testes        | TRUE / FALSE       | SHOULD-FIX se FALSE   |
| Opiniao       | n/a                | so se contradito      |
