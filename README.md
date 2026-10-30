# Claude Code Status Line (PowerShell)

Status line de duas linhas para o [Claude Code](https://code.claude.com/docs) no Windows,
com barras coloridas de **contexto**, **limite de 5 horas** e **limite de 7 dias** — cada
limite mostrando **quando renova** e **quanto falta**.

```
Opus 5 v2.1.231 | meu-projeto | git: main *
Contexto [████░░░░░░] 46% 70k / 1M | Token 5h [██░░░░░░░░] 23% ↻ 19:01 (4h32m) | Token 7D [████░░░░░░] 41% ↻ 19/ago 09:58 (6d19h)
```

## O que aparece

**Linha 1:** modelo em uso, versão do Claude Code, pasta atual e estado do git (`branch ok` quando limpo, `branch *`
quando há alterações).

**Linha 2:** três medidores, cada um com barra de 10 blocos e percentual colorido:

| Medidor | Conteúdo |
| --- | --- |
| `Contexto` | quanto da janela de contexto já foi usado, com tokens usados / tamanho total |
| `Token 5h` | consumo do limite de 5 horas + hora da renovação + tempo restante |
| `Token 7D` | consumo do limite de 7 dias + data da renovação + tempo restante |

Cores do percentual: verde abaixo de 50%, amarelo até 65%, laranja até 80%, vermelho acima disso.

## Detalhes de implementação

- **Contexto descontando o auto-compact.** O Claude Code dispara o compact antes de encher a
  janela, então o script normaliza o percentual sobre o espaço realmente utilizável
  (`AUTO_COMPACT_BUFFER_PCT = 16.5`). O número reflete o quanto falta para o compact, não para
  o limite teórico.
- **Cache dos limites.** O bloco `rate_limits` só chega no JSON depois da primeira resposta da
  API na sessão, e apenas para assinantes Pro/Max. Até lá o script reaproveita o último valor
  conhecido, gravado em `~/.claude/cache/statusline-rate-limits.json`.
- **Renovação vencida some.** Se o `resets_at` em cache já passou, o horário deixa de ser
  exibido em vez de mostrar um dado obsoleto.
- **Mês abreviado em PT-BR.** A data sai como `19/ago` (lista fixa, sem depender da cultura do
  sistema) para não se confundir com a hora `19:00` do medidor de 5 horas.

## Instalação

1. Copie `statusline.ps1` para `~/.claude/statusline.ps1`:

   ```powershell
   Copy-Item .\statusline.ps1 "$env:USERPROFILE\.claude\statusline.ps1"
   ```

2. Adicione ao seu `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/SEU_USUARIO/.claude/statusline.ps1\"",
       "padding": 2
     }
   }
   ```

   Troque `SEU_USUARIO` pelo seu nome de usuário do Windows.

3. Reinicie o Claude Code (ou rode `/statusline` para recarregar).

## Requisitos

- **PowerShell 7+ (`pwsh`)** — o Windows PowerShell 5.1 não interpreta a sequência `` `e ``
  usada para as cores ANSI.
- **Terminal com suporte a UTF-8 e ANSI** — Windows Terminal funciona por padrão.
- **Fonte com os glifos de bloco** (`█`, `░`) e a seta `↻`. Se a seta sair deformada na sua
  fonte, troque o caractere na função `New-ResetDisplay`.
- Os medidores de 5h e 7d dependem de assinatura Claude.ai (Pro/Max); sem isso eles ficam como
  `[░░░░░░░░░░] --`.

## Teste rápido sem abrir o Claude Code

```powershell
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$json = @{
  model = @{ display_name = 'Opus 5' }
  version = '2.1.231'
  workspace = @{ current_dir = $PWD.Path }
  context_window = @{ remaining_percentage = 62.0; context_window_size = 200000; total_input_tokens = 78000; total_output_tokens = 4000 }
  rate_limits = @{
    five_hour = @{ used_percentage = 23.5; resets_at = ($now + 16380) }
    seven_day = @{ used_percentage = 41.2; resets_at = ($now + 588600) }
  }
} | ConvertTo-Json -Depth 5
$json | pwsh -NoProfile -ExecutionPolicy Bypass -File .\statusline.ps1
```

## Personalização

| Quero mudar | Onde mexer |
| --- | --- |
| Largura da barra | parâmetro `Width` em `New-Bar` / `New-PrettyUsageDisplay` |
| Faixas de cor | função `New-PrettyUsageDisplay` |
| Marcador de renovação (`↻`) | função `New-ResetDisplay` |
| Formato da data / tempo restante | funções `New-ResetDisplay` e `Format-TimeRemaining` |
| Rótulos e ordem dos medidores | montagem de `$line2` no fim do arquivo |

## Referência

Campos do JSON recebido via stdin: [documentação oficial do status line](https://code.claude.com/docs/en/statusline).

## Licença

MIT — veja [LICENSE](LICENSE).
