# QA: <Título da execução>

## Resumo

| | |
|---|---|
| **Veredito** | `<PASS \| FAIL \| PARCIAL>` |
| **Projeto** | `<nome>` — `<caminho absoluto>` |
| **Ambiente** | `<localhost \| staging \| prod>` — `<base URL>` |
| **Branch / commit** | `<branch>` @ `<sha curto>` |
| **Plano de testes** | `<arquivo, PR #n, issue ou "inline">` |
| **Conta usada** | `<e-mail ou papel>` (perfil de vault `<qa-projeto-ambiente>`) |
| **Sessão do navegador** | `<agent-browser session id>` |
| **Driver** | agent-browser `<versão>` |
| **Data da execução** | `<YYYY-MM-DD>` |

<Uma ou duas frases com o desfecho. Diga explicitamente que as notas de ambiente estão em
seção própria e não são defeitos do código.>

## Escopo

<O que a UI em execução consegue e não consegue exercitar. Liste os critérios de aceite que são
backend-only e diga qual teste automatizado os cobre. Nada aqui deve virar um story fingido no
navegador.>

## Tela provisória (remover se não se aplica)

<Inclua só quando uma tela testada é harness/placeholder. Diga que os screenshots são evidência
de comportamento, não de design final, e qual tarefa entrega a UI definitiva.>

## Dados alvo

<A conta ou registro descartável mutado, seu id, e a confirmação de que voltou ao estado
original ao fim da execução.>

## Histórias e resultados

### US-1: <nome>

1. **Passos:** <ações executadas, na ordem>
2. **Esperado:** <comportamento + textos/rótulos exatos que devem aparecer>
3. **Obtido:** <comportamento observado + status HTTP das chamadas envolvidas>
4. **Resultado:** `<PASS \| FAIL \| BLOCKED>` — evidência: `screenshots/<arquivo>.png`

<Repita o bloco para cada história. BLOCKED exige apontar qual nota de ambiente o bloqueou.>

## Evidência de rede

| Método | Rota | Status | Significado |
|---|---|---|---|
| `POST` | `/api/...` | `201` | <o que comprova> |

## Console e erros de página

<Saída relevante de `console` / `errors`, ou "nenhum erro de página durante a execução".>

## Notas de ambiente (não são defeitos)

1. <ex.: cookie de auth cross-site derrubado no reload; contornado com pushstate>
2. <ex.: timeout de inatividade elevado para a execução>
3. <ex.: 404 por lag de deploy até o backend subir>

## Estado dos dados e limpeza

<Confirme que toda mutação foi revertida e cite a resposta ou o snapshot que comprova. Diga se
o servidor local foi parado e se a sessão foi fechada persistindo o estado.>

## Screenshots

1. `screenshots/<arquivo>.png` — <o que mostra> (US-n)

## Como reproduzir

```
/fullstack-pr-qa projeto=<caminho> plano=<origem> auth=@<perfil> env=<ambiente>
```
