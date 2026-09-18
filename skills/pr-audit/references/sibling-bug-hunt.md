# Sibling Bug Hunt

Protocolo para procurar o mesmo padrao de bug em codigo NAO tocado pelo PR. Usado na Fase 4.

A premissa: bugs raramente sao unicos. Se um padrao aparece em um lugar, e provavel que apareca em outros — especialmente em monorepos com modulos similares.

---

## 1. Identificar a forma do bug

Antes de buscar, escrever em 1-2 linhas a forma do bug. Exemplos:
- "Mapeamento de coluna → param invertido em `apiFilters`"
- "Split de string pipe-separated faltando antes de enviar para API"
- "Falta de validacao de tenant em consumer Kafka"
- "Cache sem invalidacao apos mutacao"

Extrair tambem:
- **Simbolos** envolvidos: nomes de constantes, funcoes, types, queries
- **Estrutura** do bug: `if x then y` invertido, `forEach` sem early return, etc

---

## 2. Estrategias de busca (paralelas)

### 2.1 — Busca por simbolo identico
Grep pelos nomes de constantes/funcoes envolvidas no bug em todo o repo:

```
grep -rn "FILTER_FIELD_MAP\|apiFilters" --include="*.tsx" --include="*.ts" /caminho/repo
```

Listar todos os arquivos. Filtrar os ja tocados pelo PR. Os restantes sao candidatos.

### 2.2 — Busca por padrao estrutural
Identificar a "assinatura" estrutural do bug e procurar instances semelhantes. Ex se o bug e "mapping invertido":

```
grep -rn "['\"]_like['\"]\s*=" /caminho/repo
```

ou se e "split faltando":

```
grep -rn "filter.value" --include="*.tsx" /caminho/repo
```

### 2.3 — Busca por filename / convencao
Em monorepos, modulos com a mesma funcao geralmente tem nomes parecidos. Ex:

```
find /caminho/repo -name "data-table.tsx" -o -name "filter-bar.tsx"
```

---

## 3. Confirmar candidatos

Para cada arquivo candidato:

1. **Ler o arquivo completo** (nao confiar so no trecho do grep)
2. **Verificar contexto**: o codigo realmente faz o que o padrao do bug indica?
3. **Confirmar reprodutibilidade**: o caminho de execucao do bug realmente existe?
4. **Comparar com o fix do PR atual**: a correcao se aplica diretamente, ou o contexto e diferente?

So reporta candidatos onde os 4 itens batem.

---

## 4. Reportar

Para cada bug irmao confirmado:
- `path:line` exato
- Snippet de 5-10 linhas do trecho problematico
- Frase em 1-2 linhas explicando por que reproduz
- Sugestao de fix (pode ser apenas referenciar o fix do PR atual)
- Severidade: tipicamente BLOCKING (mesmo padrao do bug que motivou o PR)

---

## 5. Anti-padroes

NAO reportar:
- Candidatos onde voce nao leu o arquivo completo
- "Possivel bug" sem confirmacao explicita do fluxo
- Arquivos onde o contexto e diferente ainda que o simbolo seja igual
- Mais de 5 irmaos sem evidencia clara (ruido)

A confianca do parecer depende de cada finding ser solido. Um falso positivo aqui derruba a credibilidade do parecer inteiro.
